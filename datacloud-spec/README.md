# Data Cloud schema spec (reference, not deployable)

These XML files describe the Data Cloud objects that the POC depends on, but **they are NOT deployed via `sf project deploy start`**. The Salesforce CLI's source-deploy-retrieve registry does not currently cover `MktDataStream`, `MktDataModel`, `MktDataTransformObject`, or `Retriever` as deployable source types.

They live here as a specification: anyone reproducing this POC should configure these objects in the **Data Cloud UI** by mirroring the schema in these files. The step-by-step UI walkthrough is in [`docs/datacloud-setup.md`](../docs/datacloud-setup.md).

## Files

| File | What it describes |
|---|---|
| `dataStreams/ContentfulAssetWebhook.dataStream-meta.xml` | The DLO that receives Contentful webhook payloads |
| `mktDataModels/MarketingImage.mktDataModel-meta.xml` | The `MarketingImage__dlm` DMO, with locale / campaign / visualStyle variant fields and the `isActive` soft-delete flag |
| `mktDataTransformsObjects/ContentfulToMarketingImage.mktDataTransformObject-meta.xml` | DLO → DMO mapping, including the regex extracts that parse Contentful tags into variant fields and the `IF(CONTAINS(eventType, "publish"), …)` derivation of `isActive` |
| `retrievers/MarketingImageRetriever.retriever-meta.xml` | The hybrid retriever (structured filters + semantic ranking) that `SelectMarketingImage.cls` calls |

## Why not deployable?

As of this writing, Data Cloud metadata is created in-UI (or via Data Cloud's own CLI/API, not the standard `sf project deploy`). If future `sf` releases add registry entries for these types, these files are already in the correct shape to be moved into `force-app/main/default/` and deployed.
