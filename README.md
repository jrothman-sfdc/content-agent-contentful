# Autonomous Image Selection in the MCA Content Builder Agent — POC

## What this is

An Agentforce agent for Marketing Cloud Advanced (MCA) that semantically ranks and recommends images from a Contentful library when a user generates email sections — backed by a Data Cloud catalog of Contentful assets kept in sync via webhook.

**Audience:** Internal demo. Not production hardened — no governance flag, no audit trail, no fallback logic, no security review.

**Variant dimensions:** Images are selected along three axes:
- `locale` — driven by the content builder canvas's `TargetLanguage`
- `campaign` — inferred from the user prompt or passed via session context
- `visualStyle` — inferred from tone cues in the user prompt or passed via session context

Within those structured filters, a semantic retriever ranks matches on `keyMessage` + optional context.

---

## This repo is one of two

This project assumes a sibling repo — [**contentful-cms-extension**](https://github.com/jrothman-sfdc/contentful-cms-extension) — provides the Content Builder editor extension LWC that actually injects images into the canvas. That repo is the user-facing surface. **This** repo adds:

- A **Data Cloud catalog** of Contentful assets (kept in sync via webhook) with semantic retrieval
- An **Agentforce agent** that recommends images from the catalog based on content being generated
- A **swappable provider** (`DataCloudCatalogProvider`) that the sibling LWC can use instead of hitting Contentful directly, giving it variant filtering + semantic ranking

**Install order:** install `contentful-cms-extension` first (basic Contentful browsing in the editor), then install this project on top to upgrade the selection intelligence and add agent-driven recommendations.

If all you want is a Contentful picker in the MCA email editor with no AI, **you don't need this repo at all** — install the sibling and stop there.

---

## Architecture (with both repos installed)

```
                        ┌───────────────────────────────────────────┐
                        │             Contentful Space               │
                        │   (assets tagged by locale, campaign,       │
                        │    visualStyle; title + description for     │
                        │    semantic ranking)                        │
                        └─────────┬────────────────┬────────────────┘
                                  │                │
                     Asset.publish │                │ CDA queries
                     webhook       │                │ (direct, from sibling repo)
                                   ▼                │
                        ┌───────────────────────────┼──────────────┐
                        │   Data Cloud Ingestion    │              │
                        │   API endpoint            │              │
                        │   → DLO → mapping →       │              │
                        │   MarketingImage__dlm     │              │
                        │   semantic index          │              │
                        └──────────────┬────────────┘              │
                                       │                           │
                                       │ Retriever                  │
                                       ▼                           │
                        ┌───────────────────────────┐              │
                        │  DataCloudCatalogProvider │  ───────────▶│
                        │  (this repo)              │   drop-in    │
                        │  implements               │   replaces   │
                        │  IContentfulAssetProvider │   Direct...  │
                        │  from sibling repo        │              │
                        └──────────────┬────────────┘              │
                                       │                           │
                        ┌──────────────┼──────────────┐            │
                        │              │              │            │
                        ▼              ▼              │            │
            ┌─────────────────┐  ┌─────────────────┐  │            │
            │ Agentforce      │  │ CMS Editor      │  │            │
            │ agent calls     │  │ Extension LWC   │  │            │
            │ SelectMarketing │  │ (sibling repo)  │  │            │
            │ Image invocable │  │ user-triggered  │  │            │
            └─────────────────┘  └────────┬────────┘  │            │
                                          │           │            │
                                          ▼           ▼            │
                        ┌───────────────────────────────────┐      │
                        │  MCA Content Builder canvas       │      │
                        │  renders image via updateContent  │      │
                        └───────────────────────────────────┘      │
                                                                   │
                                                      No DC needed │
                                                      path         │
                                                                   ▼
                                             (just the LWC + Contentful,
                                              sibling repo standalone)
```

---

## What this repo contributes

### Apex
- `SelectMarketingImage` — `@InvocableMethod` the Agentforce agent calls
- `DataCloudCatalogProvider` — implements `IContentfulAssetProvider` from the sibling repo; queries the Data Cloud retriever instead of Contentful directly
- `DataCloudRetrieverClient` — thin REST wrapper for the Data Cloud retriever

### Data Cloud (spec only — configured in UI)
- `MarketingImage__dlm` DMO with `locale`, `campaign`, `visualStyle` variant fields + `isActive` soft-delete
- DLO shape matching the Contentful webhook payload
- DLO → DMO mapping (regex-parses tags into variant fields; derives `isActive` from Contentful event topic)
- Semantic retriever with hybrid filter + ranking

### Contentful sync
- Webhook config documented in `docs/contentful-webhook-setup.md`
- Seed script (`scripts/seed-contentful-assets.js`) to populate a demo catalog

### Agent
- Reference `.agent` file documenting the modified `CreateOrRefineSectionWithContent` reasoning
- Agent-build runbook (`docs/agent-build-runbook.md`)
- Demo script (`docs/demo-script.md`)

---

## Prerequisites

- Salesforce org with **Data Cloud**, **Agentforce**, and **Marketing Cloud Advanced** enabled
- **`contentful-cms-extension` repo installed** in the same org (this repo depends on `IContentfulAssetProvider` and `ContentfulAssetService` from there)
- **Contentful** space with Content Management API access (for the seed script)
- **`sf` CLI** v2.x authenticated to the target Salesforce org
- **Node.js** 18+ for running the Contentful seed script
- Permission to create agents in the Agent Builder UI

---

## Reproduction runbook

### 0. Install the sibling repo first

```bash
git clone https://github.com/jrothman-sfdc/contentful-cms-extension.git
cd contentful-cms-extension
sf project deploy start --target-org <your-org-alias>
```

Follow its README to configure the Contentful Named Credential. **At this point the LWC extension works standalone — you can insert Contentful images into MCA emails without any of the rest of this repo.**

### 1. Clone this repo and install seed-script dependencies

```bash
git clone https://github.com/jrothman-sfdc/content-agent-contentful.git
cd content-agent-contentful/scripts
npm install
```

### 2. Deploy this repo's Salesforce metadata

```bash
cd ..
sf project deploy start --target-org <your-org-alias>
sf org assign permset --name MarketingImageAgent --target-org <your-org-alias>
```

### 3. Configure Data Cloud

Follow [docs/datacloud-setup.md](docs/datacloud-setup.md): create the DMO, DLO, mapping, retriever in the Data Cloud UI (SFDX source for these types isn't supported — spec XML lives in `datacloud-spec/` for reference).

### 4. Point the sibling LWC at Data Cloud

In Setup → Custom Metadata Types → `Contentful_Config__mdt`, set `Provider_Class__c = 'DataCloudCatalogProvider'`. This flips the sibling LWC from direct Contentful calls to Data Cloud retrieval.

### 5. Configure the Contentful → Data Cloud webhook

Follow [docs/contentful-webhook-setup.md](docs/contentful-webhook-setup.md).

### 6. Seed Contentful with demo assets

```bash
cd scripts
cp .env.example .env   # fill in CONTENTFUL_CMA_TOKEN, SPACE_ID, ENVIRONMENT
npm run seed
```

### 7. Verify DMO population

```bash
./scripts/verify-dmo.sh <your-org-alias>
```

### 8. Build the agent in Agent Builder UI

Follow [docs/agent-build-runbook.md](docs/agent-build-runbook.md). The CLI historically mis-types this agent, so it's built manually.

### 9. Run the demo

See [docs/demo-script.md](docs/demo-script.md).

---

## Repository layout

```
├── force-app/main/default/
│   ├── classes/
│   │   ├── SelectMarketingImage.cls              @InvocableMethod the agent calls
│   │   ├── SelectMarketingImageTest.cls
│   │   ├── DataCloudRetrieverClient.cls          Thin REST wrapper
│   │   └── DataCloudCatalogProvider.cls          Implements IContentfulAssetProvider from sibling repo
│   └── permissionsets/
│       └── MarketingImageAgent.permissionset-meta.xml
├── datacloud-spec/                               Data Cloud schema (configured in UI, not SFDX-deployable)
│   ├── dataStreams/
│   ├── mktDataModels/
│   ├── mktDataTransformsObjects/
│   └── retrievers/
├── scripts/
│   ├── seed-contentful-assets.js
│   ├── verify-dmo.sh
│   ├── seed-assets/
│   └── package.json
├── docs/
│   ├── datacloud-setup.md
│   ├── contentful-webhook-setup.md
│   ├── agent-build-runbook.md
│   ├── demo-script.md
│   └── troubleshooting.md
├── reference/
│   └── content-builder-agent.agent               Reference AgentScript (not deployed)
├── sfdx-project.json
└── README.md
```

---

## Explicitly out of scope

- Everything the sibling repo covers (the LWC, Contentful auth, direct-provider path)
- Governance / "approved for autonomous use" flag workflow
- Audit logging of agent selections
- Confidence thresholds and no-result fallbacks
- Observability dashboards
- `AiEvaluationDefinition` test specs — manual testing only
- Security review, PII classification, DLP
