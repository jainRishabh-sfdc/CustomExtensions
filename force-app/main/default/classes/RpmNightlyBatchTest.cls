/**
 * Description    : Unit tests for RpmNightlyBatch.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
@IsTest
private class RpmNightlyBatchTest {
    @IsTest
    static void sweepRaisesDeviceAlertsBillingAndRisk() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RPM_Device__c d = RpmTestFactory.assignedDevice(p, '111');
        d.Last_Reading_At__c = RpmTestFactory.NOW.addDays(-20);
        d.Battery_Percent__c = 18;
        update d;

        Test.startTest();
        Database.executeBatch(new RpmNightlyBatch(), 100);
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM RPM_Alert__c WHERE Category__c = 'Device']);
        System.assertEquals(1, [SELECT COUNT() FROM RPM_Billing_Period__c WHERE Patient__c = :p.Id]);
        RPM_Patient__c after = [SELECT Risk_Level__c, Risk_Reasons__c FROM RPM_Patient__c WHERE Id = :p.Id];
        System.assertEquals('YELLOW', after.Risk_Level__c, 'silent 15 + battery 10 = 25');
        System.assert(after.Risk_Reasons__c.contains('Device silent'));
    }

    @IsTest
    static void schedulableQueuesBatch() {
        Test.startTest();
        String jobId = System.schedule('RPM nightly test', '0 0 2 * * ?', new RpmNightlyBatch());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}
