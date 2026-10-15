/**
 * Description    : Unit tests for RpmConsoleController.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
@IsTest
private class RpmConsoleControllerTest {
    static RPM_Patient__c setupCritical() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RpmTestFactory.assignedDevice(p, '111');
        RpmReadingService.ingest(new List<RpmReadingInput>{
            RpmTestFactory.bp('a', '111', RpmTestFactory.NOW.addDays(-2), 128, 80),
            RpmTestFactory.bp('b', '111', RpmTestFactory.NOW.addMinutes(-5), 185, 110)
        });
        return p;
    }

    @IsTest
    static void todayShowsCriticalFirst() {
        setupCritical();
        Map<String, Object> t = RpmConsoleController.getToday();
        System.assertEquals(1, t.get('critical'));
        System.assertEquals(1, t.get('redPatients'));
        System.assertEquals(1, t.get('patients'));
        List<Map<String, Object>> todo = (List<Map<String, Object>>) t.get('todo');
        System.assertEquals('Critical', todo[0].get('severity'));
    }

    @IsTest
    static void patientListAndDetail() {
        RPM_Patient__c p = setupCritical();
        System.assertEquals(1, RpmConsoleController.getPatients(null).size());
        System.assertEquals(1, RpmConsoleController.getPatients('RED').size());
        System.assertEquals(0, RpmConsoleController.getPatients('GREEN').size());

        Map<String, Object> d = RpmConsoleController.getPatientDetail(p.Id, 30);
        List<Map<String, Object>> readings = (List<Map<String, Object>>) d.get('readings');
        System.assertEquals(2, readings.size());
        System.assertEquals('critical', readings[1].get('flag'));
        System.assertEquals(1, ((List<Object>) d.get('devices')).size());
        System.assertEquals(1, ((List<Object>) d.get('alerts')).size());
        System.assertNotEquals(null, d.get('billing'));
    }

    @IsTest
    static void logTimeFeedsBilling() {
        RPM_Patient__c p = setupCritical();
        RpmConsoleController.logTime(p.Id, 22, 'Phone call with patient', true, 'Reviewed high reading');
        Map<String, Object> d = RpmConsoleController.getPatientDetail(p.Id, 30);
        Map<String, Object> billing = (Map<String, Object>) d.get('billing');
        System.assertEquals(22, billing.get('minutes'));
        System.assert(((String) billing.get('codes')).contains('99457'));
        try {
            RpmConsoleController.logTime(p.Id, 0, null, false, null);
            System.assert(false, 'should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('between'));
        }
    }

    @IsTest
    static void alertActionsWalkWorkflow() {
        setupCritical();
        Id alertId = [SELECT Id FROM RPM_Alert__c LIMIT 1].Id;
        RpmConsoleController.checkAlert(alertId, null);
        RpmConsoleController.assignAlert(alertId, UserInfo.getUserId());
        try {
            RpmConsoleController.recordCall(alertId, 'Spoke with patient', null, null, null);
            System.assert(false, 'should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('three'), e.getMessage());
        }
        RpmConsoleController.recordCall(alertId, 'Spoke with patient', 'None reported', 'Yes - primary provider', null);
        RpmConsoleController.reviewAlert(alertId, null);
        RpmConsoleController.closeAlert(alertId, 'Recheck scheduled');

        System.assertEquals(0, RpmConsoleController.getAlerts('open').size());
        List<Map<String, Object>> closed = RpmConsoleController.getAlerts('closed');
        System.assertEquals(1, closed.size());
        System.assertEquals(6, ((List<Object>) closed[0].get('history')).size());
        System.assertNotEquals(null, RpmConsoleController.getTeam());
    }

    @IsTest
    static void alertFilters() {
        setupCritical();
        System.assertEquals(1, RpmConsoleController.getAlerts('critical').size());
        System.assertEquals(1, RpmConsoleController.getAlerts('health').size());
        System.assertEquals(0, RpmConsoleController.getAlerts('device').size());
    }

    @IsTest
    static void deviceHandoutAndReturn() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RPM_Device__c d = new RPM_Device__c(Name = 'Shelf cuff', IMEI__c = '222', Status__c = 'In Stock', Location__c = 'Shelf A');
        insert d;

        Map<String, Object> before = RpmConsoleController.getDevices();
        System.assertEquals(1, ((List<Object>) before.get('stock')).size());

        try {
            RpmConsoleController.assignDevice(d.Id, p.Id, true, true, false, true);
            System.assert(false, 'should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), e.getMessage());
        }

        RpmConsoleController.assignDevice(d.Id, p.Id, true, true, true, true);
        RPM_Device__c live = [SELECT Status__c, Current_Patient__c FROM RPM_Device__c WHERE Id = :d.Id];
        System.assertEquals('Assigned', live.Status__c);
        System.assertEquals(p.Id, live.Current_Patient__c);
        System.assertEquals(1, [SELECT COUNT() FROM RPM_Device_Assignment__c WHERE Device__c = :d.Id AND End_At__c = NULL]);

        try {
            RpmConsoleController.assignDevice(d.Id, p.Id, true, true, true, true);
            System.assert(false, 'assigned device cannot be handed out again');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('in stock'), e.getMessage());
        }

        RpmConsoleController.returnDevice(d.Id, 'Cracked display');
        RPM_Device__c back = [SELECT Status__c, Current_Patient__c FROM RPM_Device__c WHERE Id = :d.Id];
        System.assertEquals('Return Pending', back.Status__c);
        System.assertEquals(null, back.Current_Patient__c);
        System.assertEquals(0, [SELECT COUNT() FROM RPM_Device_Assignment__c WHERE Device__c = :d.Id AND End_At__c = NULL]);
        System.assertEquals(1, ((List<Object>) RpmConsoleController.getDevices().get('returns')).size());
    }

    @IsTest
    static void billingBoard() {
        setupCritical();
        List<Map<String, Object>> rows = RpmConsoleController.getBilling();
        System.assertEquals(1, rows.size());
        System.assertEquals(2, rows[0].get('readingDays'));
    }

    @IsTest
    static void sortPutsCriticalFirst() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'severity' => 'Routine', 'dueAt' => null },
            new Map<String, Object>{ 'severity' => 'Critical', 'dueAt' => Datetime.now() },
            new Map<String, Object>{ 'severity' => 'Urgent', 'dueAt' => Datetime.now().addHours(1) },
            new Map<String, Object>{ 'severity' => 'Urgent', 'dueAt' => Datetime.now() }
        };
        rows.sort(new RpmConsoleController.SeverityThenDue());
        System.assertEquals('Critical', rows[0].get('severity'));
        System.assert(((Datetime) rows[1].get('dueAt')) < ((Datetime) rows[2].get('dueAt')));
        System.assertEquals('Routine', rows[3].get('severity'));
    }
}
