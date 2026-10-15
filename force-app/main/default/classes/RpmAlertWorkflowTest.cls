/**
 * Description    : Unit tests for RpmAlertWorkflow.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
@IsTest
private class RpmAlertWorkflowTest {
    static RPM_Alert__c raise(Integer sys) {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RpmTestFactory.assignedDevice(p, '111');
        RpmReadingService.ingest(new List<RpmReadingInput>{ RpmTestFactory.bp('e', '111', RpmTestFactory.NOW.addMinutes(-5), sys, 100) });
        return [SELECT Id, Patient__c FROM RPM_Alert__c LIMIT 1];
    }

    @IsTest
    static void criticalAlertWalksAllSixSteps() {
        RPM_Alert__c a = raise(185);

        RpmAlertWorkflow.markChecked(a.Id, null);
        RpmAlertWorkflow.assign(a.Id, UserInfo.getUserId());
        RpmAlertWorkflow.recordCall(a.Id, 'Spoke with patient', 'None reported', 'Yes - primary provider', 'Recheck 168/98');
        RpmAlertWorkflow.providerReviewed(a.Id, null);
        RpmAlertWorkflow.close(a.Id, 'Recheck scheduled');

        RPM_Alert__c done = [SELECT Step__c, Disposition__c, Closed_At__c, Call_Outcome__c FROM RPM_Alert__c WHERE Id = :a.Id];
        System.assertEquals('Closed', done.Step__c);
        System.assertEquals('Recheck scheduled', done.Disposition__c);
        System.assertNotEquals(null, done.Closed_At__c);
        System.assertEquals(6, [SELECT COUNT() FROM RPM_Alert_Event__c WHERE Alert__c = :a.Id], 'raise + 5 moves logged');
        System.assertEquals('GREEN', [SELECT Risk_Level__c FROM RPM_Patient__c WHERE Id = :a.Patient__c].Risk_Level__c, 'risk drops after close');
    }

    @IsTest
    static void criticalCallNeedsAllThreeAnswers() {
        RPM_Alert__c a = raise(185);
        RpmAlertWorkflow.markChecked(a.Id, null);
        RpmAlertWorkflow.assign(a.Id, UserInfo.getUserId());
        try {
            RpmAlertWorkflow.recordCall(a.Id, 'Spoke with patient', null, null, null);
            System.assert(false, 'should have thrown');
        } catch (RpmAlertWorkflow.WorkflowException e) {
            System.assert(e.getMessage().contains('three'), e.getMessage());
        }
        System.assertEquals('Assigned', [SELECT Step__c FROM RPM_Alert__c WHERE Id = :a.Id].Step__c);
    }

    @IsTest
    static void urgentCallNeedsOnlyOutcome() {
        RPM_Alert__c a = raise(160);
        RpmAlertWorkflow.markChecked(a.Id, null);
        RpmAlertWorkflow.assign(a.Id, UserInfo.getUserId());
        RpmAlertWorkflow.recordCall(a.Id, 'Left voicemail', null, null, null);
        System.assertEquals('Patient Called', [SELECT Step__c FROM RPM_Alert__c WHERE Id = :a.Id].Step__c);
    }

    @IsTest
    static void stepsCannotBeSkipped() {
        RPM_Alert__c a = raise(185);
        try {
            RpmAlertWorkflow.close(a.Id, 'No change needed');
            System.assert(false, 'should have thrown');
        } catch (RpmAlertWorkflow.WorkflowException e) {
            System.assert(e.getMessage().contains('Checked'), e.getMessage());
        }
    }

    @IsTest
    static void healthAlertCannotUseDeviceShortcut() {
        RPM_Alert__c a = raise(185);
        try {
            RpmAlertWorkflow.closeDeviceAlert(a.Id, null);
            System.assert(false, 'should have thrown');
        } catch (RpmAlertWorkflow.WorkflowException e) {
            System.assert(e.getMessage().contains('six steps'), e.getMessage());
        }
    }

    @IsTest
    static void historyAndAlertsAreImmutable() {
        RPM_Alert__c a = raise(185);
        RPM_Alert_Event__c ev = [SELECT Id, Detail__c FROM RPM_Alert_Event__c LIMIT 1];
        ev.Detail__c = 'tampered';
        Database.SaveResult upd = Database.update(ev, false);
        System.assert(!upd.isSuccess(), 'event update blocked');
        Database.DeleteResult del = Database.delete(ev, false);
        System.assert(!del.isSuccess(), 'event delete blocked');
        Database.DeleteResult delAlert = Database.delete(a, false);
        System.assert(!delAlert.isSuccess(), 'alert delete blocked');
    }

    @IsTest
    static void nextStepHelper() {
        System.assertEquals('Checked', RpmAlertWorkflow.nextStep('New'));
        System.assertEquals('Closed', RpmAlertWorkflow.nextStep('Closed'));
    }
}
