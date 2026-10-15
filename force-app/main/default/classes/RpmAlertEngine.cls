/**
 * Description    : Raises health and device alerts from readings and telemetry using the active protocol.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Raises alerts from readings and device telemetry using the active protocol.
 *
 * Health rules (systolic only; diastolic is charted, not alerted):
 *   - above Critical_Systolic   -> Critical
 *   - above Alert_Systolic      -> Urgent
 *   - below Low_Systolic        -> Urgent
 *   - average rise over window  -> Routine (one open trend alert per patient)
 * Device rules:
 *   - no reading for Silent_Days -> Urgent
 *   - battery below threshold    -> Routine
 *
 * Every alert carries a Dedupe_Key__c so re-running never creates doubles.
 */
public with sharing class RpmAlertEngine {
    public static final String RULE_CRITICAL = 'Critical Systolic';
    public static final String RULE_HIGH = 'High Systolic';
    public static final String RULE_LOW = 'Low Systolic';
    public static final String RULE_TREND = 'Rising Trend';
    public static final String RULE_SILENT = 'Device Silent';
    public static final String RULE_BATTERY = 'Low Battery';

    public static List<RPM_Alert__c> evaluateReadings(List<RPM_Reading__c> readings) {
        RpmProtocol p = RpmProtocol.active();
        Datetime now = RpmClock.now();
        Map<String, RPM_Alert__c> candidates = new Map<String, RPM_Alert__c>();
        Set<Id> bpPatients = new Set<Id>();

        for (RPM_Reading__c r : readings) {
            if (r.Patient__c == null || r.Systolic__c == null || r.Reading_Type__c != 'Blood Pressure') {
                continue;
            }
            bpPatients.add(r.Patient__c);
            String bp = r.Systolic__c.intValue() + '/' + (r.Diastolic__c == null ? '?' : String.valueOf(r.Diastolic__c.intValue()));
            if (r.Systolic__c > p.criticalSystolic) {
                put(candidates, health(r, 'Critical', RULE_CRITICAL, 'Critical BP ' + bp + ' (above ' + p.criticalSystolic + ')', p, now));
            } else if (r.Systolic__c > p.alertSystolic) {
                put(candidates, health(r, 'Urgent', RULE_HIGH, 'High reading ' + bp + ' (above ' + p.alertSystolic + ')', p, now));
            } else if (r.Systolic__c < p.lowSystolic) {
                put(candidates, health(r, 'Urgent', RULE_LOW, 'Low reading ' + bp + ' (below ' + p.lowSystolic + ')', p, now));
            }
        }

        for (RPM_Alert__c trend : trendAlerts(bpPatients, p, now)) {
            put(candidates, trend);
        }
        return insertNew(candidates.values());
    }

    public static List<RPM_Alert__c> evaluateDevices(List<RPM_Device__c> devices) {
        RpmProtocol p = RpmProtocol.active();
        Datetime now = RpmClock.now();
        Map<String, RPM_Alert__c> candidates = new Map<String, RPM_Alert__c>();
        for (RPM_Device__c d : devices) {
            if (d.Status__c != 'Assigned' || d.Current_Patient__c == null) {
                continue;
            }
            String episode = d.Last_Reading_At__c == null ? 'never' : String.valueOf(d.Last_Reading_At__c.getTime());
            Boolean silent = d.Last_Reading_At__c == null || d.Last_Reading_At__c < now.addDays(-p.silentDays.intValue());
            if (silent) {
                Integer daysSilent = d.Last_Reading_At__c == null ? null : ((now.getTime() - d.Last_Reading_At__c.getTime()) / 86400000L).intValue();
                String summary = d.Last_Reading_At__c == null
                    ? 'Device has never sent a reading'
                    : 'Device silent for ' + daysSilent + ' days';
                put(candidates, device(d, 'Urgent', RULE_SILENT, summary, 'SILENT:' + d.Id + ':' + episode, p, now));
            }
            if (d.Battery_Percent__c != null && d.Battery_Percent__c < p.lowBatteryPercent) {
                put(candidates, device(d, 'Routine', RULE_BATTERY, 'Battery low (' + d.Battery_Percent__c.intValue() + '%)', 'BAT:' + d.Id + ':' + episode, p, now));
            }
        }
        return insertNew(candidates.values());
    }

    private static List<RPM_Alert__c> trendAlerts(Set<Id> patientIds, RpmProtocol p, Datetime now) {
        List<RPM_Alert__c> out = new List<RPM_Alert__c>();
        if (patientIds.isEmpty()) {
            return out;
        }
        Set<Id> alreadyOpen = new Set<Id>();
        for (RPM_Alert__c a : [
            SELECT Patient__c
            FROM RPM_Alert__c
            WHERE Patient__c IN :patientIds AND Rule__c = :RULE_TREND AND Step__c != 'Closed'
            WITH USER_MODE
        ]) {
            alreadyOpen.add(a.Patient__c);
        }
        Integer window = p.trendWindowDays.intValue();
        Datetime currentStart = now.addDays(-window);
        Datetime priorStart = now.addDays(-2 * window);
        Map<Id, List<Decimal>> current = new Map<Id, List<Decimal>>();
        Map<Id, List<Decimal>> prior = new Map<Id, List<Decimal>>();
        for (RPM_Reading__c r : [
            SELECT Patient__c, Systolic__c, Measured_At__c
            FROM RPM_Reading__c
            WHERE Patient__c IN :patientIds AND Reading_Type__c = 'Blood Pressure'
                AND Systolic__c != NULL AND Measured_At__c >= :priorStart
            WITH USER_MODE
        ]) {
            Map<Id, List<Decimal>> bucket = r.Measured_At__c >= currentStart ? current : prior;
            if (!bucket.containsKey(r.Patient__c)) {
                bucket.put(r.Patient__c, new List<Decimal>());
            }
            bucket.get(r.Patient__c).add(r.Systolic__c);
        }
        for (Id pid : patientIds) {
            if (alreadyOpen.contains(pid) || !current.containsKey(pid) || !prior.containsKey(pid)) {
                continue;
            }
            // need at least 3 readings in each window to call it a trend
            if (current.get(pid).size() < 3 || prior.get(pid).size() < 3) {
                continue;
            }
            Decimal rise = avg(current.get(pid)) - avg(prior.get(pid));
            if (rise >= p.trendRiseSystolic) {
                out.add(new RPM_Alert__c(
                    Patient__c = pid,
                    Category__c = 'Health',
                    Severity__c = 'Routine',
                    Rule__c = RULE_TREND,
                    Summary__c = 'Average systolic up ' + rise.setScale(1) + ' over ' + window + ' days',
                    Step__c = 'New',
                    Protocol_Version__c = p.version,
                    Due_At__c = p.dueAt('Routine', now),
                    Dedupe_Key__c = 'TREND:' + pid + ':' + now.date()
                ));
            }
        }
        return out;
    }

    private static RPM_Alert__c health(RPM_Reading__c r, String severity, String rule, String summary, RpmProtocol p, Datetime now) {
        return new RPM_Alert__c(
            Patient__c = r.Patient__c,
            Reading__c = r.Id,
            Device__c = r.Device__c,
            Category__c = 'Health',
            Severity__c = severity,
            Rule__c = rule,
            Summary__c = summary.left(255),
            Step__c = 'New',
            Protocol_Version__c = p.version,
            Due_At__c = p.dueAt(severity, now),
            Dedupe_Key__c = rule.deleteWhitespace().toUpperCase() + ':' + r.Id
        );
    }

    private static RPM_Alert__c device(RPM_Device__c d, String severity, String rule, String summary, String key, RpmProtocol p, Datetime now) {
        return new RPM_Alert__c(
            Patient__c = d.Current_Patient__c,
            Device__c = d.Id,
            Category__c = 'Device',
            Severity__c = severity,
            Rule__c = rule,
            Summary__c = summary.left(255),
            Step__c = 'New',
            Protocol_Version__c = p.version,
            Due_At__c = p.dueAt(severity, now),
            Dedupe_Key__c = key.left(120)
        );
    }

    private static void put(Map<String, RPM_Alert__c> m, RPM_Alert__c a) {
        if (!m.containsKey(a.Dedupe_Key__c)) {
            m.put(a.Dedupe_Key__c, a);
        }
    }

    /** Inserts alerts, silently skipping ones whose dedupe key already exists. */
    private static List<RPM_Alert__c> insertNew(List<RPM_Alert__c> alerts) {
        List<RPM_Alert__c> created = new List<RPM_Alert__c>();
        if (alerts.isEmpty()) {
            return created;
        }
        Database.SaveResult[] srs = Database.insert(alerts, false, AccessLevel.USER_MODE);
        List<RPM_Alert_Event__c> events = new List<RPM_Alert_Event__c>();
        for (Integer i = 0; i < srs.size(); i++) {
            if (srs[i].isSuccess()) {
                created.add(alerts[i]);
                events.add(new RPM_Alert_Event__c(
                    Alert__c = alerts[i].Id,
                    To_Step__c = 'New',
                    Detail__c = ('Raised by rule "' + alerts[i].Rule__c + '" (protocol ' + alerts[i].Protocol_Version__c + ')').left(255),
                    Actor__c = UserInfo.getUserId(),
                    Occurred_At__c = RpmClock.now()
                ));
            }
        }
        if (!events.isEmpty()) {
            Database.insert(events, true, AccessLevel.USER_MODE);
        }
        return created;
    }

    private static Decimal avg(List<Decimal> values) {
        Decimal sum = 0;
        for (Decimal v : values) {
            sum += v;
        }
        return sum / values.size();
    }
}
