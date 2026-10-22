# Data Cloud setup

The XML files under `force-app/main/default/{dataStreams,mktDataModels,mktDataTransformsObjects,retrievers}/` are a **documented schema specification**. In some orgs they will deploy via `sf project deploy start`; in others you'll need to configure these objects manually in the Data Cloud UI, mirroring the XML. This doc walks the manual path, which always works.

## Prerequisites

- Data Cloud provisioned on the org (`salesforce-ea-zh4347` is confirmed provisioned).
- You are a Data Cloud admin.
- An Ingestion API connector will be created in step 1.

## 1. Create the Ingestion API connector

Setup → Data Cloud → **Ingestion API** → **New**.

- **Name:** `ContentfulWebhook`
- **Connector type:** Ingestion API
- Upload a schema file matching `ContentfulAssetWebhook.dataStream-meta.xml` → `ingestionSchema`. The simplest route is a hand-written OpenAPI/JSON schema with these fields (all strings except `width`, `height` numbers, `updatedAt` datetime):
  - `assetId` (primary key, required)
  - `url`, `title`, `description`, `fileName`, `mimeType`, `tags`, `eventType`
  - `width`, `height` (number)
  - `updatedAt` (datetime)

Save, then copy the connector's **endpoint URL** and generate an **OAuth access token** for a Connected App you'll point the Contentful webhook at. Keep both — they go into the Contentful webhook config.

## 2. Create the Data Lake Object (DLO)

Setup → Data Cloud → **Data Streams** → **New**.

- **Source:** the `ContentfulWebhook` connector from step 1.
- **DLO name:** `ContentfulAssetWebhook`
- **Category:** Engagement
- Map the connector fields to DLO fields 1:1 (same names).

Deploy. The DLO is now live and will accept POSTs from Contentful.

## 3. Create the Data Model Object (DMO)

Setup → Data Cloud → **Data Model** → **New Data Model Object**.

- **Name:** `MarketingImage`
- **API name:** `MarketingImage__dlm`
- **Category:** Engagement
- **Primary key:** `assetId__c`
- Create fields per `MarketingImage.mktDataModel-meta.xml`:
  | Field | Type | Notes |
  |---|---|---|
  | `assetId__c` | Text | Primary key |
  | `url__c` | Text | |
  | `altText__c` | Text | |
  | `title__c` | Text | |
  | `description__c` | Long text | |
  | `tags__c` | Text | Raw comma-separated tag string |
  | `locale__c` | Text | Variant dimension |
  | `campaign__c` | Text | Variant dimension |
  | `visualStyle__c` | Text | Variant dimension |
  | `isActive__c` | Boolean | Soft-delete flag |
  | `mimeType__c` | Text | |
  | `width__c` | Number | |
  | `height__c` | Number | |
  | `updatedAt__c` | DateTime | |

## 4. Map DLO → DMO

Setup → Data Cloud → **Data Model** → `MarketingImage__dlm` → **Mappings** → **New Mapping**.

- **Source:** `ContentfulAssetWebhook` DLO
- Direct field mappings:
  - `assetId` → `assetId__c`
  - `url` → `url__c`
  - `title` → `title__c` **and** `title` → `altText__c` (title doubles as alt text when none provided)
  - `description` → `description__c`
  - `tags` → `tags__c`
  - `mimeType` → `mimeType__c`
  - `width` → `width__c`
  - `height` → `height__c`
  - `updatedAt` → `updatedAt__c`
- **Derived field** → `isActive__c`
  - Formula: `IF(CONTAINS(eventType, "publish"), true, false)`
- **Derived field** → `locale__c`
  - Formula: `REGEXP_EXTRACT(tags, "locale_([A-Za-z_]+)", 1)` (your org's formula engine may call it `REGEX_EXTRACT`)
- **Derived field** → `campaign__c`
  - Formula: `REGEXP_EXTRACT(tags, "campaign_([A-Za-z0-9_]+)", 1)`
- **Derived field** → `visualStyle__c`
  - Formula: `REGEXP_EXTRACT(tags, "visualStyle_([A-Za-z0-9_]+)", 1)`

Save and run the mapping.

## 5. Create the semantic index + retriever

Setup → Data Cloud → **Search Index** (or **Retrievers**) → **New**.

- **Name:** `MarketingImageRetriever`
- **Source:** `MarketingImage__dlm`
- **Semantic index fields:** `title__c`, `description__c`, `tags__c`
- **Static filter:** `isActive__c = true`
- **Parameter filters** (all optional at query time):
  - `locale` → `locale__c = {input}`
  - `campaign` → `campaign__c = {input}`
  - `visualStyle` → `visualStyle__c = {input}`
- **Top K:** 1
- **Output fields:** `assetId__c`, `url__c`, `altText__c`, `campaign__c`, `visualStyle__c`

## 6. Verify

Run a direct retriever query from the Data Cloud UI, with:
- `semanticQuery = "summer promotional email"`
- `locale = en_US` (if you've seeded any)

You should get back whichever seeded asset most closely matches, or empty if the catalog hasn't been seeded yet.

## 7. Permissions

The user who will build the agent needs:
- Data Cloud Admin or Data Cloud User permset
- Read access to `MarketingImage__dlm`
- Invoke access to the retriever

For the agent user specifically, assign the `MarketingImageAgent` permission set (deployed from this repo).
