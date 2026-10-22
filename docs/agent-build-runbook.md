# Agent build runbook (manual, in Agent Builder UI)

The agent is built manually in the Agent Builder UI because the Salesforce CLI historically mis-types `AgentforceEmployeeAgent` templates when deployed from source. This doc walks you through mirroring `reference/content-builder-agent.agent` in the UI.

**Before you start:**
- Metadata deployed (`sf project deploy start`).
- Permission set `MarketingImageAgent` assigned to your user AND the agent user.
- Data Cloud retriever confirmed returning results against seeded assets.
- Render spike completed — see `docs/troubleshooting.md`.

## Step 1 — Clone the stock agent

Setup → Agentforce → **Agents** → find `CMS Content Agent` (the stock agent, template `sfdc_cms__ContentBuilderAgent`) → **Clone**.

- **Agent Label:** `CMS Content Agent (Image POC)`
- **API Name:** `CMS_Content_Agent_Image_POC`
- **Description:** `Clone of the stock CMS Content Builder agent plus an autonomous image-selection action backed by a Data Cloud catalog of Contentful assets.`

Save. **Do NOT activate yet.**

## Step 2 — Add the new session context variables (optional)

Agent detail → **Session Context Variables** → **Add**.

| Name | Type | Visibility | Description |
|---|---|---|---|
| `Campaign` | Text (mutable) | External | Optional campaign override from the host app |
| `VisualStyle` | Text (mutable) | External | Optional visual-style override from the host app |

Skip this step if your host app will not supply these — the agent will infer from the user's prompt instead. The variables cause no harm when present-but-unset.

## Step 3 — Add the SelectMarketingImage action

Agent detail → **Actions** → **Add → From Apex invocable**.

- Select `Marketing Cloud: Select Marketing Image` (the Apex method deployed earlier).
- Label: `Marketing Cloud: Select Marketing Image`
- Description: *(paste from the SelectMarketingImage section of `reference/content-builder-agent.agent`)*
- **Require user confirmation:** off
- **Include in progress indicator:** on

For each input (`keyMessage`, `contextDescription`, `locale`, `campaign`, `visualStyle`):
- Set the description from the reference file.
- `is_required`: true only for `keyMessage`.
- `is_user_input`: false (the planner fills these — they do not come directly from user text).

For each output (`assetUrl`, `altText`, `assetId`, `campaign`, `visualStyle`, `imageBlockJson`):
- `is_displayable`: true for `assetUrl`, `altText`, `campaign`, `visualStyle`. False for `assetId` and `imageBlockJson`.
- `is_used_by_planner`: true for `assetUrl`, `altText`, `assetId`, `imageBlockJson`.

The `imageBlockJson` output is the key one — it's a ready-to-splice `lightning/html` block (serialized JSON) that the agent injects into `blockValue`. The agent does NOT emit a `lightning/image` block for externally-sourced images, because the MCA schema rejects them.

Save.

## Step 4 — Attach the action to the ContentCreation topic

Agent detail → Topics → **ContentCreation** → Actions → **Add existing** → select `Marketing Cloud: Select Marketing Image`.

## Step 5 — Update the ContentCreation topic reasoning instructions

In the topic's reasoning instructions, append:

> When CreateOrRefineSectionWithContent generates a section that needs an image, call SelectMarketingImage BEFORE returning the final JSON patch. The MCA email schema rejects external URLs on lightning/image blocks (imageInfo.source.type must equal "imageReference" with a Salesforce CMS asset ref), so for externally-sourced images we use the lightning/html block that SelectMarketingImage returns as imageBlockJson.

## Step 6 — Update CreateOrRefineSectionWithContent action-specific instructions

In the action's "when to use" / reasoning text, add:

> If the resulting section needs an image, you MUST call SelectMarketingImage FIRST and then splice its imageBlockJson output into blockValue. Map SelectMarketingImage inputs:
> - `keyMessage`: the keyMessage you passed into this action
> - `contextDescription`: the generated section's heading + first paragraph
> - `locale`: the `TargetLanguage` session variable, verbatim (do not transform)
> - `campaign`: the `Campaign` session variable if set; otherwise infer from `userInput` / `keyMessage` if a clear campaign is named (e.g. "summer sale" → `summer_sale`); otherwise omit
> - `visualStyle`: the `VisualStyle` session variable if set; otherwise infer from tone cues in `userInput` / `personality` (e.g. "editorial" → `editorial`, "clean product shot" → `product_shot`); otherwise omit
>
> Then in blockValue:
> - If the generated section contains any `lightning/image` placeholder, REMOVE it (the canvas rejects it at save time).
> - Parse `SelectMarketingImage`'s `imageBlockJson` into an object and insert it into the same column where the placeholder was, or append to the section's first column if no placeholder existed.
> - If `imageBlockJson` is empty (no catalog match), leave the section without an image rather than inserting a broken block.

## Step 7 — Activate & smoke test

Activate the agent. Open the Preview pane and try:

> "Create a promo email section with a headline, paragraph, and image for our summer sale."

Expected plan:
1. `CreateOrRefineSectionWithContent` generates the section with an image component.
2. `SelectMarketingImage` runs with `keyMessage="summer sale promo"`, `campaign="summer_sale"`, `locale=` (whatever `TargetLanguage` is set to in preview).
3. The returned `assetUrl` is injected into the section's image component.
4. The final JSON Patch is returned to the preview.

If step 2 doesn't fire, re-check the reasoning instructions in step 5 and 6. The agent's planner follows what's written there; it won't call an action it hasn't been told to call.

## Step 8 — Point the host app at the new agent

In Content Builder's agent assignment (or wherever MCA selects which Agentforce agent runs for content assistance), swap in `CMS_Content_Agent_Image_POC`. The host app's existing `TargetLanguage` session variable will flow through automatically.
