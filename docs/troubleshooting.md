# Troubleshooting & known risks

## Pre-build render spike (do this first)

Before any of the agent work, confirm the MCA Content Builder canvas renders a Contentful URL in an image component. If it doesn't, the whole POC falls over — stop and figure out why before continuing.

**How to spike:**

1. Create a draft email in Content Builder.
2. Drag an image component onto the canvas.
3. In the component's `src`, paste any Contentful CDN URL you've already published, e.g. `https://images.ctfassets.net/<space>/<asset>/<hash>/filename.jpg`.
4. Confirm the image renders in the canvas preview AND when you send a test send.

**If it doesn't render:**
- CSP / referrer-policy issue? Check the canvas iframe's console for blocked requests.
- Is MCA's content proxy rewriting external URLs? Look for a `src` that got replaced with a tracking pixel wrapper that doesn't resolve.
- Content type restriction? Confirm the image component accepts arbitrary URLs vs only CMS-managed assets.

Any of those paths require a host-app fix which is outside POC scope — you'd need to escalate to the MCA engineering team.

## Known risks (from the plan)

### 1. MCA JSON Patch render path
Mitigated by the spike above. Highest-severity unknown.

### 2. Contentful webhook payload shape vs Data Cloud Ingestion API source schema
The payload template in `docs/contentful-webhook-setup.md` was written against Contentful's current webhook DSL. If Contentful has updated their filter syntax (e.g. `map`/`join` filter names), the `tags` field will arrive as an array JSON string instead of a comma-separated string, and the DMO mapping regex won't match.

**Symptom:** DMO rows appear but `locale__c` / `campaign__c` / `visualStyle__c` are all empty.

**Fix:** Open Data Cloud → Data Streams → `ContentfulAssetWebhook` → Monitor → inspect a sample inbound payload. Adjust either (a) the Contentful payload template to produce the expected shape, or (b) the DMO mapping's regex to parse what's actually arriving.

### 3. Retriever relevance quality
With only 20–50 seed assets, edge-case prompts may return odd matches.

**Mitigation:** Keep the demo script tight. Rehearse. If a prompt returns an unexpected asset, either:
- Add a more specific tag/description to the preferred asset (reseed), or
- Reword the demo prompt so it semantically aligns.

### 4. Agent-build CLI mis-typing issue
Why the agent is built in-UI, not via `sf project deploy start`. Do not attempt to export the agent via `sf agent generate` and re-import — it will corrupt the agent template type to `Standard` instead of `AgentforceEmployeeAgent`.

### 5. Named Credential for the Data Cloud retriever call
`DataCloudRetrieverClient.cls` uses a Named Credential `DataCloud`. If your org exposes the retriever via a different mechanism (first-party Apex, ConnectApi, or a different REST path shape), update that one class — `SelectMarketingImage.cls` is unaffected.

**Setup for the Named Credential:**
- Setup → Security → Named Credentials → New Named Credential
- Label: `Data Cloud`, Name: `DataCloud`
- URL: your org's Data Cloud API base (e.g. `https://<your-org>.c360a.salesforce.com`)
- Identity Type: Named Principal
- Auth Protocol: OAuth 2.0 against a Connected App that has Data Cloud API scopes
- Mark "Generate Authorization Header" ON

### 6. OAuth token refresh for the Contentful webhook auth header
The Data Cloud Ingestion API bearer token used in the webhook config will expire. For a POC demo this is fine — just generate a long-lived token at setup time. For anything production you'd rotate via refresh-token flow.

### 7. Protocol-relative Contentful URLs
Contentful returns `//images.ctfassets.net/...` instead of `https://images.ctfassets.net/...`. The webhook payload template prepends `https:` for this reason. If you ever bypass the template and ingest raw payloads, you'll end up with URLs that don't resolve.

## Common runtime errors

| Symptom | Likely cause | Fix |
|---|---|---|
| Agent returns copy but no image | `SelectMarketingImage` returned empty | Check retriever directly from Data Cloud UI with the same filters; usually a tag/filter mismatch |
| Image appears broken (404) | `url__c` has `null:` prefix or missing scheme | Re-check the webhook payload template; reseed the affected asset |
| Agent never calls `SelectMarketingImage` | Reasoning instructions not saved in Agent Builder | Re-apply `docs/agent-build-runbook.md` steps 5–6 |
| Retriever call errors with 401 | Named Credential `DataCloud` not set up or lacks Data Cloud scope | See risk 5 above |
| DMO row created but `isActive__c = false` after a publish | `eventType` field didn't carry the Contentful topic string | Confirm the payload template includes `"eventType": "{ /topic }"` |
| Contentful tag ID rejected on seed | Tag ID had colon, hyphen, or special char | Seed script normalizes, but a hand-created tag with `-` or `:` won't match the mapping regex. Use underscores. |
