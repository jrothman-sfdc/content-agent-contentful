/**
 * Thin @InvocableMethod wrapper around DataCloudCatalogProvider for the Agentforce agent.
 *
 * The business logic lives in DataCloudCatalogProvider so the sibling repo's
 * ContentfulAssetService (via IContentfulAssetProvider) and this agent action share
 * one code path. If you want to change ranking, filtering, or output shape, do it there.
 */
public with sharing class SelectMarketingImage {

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

        @InvocableVariable(label='Selected Campaign' description='The campaign variant of the asset actually returned.')
        public String campaign;

        @InvocableVariable(label='Selected Visual Style' description='The visualStyle variant of the asset actually returned.')
        public String visualStyle;
    }

    @InvocableMethod(
        label='Marketing Cloud: Select Marketing Image'
        description='Selects the best-matching marketing image from the Data Cloud MarketingImage catalog using a hybrid filter + semantic ranking retriever. Returns the top asset or empty strings if no match.'
        category='Marketing Cloud')
    public static List<Response> run(List<Request> requests) {
        DataCloudCatalogProvider provider = new DataCloudCatalogProvider();
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            results.add(selectOne(provider, req));
        }
        return results;
    }

    private static Response selectOne(DataCloudCatalogProvider provider, Request req) {
        Response resp = emptyResponse();
        if (String.isBlank(req.keyMessage)) return resp;

        Map<String, Object> opts = new Map<String, Object>{
            'locale'             => req.locale,
            'campaign'           => req.campaign,
            'visualStyle'        => req.visualStyle,
            'contextDescription' => req.contextDescription
        };
        List<DataCloudCatalogProvider.AssetDTO> hits = provider.search(req.keyMessage, opts);
        if (hits == null || hits.isEmpty()) return resp;

        DataCloudCatalogProvider.AssetDTO top = hits.get(0);
        resp.assetUrl    = top.url;
        resp.altText     = top.altText;
        resp.assetId     = top.assetId;
        resp.campaign    = top.campaign;
        resp.visualStyle = top.visualStyle;
        return resp;
    }

    private static Response emptyResponse() {
        Response r = new Response();
        r.assetUrl = ''; r.altText = ''; r.assetId = ''; r.campaign = ''; r.visualStyle = '';
        return r;
    }
}
