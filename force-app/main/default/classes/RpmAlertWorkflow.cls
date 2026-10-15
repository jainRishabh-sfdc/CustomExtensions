/**
 * Description    : Moves alerts through the six-step workflow and logs every step.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * The six-step alert workflow:
 *   New -> Checked -> Assigned -> Patient Called -> Provider Reviewed -> Closed
 *
 * Steps cannot be skipped. A Critical alert cannot leave "Assigned" until the
 * call record (outcome, symptoms, provider notified) is complete.
 * Device alerts may be closed from any open step once fixed.
 * Every move writes an append-only RPM_Alert_Event__c row.
 */
public with sharing class RpmAlertWorkflow {
    public static final List<String> STEPS = new List<String>{
        'New', 'Checked', 'Assigned', 'Patient Called', 'Provider Reviewed', 'Closed'
    };

    public class WorkflowException extends Exception {
    }

    public static void markChecked(Id alertId, String note) {
        RPM_Alert__c a = load(alertId);
        move(a, 'New', 'Checked', String.isBlank(note) ? 'Reading checked' : note);
    }

    public static void assign(Id alertId, Id userId) {
        if (userId == null) {
            throw new WorkflowException('Choose who owns this alert.');
        }
        RPM_Alert__c a = load(alertId);
        a.Assigned_To__c = userId;
        move(a, 'Checked', 'Assigned', 'Assigned to user ' + userId);
    }

    public static void recordCall(Id alertId, String outcome, String symptoms, String providerNotified, String note) {
        RPM_Alert__c a = load(alertId);
        if (String.isBlank(outcome)) {
            throw new WorkflowException('Record whether the patient was reached.');
        }
        if (a.Severity__c == 'Critical' && (String.isBlank(symptoms) || String.isBlank(providerNotified))) {
            throw new WorkflowException('Critical alert: answer all three call questions (reached, symptoms, provider notified).');
        }
        a.Call_Outcome__c = outcome;
        a.Symptoms__c = symptoms;
        a.Provider_Notified__c = providerNotified;
        String detail = 'Call: ' + outcome;
        if (!String.isBlank(symptoms)) {
            detail += ' | Symptoms: ' + symptoms;
        }
        if (!String.isBlank(providerNotified)) {
            detail += ' | Provider: ' + providerNotified;
        }
        if (!String.isBlank(note)) {
            detail += ' | ' + note;
        }
        move(a, 'Assigned', 'Patient Called', detail);
    }

    public static void providerReviewed(Id alertId, String note) {
        RPM_Alert__c a = load(alertId);
        move(a, 'Patient Called', 'Provider Reviewed', String.isBlank(note) ? 'Provider reviewed' : note);
    }

    public static void close(Id alertId, String disposition) {
        if (String.isBlank(disposition)) {
            throw new WorkflowException('Choose what was done before closing.');
        }
        RPM_Alert__c a = load(alertId);
        a.Disposition__c = disposition;
        a.Closed_At__c = RpmClock.now();
        move(a, 'Provider Reviewed', 'Closed', 'Closed: ' + disposition);
    }

    public static void closeDeviceAlert(Id alertId, String note) {
        RPM_Alert__c a = load(alertId);
        if (a.Category__c != 'Device') {
            throw new WorkflowException('Only device alerts can be closed directly. Health alerts must walk all six steps.');
        }
        a.Disposition__c = 'Device fixed';
        a.Closed_At__c = RpmClock.now();
        move(a, a.Step__c, 'Closed', String.isBlank(note) ? 'Device issue resolved' : note);
    }

    private static RPM_Alert__c load(Id alertId) {
        List<RPM_Alert__c> rows = [
            SELECT Id, Step__c, Severity__c, Category__c, Call_Outcome__c, Assigned_To__c, Patient__c
            FROM RPM_Alert__c
            WHERE Id = :alertId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new WorkflowException('Alert not found or not accessible.');
        }
        return rows[0];
    }

    private static void move(RPM_Alert__c a, String expectedFrom, String toStep, String detail) {
        if (a.Step__c == 'Closed') {
            throw new WorkflowException('This alert is already closed.');
        }
        if (a.Step__c != expectedFrom) {
            throw new WorkflowException('This alert is at "' + a.Step__c + '". Next step is "' + nextStep(a.Step__c) + '".');
        }
        String fromStep = a.Step__c;
        a.Step__c = toStep;
        Database.update(a, true, AccessLevel.USER_MODE);
        Database.insert(new RPM_Alert_Event__c(
            Alert__c = a.Id,
            From_Step__c = fromStep,
            To_Step__c = toStep,
            Detail__c = detail == null ? null : detail.left(255),
            Actor__c = UserInfo.getUserId(),
            Occurred_At__c = RpmClock.now()
        ), true, AccessLevel.USER_MODE);
        if (toStep == 'Closed' && a.Patient__c != null) {
            RpmRiskService.refresh(new Set<Id>{ a.Patient__c });
        }
    }

    public static String nextStep(String current) {
        Integer i = STEPS.indexOf(current);
        return (i < 0 || i >= STEPS.size() - 1) ? current : STEPS[i + 1];
    }
}
