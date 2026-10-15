/**
 * Description    : REST endpoint /rpm/v1/readings that receives device readings.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Inbound endpoint for device readings.
 *
 *   POST /services/apexrest/rpm/v1/readings
 *   Body: one RpmReadingInput object, or a JSON array of up to 200.
 *   Auth: OAuth (Connected App / External Client App) as a user with the
 *         RPM_Integration permission set.
 *
 * Device vendors usually push webhooks without OAuth, so a small gateway
 * (e.g. an AWS Lambda) receives the vendor webhook, verifies its signature,
 * maps it to RpmReadingInput and posts here.
 *
 * Responses: 200 with IngestResult, 400 bad JSON, 413 too many items.
 */
@RestResource(urlMapping='/rpm/v1/readings')
global with sharing class RpmReadingApi {
    @HttpPost
    global static void receive() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String body = (req.requestBody == null) ? '' : req.requestBody.toString().trim();
        if (String.isBlank(body)) {
            respond(res, 400, new Map<String, Object>{ 'error' => 'Empty body' });
            return;
        }

        List<RpmReadingInput> inputs;
        try {
            if (body.startsWith('[')) {
                inputs = (List<RpmReadingInput>) JSON.deserialize(body, List<RpmReadingInput>.class);
            } else {
                inputs = new List<RpmReadingInput>{ (RpmReadingInput) JSON.deserialize(body, RpmReadingInput.class) };
            }
        } catch (JSONException e) {
            respond(res, 400, new Map<String, Object>{ 'error' => 'Invalid JSON: ' + e.getMessage() });
            return;
        }

        if (inputs.size() > RpmReadingService.MAX_BATCH) {
            respond(res, 413, new Map<String, Object>{ 'error' => 'Send at most ' + RpmReadingService.MAX_BATCH + ' readings per request' });
            return;
        }

        RpmReadingService.IngestResult result = RpmReadingService.ingest(inputs);
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(result));
    }

    private static void respond(RestResponse res, Integer status, Object payload) {
        res.statusCode = status;
        res.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}
