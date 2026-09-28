#!/usr/bin/env bash
# Release gate for references/runtime-footer-rate-tier.patch.
#
# Clones NousResearch/hermes-agent main into a fresh scratch directory and
# checks that the patch still applies cleanly. Run this after any upstream
# runtime_footer.py drift, or on a schedule, to catch the patch going stale
# before a user hits the failure.
#
# Usage: scripts/check-patch.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="$REPO_ROOT/references/runtime-footer-rate-tier.patch"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Cloning NousResearch/hermes-agent main into $WORK_DIR ..."
git clone --depth 50 --quiet https://github.com/NousResearch/hermes-agent "$WORK_DIR"

cd "$WORK_DIR"
SHA="$(git rev-parse HEAD)"
echo "Checking $PATCH against $SHA"

if git apply --check "$PATCH"; then
  echo "OK: patch applies cleanly to NousResearch/hermes-agent main @ $SHA"
  exit 0
else
  echo "FAIL: patch no longer applies to NousResearch/hermes-agent main @ $SHA" >&2
  echo "Upstream has drifted past the file lines this patch targets. Port the" >&2
  echo "rate-tier change onto the current gateway/runtime_footer.py by hand" >&2
  echo "(use the running implementation in ~/.hermes/hermes-agent as reference)" >&2
  echo "and regenerate references/runtime-footer-rate-tier.patch." >&2
  exit 1
fi
