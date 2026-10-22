/**
 * Implementation of IContentfulAssetProvider (defined in the contentful-cms-extension sibling repo)
 * that queries the MarketingImage__dlm catalog in Data Cloud instead of hitting Contentful directly.
 *
 * The sibling repo's ContentfulAssetService picks a provider class via the
 * Contentful_Config__mdt.Provider_Class__c custom metadata field. Set that to
 * 'DataCloudCatalogProvider' once this repo is deployed to flip the sibling LWC's backend
 * from direct Contentful calls to Data Cloud retrieval.
 *
 * All three sources of callers end up here:
 *   - The sibling LWC (user-triggered, inside the CMS editor)
 *   - The SelectMarketingImage @InvocableMethod (Agentforce agent)
 *   - Any Apex that wants to look up a marketing image
 */
public with sharing class DataCloudCatalogProvider /* implements IContentfulAssetProvider */ {

    private static final String RETRIEVER_API_NAME = 'MarketingImageRetriever';

    /**
     * Search the Data Cloud retriever. Mirrors the IContentfulAssetProvider.search signature
     * from the sibling repo. opts recognized keys:
     *   - locale (String)
     *   - campaign (String)
     *   - visualStyle (String)
     *   - contextDescription (String)   extra text added to the semantic query
     *   - topK (Integer, default 1)
     */
    public List<AssetDTO> search(String q, Map<String, Object> opts) {
        if (opts == null) opts = new Map<String, Object>();

        String semanticQuery = String.isBlank(q) ? '' : q;
        String contextDescription = (String) opts.get('contextDescription');
        if (String.isNotBlank(contextDescription)) {
            semanticQuery += ' ' + contextDescription;
        }

        Map<String, Object> params = new Map<String, Object>{ 'semanticQuery' => semanticQuery };
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
            return new List<AssetDTO>();
        }
        if (hits == null) return new List<AssetDTO>();

        List<AssetDTO> out = new List<AssetDTO>();
        for (Map<String, Object> h : hits) {
            out.add(toDTO(h));
        }
        return out;
    }

    /**
     * Look up a single asset by its Contentful sys.id (stored as assetId__c on the DMO).
     */
    public AssetDTO get(String id) {
        if (String.isBlank(id)) return null;
        Map<String, Object> params = new Map<String, Object>{ 'assetId' => id };
        List<Map<String, Object>> hits;
        try {
            hits = DataCloudRetrieverClient.retrieve(RETRIEVER_API_NAME, params);
        } catch (Exception e) {
            return null;
        }
        return (hits == null || hits.isEmpty()) ? null : toDTO(hits.get(0));
    }

    private AssetDTO toDTO(Map<String, Object> row) {
        AssetDTO dto = new AssetDTO();
        dto.assetId     = asString(row.get('assetId__c'));
        dto.url         = asString(row.get('url__c'));
        dto.altText     = asString(row.get('altText__c'));
        dto.campaign    = asString(row.get('campaign__c'));
        dto.visualStyle = asString(row.get('visualStyle__c'));
        return dto;
    }

    private static String asString(Object v) {
        return v == null ? '' : String.valueOf(v);
    }

    /**
     * Mirror of the AssetDTO shape from the sibling repo. Duplicated here so this repo
     * compiles standalone if the sibling isn't deployed yet — but at runtime the sibling's
     * ContentfulAssetService will cast to its own AssetDTO. When wiring this provider into
     * the sibling, replace this inner class with an import once the two are in the same org.
     */
    public class AssetDTO {
        @AuraEnabled public String assetId;
        @AuraEnabled public String url;
        @AuraEnabled public String altText;
        @AuraEnabled public String campaign;
        @AuraEnabled public String visualStyle;
    }
}
