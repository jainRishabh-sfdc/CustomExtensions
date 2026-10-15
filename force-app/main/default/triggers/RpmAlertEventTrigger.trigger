/**
 * Description    : Blocks updates and deletes on alert history (RPM_Alert_Event__c).
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Alert history is the permanent audit record. It can be added to, never changed or removed.
 */
trigger RpmAlertEventTrigger on RPM_Alert_Event__c(before update, before delete) {
    List<RPM_Alert_Event__c> rows = Trigger.isDelete ? Trigger.old : Trigger.new;
    for (RPM_Alert_Event__c e : rows) {
        e.addError('Alert history is permanent and cannot be changed or deleted.');
    }
}
