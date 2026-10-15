/**
 * Description    : Unit tests for RpmReadingService.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
@IsTest
private class RpmReadingServiceTest {
    @IsTest
    static void matchesReadingToPatientAndUpdatesDevice() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RPM_Device__c d = RpmTestFactory.assignedDevice(p, '111');

        Test.startTest();
        RpmReadingService.IngestResult res = RpmReadingService.ingest(new List<RpmReadingInput>{
            RpmTestFactory.bp('e1', '111', RpmTestFactory.NOW.addHours(-2), 128, 80)
        });
        Test.stopTest();

        System.assertEquals(1, res.created, 'one reading stored');
        System.assertEquals(0, res.alertsRaised, 'normal reading raises no alert');
        RPM_Reading__c r = [SELECT Patient__c, Match_Status__c, Raw_Payload__c FROM RPM_Reading__c];
        System.assertEquals(p.Id, r.Patient__c);
        System.assertEquals('Matched', r.Match_Status__c);
        System.assert(r.Raw_Payload__c.contains('"imei":"111"'), 'raw payload kept');
        RPM_Device__c dev = [SELECT Battery_Percent__c, Last_Reading_At__c FROM RPM_Device__c WHERE Id = :d.Id];
        System.assertEquals(80, dev.Battery_Percent__c);
        System.assertEquals(RpmTestFactory.NOW.addHours(-2), dev.Last_Reading_At__c);
        System.assertEquals('GREEN', [SELECT Risk_Level__c FROM RPM_Patient__c WHERE Id = :p.Id].Risk_Level__c);
    }

    @IsTest
    static void dropsDuplicateEvents() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RpmTestFactory.assignedDevice(p, '111');
        RpmReadingInput r = RpmTestFactory.bp('dup', '111', RpmTestFactory.NOW.addHours(-1), 120, 75);

        RpmReadingService.IngestResult first = RpmReadingService.ingest(new List<RpmReadingInput>{ r, r });
        RpmReadingService.IngestResult second = RpmReadingService.ingest(new List<RpmReadingInput>{ r });

        System.assertEquals(1, first.created);
        System.assertEquals(1, first.duplicates, 'in-batch duplicate dropped');
        System.assertEquals(0, second.created);
        System.assertEquals(1, second.duplicates, 'already-stored event dropped');
        System.assertEquals(1, [SELECT COUNT() FROM RPM_Reading__c]);
    }

    @IsTest
    static void keepsUnknownDeviceReadings() {
        RpmTestFactory.freezeClock();
        RpmReadingService.IngestResult res = RpmReadingService.ingest(new List<RpmReadingInput>{
            RpmTestFactory.bp('e9', '999', RpmTestFactory.NOW.addHours(-1), 120, 75)
        });
        System.assertEquals(1, res.created);
        System.assertEquals(1, res.unmatched);
        System.assertEquals('Unknown Device', [SELECT Match_Status__c FROM RPM_Reading__c].Match_Status__c);
    }

    @IsTest
    static void readingBeforeAssignmentIsNotMatched() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RpmTestFactory.assignedDevice(p, '111'); // assigned from NOW-60d
        RpmReadingService.IngestResult res = RpmReadingService.ingest(new List<RpmReadingInput>{
            RpmTestFactory.bp('old', '111', RpmTestFactory.NOW.addDays(-90), 120, 75)
        });
        System.assertEquals(1, res.unmatched);
        System.assertEquals('No Active Assignment', [SELECT Match_Status__c FROM RPM_Reading__c].Match_Status__c);
    }

    @IsTest
    static void rejectsInvalidItems() {
        RpmTestFactory.freezeClock();
        RpmReadingInput noImei = RpmTestFactory.bp('a', null, RpmTestFactory.NOW, 120, 80);
        RpmReadingInput future = RpmTestFactory.bp('b', '1', RpmTestFactory.NOW.addDays(2), 120, 80);
        RpmReadingInput absurd = RpmTestFactory.bp('c', '1', RpmTestFactory.NOW, 900, 80);
        RpmReadingService.IngestResult res = RpmReadingService.ingest(new List<RpmReadingInput>{ noImei, future, absurd });
        System.assertEquals(3, res.errors.size());
        System.assertEquals(0, res.created);
    }

    @IsTest
    static void criticalReadingRaisesAlertAndRedRisk() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RpmTestFactory.assignedDevice(p, '111');

        RpmReadingService.IngestResult res = RpmReadingService.ingest(new List<RpmReadingInput>{
            RpmTestFactory.bp('crit', '111', RpmTestFactory.NOW.addMinutes(-5), 181, 112)
        });

        System.assertEquals(1, res.alertsRaised);
        RPM_Alert__c a = [SELECT Severity__c, Rule__c, Step__c, Protocol_Version__c, Due_At__c, Summary__c FROM RPM_Alert__c];
        System.assertEquals('Critical', a.Severity__c);
        System.assertEquals(RpmAlertEngine.RULE_CRITICAL, a.Rule__c);
        System.assertEquals('New', a.Step__c);
        System.assertEquals('1.0-default', a.Protocol_Version__c);
        System.assertEquals(RpmTestFactory.NOW.addMinutes(60), a.Due_At__c, '60-minute critical SLA');
        System.assert(a.Summary__c.contains('181/112'));
        System.assertEquals(1, [SELECT COUNT() FROM RPM_Alert_Event__c], 'raise is logged');
        System.assertEquals('RED', [SELECT Risk_Level__c FROM RPM_Patient__c WHERE Id = :p.Id].Risk_Level__c);
    }
}
