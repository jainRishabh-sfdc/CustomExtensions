/**
 * Description    : Loads the active alert protocol thresholds from RPM_Protocol__mdt.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Active alert protocol, read from RPM_Protocol__mdt (subscriber-editable).
 * Falls back to safe defaults when no record is marked Active.
 * Every alert stores the version it was raised under, for audit.
 */
public inherited sharing class RpmProtocol {
    public String version = '1.0-default';
    public Decimal alertSystolic = 150;
    public Decimal criticalSystolic = 180;
    public Decimal lowSystolic = 90;
    public Decimal criticalSlaMinutes = 60;
    public Decimal urgentSlaHours = 4;
    public Decimal routineSlaHours = 72;
    public Decimal trendWindowDays = 14;
    public Decimal trendRiseSystolic = 6;
    public Decimal silentDays = 7;
    public Decimal lowBatteryPercent = 25;

    private static RpmProtocol cached;

    @TestVisible
    private static RPM_Protocol__mdt testRecord;

    public static RpmProtocol active() {
        if (cached != null) {
            return cached;
        }
        RpmProtocol p = new RpmProtocol();
        RPM_Protocol__mdt rec = testRecord;
        if (rec == null && !Test.isRunningTest()) {
            for (RPM_Protocol__mdt m : RPM_Protocol__mdt.getAll().values()) {
                if (m.Active__c) {
                    rec = m;
                    break;
                }
            }
        }
        if (rec != null) {
            p.apply(rec);
        }
        cached = p;
        return p;
    }

    @TestVisible
    private static void reset() {
        cached = null;
    }

    public Datetime dueAt(String severity, Datetime fromTime) {
        if (severity == 'Critical') {
            return fromTime.addMinutes(criticalSlaMinutes.intValue());
        }
        if (severity == 'Urgent') {
            return fromTime.addHours(urgentSlaHours.intValue());
        }
        return fromTime.addHours(routineSlaHours.intValue());
    }

    private void apply(RPM_Protocol__mdt m) {
        version = String.isBlank(m.Version__c) ? version : m.Version__c;
        alertSystolic = nz(m.Alert_Systolic__c, alertSystolic);
        criticalSystolic = nz(m.Critical_Systolic__c, criticalSystolic);
        lowSystolic = nz(m.Low_Systolic__c, lowSystolic);
        criticalSlaMinutes = nz(m.Critical_SLA_Minutes__c, criticalSlaMinutes);
        urgentSlaHours = nz(m.Urgent_SLA_Hours__c, urgentSlaHours);
        routineSlaHours = nz(m.Routine_SLA_Hours__c, routineSlaHours);
        trendWindowDays = nz(m.Trend_Window_Days__c, trendWindowDays);
        trendRiseSystolic = nz(m.Trend_Rise_Systolic__c, trendRiseSystolic);
        silentDays = nz(m.Silent_Days__c, silentDays);
        lowBatteryPercent = nz(m.Low_Battery_Percent__c, lowBatteryPercent);
    }

    private static Decimal nz(Decimal value, Decimal fallback) {
        return value == null ? fallback : value;
    }
}
