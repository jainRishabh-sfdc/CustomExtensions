/**
 * Description    : Unit tests for RpmAlertEngine.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
@IsTest
private class RpmAlertEngineTest {
    @IsTest
    static void highAndLowReadingsRaiseUrgentAlerts() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RpmTestFactory.assignedDevice(p, '111');

        RpmReadingService.ingest(new List<RpmReadingInput>{
            RpmTestFactory.bp('hi', '111', RpmTestFactory.NOW.addHours(-3), 161, 92),
            RpmTestFactory.bp('lo', '111', RpmTestFactory.NOW.addHours(-2), 84, 50),
            RpmTestFactory.bp('ok', '111', RpmTestFactory.NOW.addHours(-1), 150, 100) // exactly 150 = not above the line; diastolic never alerts
        });

        Map<String, RPM_Alert__c> byRule = new Map<String, RPM_Alert__c>();
        for (RPM_Alert__c a : [SELECT Rule__c, Severity__c, Due_At__c FROM RPM_Alert__c]) {
            byRule.put(a.Rule__c, a);
        }
        System.assertEquals(2, byRule.size());
        System.assertEquals('Urgent', byRule.get(RpmAlertEngine.RULE_HIGH).Severity__c);
        System.assertEquals('Urgent', byRule.get(RpmAlertEngine.RULE_LOW).Severity__c);
        System.assertEquals(RpmTestFactory.NOW.addHours(4), byRule.get(RpmAlertEngine.RULE_HIGH).Due_At__c);
    }

    @IsTest
    static void risingTrendRaisesOneRoutineAlert() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RpmTestFactory.assignedDevice(p, '111');
        List<RpmReadingInput> prior = new List<RpmReadingInput>();
        for (Integer i = 0; i < 4; i++) {
            prior.add(RpmTestFactory.bp('p' + i, '111', RpmTestFactory.NOW.addDays(-20 - i), 125, 80));
        }
        RpmReadingService.ingest(prior);
        List<RpmReadingInput> recent = new List<RpmReadingInput>();
        for (Integer i = 0; i < 4; i++) {
            recent.add(RpmTestFactory.bp('c' + i, '111', RpmTestFactory.NOW.addDays(-1 - i), 134, 82));
        }
        RpmReadingService.ingest(recent);
        // a second batch must not open a second trend alert
        RpmReadingService.ingest(new List<RpmReadingInput>{ RpmTestFactory.bp('c9', '111', RpmTestFactory.NOW.addHours(-1), 135, 82) });

        List<RPM_Alert__c> trend = [SELECT Severity__c FROM RPM_Alert__c WHERE Rule__c = :RpmAlertEngine.RULE_TREND];
        System.assertEquals(1, trend.size());
        System.assertEquals('Routine', trend[0].Severity__c);
    }

    @IsTest
    static void silentDeviceAndLowBattery() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RPM_Device__c d = RpmTestFactory.assignedDevice(p, '111');
        d.Last_Reading_At__c = RpmTestFactory.NOW.addDays(-20);
        d.Battery_Percent__c = 18;
        update d;
        RPM_Device__c loaded = [SELECT Id, Status__c, Current_Patient__c, Last_Reading_At__c, Battery_Percent__c FROM RPM_Device__c WHERE Id = :d.Id];

        List<RPM_Alert__c> first = RpmAlertEngine.evaluateDevices(new List<RPM_Device__c>{ loaded });
        List<RPM_Alert__c> again = RpmAlertEngine.evaluateDevices(new List<RPM_Device__c>{ loaded });

        System.assertEquals(2, first.size(), 'silent + battery');
        System.assertEquals(0, again.size(), 'dedupe key prevents repeats');
        RPM_Alert__c silent = [SELECT Summary__c, Severity__c FROM RPM_Alert__c WHERE Rule__c = :RpmAlertEngine.RULE_SILENT];
        System.assertEquals('Urgent', silent.Severity__c);
        System.assert(silent.Summary__c.contains('20 days'), silent.Summary__c);
    }

    @IsTest
    static void customProtocolIsUsed() {
        RpmClock.fixedNow = RpmTestFactory.NOW;
        RpmProtocol.reset();
        RpmProtocol.testRecord = new RPM_Protocol__mdt(Version__c = '2.2-draft', Active__c = true, Alert_Systolic__c = 140, Critical_Systolic__c = 180);
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RpmTestFactory.assignedDevice(p, '111');

        RpmReadingService.ingest(new List<RpmReadingInput>{ RpmTestFactory.bp('x', '111', RpmTestFactory.NOW.addHours(-1), 145, 85) });

        RPM_Alert__c a = [SELECT Rule__c, Protocol_Version__c FROM RPM_Alert__c];
        System.assertEquals(RpmAlertEngine.RULE_HIGH, a.Rule__c);
        System.assertEquals('2.2-draft', a.Protocol_Version__c);
    }
}
