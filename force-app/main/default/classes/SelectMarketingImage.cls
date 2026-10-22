public with sharing class SelectMarketingImage {

    private static final String RETRIEVER_API_NAME = 'MarketingImageRetriever';

    public class Request {
        @InvocableVariable(label='Key Message' description='Concise statement of the content\'s point. Drives semantic ranking.' required=true)
        public String keyMessage;

        @InvocableVariable(label='Context Description' description='Optional extra semantic signal, e.g. the section\'s surrounding copy.' required=false)
        public String contextDescription;

        @InvocableVariable(label='Locale' description='Variant filter. e.g. en_US. Omit for any locale.' required=false)
        public String locale;

        @InvocableVariable(label='Campaign' description='Variant filter. e.g. summer_sale. Omit for any campaign.' required=false)
        public String campaign;

        @InvocableVariable(label='Visual Style' description='Variant filter. e.g. editorial, product_shot. Omit for any style.' required=false)
        public String visualStyle;
    }

    public class Response {
        @InvocableVariable(label='Asset URL' description='Contentful CDN URL of the selected image. Empty string if no match.')
        public String assetUrl;

        @InvocableVariable(label='Alt Text' description='Alt text of the selected image.')
        public String altText;

        @InvocableVariable(label='Asset ID' description='Contentful sys.id of the selected image.')
        public String assetId;

        @InvocableVariable(label='Selected Campaign' description='The campaign variant of the asset actually returned (may differ from the requested filter when omitted).')
        public String campaign;

        @InvocableVariable(label='Selected Visual Style' description='The visualStyle variant of the asset actually returned.')
        public String visualStyle;
    }

    @InvocableMethod(
        label='Marketing Cloud: Select Marketing Image'
        description='Selects the best-matching marketing image from the Data Cloud MarketingImage catalog using a hybrid filter + semantic ranking retriever. Returns the top asset or empty strings if no match.'
        category='Marketing Cloud')
    public static List<Response> run(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            results.add(selectOne(req));
        }
        return results;
    }

    private static Response selectOne(Request req) {
        Response resp = new Response();
        resp.assetUrl = '';
        resp.altText = '';
        resp.assetId = '';
        resp.campaign = '';
        resp.visualStyle = '';

        if (String.isBlank(req.keyMessage)) {
            return resp;
        }

        String semanticQuery = req.keyMessage;
        if (String.isNotBlank(req.contextDescription)) {
            semanticQuery += ' ' + req.contextDescription;
        }

        Map<String, Object> params = new Map<String, Object>();
        params.put('semanticQuery', semanticQuery);
        if (String.isNotBlank(req.locale))      params.put('locale', req.locale);
        if (String.isNotBlank(req.campaign))    params.put('campaign', req.campaign);
        if (String.isNotBlank(req.visualStyle)) params.put('visualStyle', req.visualStyle);

        List<Map<String, Object>> hits;
        try {
            hits = DataCloudRetrieverClient.retrieve(RETRIEVER_API_NAME, params);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'MarketingImageRetriever call failed: ' + e.getMessage());
            return resp;
        }

        if (hits == null || hits.isEmpty()) {
            return resp;
        }

        Map<String, Object> top = hits.get(0);
        resp.assetUrl    = asString(top.get('url__c'));
        resp.altText     = asString(top.get('altText__c'));
        resp.assetId     = asString(top.get('assetId__c'));
        resp.campaign    = asString(top.get('campaign__c'));
        resp.visualStyle = asString(top.get('visualStyle__c'));
        return resp;
    }

    private static String asString(Object v) {
        return v == null ? '' : String.valueOf(v);
    }
}
