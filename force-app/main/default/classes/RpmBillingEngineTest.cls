/**
 * Description    : Unit tests for RpmBillingEngine.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
@IsTest
private class RpmBillingEngineTest {
    static RPM_Patient__c mem(Boolean consent, Boolean locked, Boolean setupBilled) {
        return new RPM_Patient__c(
            Consent_Date__c = consent ? Date.newInstance(2026, 6, 1) : null,
            Billing_Locked__c = locked,
            Billing_Lock_Reason__c = locked ? 'ACCESS model' : null,
            Setup_Billed__c = setupBilled
        );
    }

    @IsTest
    static void sixteenDaysAndTwentyMinutes() {
        RpmBillingEngine.Summary s = RpmBillingEngine.evaluate(mem(true, false, true), 16, 20, true, true);
        System.assertEquals(new List<String>{ '99454', '99457' }, s.codes);
        System.assertEquals('Ready to Bill', s.status);
    }

    @IsTest
    static void fifteenDaysUsesNewSupplyCode() {
        RpmBillingEngine.Summary s = RpmBillingEngine.evaluate(mem(true, false, true), 15, 0, false, true);
        System.assertEquals(new List<String>{ '99445' }, s.codes);
    }

    @IsTest
    static void oneDayBillsNothing() {
        RpmBillingEngine.Summary s = RpmBillingEngine.evaluate(mem(true, false, false), 1, 5, true, true);
        System.assert(s.codes.isEmpty());
        System.assertEquals('Accruing', s.status);
    }

    @IsTest
    static void setupCodeOnlyOnce() {
        System.assert(RpmBillingEngine.evaluate(mem(true, false, false), 3, 0, false, true).codes.contains('99453'));
        System.assert(!RpmBillingEngine.evaluate(mem(true, false, true), 3, 0, false, true).codes.contains('99453'));
    }

    @IsTest
    static void managementMinutes() {
        System.assertEquals(new List<String>(), RpmBillingEngine.evaluate(mem(true, false, true), 0, 9, true, true).codes);
        System.assertEquals(new List<String>{ '99470' }, RpmBillingEngine.evaluate(mem(true, false, true), 0, 19, true, true).codes);
        System.assertEquals(new List<String>{ '99457' }, RpmBillingEngine.evaluate(mem(true, false, true), 0, 39, true, true).codes);
        System.assertEquals(new List<String>{ '99457', '99458x2' }, RpmBillingEngine.evaluate(mem(true, false, true), 0, 61, true, true).codes);
        System.assertEquals(new List<String>(), RpmBillingEngine.evaluate(mem(true, false, true), 0, 61, false, true).codes, 'no interactive communication = no management code');
    }

    @IsTest
    static void doubleBillingGuardAndConsent() {
        RpmBillingEngine.Summary locked = RpmBillingEngine.evaluate(mem(true, true, false), 20, 40, true, true);
        System.assert(locked.codes.isEmpty());
        System.assertEquals('Blocked', locked.status);
        System.assert(locked.blockedReason.contains('ACCESS'));

        RpmBillingEngine.Summary noConsent = RpmBillingEngine.evaluate(mem(false, false, false), 20, 40, true, true);
        System.assertEquals('No RPM consent on file', noConsent.blockedReason);
    }

    @IsTest
    static void openPeriodStaysAccruing() {
        RpmBillingEngine.Summary s = RpmBillingEngine.evaluate(mem(true, false, true), 16, 20, true, false);
        System.assertEquals('Accruing', s.status);
    }

    @IsTest
    static void recalculateCountsDistinctDaysAndMinutes() {
        RpmTestFactory.freezeClock(); // Aug 10, 2026
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        p.Setup_Billed__c = true;
        update p;
        RpmTestFactory.assignedDevice(p, '111');
        List<RpmReadingInput> reads = new List<RpmReadingInput>();
        for (Integer day = 1; day <= 5; day++) {
            Datetime at = Datetime.newInstance(Date.newInstance(2026, 8, day), Time.newInstance(9, 0, 0, 0));
            reads.add(RpmTestFactory.bp('a' + day, '111', at, 125, 80));
            reads.add(RpmTestFactory.bp('b' + day, '111', at.addHours(3), 127, 81)); // same day, counted once
        }
        RpmReadingService.ingest(reads);
        insert new List<RPM_Time_Entry__c>{
            new RPM_Time_Entry__c(Patient__c = p.Id, Entry_Date__c = Date.newInstance(2026, 8, 3), Minutes__c = 12, Interactive__c = true, Activity__c = 'Phone call with patient'),
            new RPM_Time_Entry__c(Patient__c = p.Id, Entry_Date__c = Date.newInstance(2026, 8, 6), Minutes__c = 10, Activity__c = 'Reviewed readings'),
            new RPM_Time_Entry__c(Patient__c = p.Id, Entry_Date__c = Date.newInstance(2026, 7, 28), Minutes__c = 30, Interactive__c = true, Activity__c = 'Phone call with patient')
        };

        List<RPM_Billing_Period__c> out = RpmBillingEngine.recalculate(new Set<Id>{ p.Id }, RpmTestFactory.NOW.date());
        RpmBillingEngine.recalculate(new Set<Id>{ p.Id }, RpmTestFactory.NOW.date()); // idempotent

        System.assertEquals(1, [SELECT COUNT() FROM RPM_Billing_Period__c], 'one row per patient per month');
        RPM_Billing_Period__c bp = [SELECT Reading_Days__c, Care_Minutes__c, Codes__c, Status__c, Period_Start__c, Rules_Version__c FROM RPM_Billing_Period__c];
        System.assertEquals(5, bp.Reading_Days__c);
        System.assertEquals(22, bp.Care_Minutes__c, 'July entry excluded');
        System.assertEquals('99445,99457', bp.Codes__c);
        System.assertEquals('Accruing', bp.Status__c, 'August not over yet');
        System.assertEquals(Date.newInstance(2026, 8, 1), bp.Period_Start__c);
        System.assertEquals(RpmBillingEngine.RULES_VERSION, bp.Rules_Version__c);
    }

    @IsTest
    static void billedPeriodIsNeverOverwritten() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        insert new RPM_Billing_Period__c(
            Patient__c = p.Id,
            Period_Key__c = p.Id + ':' + String.valueOf(Date.newInstance(2026, 8, 1)),
            Period_Start__c = Date.newInstance(2026, 8, 1),
            Period_End__c = Date.newInstance(2026, 8, 31),
            Codes__c = '99454',
            Status__c = 'Billed'
        );
        RpmBillingEngine.recalculate(new Set<Id>{ p.Id }, RpmTestFactory.NOW.date());
        RPM_Billing_Period__c bp = [SELECT Codes__c, Status__c FROM RPM_Billing_Period__c];
        System.assertEquals('Billed', bp.Status__c);
        System.assertEquals('99454', bp.Codes__c);
    }
}
