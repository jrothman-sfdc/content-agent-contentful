#!/usr/bin/env node
/**
 * Seed Contentful with demo marketing assets for the Content Builder image-selection POC.
 *
 * Reads seed-assets/manifest.json. For each asset:
 *   1. Ensures the required tags exist in the space (creates missing ones).
 *   2. Uploads the binary from seed-assets/<file>.
 *   3. Creates (or updates, keyed by assetKey) a Contentful asset with:
 *        - title / description
 *        - locale, campaign, visualStyle tags (format: dimension_value, e.g. locale_en_US)
 *   4. Processes and publishes it.
 *
 * Publish fires the webhook subscribed in Contentful which lands the asset in
 * the Data Cloud MarketingImage DMO (see docs/contentful-webhook-setup.md).
 *
 * Usage:
 *   cp .env.example .env     # fill in CONTENTFUL_CMA_TOKEN, SPACE_ID, ENVIRONMENT
 *   npm install
 *   npm run seed             # upload & publish everything
 *   npm run seed:dry-run     # parse manifest, confirm files exist, no API calls
 */

import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve, join } from 'node:path';
import mime from 'mime-types';
import contentfulManagement from 'contentful-management';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SEED_DIR = join(__dirname, 'seed-assets');
const MANIFEST_PATH = join(SEED_DIR, 'manifest.json');

const DRY_RUN = process.argv.includes('--dry-run');

const {
  CONTENTFUL_CMA_TOKEN,
  CONTENTFUL_SPACE_ID,
  CONTENTFUL_ENVIRONMENT = 'master',
} = process.env;

function requireEnv(name, value) {
  if (!value) {
    console.error(`Missing ${name}. Copy .env.example to .env and fill it in.`);
    process.exit(1);
  }
}

function tagId(dimension, value) {
  // Contentful tag IDs: letters, numbers, underscores, dashes. Normalize value.
  const safe = String(value).replace(/[^A-Za-z0-9_]/g, '_');
  return `${dimension}_${safe}`;
}

async function ensureTag(environment, id, name) {
  try {
    return await environment.getTag(id);
  } catch (err) {
    if (err.name === 'NotFound' || /404/.test(String(err))) {
      return environment.createTag(id, name, 'public');
    }
    throw err;
  }
}

async function ensureAllTags(environment, manifest) {
  const needed = new Map(); // id -> displayName
  for (const row of manifest.assets) {
    needed.set(tagId('locale', row.locale), `Locale: ${row.locale}`);
    needed.set(tagId('campaign', row.campaign), `Campaign: ${row.campaign}`);
    needed.set(tagId('visualStyle', row.visualStyle), `Visual Style: ${row.visualStyle}`);
  }
  for (const [id, name] of needed) {
    process.stdout.write(`  tag ${id} ... `);
    if (DRY_RUN) { console.log('(dry-run)'); continue; }
    await ensureTag(environment, id, name);
    console.log('ok');
  }
}

async function upsertAsset(environment, row) {
  const assetKey = row.assetKey; // stable identifier the webhook will carry forward as the DMO primary key

  // Try to fetch an existing asset by searching for one whose title matches assetKey in metadata.
  // Contentful doesn't let us set sys.id on create, so we track the mapping via the asset's "assetKey" tag.
  const existing = await environment.getAssets({
    'metadata.tags.sys.id[in]': tagId('assetKey', assetKey),
    limit: 1,
  });

  const filePath = resolve(SEED_DIR, row.file);
  if (!existsSync(filePath)) {
    throw new Error(`Missing file: ${filePath}`);
  }
  const contentType = mime.lookup(filePath) || 'application/octet-stream';
  const fileBuffer = await readFile(filePath);

  const tags = [
    { sys: { type: 'Link', linkType: 'Tag', id: tagId('locale', row.locale) } },
    { sys: { type: 'Link', linkType: 'Tag', id: tagId('campaign', row.campaign) } },
    { sys: { type: 'Link', linkType: 'Tag', id: tagId('visualStyle', row.visualStyle) } },
    { sys: { type: 'Link', linkType: 'Tag', id: tagId('assetKey', assetKey) } },
  ];

  const fields = {
    title: { 'en-US': row.title },
    description: { 'en-US': row.description || '' },
    file: {
      'en-US': {
        contentType,
        fileName: row.file,
        file: fileBuffer,
      },
    },
  };

  if (DRY_RUN) {
    console.log(`  [dry-run] would upsert ${assetKey} (${row.file}) tags=${tags.map(t => t.sys.id).join(',')}`);
    return;
  }

  let asset;
  if (existing.items.length > 0) {
    asset = existing.items[0];
    asset.fields = fields;
    asset.metadata = { tags };
    asset = await asset.update();
    console.log(`  updated ${assetKey}`);
  } else {
    asset = await environment.createAssetWithId(assetKey, { fields, metadata: { tags } });
    console.log(`  created ${assetKey}`);
  }

  asset = await asset.processForAllLocales();
  asset = await asset.publish();
  console.log(`  published ${assetKey} -> ${asset.fields.file['en-US'].url}`);
}

async function main() {
  if (!DRY_RUN) {
    requireEnv('CONTENTFUL_CMA_TOKEN', CONTENTFUL_CMA_TOKEN);
    requireEnv('CONTENTFUL_SPACE_ID', CONTENTFUL_SPACE_ID);
  }

  if (!existsSync(MANIFEST_PATH)) {
    console.error(`Missing manifest at ${MANIFEST_PATH}`);
    console.error('See seed-assets/manifest.example.json for the expected format.');
    process.exit(1);
  }
  const manifest = JSON.parse(await readFile(MANIFEST_PATH, 'utf8'));
  if (!Array.isArray(manifest.assets) || manifest.assets.length === 0) {
    console.error('manifest.json has no assets.');
    process.exit(1);
  }
  console.log(`Loaded ${manifest.assets.length} assets from manifest.`);

  let environment;
  if (!DRY_RUN) {
    const client = contentfulManagement.createClient({ accessToken: CONTENTFUL_CMA_TOKEN });
    const space = await client.getSpace(CONTENTFUL_SPACE_ID);
    environment = await space.getEnvironment(CONTENTFUL_ENVIRONMENT);
  }

  console.log('\nEnsuring tags exist...');
  if (!DRY_RUN) await ensureAllTags(environment, manifest);
  else await ensureAllTags(null, manifest);

  console.log('\nSeeding assets...');
  for (const row of manifest.assets) {
    try {
      if (DRY_RUN) await upsertAsset(null, row);
      else await upsertAsset(environment, row);
    } catch (err) {
      console.error(`  FAILED ${row.assetKey}:`, err.message);
    }
  }

  console.log('\nDone.');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
