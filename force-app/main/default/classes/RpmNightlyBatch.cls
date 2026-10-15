/**
 * Description    : Nightly batch: raises device alerts, recalculates billing and refreshes risk.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Nightly sweep over enrolled patients:
 *   1. raise device alerts (silent cuff, low battery)
 *   2. recalculate this month's billing period (and last month's in the first 5 days)
 *   3. refresh risk level
 *
 * Schedule once from Anonymous Apex:
 *   System.schedule('RPM nightly', '0 0 2 * * ?', new RpmNightlyBatch());
 */
public with sharing class RpmNightlyBatch implements Database.Batchable<SObject>, Schedulable {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id FROM RPM_Patient__c WHERE Status__c = 'Enrolled' WITH USER_MODE
        ]);
    }

    public void execute(Database.BatchableContext bc, List<RPM_Patient__c> scope) {
        Set<Id> ids = new Map<Id, RPM_Patient__c>(scope).keySet();

        List<RPM_Device__c> devices = [
            SELECT Id, Status__c, Current_Patient__c, Last_Reading_At__c, Battery_Percent__c
            FROM RPM_Device__c
            WHERE Current_Patient__c IN :ids AND Status__c = 'Assigned'
            WITH USER_MODE
        ];
        RpmAlertEngine.evaluateDevices(devices);

        Date today = RpmClock.today();
        RpmBillingEngine.recalculate(ids, today);
        if (today.day() <= 5) {
            // late-arriving readings and time entries for last month
            RpmBillingEngine.recalculate(ids, today.toStartOfMonth().addDays(-1));
        }

        RpmRiskService.refresh(ids);
    }

    public void finish(Database.BatchableContext bc) {
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new RpmNightlyBatch(), 100);
    }
}
