/**
 * Implementation of IContentfulAssetProvider (defined in the contentful-cms-extension
 * sibling repo) that queries the MarketingImage__dlm catalog in Data Cloud instead of
 * hitting Contentful directly.
 *
 * HARD DEPENDENCY: contentful-cms-extension must be deployed to the org first. This
 * class references IContentfulAssetProvider and ContentfulAssetDTO from that package.
 *
 * The sibling repo's ContentfulAssetService resolves providers by class name from
 * Contentful_Config__mdt.Default.Provider_Class__c. Set that to
 * 'DataCloudCatalogProvider' once this repo is deployed to flip the sibling LWC's
 * backend from Direct Contentful calls to Data Cloud retrieval.
 *
 * All three sources of callers end up here:
 *   - The sibling LWC (user-triggered, inside the CMS editor)
 *   - The SelectMarketingImage @InvocableMethod (Agentforce agent, this repo)
 *   - Any Apex that calls ContentfulAssetService directly
 */
public with sharing class DataCloudCatalogProvider implements IContentfulAssetProvider {

    private static final String RETRIEVER_API_NAME = 'MarketingImageRetriever';

    public List<ContentfulAssetDTO> search(String q, Map<String, Object> opts) {
        if (opts == null) opts = new Map<String, Object>();
        Integer topK = opts.containsKey('topK') ? (Integer) opts.get('topK') : 1;

        String semanticQuery = String.isBlank(q) ? '' : q;
        Object ctx = opts.get('contextDescription');
        if (ctx != null && String.isNotBlank(String.valueOf(ctx))) {
            semanticQuery += ' ' + String.valueOf(ctx);
        }

        Map<String, Object> params = new Map<String, Object>{
            'semanticQuery' => semanticQuery,
            'topK' => topK
        };
        for (String key : new List<String>{ 'locale', 'campaign', 'visualStyle' }) {
            Object v = opts.get(key);
            if (v != null && String.isNotBlank(String.valueOf(v))) {
                params.put(key, v);
            }
        }

        List<Map<String, Object>> hits;
        try {
            hits = DataCloudRetrieverClient.retrieve(RETRIEVER_API_NAME, params);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'MarketingImageRetriever call failed: ' + e.getMessage());
            return new List<ContentfulAssetDTO>();
        }
        if (hits == null) return new List<ContentfulAssetDTO>();

        List<ContentfulAssetDTO> out = new List<ContentfulAssetDTO>();
        for (Map<String, Object> h : hits) {
            out.add(toDTO(h));
        }
        return out;
    }

    public ContentfulAssetDTO get(String id) {
        if (String.isBlank(id)) return null;
        Map<String, Object> params = new Map<String, Object>{ 'assetId' => id };
        List<Map<String, Object>> hits;
        try {
            hits = DataCloudRetrieverClient.retrieve(RETRIEVER_API_NAME, params);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'MarketingImageRetriever get failed: ' + e.getMessage());
            return null;
        }
        return (hits == null || hits.isEmpty()) ? null : toDTO(hits.get(0));
    }

    private ContentfulAssetDTO toDTO(Map<String, Object> row) {
        ContentfulAssetDTO dto = new ContentfulAssetDTO();
        dto.assetId     = asString(row.get('assetId__c'));
        dto.url         = asString(row.get('url__c'));
        dto.altText     = asString(row.get('altText__c'));
        dto.title       = asString(row.get('title__c'));
        dto.description = asString(row.get('description__c'));
        dto.locale      = asString(row.get('locale__c'));
        dto.campaign    = asString(row.get('campaign__c'));
        dto.visualStyle = asString(row.get('visualStyle__c'));
        return dto;
    }

    private static String asString(Object v) {
        return v == null ? '' : String.valueOf(v);
    }
}
