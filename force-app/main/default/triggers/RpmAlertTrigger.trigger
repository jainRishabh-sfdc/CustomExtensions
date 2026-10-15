/**
 * Description    : Blocks deletion of alerts (RPM_Alert__c).
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Alerts are audit records: they are closed, never deleted.
 * (Deleting an alert would also cascade-delete its permanent history.)
 */
trigger RpmAlertTrigger on RPM_Alert__c(before delete) {
    for (RPM_Alert__c a : Trigger.old) {
        a.addError('Alerts cannot be deleted. Close the alert with a disposition instead.');
    }
}
