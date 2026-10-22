#!/usr/bin/env bash
# Quick sanity check: list current MarketingImage__dlm rows from Data Cloud via sf CLI.
#
# Usage: ./verify-dmo.sh <org-alias>
#
# Requires: sf CLI v2+ with the data-cloud plugin, and the user authenticated to the org.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <org-alias>"
  exit 1
fi
ORG="$1"

echo "Querying MarketingImage__dlm in org '$ORG'..."
sf data-cloud query \
  --target-org "$ORG" \
  --query "SELECT assetId__c, title__c, locale__c, campaign__c, visualStyle__c, isActive__c, url__c FROM MarketingImage__dlm LIMIT 100"
