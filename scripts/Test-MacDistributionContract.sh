#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/macos-distribution.yml"
VALIDATOR="$ROOT_DIR/scripts/Validate-MacDistribution.sh"

fail() {
  printf 'macOS distribution contract failed: %s\n' "$1" >&2
  exit 1
}

require_text() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file" || fail "$file is missing: $needle"
}

for required in \
  'workflow_dispatch:' \
  'macos-15-intel' \
  'runs-on: macos-15' \
  'app_zip_sha256' \
  'validation_bundle_sha256' \
  'Validate-MacDistribution.sh'; do
  require_text "$WORKFLOW" "$required"
done

for required in \
  "Voice-Dictation-macOS-\$VERSION.zip" \
  "Voice-Dictation-macOS-Universal-Validation-\$VERSION.zip" \
  'bootstrap release must remain a draft' \
  'Voice-Dictation-MacValidation/VoiceDictationMacValidation' \
  'Voice-Dictation-MacValidation/run-mac-validation.sh' \
  'VD_MAC_VALIDATION_MODEL_PRELOAD' \
  'VD_MAC_VALIDATION_CASE' \
  'VD_MAC_VALIDATION_SILENCE' \
  'assert_universal2' \
  'codesign --verify --deep --strict'; do
  require_text "$VALIDATOR" "$required"
done

if grep -Eiq 'swift[[:space:]]+test|xcodebuild|git[[:space:]]+(clone|fetch)|Voice-Dictation\.git' "$WORKFLOW" "$VALIDATOR"; then
  fail 'binary-only validation must not build or fetch private source'
fi
if grep -Fq 'VD_INTEL_VALIDATION_' "$VALIDATOR"; then
  fail 'macOS validation markers must be architecture-neutral'
fi
if grep -Fq 'run-intel-validation.sh' "$VALIDATOR"; then
  fail 'macOS validation launcher must be architecture-neutral'
fi

bash -n "$VALIDATOR"
printf 'macOS binary-only distribution contract checks passed.\n'
