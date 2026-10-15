/**
 * Description    : Computes each patient's GREEN / YELLOW / RED risk level.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Computes the GREEN / YELLOW / RED risk level shown on the patient roster.
 *
 * Runs without sharing on purpose: risk is a system-computed field that must
 * stay correct no matter which user's action triggered the refresh (a nurse
 * closing an alert, the device gateway posting a reading). It only writes
 * Risk_Level__c, Risk_Reasons__c and Last_Reading_At__c.
 *
 * Scoring (tune with the client's clinical team):
 *   open Critical health alert -> always RED
 *   open Urgent health alert   +10 each
 *   open Routine health alert  +5 each
 *   device silent              +15
 *   device battery low         +10
 *   score >= 50 RED, >= 20 YELLOW, else GREEN
 */
public without sharing class RpmRiskService {
    public class Assessment {
        public String level;
        public Integer score = 0;
        public List<String> reasons = new List<String>();
    }

    public static void refresh(Set<Id> patientIds) {
        if (patientIds == null || patientIds.isEmpty()) {
            return;
        }
        List<RPM_Patient__c> patients = [
            SELECT Id, Risk_Level__c, Risk_Reasons__c,
                (SELECT Category__c, Severity__c, Rule__c FROM Alerts__r WHERE Step__c != 'Closed')
            FROM RPM_Patient__c
            WHERE Id IN :patientIds
        ];
        List<RPM_Patient__c> changed = new List<RPM_Patient__c>();
        for (RPM_Patient__c p : patients) {
            Assessment a = assess(p.Alerts__r);
            String reasons = a.reasons.isEmpty() ? null : String.join(a.reasons, '; ').left(255);
            if (p.Risk_Level__c != a.level || p.Risk_Reasons__c != reasons) {
                changed.add(new RPM_Patient__c(Id = p.Id, Risk_Level__c = a.level, Risk_Reasons__c = reasons));
            }
        }
        if (!changed.isEmpty()) {
            update changed;
        }
    }

    public static void stampLastReading(Map<Id, Datetime> lastByPatient) {
        if (lastByPatient == null || lastByPatient.isEmpty()) {
            return;
        }
        List<RPM_Patient__c> updates = new List<RPM_Patient__c>();
        for (RPM_Patient__c p : [
            SELECT Id, Last_Reading_At__c FROM RPM_Patient__c WHERE Id IN :lastByPatient.keySet()
        ]) {
            Datetime incoming = lastByPatient.get(p.Id);
            if (p.Last_Reading_At__c == null || incoming > p.Last_Reading_At__c) {
                updates.add(new RPM_Patient__c(Id = p.Id, Last_Reading_At__c = incoming));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    @TestVisible
    private static Assessment assess(List<RPM_Alert__c> openAlerts) {
        Assessment a = new Assessment();
        Boolean critical = false;
        for (RPM_Alert__c al : openAlerts) {
            if (al.Category__c == 'Health') {
                if (al.Severity__c == 'Critical') {
                    critical = true;
                    a.score += 25;
                    a.reasons.add('Critical alert open');
                } else if (al.Severity__c == 'Urgent') {
                    a.score += 10;
                    a.reasons.add(al.Rule__c + ' alert open');
                } else {
                    a.score += 5;
                    a.reasons.add(al.Rule__c + ' alert open');
                }
            } else if (al.Rule__c == RpmAlertEngine.RULE_SILENT) {
                a.score += 15;
                a.reasons.add('Device silent');
            } else if (al.Rule__c == RpmAlertEngine.RULE_BATTERY) {
                a.score += 10;
                a.reasons.add('Battery low');
            }
        }
        a.level = (critical || a.score >= 50) ? 'RED' : (a.score >= 20 ? 'YELLOW' : 'GREEN');
        return a;
    }
}
