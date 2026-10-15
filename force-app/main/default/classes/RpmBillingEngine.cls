/**
 * Description    : Works out the RPM CPT codes each patient is eligible for in a billing period.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Works out which RPM CPT codes a patient is eligible for in a billing period.
 *
 * RULES_VERSION CPT-2026.1 (CY2026 Medicare Physician Fee Schedule):
 *   99453  one-time device setup/education     -> 2+ reading days, once per episode
 *   99454  device supply, 30 days              -> 16+ reading days
 *   99445  device supply, 30 days              -> 2-15 reading days
 *   99470  treatment management, first 10 min  -> 10-19 min with interactive communication
 *   99457  treatment management, first 20 min  -> 20+ min with interactive communication
 *   99458  each additional 20 min              -> per full 20 min beyond the first 20
 *
 * IMPORTANT: re-verify these against the CY2027 final rule and each commercial
 * payer's policy before go-live. Commercial payers often still use the older
 * 16-day / 20-minute-only rules; make per-payer overrides the next iteration.
 *
 * Nothing is produced when the patient is billing-locked (double-billing guard,
 * e.g. paid through the CMS ACCESS model) or has no RPM consent on file.
 */
public with sharing class RpmBillingEngine {
    public static final String RULES_VERSION = 'CPT-2026.1';

    public class Summary {
        public Integer readingDays = 0;
        public Decimal minutes = 0;
        public Boolean interactive = false;
        public List<String> codes = new List<String>();
        public String blockedReason;
        public String status;
    }

    /** Pure rule evaluation, no database access. */
    public static Summary evaluate(RPM_Patient__c p, Integer readingDays, Decimal minutes, Boolean interactive, Boolean periodEnded) {
        Summary s = new Summary();
        s.readingDays = readingDays == null ? 0 : readingDays;
        s.minutes = minutes == null ? 0 : minutes;
        s.interactive = interactive == true;

        if (p.Billing_Locked__c) {
            s.blockedReason = 'Billing locked' + (String.isBlank(p.Billing_Lock_Reason__c) ? '' : ': ' + p.Billing_Lock_Reason__c);
            s.status = 'Blocked';
            return s;
        }
        if (p.Consent_Date__c == null) {
            s.blockedReason = 'No RPM consent on file';
            s.status = 'Blocked';
            return s;
        }

        if (!p.Setup_Billed__c && s.readingDays >= 2) {
            s.codes.add('99453');
        }
        if (s.readingDays >= 16) {
            s.codes.add('99454');
        } else if (s.readingDays >= 2) {
            s.codes.add('99445');
        }

        if (s.interactive) {
            if (s.minutes >= 20) {
                s.codes.add('99457');
                Integer extra = ((s.minutes - 20) / 20).intValue();
                if (extra > 0) {
                    s.codes.add('99458x' + extra);
                }
            } else if (s.minutes >= 10) {
                s.codes.add('99470');
            }
        }

        s.status = s.codes.isEmpty() ? 'Accruing' : (periodEnded ? 'Ready to Bill' : 'Accruing');
        return s;
    }

    /** Calendar-month period containing the given date. */
    public static Date periodStart(Date d) {
        return d.toStartOfMonth();
    }

    public static Date periodEnd(Date d) {
        return d.toStartOfMonth().addMonths(1).addDays(-1);
    }

    /**
     * Recalculates and upserts one RPM_Billing_Period__c per patient for the
     * month containing asOf.
     */
    public static List<RPM_Billing_Period__c> recalculate(Set<Id> patientIds, Date asOf) {
        List<RPM_Billing_Period__c> out = new List<RPM_Billing_Period__c>();
        if (patientIds == null || patientIds.isEmpty()) {
            return out;
        }
        Date startD = periodStart(asOf);
        Date endD = periodEnd(asOf);
        Datetime startDt = Datetime.newInstance(startD, Time.newInstance(0, 0, 0, 0));
        Datetime endDt = Datetime.newInstance(endD.addDays(1), Time.newInstance(0, 0, 0, 0));
        Boolean ended = RpmClock.today() > endD;

        Map<Id, Integer> days = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Patient__c pid, DAY_ONLY(convertTimezone(Measured_At__c)) d
            FROM RPM_Reading__c
            WHERE Patient__c IN :patientIds AND Match_Status__c = 'Matched'
                AND Measured_At__c >= :startDt AND Measured_At__c < :endDt
            WITH USER_MODE
            GROUP BY Patient__c, DAY_ONLY(convertTimezone(Measured_At__c))
        ]) {
            Id pid = (Id) ar.get('pid');
            days.put(pid, (days.containsKey(pid) ? days.get(pid) : 0) + 1);
        }

        Map<Id, Decimal> mins = new Map<Id, Decimal>();
        Set<Id> interactive = new Set<Id>();
        for (RPM_Time_Entry__c t : [
            SELECT Patient__c, Minutes__c, Interactive__c
            FROM RPM_Time_Entry__c
            WHERE Patient__c IN :patientIds AND Entry_Date__c >= :startD AND Entry_Date__c <= :endD
            WITH USER_MODE
        ]) {
            mins.put(t.Patient__c, (mins.containsKey(t.Patient__c) ? mins.get(t.Patient__c) : 0) + t.Minutes__c);
            if (t.Interactive__c) {
                interactive.add(t.Patient__c);
            }
        }

        // Never overwrite a period that has already been billed
        Set<Id> alreadyBilled = new Set<Id>();
        for (RPM_Billing_Period__c bp : [
            SELECT Patient__c
            FROM RPM_Billing_Period__c
            WHERE Patient__c IN :patientIds AND Period_Start__c = :startD AND Status__c = 'Billed'
            WITH USER_MODE
        ]) {
            alreadyBilled.add(bp.Patient__c);
        }

        for (RPM_Patient__c p : [
            SELECT Id, Billing_Locked__c, Billing_Lock_Reason__c, Consent_Date__c, Setup_Billed__c
            FROM RPM_Patient__c
            WHERE Id IN :patientIds
            WITH USER_MODE
        ]) {
            if (alreadyBilled.contains(p.Id)) {
                continue;
            }
            Summary s = evaluate(p, days.get(p.Id), mins.get(p.Id), interactive.contains(p.Id), ended);
            out.add(new RPM_Billing_Period__c(
                Patient__c = p.Id,
                Period_Key__c = p.Id + ':' + String.valueOf(startD),
                Period_Start__c = startD,
                Period_End__c = endD,
                Reading_Days__c = s.readingDays,
                Care_Minutes__c = s.minutes,
                Interactive_Done__c = s.interactive,
                Codes__c = s.codes.isEmpty() ? null : String.join(s.codes, ','),
                Blocked_Reason__c = s.blockedReason,
                Status__c = s.status,
                Rules_Version__c = RULES_VERSION
            ));
        }
        if (!out.isEmpty()) {
            Database.upsert(out, RPM_Billing_Period__c.Period_Key__c, true, AccessLevel.USER_MODE);
        }
        return out;
    }
}
