/**
 * Thin @InvocableMethod wrapper around DataCloudCatalogProvider for the Agentforce agent.
 *
 * The business logic lives in DataCloudCatalogProvider so the sibling repo's
 * ContentfulAssetService (via IContentfulAssetProvider) and this agent action share
 * one code path. To change ranking, filtering, or output shape, edit the provider.
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

        @InvocableVariable(label='Image Block JSON' description='A ready-to-inject lightning/html block (JSON string) containing an <img> tag with the selected URL. The agent can paste this into blockValue for CreateOrRefineSectionWithContent. Empty string if no match.')
        public String imageBlockJson;
    }

    @InvocableMethod(
        label='Marketing Cloud: Select Marketing Image'
        description='Selects the best-matching marketing image from the Data Cloud MarketingImage catalog using a hybrid filter + semantic ranking retriever. Returns the asset URL, alt text, and a ready-to-inject lightning/html image block for the agent to splice into blockValue.'
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
            'contextDescription' => req.contextDescription,
            'topK'               => 1
        };
        List<ContentfulAssetDTO> hits = provider.search(req.keyMessage, opts);
        if (hits == null || hits.isEmpty()) return resp;

        ContentfulAssetDTO top = hits.get(0);
        resp.assetUrl       = top.url;
        resp.altText        = String.isNotBlank(top.altText) ? top.altText : top.title;
        resp.assetId        = top.assetId;
        resp.campaign       = top.campaign;
        resp.visualStyle    = top.visualStyle;
        resp.imageBlockJson = buildImageBlockJson(top.url, resp.altText);
        return resp;
    }

    /**
     * Produce a serialized lightning/html block JSON string that the agent can inject
     * into blockValue. The MCA email schema rejects external URLs on lightning/image
     * blocks (imageInfo.source must be an imageReference to a CMS asset), so we use
     * lightning/html with a raw <img> tag — same pattern as the sibling LWC extension.
     */
    private static String buildImageBlockJson(String url, String alt) {
        if (String.isBlank(url)) return '';
        String safeSrc = escapeHtmlAttr(url);
        String safeAlt = escapeHtmlAttr(alt == null ? '' : alt);
        Map<String, Object> block = new Map<String, Object>{
            'id'         => newUuid(),
            'type'       => 'block',
            'definition' => 'lightning/html',
            'attributes' => new Map<String, Object>{
                'rawHtml' => '<img src="' + safeSrc + '" alt="' + safeAlt +
                             '" style="max-width:100%;height:auto;display:block;" />'
            }
        };
        return JSON.serialize(block);
    }

    private static String escapeHtmlAttr(String s) {
        if (s == null) return '';
        return s.replace('&', '&amp;')
                .replace('"', '&quot;')
                .replace('<', '&lt;')
                .replace('>', '&gt;');
    }

    private static String newUuid() {
        Blob b = Crypto.generateAesKey(128);
        String hex = EncodingUtil.convertToHex(b);
        return hex.substring(0, 8)  + '-' +
               hex.substring(8, 12) + '-4' +
               hex.substring(13, 16) + '-' +
               hex.substring(16, 20) + '-' +
               hex.substring(20, 32);
    }

    private static Response emptyResponse() {
        Response r = new Response();
        r.assetUrl = ''; r.altText = ''; r.assetId = '';
        r.campaign = ''; r.visualStyle = ''; r.imageBlockJson = '';
        return r;
    }
}
