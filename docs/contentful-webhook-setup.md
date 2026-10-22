# Contentful → Data Cloud webhook

Keeps `MarketingImage__dlm` in sync with Contentful: a publish lands a row with `isActive = true`, an unpublish or delete flips it to `false`.

## Prerequisites

- Data Cloud Ingestion API endpoint URL + OAuth bearer token (from `docs/datacloud-setup.md` step 1).
- Admin access to the Contentful space.

## 1. Create the webhook

Contentful → **Settings → Webhooks → Add webhook**.

- **Name:** `Data Cloud sync`
- **URL:** paste the Data Cloud Ingestion API endpoint. It will look roughly like:
  ```
  https://<your-org>.c360a.salesforce.com/api/v1/ingest/sources/ContentfulWebhook/ContentfulAssetWebhook
  ```
  (your exact path is shown on the connector detail page in Data Cloud.)
- **Method:** POST.
- **Content type:** `application/json`.

## 2. Headers

Add two custom headers:

| Key | Value |
|---|---|
| `Authorization` | `Bearer <OAuth access token from Data Cloud connected app>` |
| `Content-Type` | `application/json` |

Mark the Authorization header as a **secret** so it's masked in the Contentful UI.

> **Note on token lifetime:** OAuth access tokens for the Data Cloud Ingestion API expire. For POC purposes a long-lived token is fine. For anything beyond a demo you'd rotate via a Connected App's refresh-token flow, which is out of POC scope.

## 3. Event filters

Only trigger on three asset events:

| Topic |
|---|
| `ContentManagement.Asset.publish` |
| `ContentManagement.Asset.unpublish` |
| `ContentManagement.Asset.delete` |

Leave `Asset.create`, `Asset.save`, etc. unchecked — they'd flood Data Cloud with unprocessed drafts.

## 4. Payload template (critical)

Contentful's default payload is the full raw asset JSON with locale-nested fields. The DLO expects a flat shape. **Customize the payload** in the webhook settings:

```json
{
  "assetId": "{ /payload/sys/id }",
  "url": "https:{ /payload/fields/file/en-US/url }",
  "title": "{ /payload/fields/title/en-US }",
  "description": "{ /payload/fields/description/en-US }",
  "fileName": "{ /payload/fields/file/en-US/fileName }",
  "mimeType": "{ /payload/fields/file/en-US/contentType }",
  "width": "{ /payload/fields/file/en-US/details/image/width }",
  "height": "{ /payload/fields/file/en-US/details/image/height }",
  "tags": "{ /payload/metadata/tags | map: 'sys.id' | join: ',' }",
  "eventType": "{ /topic }",
  "updatedAt": "{ /payload/sys/updatedAt }"
}
```

Notes:
- Contentful's CDN URLs come back **protocol-relative** (`//images.ctfassets.net/...`), so we prepend `https:` in the template.
- `tags` is flattened to a comma-separated string of tag IDs like `locale_en_US,campaign_summer_sale,visualStyle_editorial`. The DMO mapping parses this with regex to extract each variant dimension.
- The `| map` / `| join` filters shown above are Contentful's webhook transformation DSL — confirm against the current Contentful docs; depending on space settings you may need a slightly different filter chain.
- For `Asset.unpublish` and `Asset.delete`, several `fields.*` paths won't resolve. That's fine — the mapping only needs `assetId` and `eventType` for soft deletes. Any missing fields come through as empty strings and don't break the DLO insert.

## 5. Test

In Contentful, publish any asset. Within a few seconds:

```bash
./scripts/verify-dmo.sh <your-org-alias>
```

You should see a row for the asset with `isActive__c = true`.

Then unpublish the same asset and re-run — `isActive__c` should flip to `false`, same row.

## 6. Troubleshooting

- **Webhook UI shows 401 / 403:** OAuth token wrong or expired. Regenerate in the Data Cloud connected app.
- **200 OK but no DMO row:** the DLO received the payload but the mapping didn't produce a valid DMO row. Check Data Cloud → Data Streams → ContentfulAssetWebhook → Monitor; look for rows with mapping errors (usually a missing `assetId` or a regex mismatch on tags).
- **Row appears but `locale`/`campaign`/`visualStyle` are empty:** your tag naming convention doesn't match the regex. Confirm tags are shaped exactly `locale_<value>`, `campaign_<value>`, `visualStyle_<value>` with underscore separators, not hyphens or colons.
- **URL is `null:` prefixed:** the asset wasn't fully processed before publish. Re-publish, or in Contentful hit "Process asset" first.
