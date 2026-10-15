/**
 * Description    : Test data factory for RPM unit tests.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
@IsTest
public class RpmTestFactory {
    public static final Datetime NOW = Datetime.newInstanceGmt(2026, 8, 10, 12, 0, 0);

    public static void freezeClock() {
        RpmClock.fixedNow = NOW;
        RpmProtocol.reset();
    }

    public static RPM_Patient__c patient(String emrId) {
        RPM_Patient__c p = new RPM_Patient__c(
            Name = 'Test ' + emrId,
            EMR_Patient_Id__c = emrId,
            Status__c = 'Enrolled',
            Payer_Type__c = 'Commercial',
            Payer__c = 'Test Health Plan',
            Enrollment_Date__c = NOW.date().addDays(-40),
            Consent_Date__c = NOW.date().addDays(-40)
        );
        insert p;
        return p;
    }

    /** Device assigned to the patient from 60 days ago, open-ended. */
    public static RPM_Device__c assignedDevice(RPM_Patient__c p, String imei) {
        RPM_Device__c d = new RPM_Device__c(
            Name = 'Cuff ' + imei,
            IMEI__c = imei,
            Serial_Number__c = 'SN-' + imei,
            Model__c = 'iBloodPressure 2.0',
            Device_Type__c = 'Blood Pressure',
            Vendor__c = 'Smart Meter',
            Status__c = 'Assigned',
            Current_Patient__c = p.Id,
            Battery_Percent__c = 90
        );
        insert d;
        insert new RPM_Device_Assignment__c(
            Patient__c = p.Id,
            Device__c = d.Id,
            Start_At__c = NOW.addDays(-60),
            Identity_Verified__c = true,
            Training_Done__c = true,
            Test_Reading_Received__c = true,
            Loaner_Acknowledged__c = true
        );
        return d;
    }

    public static RpmReadingInput bp(String eventId, String imei, Datetime at, Integer sys, Integer dia) {
        RpmReadingInput r = new RpmReadingInput();
        r.eventId = eventId;
        r.imei = imei;
        r.measuredAt = at;
        r.type = 'Blood Pressure';
        r.systolic = sys;
        r.diastolic = dia;
        r.pulse = 70;
        r.battery = 80;
        r.signal = -70;
        return r;
    }
}
