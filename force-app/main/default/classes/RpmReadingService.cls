/**
 * Description    : Stores and matches incoming readings, then runs alerts and risk refresh.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Stores incoming device readings, matches them to the patient who held the
 * device at measurement time, updates device telemetry, then runs the alert
 * engine and risk refresh.
 *
 * Duplicate deliveries (same eventId) are dropped. Readings from unknown
 * devices are kept with Match_Status__c = 'Unknown Device' so nothing is lost.
 */
public with sharing class RpmReadingService {
    public static final Integer MAX_BATCH = 200;

    public class IngestResult {
        public Integer received = 0;
        public Integer created = 0;
        public Integer duplicates = 0;
        public Integer unmatched = 0;
        public Integer alertsRaised = 0;
        public List<String> errors = new List<String>();
    }

    public static IngestResult ingest(List<RpmReadingInput> inputs) {
        IngestResult result = new IngestResult();
        if (inputs == null || inputs.isEmpty()) {
            return result;
        }
        result.received = inputs.size();

        // 1. Validate and drop in-batch duplicates
        Map<String, RpmReadingInput> byEvent = new Map<String, RpmReadingInput>();
        Set<String> imeis = new Set<String>();
        for (Integer i = 0; i < inputs.size(); i++) {
            RpmReadingInput inp = inputs[i];
            String problem = validate(inp);
            if (problem != null) {
                result.errors.add('Item ' + i + ': ' + problem);
                continue;
            }
            if (byEvent.containsKey(inp.eventId)) {
                result.duplicates++;
                continue;
            }
            byEvent.put(inp.eventId, inp);
            imeis.add(inp.imei);
        }
        if (byEvent.isEmpty()) {
            return result;
        }

        // 2. Drop events already stored
        for (RPM_Reading__c existing : [
            SELECT Source_Event_Id__c
            FROM RPM_Reading__c
            WHERE Source_Event_Id__c IN :byEvent.keySet()
            WITH USER_MODE
        ]) {
            byEvent.remove(existing.Source_Event_Id__c);
            result.duplicates++;
        }
        if (byEvent.isEmpty()) {
            return result;
        }

        // 3. Resolve devices and assignments
        Map<String, RPM_Device__c> devices = new Map<String, RPM_Device__c>();
        for (RPM_Device__c d : [
            SELECT Id, IMEI__c, Battery_Percent__c, Signal_dBm__c, Last_Reading_At__c
            FROM RPM_Device__c
            WHERE IMEI__c IN :imeis
            WITH USER_MODE
        ]) {
            devices.put(d.IMEI__c, d);
        }
        Map<Id, List<RPM_Device_Assignment__c>> assignmentsByDevice = new Map<Id, List<RPM_Device_Assignment__c>>();
        Set<Id> deviceIds = new Set<Id>();
        for (RPM_Device__c d : devices.values()) {
            deviceIds.add(d.Id);
        }
        for (RPM_Device_Assignment__c a : [
            SELECT Id, Device__c, Patient__c, Start_At__c, End_At__c
            FROM RPM_Device_Assignment__c
            WHERE Device__c IN :deviceIds
            WITH USER_MODE
            ORDER BY Start_At__c DESC
        ]) {
            if (!assignmentsByDevice.containsKey(a.Device__c)) {
                assignmentsByDevice.put(a.Device__c, new List<RPM_Device_Assignment__c>());
            }
            assignmentsByDevice.get(a.Device__c).add(a);
        }

        // 4. Build readings
        List<RPM_Reading__c> readings = new List<RPM_Reading__c>();
        Map<Id, RPM_Device__c> deviceUpdates = new Map<Id, RPM_Device__c>();
        for (RpmReadingInput inp : byEvent.values()) {
            RPM_Device__c dev = devices.get(inp.imei);
            RPM_Reading__c r = new RPM_Reading__c(
                Source_Event_Id__c = inp.eventId,
                Measured_At__c = inp.measuredAt,
                Reading_Type__c = String.isBlank(inp.type) ? 'Blood Pressure' : inp.type,
                Systolic__c = inp.systolic,
                Diastolic__c = inp.diastolic,
                Pulse__c = inp.pulse,
                Weight_lb__c = inp.weightLb,
                Raw_Payload__c = JSON.serialize(inp)
            );
            if (dev == null) {
                r.Match_Status__c = 'Unknown Device';
                result.unmatched++;
            } else {
                r.Device__c = dev.Id;
                Id patientId = patientAt(assignmentsByDevice.get(dev.Id), inp.measuredAt);
                if (patientId == null) {
                    r.Match_Status__c = 'No Active Assignment';
                    result.unmatched++;
                } else {
                    r.Patient__c = patientId;
                    r.Match_Status__c = 'Matched';
                }
                trackTelemetry(deviceUpdates, dev, inp);
            }
            readings.add(r);
        }

        // 5. Save (partial success so one bad row cannot block the batch)
        List<RPM_Reading__c> saved = new List<RPM_Reading__c>();
        Database.SaveResult[] srs = Database.insert(readings, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < srs.size(); i++) {
            if (srs[i].isSuccess()) {
                saved.add(readings[i]);
                result.created++;
            } else if (isDuplicateError(srs[i])) {
                result.duplicates++;
            } else {
                result.errors.add(readings[i].Source_Event_Id__c + ': ' + srs[i].getErrors()[0].getMessage());
            }
        }

        if (!deviceUpdates.isEmpty()) {
            Database.update(deviceUpdates.values(), false, AccessLevel.USER_MODE);
        }

        // 6. Patient last-reading stamp, alerts, risk
        Set<Id> patientIds = new Set<Id>();
        Map<Id, Datetime> lastByPatient = new Map<Id, Datetime>();
        List<RPM_Reading__c> matched = new List<RPM_Reading__c>();
        for (RPM_Reading__c r : saved) {
            if (r.Patient__c == null) {
                continue;
            }
            matched.add(r);
            patientIds.add(r.Patient__c);
            Datetime prev = lastByPatient.get(r.Patient__c);
            if (prev == null || r.Measured_At__c > prev) {
                lastByPatient.put(r.Patient__c, r.Measured_At__c);
            }
        }
        if (!matched.isEmpty()) {
            result.alertsRaised = RpmAlertEngine.evaluateReadings(matched).size();
            RpmRiskService.stampLastReading(lastByPatient);
            RpmRiskService.refresh(patientIds);
        }
        return result;
    }

    @TestVisible
    private static String validate(RpmReadingInput inp) {
        if (inp == null) {
            return 'empty item';
        }
        if (String.isBlank(inp.eventId)) {
            return 'eventId is required';
        }
        if (String.isBlank(inp.imei)) {
            return 'imei is required';
        }
        if (inp.measuredAt == null) {
            return 'measuredAt is required';
        }
        if (inp.measuredAt > RpmClock.now().addHours(1)) {
            return 'measuredAt is in the future';
        }
        Boolean isBp = String.isBlank(inp.type) || inp.type == 'Blood Pressure';
        if (isBp && (inp.systolic == null || inp.diastolic == null)) {
            return 'systolic and diastolic are required for blood pressure';
        }
        if (isBp && (inp.systolic < 40 || inp.systolic > 300 || inp.diastolic < 20 || inp.diastolic > 200)) {
            return 'blood pressure out of physical range';
        }
        return null;
    }

    private static Id patientAt(List<RPM_Device_Assignment__c> assignments, Datetime measuredAt) {
        if (assignments == null) {
            return null;
        }
        for (RPM_Device_Assignment__c a : assignments) {
            if (a.Start_At__c <= measuredAt && (a.End_At__c == null || a.End_At__c > measuredAt)) {
                return a.Patient__c;
            }
        }
        return null;
    }

    private static void trackTelemetry(Map<Id, RPM_Device__c> updates, RPM_Device__c dev, RpmReadingInput inp) {
        RPM_Device__c u = updates.get(dev.Id);
        if (u == null) {
            u = new RPM_Device__c(Id = dev.Id, Last_Reading_At__c = dev.Last_Reading_At__c);
            updates.put(dev.Id, u);
        }
        if (u.Last_Reading_At__c == null || inp.measuredAt >= u.Last_Reading_At__c) {
            u.Last_Reading_At__c = inp.measuredAt;
            if (inp.battery != null) {
                u.Battery_Percent__c = inp.battery;
            }
            if (inp.signal != null) {
                u.Signal_dBm__c = inp.signal;
            }
        }
    }

    private static Boolean isDuplicateError(Database.SaveResult sr) {
        for (Database.Error e : sr.getErrors()) {
            if (e.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }
}
