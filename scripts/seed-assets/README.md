# seed-assets/

Drop your demo image files (JPG / PNG, ~2MB max each) in this directory, then describe them in `manifest.json`.

## Setup

1. Copy `manifest.example.json` to `manifest.json`.
2. For each row, make sure:
   - `file` points to a real file in this directory.
   - `assetKey` is unique, letters/numbers/underscores/dashes only. This becomes the Contentful `sys.id` and the Data Cloud `assetId__c` primary key.
   - `locale`, `campaign`, `visualStyle` use values appropriate for your demo. The seed script normalizes any non-alphanumeric characters to `_` when creating Contentful tags.
   - `title` and `description` are meaningful English — the Data Cloud retriever's semantic index uses them for ranking, so write them like real alt text / caption copy.

## Variant dimensions for the demo

Pick at least 2 values per dimension so the demo can show swaps:

- **locale** — e.g. `en_US`, `en_GB`
- **campaign** — e.g. `summer_sale`, `holiday`, `back_to_school`
- **visualStyle** — e.g. `editorial`, `product_shot`, `lifestyle`, `bright`, `muted`

## Running

```bash
# From the scripts/ directory:
npm install
npm run seed:dry-run    # confirms manifest is valid and files exist
npm run seed            # uploads, tags, and publishes to Contentful
```

The script is idempotent — running it twice updates existing assets rather than duplicating them.

## Images not committed

Binary image files are gitignored by default so the repo stays small. If you want other people to reproduce this with the same assets, either:

- Commit the images directly (remove the ignore rule in `scripts/seed-assets/.gitignore`), or
- Host them somewhere and update the README with a one-line `curl` / `wget` fetch step.
