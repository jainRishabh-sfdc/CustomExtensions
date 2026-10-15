/**
 * Description    : Unit tests for RpmReadingApi.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
@IsTest
private class RpmReadingApiTest {
    static RestResponse call(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/rpm/v1/readings';
        req.httpMethod = 'POST';
        req.requestBody = body == null ? null : Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        RpmReadingApi.receive();
        return RestContext.response;
    }

    @IsTest
    static void acceptsSingleObject() {
        RpmTestFactory.freezeClock();
        RPM_Patient__c p = RpmTestFactory.patient('P1');
        RpmTestFactory.assignedDevice(p, '356938035688340');
        RestResponse res = call('{"eventId":"sm-1","imei":"356938035688340","measuredAt":"2026-08-09T07:41:00Z","type":"Blood Pressure","systolic":181,"diastolic":112,"pulse":96,"battery":91,"signal":-69}');
        System.assertEquals(200, res.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(1, body.get('created'));
        System.assertEquals(1, body.get('alertsRaised'));
    }

    @IsTest
    static void acceptsArray() {
        RpmTestFactory.freezeClock();
        RestResponse res = call('[{"eventId":"a","imei":"x","measuredAt":"2026-08-09T07:41:00Z","systolic":120,"diastolic":80},{"eventId":"b","imei":"x","measuredAt":"2026-08-09T08:41:00Z","systolic":121,"diastolic":80}]');
        System.assertEquals(200, res.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(2, body.get('created'));
        System.assertEquals(2, body.get('unmatched'));
    }

    @IsTest
    static void rejectsBadInput() {
        System.assertEquals(400, call(null).statusCode);
        System.assertEquals(400, call('{not json').statusCode);
        List<String> many = new List<String>();
        for (Integer i = 0; i < 201; i++) {
            many.add('{"eventId":"e' + i + '"}');
        }
        System.assertEquals(413, call('[' + String.join(many, ',') + ']').statusCode);
    }
}
