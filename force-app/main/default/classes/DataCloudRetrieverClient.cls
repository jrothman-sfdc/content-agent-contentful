/**
 * Thin wrapper around the Data Cloud Retriever REST API.
 *
 * POC NOTE: Named Credential wiring and the exact retriever REST path differ
 * by org release. This class centralizes the call so SelectMarketingImage
 * stays focused on business logic. If your org exposes retrievers via Apex
 * (e.g. ConnectApi or a first-party invocable), swap this implementation
 * to call that directly and keep the same signature.
 */
public with sharing class DataCloudRetrieverClient {

    private static final String NAMED_CREDENTIAL = 'callout:DataCloud';
    private static final String RETRIEVE_PATH    = '/services/data/v63.0/ssot/retrievers/';

    public static List<Map<String, Object>> retrieve(String retrieverApiName, Map<String, Object> params) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + RETRIEVE_PATH + retrieverApiName + '/invoke');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, Object>{ 'parameters' => params }));
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new RetrieverException('Retriever returned HTTP ' + res.getStatusCode() + ': ' + res.getBody());
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Object hitsRaw = payload.get('results');
        if (hitsRaw == null) {
            return new List<Map<String, Object>>();
        }

        List<Object> hits = (List<Object>) hitsRaw;
        List<Map<String, Object>> flat = new List<Map<String, Object>>();
        for (Object h : hits) {
            flat.add((Map<String, Object>) h);
        }
        return flat;
    }

    public class RetrieverException extends Exception {}
}
