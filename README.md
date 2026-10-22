# Autonomous Image Selection in the MCA Content Builder Agent — POC

## What this is

A proof-of-concept Agentforce agent for Marketing Cloud Advanced (MCA) that autonomously selects images from a Contentful library when generating email / landing-page sections. The agent is a full clone of Salesforce's `sfdc_cms__ContentBuilderAgent` plus one new action, `SelectMarketingImage`, that queries a Data Cloud DMO populated by Contentful via webhook.

**Audience:** Internal demo. Not production hardened — no governance flag, no audit trail, no fallback logic, no security review.

**Variant dimensions:** Images are selected along three axes:
- `locale` — driven by the content builder canvas's `TargetLanguage`
- `campaign` — inferred from the user prompt or passed via session context
- `visualStyle` — inferred from tone cues in the user prompt or passed via session context

Within those structured filters, a semantic retriever ranks matches on `keyMessage` + optional context.

---

## How it fits together

```
                        ┌───────────────────────────────────────────┐
                        │             Contentful Space               │
                        │   (assets tagged by locale, campaign,       │
                        │    visualStyle; title + description for     │
                        │    semantic ranking)                        │
                        └──────────────┬────────────────────────────┘
                                       │  Asset.publish /
                                       │  Asset.unpublish /
                                       │  Asset.delete  (webhook)
                                       ▼
                        ┌───────────────────────────────────────────┐
                        │   Data Cloud Ingestion API endpoint        │
                        │   → DLO → mapping → MarketingImage__dlm    │
                        │   (soft delete via isActive on unpublish)  │
                        │   semantic index on title+description+tags │
                        └──────────────┬────────────────────────────┘
                                       │  Retriever
                                       ▼
                        ┌───────────────────────────────────────────┐
                        │   Apex invocable: SelectMarketingImage     │
                        │   inputs: keyMessage, locale, campaign,    │
                        │           visualStyle, contextDescription  │
                        │   outputs: assetUrl, altText, assetId, ... │
                        └──────────────┬────────────────────────────┘
                                       │  called by
                                       ▼
                        ┌───────────────────────────────────────────┐
                        │   Agentforce agent (built in-org, UI)      │
                        │   clone of CMS Content Builder agent +     │
                        │   SelectMarketingImage action; modified    │
                        │   CreateOrRefineSectionWithContent         │
                        │   reasoning instructions inject assetUrl   │
                        │   into blockValue image components         │
                        └──────────────┬────────────────────────────┘
                                       │  JSON Patch
                                       ▼
                        ┌───────────────────────────────────────────┐
                        │   MCA Content Builder canvas renders       │
                        │   generated copy + Contentful-hosted image │
                        └───────────────────────────────────────────┘
```

---

## Prerequisites

- Salesforce org with **Data Cloud**, **Agentforce**, and **Marketing Cloud Advanced** enabled
- **Contentful** space with Content Management API access
- **`sf` CLI** v2.x authenticated to the target Salesforce org
- **Node.js** 18+ for running the Contentful seed script
- Permission to create agents in the Agent Builder UI

---

## Reproduction runbook

Follow in order. Each step references its own doc for detail.

### 1. Clone this repo and install seed-script dependencies

```bash
git clone <this-repo-url> content-agent-contentful
cd content-agent-contentful/scripts
npm install
```

### 2. Deploy Salesforce metadata

```bash
sf project deploy start --target-org <your-org-alias>
```

This deploys:
- `SelectMarketingImage` Apex class (+ test + retriever client helper)
- `MarketingImageAgent` permission set
- `Contentful_Image` custom CMS content type

**Not deployed via SFDX** (configure manually in the Data Cloud UI — see [docs/datacloud-setup.md](docs/datacloud-setup.md)):
- `MarketingImage__dlm` DMO + supporting DLO + mapping + retriever
- Reference XML lives in `datacloud-spec/` for anyone reproducing the schema

Then assign the permission set to the user running the agent (and to the Agentforce agent user):

```bash
sf org assign permset --name MarketingImageAgent --target-org <your-org-alias>
```

### 3. Enable Data Cloud ingestion for the DLO

Follow [docs/datacloud-setup.md](docs/datacloud-setup.md): create the Ingestion API connector, confirm the DLO is receiving data, verify the retriever returns results against the empty DMO (it shouldn't crash).

### 4. Configure the Contentful → Data Cloud webhook

Follow [docs/contentful-webhook-setup.md](docs/contentful-webhook-setup.md): create the webhook in Contentful pointing at your Data Cloud Ingestion API endpoint, subscribe to publish / unpublish / delete, apply the payload template.

### 5. Seed Contentful with demo assets

Place a Contentful CMA token in `scripts/.env` (see `.env.example`), then:

```bash
cd scripts
npm run seed
```

This uploads 20–50 images from `scripts/seed-assets/` with full variant metadata (locale × campaign × visualStyle). The webhook will fire and populate the DMO.

### 6. Verify DMO population

```bash
cd scripts
./verify-dmo.sh <your-org-alias>
```

Should list all seeded assets with `isActive = true`.

### 7. Spike the MCA render path

Before building the agent, confirm the content builder canvas renders a Contentful URL in an image component. Hardcoded JSON Patch test described in [docs/troubleshooting.md](docs/troubleshooting.md). **If this fails, stop and fix before continuing.**

### 8. Build the agent in the Agent Builder UI

Follow [docs/agent-build-runbook.md](docs/agent-build-runbook.md) carefully. The CLI historically mis-types this agent, so **the agent is built manually in-org**. The runbook includes the final reasoning instructions and action wiring; [reference/content-builder-agent.agent](reference/content-builder-agent.agent) is the canonical AgentScript representation to mirror in the UI.

### 9. Run the demo

See [docs/demo-script.md](docs/demo-script.md) for the scripted prompts and expected behavior across the three variant dimensions.

---

## Repository layout

```
├── force-app/main/default/
│   ├── classes/                       SelectMarketingImage Apex class
│   ├── permissionsets/                MarketingImageAgent permset
│   └── managedContentTypes/           Contentful_Image custom CMS content type
├── datacloud-spec/                    Data Cloud schema (configured in UI, not SFDX-deployable)
│   ├── dataStreams/                   DLO for Contentful webhook payloads
│   ├── mktDataModels/                 MarketingImage__dlm DMO
│   ├── mktDataTransformsObjects/      DLO → DMO mapping
│   └── retrievers/                    Data Cloud Retriever
├── scripts/
│   ├── seed-contentful-assets.js      Node CMA-SDK seed script
│   ├── seed-assets/                   Local images + manifest.json
│   ├── verify-dmo.sh                  Query DMO rows via sf CLI
│   └── package.json
├── docs/
│   ├── datacloud-setup.md
│   ├── contentful-webhook-setup.md
│   ├── agent-build-runbook.md
│   ├── demo-script.md
│   └── troubleshooting.md
├── reference/
│   └── content-builder-agent.agent    Reference AgentScript (NOT deployed)
├── sfdx-project.json
└── README.md (this file)
```

---

## Explicitly out of scope

- Governance / "approved for autonomous use" flag workflow
- Audit logging of agent selections
- Confidence thresholds and no-result fallbacks
- Multi-image sections (one image per section for demo)
- "Replace this image" refinement flow
- Observability dashboards and session trace analysis
- `AiEvaluationDefinition` test specs — manual testing only
- Security review, PII classification, DLP

---

## Known risks

See [docs/troubleshooting.md](docs/troubleshooting.md).
