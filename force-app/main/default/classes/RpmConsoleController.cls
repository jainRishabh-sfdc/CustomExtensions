/**
 * Description    : Server-side controller for the RPM Command console (rpmConsole LWC).
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Server side for the RPM Command console (rpmConsole LWC).
 * All reads run in user mode so clinic users only see what their
 * permission set and sharing allow. Workflow rules live in RpmAlertWorkflow;
 * this class only adapts them for the UI.
 */
public with sharing class RpmConsoleController {
    private static final Set<String> TEAM_PERMSETS = new Set<String>{ 'RPM_Admin', 'RPM_Clinician' };

    // ---------------------------------------------------------------- Today

    @AuraEnabled
    public static Map<String, Object> getToday() {
        Map<String, Object> out = new Map<String, Object>();
        out.put('critical', [SELECT COUNT() FROM RPM_Alert__c WHERE Severity__c = 'Critical' AND Category__c = 'Health' AND Step__c != 'Closed' WITH USER_MODE]);
        out.put('healthOpen', [SELECT COUNT() FROM RPM_Alert__c WHERE Category__c = 'Health' AND Step__c != 'Closed' WITH USER_MODE]);
        out.put('deviceOpen', [SELECT COUNT() FROM RPM_Alert__c WHERE Category__c = 'Device' AND Step__c != 'Closed' WITH USER_MODE]);
        out.put('overdue', [SELECT COUNT() FROM RPM_Alert__c WHERE Step__c != 'Closed' AND Due_At__c < :RpmClock.now() WITH USER_MODE]);
        out.put('redPatients', [SELECT COUNT() FROM RPM_Patient__c WHERE Status__c = 'Enrolled' AND Risk_Level__c = 'RED' WITH USER_MODE]);
        out.put('patients', [SELECT COUNT() FROM RPM_Patient__c WHERE Status__c = 'Enrolled' WITH USER_MODE]);
        out.put('readyToBill', [SELECT COUNT() FROM RPM_Billing_Period__c WHERE Status__c = 'Ready to Bill' WITH USER_MODE]);

        List<Map<String, Object>> todo = new List<Map<String, Object>>();
        for (RPM_Alert__c a : [
            SELECT Id, Summary__c, Severity__c, Category__c, Step__c, Due_At__c, Patient__c, Patient__r.Name, Assigned_To__r.Name
            FROM RPM_Alert__c
            WHERE Step__c != 'Closed'
            WITH USER_MODE
            ORDER BY Due_At__c ASC NULLS LAST
            LIMIT 50
        ]) {
            todo.add(alertRow(a));
        }
        todo.sort(new SeverityThenDue());
        while (todo.size() > 10) {
            todo.remove(todo.size() - 1);
        }
        out.put('todo', todo);
        return out;
    }

    // ------------------------------------------------------------- Patients

    @AuraEnabled
    public static List<Map<String, Object>> getPatients(String risk) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        String r = String.isBlank(risk) ? null : risk;
        for (RPM_Patient__c p : [
            SELECT Id, Name, Risk_Level__c, Risk_Reasons__c, Payer__c, Payer_Type__c, Diagnoses__c,
                Last_Reading_At__c, Billing_Locked__c, Status__c
            FROM RPM_Patient__c
            WHERE Status__c != 'Discharged'
            WITH USER_MODE
            ORDER BY Name
            LIMIT 500
        ]) {
            String level = p.Risk_Level__c == null ? 'GREEN' : p.Risk_Level__c;
            if (r != null && level != r) {
                continue;
            }
            rows.add(new Map<String, Object>{
                'id' => p.Id,
                'name' => p.Name,
                'risk' => p.Risk_Level__c == null ? 'GREEN' : p.Risk_Level__c,
                'reasons' => p.Risk_Reasons__c,
                'payer' => p.Payer__c,
                'payerType' => p.Payer_Type__c,
                'diagnoses' => p.Diagnoses__c,
                'lastReading' => p.Last_Reading_At__c,
                'locked' => p.Billing_Locked__c,
                'status' => p.Status__c
            });
        }
        return rows;
    }

    @AuraEnabled
    public static Map<String, Object> getPatientDetail(Id patientId, Integer days) {
        Integer range = (days == null || days <= 0) ? 30 : Math.min(days, 365);
        List<RPM_Patient__c> found = [
            SELECT Id, Name, Risk_Level__c, Risk_Reasons__c, Payer__c, Payer_Type__c, Diagnoses__c, Birth_Date__c, Sex__c,
                Consent_Date__c, Enrollment_Date__c, Billing_Locked__c, Billing_Lock_Reason__c,
                Target_Sys_High__c, Target_Sys_Low__c, Target_Dia_High__c, Target_Dia_Low__c
            FROM RPM_Patient__c
            WHERE Id = :patientId
            WITH USER_MODE
            LIMIT 1
        ];
        if (found.isEmpty()) {
            throw error('Patient not found or not accessible.');
        }
        RPM_Patient__c p = found[0];
        RpmProtocol proto = RpmProtocol.active();
        Datetime since = RpmClock.now().addDays(-range);

        List<Map<String, Object>> readings = new List<Map<String, Object>>();
        for (RPM_Reading__c r : [
            SELECT Id, Measured_At__c, Systolic__c, Diastolic__c, Pulse__c
            FROM RPM_Reading__c
            WHERE Patient__c = :patientId AND Reading_Type__c = 'Blood Pressure' AND Systolic__c != NULL AND Measured_At__c >= :since
            WITH USER_MODE
            ORDER BY Measured_At__c ASC
            LIMIT 1000
        ]) {
            String flag = r.Systolic__c > proto.criticalSystolic ? 'critical' : (r.Systolic__c > proto.alertSystolic ? 'high' : (r.Systolic__c < proto.lowSystolic ? 'low' : ''));
            readings.add(new Map<String, Object>{
                'id' => r.Id,
                'at' => r.Measured_At__c,
                'sys' => r.Systolic__c,
                'dia' => r.Diastolic__c,
                'pulse' => r.Pulse__c,
                'flag' => flag
            });
        }

        List<Map<String, Object>> devices = new List<Map<String, Object>>();
        for (RPM_Device__c d : [
            SELECT Id, Name, IMEI__c, Serial_Number__c, Model__c, Status__c, Location__c, Battery_Percent__c,
                Last_Reading_At__c, Current_Patient__c, Fulfillment__c
            FROM RPM_Device__c
            WHERE Current_Patient__c = :patientId AND Status__c = 'Assigned'
            WITH USER_MODE
        ]) {
            devices.add(deviceRow(d, null, proto));
        }

        List<Map<String, Object>> openAlerts = new List<Map<String, Object>>();
        for (RPM_Alert__c a : [
            SELECT Id, Summary__c, Severity__c, Category__c, Step__c, Due_At__c, Patient__c, Patient__r.Name, Assigned_To__r.Name
            FROM RPM_Alert__c
            WHERE Patient__c = :patientId AND Step__c != 'Closed'
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ]) {
            openAlerts.add(alertRow(a));
        }

        Date monthStart = RpmBillingEngine.periodStart(RpmClock.today());
        List<Map<String, Object>> timeRows = new List<Map<String, Object>>();
        for (RPM_Time_Entry__c t : [
            SELECT Id, Entry_Date__c, Minutes__c, Activity__c, Interactive__c, Note__c, CreatedBy.Name
            FROM RPM_Time_Entry__c
            WHERE Patient__c = :patientId AND Entry_Date__c >= :monthStart
            WITH USER_MODE
            ORDER BY Entry_Date__c DESC, CreatedDate DESC
        ]) {
            timeRows.add(new Map<String, Object>{
                'id' => t.Id,
                'date' => t.Entry_Date__c,
                'minutes' => t.Minutes__c,
                'activity' => t.Activity__c,
                'interactive' => t.Interactive__c,
                'note' => t.Note__c,
                'by' => t.CreatedBy.Name
            });
        }

        List<RPM_Billing_Period__c> periods = RpmBillingEngine.recalculate(new Set<Id>{ patientId }, RpmClock.today());
        Map<String, Object> billing = periods.isEmpty() ? null : billingRow(periods[0], p.Name);

        Map<String, Object> out = new Map<String, Object>{
            'id' => p.Id,
            'name' => p.Name,
            'risk' => p.Risk_Level__c == null ? 'GREEN' : p.Risk_Level__c,
            'reasons' => p.Risk_Reasons__c,
            'payer' => p.Payer__c,
            'payerType' => p.Payer_Type__c,
            'diagnoses' => p.Diagnoses__c,
            'birthDate' => p.Birth_Date__c,
            'sex' => p.Sex__c,
            'consentDate' => p.Consent_Date__c,
            'locked' => p.Billing_Locked__c,
            'lockReason' => p.Billing_Lock_Reason__c,
            'targetSysHigh' => p.Target_Sys_High__c,
            'targetSysLow' => p.Target_Sys_Low__c,
            'alertLine' => proto.alertSystolic,
            'criticalLine' => proto.criticalSystolic,
            'lowLine' => proto.lowSystolic,
            'protocolVersion' => proto.version,
            'readings' => readings,
            'devices' => devices,
            'alerts' => openAlerts,
            'time' => timeRows,
            'billing' => billing
        };
        return out;
    }

    @AuraEnabled
    public static void logTime(Id patientId, Integer minutes, String activity, Boolean interactive, String note) {
        if (minutes == null || minutes < 1 || minutes > 240) {
            throw error('Minutes must be between 1 and 240.');
        }
        try {
            Database.insert(new RPM_Time_Entry__c(
                Patient__c = patientId,
                Entry_Date__c = RpmClock.today(),
                Minutes__c = minutes,
                Activity__c = String.isBlank(activity) ? 'Other' : activity,
                Interactive__c = interactive == true,
                Note__c = note == null ? null : note.left(255)
            ), true, AccessLevel.USER_MODE);
            RpmBillingEngine.recalculate(new Set<Id>{ patientId }, RpmClock.today());
        } catch (DmlException e) {
            throw error(e.getDmlMessage(0));
        }
    }

    // --------------------------------------------------------------- Alerts

    @AuraEnabled
    public static List<Map<String, Object>> getAlerts(String filter) {
        String f = String.isBlank(filter) ? 'open' : filter;
        List<RPM_Alert__c> alerts;
        if (f == 'closed') {
            alerts = [
                SELECT Id, Summary__c, Severity__c, Category__c, Rule__c, Step__c, Due_At__c, Patient__c, Patient__r.Name,
                    Assigned_To__r.Name, Protocol_Version__c, Disposition__c, CreatedDate,
                    (SELECT Id, From_Step__c, To_Step__c, Detail__c, Occurred_At__c, Actor__r.Name FROM Events__r ORDER BY Occurred_At__c ASC)
                FROM RPM_Alert__c
                WHERE Step__c = 'Closed'
                WITH USER_MODE
                ORDER BY Closed_At__c DESC
                LIMIT 100
            ];
        } else {
            alerts = [
                SELECT Id, Summary__c, Severity__c, Category__c, Rule__c, Step__c, Due_At__c, Patient__c, Patient__r.Name,
                    Assigned_To__r.Name, Protocol_Version__c, Disposition__c, CreatedDate,
                    (SELECT Id, From_Step__c, To_Step__c, Detail__c, Occurred_At__c, Actor__r.Name FROM Events__r ORDER BY Occurred_At__c ASC)
                FROM RPM_Alert__c
                WHERE Step__c != 'Closed'
                WITH USER_MODE
                ORDER BY Due_At__c ASC NULLS LAST
                LIMIT 200
            ];
        }
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (RPM_Alert__c a : alerts) {
            if (f == 'critical' && !(a.Severity__c == 'Critical' && a.Category__c == 'Health')) {
                continue;
            }
            if (f == 'health' && a.Category__c != 'Health') {
                continue;
            }
            if (f == 'device' && a.Category__c != 'Device') {
                continue;
            }
            Map<String, Object> row = alertRow(a);
            row.put('rule', a.Rule__c);
            row.put('protocolVersion', a.Protocol_Version__c);
            row.put('disposition', a.Disposition__c);
            row.put('raisedAt', a.CreatedDate);
            List<Map<String, Object>> history = new List<Map<String, Object>>();
            for (RPM_Alert_Event__c e : a.Events__r) {
                history.add(new Map<String, Object>{
                    'id' => e.Id,
                    'at' => e.Occurred_At__c,
                    'from' => e.From_Step__c,
                    'to' => e.To_Step__c,
                    'detail' => e.Detail__c,
                    'by' => e.Actor__r == null ? null : e.Actor__r.Name
                });
            }
            row.put('history', history);
            rows.add(row);
        }
        if (f != 'closed') {
            rows.sort(new SeverityThenDue());
        }
        return rows;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getTeam() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Set<Id> seen = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, Assignee.Name
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name IN :TEAM_PERMSETS AND Assignee.IsActive = TRUE
            ORDER BY Assignee.Name
            LIMIT 500
        ]) {
            if (seen.add(psa.AssigneeId)) {
                rows.add(new Map<String, Object>{ 'label' => psa.Assignee.Name, 'value' => psa.AssigneeId });
            }
        }
        return rows;
    }

    @AuraEnabled
    public static void checkAlert(Id alertId, String note) {
        try {
            RpmAlertWorkflow.markChecked(alertId, note);
        } catch (Exception e) {
            throw error(e);
        }
    }

    @AuraEnabled
    public static void assignAlert(Id alertId, Id userId) {
        try {
            RpmAlertWorkflow.assign(alertId, userId);
        } catch (Exception e) {
            throw error(e);
        }
    }

    @AuraEnabled
    public static void recordCall(Id alertId, String outcome, String symptoms, String providerNotified, String note) {
        try {
            RpmAlertWorkflow.recordCall(alertId, outcome, symptoms, providerNotified, note);
        } catch (Exception e) {
            throw error(e);
        }
    }

    @AuraEnabled
    public static void reviewAlert(Id alertId, String note) {
        try {
            RpmAlertWorkflow.providerReviewed(alertId, note);
        } catch (Exception e) {
            throw error(e);
        }
    }

    @AuraEnabled
    public static void closeAlert(Id alertId, String disposition) {
        try {
            RpmAlertWorkflow.close(alertId, disposition);
        } catch (Exception e) {
            throw error(e);
        }
    }

    @AuraEnabled
    public static void closeDeviceAlert(Id alertId, String note) {
        try {
            RpmAlertWorkflow.closeDeviceAlert(alertId, note);
        } catch (Exception e) {
            throw error(e);
        }
    }

    // -------------------------------------------------------------- Devices

    @AuraEnabled
    public static Map<String, Object> getDevices() {
        RpmProtocol proto = RpmProtocol.active();
        List<Map<String, Object>> field = new List<Map<String, Object>>();
        List<Map<String, Object>> stock = new List<Map<String, Object>>();
        List<Map<String, Object>> returns = new List<Map<String, Object>>();
        for (RPM_Device__c d : [
            SELECT Id, Name, IMEI__c, Serial_Number__c, Model__c, Status__c, Location__c, Battery_Percent__c,
                Last_Reading_At__c, Current_Patient__c, Current_Patient__r.Name, Fulfillment__c
            FROM RPM_Device__c
            WHERE Status__c != 'Retired'
            WITH USER_MODE
            ORDER BY Name
            LIMIT 1000
        ]) {
            Map<String, Object> row = deviceRow(d, d.Current_Patient__r == null ? null : d.Current_Patient__r.Name, proto);
            if (d.Status__c == 'Assigned') {
                field.add(row);
            } else if (d.Status__c == 'In Stock') {
                stock.add(row);
            } else {
                returns.add(row);
            }
        }
        return new Map<String, Object>{ 'field' => field, 'stock' => stock, 'returns' => returns, 'silentDays' => proto.silentDays };
    }

    /**
     * Device handout. All four safety checks are required: right device was
     * confirmed in the UI step, two patient identifiers, teach-back training,
     * test reading received, loaner acknowledged.
     */
    @AuraEnabled
    public static void assignDevice(Id deviceId, Id patientId, Boolean identityVerified, Boolean trainingDone, Boolean testReading, Boolean loanerAck) {
        if (patientId == null) {
            throw error('Choose the patient.');
        }
        if (identityVerified != true) {
            throw error('Confirm the patient with two identifiers (name and date of birth).');
        }
        if (trainingDone != true || testReading != true || loanerAck != true) {
            throw error('Training, test reading and loaner acknowledgement are all required before a device goes live.');
        }
        List<RPM_Device__c> devs = [SELECT Id, Status__c FROM RPM_Device__c WHERE Id = :deviceId WITH USER_MODE LIMIT 1];
        if (devs.isEmpty()) {
            throw error('Device not found.');
        }
        if (devs[0].Status__c != 'In Stock') {
            throw error('Only devices in stock can be handed out.');
        }
        Datetime now = RpmClock.now();
        try {
            endOpenAssignments(deviceId, now);
            Database.insert(new RPM_Device_Assignment__c(
                Device__c = deviceId,
                Patient__c = patientId,
                Start_At__c = now,
                Identity_Verified__c = true,
                Training_Done__c = true,
                Test_Reading_Received__c = true,
                Loaner_Acknowledged__c = true
            ), true, AccessLevel.USER_MODE);
            Database.update(new RPM_Device__c(Id = deviceId, Status__c = 'Assigned', Current_Patient__c = patientId, Location__c = null), true, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw error(e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static void returnDevice(Id deviceId, String reason) {
        try {
            endOpenAssignments(deviceId, RpmClock.now());
            Database.update(new RPM_Device__c(
                Id = deviceId,
                Status__c = 'Return Pending',
                Current_Patient__c = null,
                Location__c = String.isBlank(reason) ? 'Returned' : ('Returned: ' + reason).left(120)
            ), true, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw error(e.getDmlMessage(0));
        }
    }

    // -------------------------------------------------------------- Billing

    @AuraEnabled
    public static List<Map<String, Object>> getBilling() {
        Map<Id, RPM_Patient__c> enrolled = new Map<Id, RPM_Patient__c>([
            SELECT Id, Name FROM RPM_Patient__c WHERE Status__c = 'Enrolled' WITH USER_MODE LIMIT 2000
        ]);
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (RPM_Billing_Period__c bp : RpmBillingEngine.recalculate(enrolled.keySet(), RpmClock.today())) {
            rows.add(billingRow(bp, enrolled.get(bp.Patient__c).Name));
        }
        return rows;
    }

    // -------------------------------------------------------------- helpers

    private static Map<String, Object> alertRow(RPM_Alert__c a) {
        Boolean overdue = a.Step__c != 'Closed' && a.Due_At__c != null && a.Due_At__c < RpmClock.now();
        return new Map<String, Object>{
            'id' => a.Id,
            'summary' => a.Summary__c,
            'severity' => a.Severity__c,
            'category' => a.Category__c,
            'step' => a.Step__c,
            'stepIndex' => RpmAlertWorkflow.STEPS.indexOf(a.Step__c),
            'nextStep' => RpmAlertWorkflow.nextStep(a.Step__c),
            'dueAt' => a.Due_At__c,
            'overdue' => overdue,
            'patientId' => a.Patient__c,
            'patientName' => a.Patient__r == null ? null : a.Patient__r.Name,
            'owner' => a.Assigned_To__r == null ? null : a.Assigned_To__r.Name
        };
    }

    private static Map<String, Object> deviceRow(RPM_Device__c d, String patientName, RpmProtocol proto) {
        Integer daysSilent = d.Last_Reading_At__c == null ? null : ((RpmClock.now().getTime() - d.Last_Reading_At__c.getTime()) / 86400000L).intValue();
        Boolean silent = d.Status__c == 'Assigned' && (daysSilent == null || daysSilent >= proto.silentDays);
        Boolean lowBattery = d.Battery_Percent__c != null && d.Battery_Percent__c < proto.lowBatteryPercent;
        return new Map<String, Object>{
            'id' => d.Id,
            'name' => d.Name,
            'imei' => d.IMEI__c,
            'serial' => d.Serial_Number__c,
            'model' => d.Model__c,
            'status' => d.Status__c,
            'location' => d.Location__c,
            'battery' => d.Battery_Percent__c,
            'lastReading' => d.Last_Reading_At__c,
            'daysSilent' => daysSilent,
            'silent' => silent,
            'lowBattery' => lowBattery,
            'patientId' => d.Current_Patient__c,
            'patientName' => patientName,
            'fulfillment' => d.Fulfillment__c
        };
    }

    private static Map<String, Object> billingRow(RPM_Billing_Period__c bp, String patientName) {
        return new Map<String, Object>{
            'id' => bp.Id,
            'patientId' => bp.Patient__c,
            'patientName' => patientName,
            'periodStart' => bp.Period_Start__c,
            'periodEnd' => bp.Period_End__c,
            'readingDays' => bp.Reading_Days__c,
            'minutes' => bp.Care_Minutes__c,
            'interactive' => bp.Interactive_Done__c,
            'codes' => bp.Codes__c,
            'blockedReason' => bp.Blocked_Reason__c,
            'status' => bp.Status__c,
            'rulesVersion' => bp.Rules_Version__c
        };
    }

    private static void endOpenAssignments(Id deviceId, Datetime endAt) {
        List<RPM_Device_Assignment__c> open = [
            SELECT Id FROM RPM_Device_Assignment__c WHERE Device__c = :deviceId AND End_At__c = NULL WITH USER_MODE
        ];
        for (RPM_Device_Assignment__c a : open) {
            a.End_At__c = endAt;
        }
        if (!open.isEmpty()) {
            Database.update(open, true, AccessLevel.USER_MODE);
        }
    }

    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    private static AuraHandledException error(Exception ex) {
        String message = ex instanceof DmlException ? ((DmlException) ex).getDmlMessage(0) : ex.getMessage();
        return error(message);
    }

    /** Critical first, then Urgent, then Routine; earliest due first within a severity. */
    public class SeverityThenDue implements Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            Integer ra = rank((String) a.get('severity'));
            Integer rb = rank((String) b.get('severity'));
            if (ra != rb) {
                return ra - rb;
            }
            Datetime da = (Datetime) a.get('dueAt');
            Datetime db = (Datetime) b.get('dueAt');
            if (da == db) {
                return 0;
            }
            if (da == null) {
                return 1;
            }
            if (db == null) {
                return -1;
            }
            return da < db ? -1 : 1;
        }

        private Integer rank(String severity) {
            return severity == 'Critical' ? 0 : (severity == 'Urgent' ? 1 : 2);
        }
    }
}
