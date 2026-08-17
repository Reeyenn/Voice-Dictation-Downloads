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
  'contents: write' \
  'macos-15-intel' \
  'runs-on: macos-15' \
  'app_zip_sha256' \
  'validation_bundle_sha256' \
  'Validate-MacDistribution.sh'; do
  require_text "$WORKFLOW" "$required"
done

if grep -Fq 'contents: read' "$WORKFLOW"; then
  fail 'macOS draft-release validation requires contents: write; contents: read cannot see draft releases'
fi

for required in \
  "Voice-Dictation-macOS-\$VERSION.zip" \
  "Voice-Dictation-macOS-Universal-Validation-\$VERSION.zip" \
  'bootstrap release must remain a draft' \
  'Voice-Dictation-MacValidation/VoiceDictationMacValidation' \
  'Voice-Dictation-MacValidation/run-mac-validation.sh' \
  'VALIDATED_ASSET_URLS' \
  're.fullmatch' \
  'parsed.netloc' \
  'parsed.hostname' \
  'parsed.username' \
  'parsed.password' \
  'parsed.port' \
  'parsed.params' \
  'parsed.query' \
  'parsed.fragment' \
  'exact same-repository GitHub release-asset URL' \
  'VD_MAC_VALIDATION_MODEL_PRELOAD' \
  'VD_MAC_VALIDATION_CASE' \
  'VD_MAC_VALIDATION_SILENCE' \
  'assert_universal2' \
  'codesign --verify --deep --strict'; do
  require_text "$VALIDATOR" "$required"
done
require_text "$VALIDATOR" 'clear_workflow_tokens'
require_text "$VALIDATOR" 'unset GITHUB_TOKEN GH_TOKEN'
require_text "$VALIDATOR" 'TOKEN AUTH_HEADER'
require_text "$VALIDATOR" "(cd \"\$VALIDATION_DIR\" && ./run-mac-validation.sh"
require_text "$VALIDATOR" 'PIPESTATUS[0]'
require_text "$VALIDATOR" 'for tool in curl python3 unzip shasum plutil codesign lipo file open lsof; do'
require_text "$VALIDATOR" 'open -n "$APP_PATH"'
require_text "$VALIDATOR" 'lsof -t -a -d txt -- "$APP_MAIN"'
require_text "$VALIDATOR" 'ps -axo pid,ppid,comm,args'
require_text "$VALIDATOR" 'tail -n 40 "$launch_log"'
require_text "$VALIDATOR" 'redact_diagnostics'

python3 - "$VALIDATOR" <<'PY'
from pathlib import Path
from urllib.parse import urlparse
import re
import sys

validator = Path(sys.argv[1]).read_text(encoding='utf-8')
for marker in (
    'expected_path = rf\'/repos/{re.escape(repository)}/releases/assets/[1-9][0-9]*\'',
    'validated_asset_urls[expected] = raw_url',
    'asset_urls = json.load(handle)',
):
    if marker not in validator:
        raise SystemExit(f'validator is missing URL-boundary marker: {marker}')

repository = 'Reeyenn/Voice-Dictation-Downloads'

def accepted(url: str) -> bool:
    try:
        parsed = urlparse(url)
        port = parsed.port
    except ValueError:
        return False
    expected_path = rf'/repos/{re.escape(repository)}/releases/assets/[1-9][0-9]*'
    return not (
        parsed.scheme != 'https'
        or parsed.netloc not in {'api.github.com', 'api.github.com:443'}
        or parsed.hostname != 'api.github.com'
        or parsed.username is not None
        or parsed.password is not None
        or port not in (None, 443)
        or parsed.params
        or parsed.query
        or parsed.fragment
        or '?' in url
        or '#' in url
        or re.fullmatch(expected_path, parsed.path) is None
    )

base = f'https://api.github.com/repos/{repository}/releases/assets/'
fixtures = {
    base + '123': True,
    base + '456': True,
    f'https://api.github.com:443/repos/{repository}/releases/assets/789': True,
    f'https://api.github.com/repos/Other/Voice-Dictation-Downloads/releases/assets/123': False,
    f'https://api.github.com/repos/{repository}-prefix/releases/assets/123': False,
    f'https://api.github.com/repos/{repository}-suffix/releases/assets/123': False,
    f'https://api.github.com/repos/{repository}/releases/assets/123/extra': False,
    f'https://attacker@api.github.com/repos/{repository}/releases/assets/123': False,
    f'https://api.github.com:8443/repos/{repository}/releases/assets/123': False,
    base + '123?download=1': False,
    base + '123#fragment': False,
    base + 'not-a-number': False,
    base + '0': False,
}
for url, expected in fixtures.items():
    actual = accepted(url)
    if actual != expected:
        raise SystemExit(f'asset URL fixture mismatch for {url!r}: expected {expected}, got {actual}')
print('macOS exact same-repository asset URL fixtures passed')
PY

download_start="$(grep -n '^download_asset()' "$VALIDATOR" | head -n 1 | cut -d: -f1)"
download_end="$(grep -n '^assert_sha256()' "$VALIDATOR" | head -n 1 | cut -d: -f1)"
if [[ -z "$download_start" || -z "$download_end" || "$download_end" -le "$download_start" ]]; then
  fail 'could not isolate download_asset for validated-URL contract checking'
fi
download_body="$(sed -n "${download_start},$((download_end - 1))p" "$VALIDATOR")"
if ! grep -Fq '$VALIDATED_ASSET_URLS' <<<"$download_body"; then
  fail 'download_asset must read only the validated asset URL map'
fi
if grep -Fq '$RELEASE_JSON' <<<"$download_body"; then
  fail 'download_asset must not re-read unvalidated release JSON URLs'
fi

if grep -Eiq 'swift[[:space:]]+test|xcodebuild|git[[:space:]]+(clone|fetch)|Voice-Dictation\.git' "$WORKFLOW" "$VALIDATOR"; then
  fail 'binary-only validation must not build or fetch private source'
fi
if grep -Fq 'VD_INTEL_VALIDATION_' "$VALIDATOR"; then
  fail 'macOS validation markers must be architecture-neutral'
fi
if grep -Fq 'run-intel-validation.sh' "$VALIDATOR"; then
  fail 'macOS validation launcher must be architecture-neutral'
fi
if grep -Fq "\"\$VALIDATION_EXE\" --max-latency-seconds" "$VALIDATOR"; then
  fail 'macOS validator must invoke the packaged launcher, not the binary directly'
fi
if grep -Fq "&& \"\$VALIDATION_EXE\"" "$VALIDATOR"; then
  fail 'macOS validator must not execute the validation binary outside its packaged launcher'
fi
if grep -Eiq '(^|[[:space:];|])pgrep([[:space:]]|$)|open[[:space:]]+-W|^[[:space:]]*"\$APP_MAIN"[[:space:]]' "$VALIDATOR"; then
  fail 'macOS app launch validation must use LaunchServices plus exact lsof PIDs only'
fi

scrub_line="$(grep -n '^clear_workflow_tokens$' "$VALIDATOR" | tail -n 1 | cut -d: -f1)"
open_line="$(grep -n '^open -n ' "$VALIDATOR" | head -n 1 | cut -d: -f1)"
lsof_line="$(grep -n 'lsof -t -a -d txt -- \"\$APP_MAIN\"' "$VALIDATOR" | head -n 1 | cut -d: -f1)"
diagnostics_line="$(grep -n '^[[:space:]]*show_launch_diagnostics$' "$VALIDATOR" | head -n 1 | cut -d: -f1)"
cleanup_line="$(grep -n 'kill \"\$app_pid\"' "$VALIDATOR" | head -n 1 | cut -d: -f1)"
runner_line="$(grep -n 'run-mac-validation\.sh.*--max-latency-seconds' "$VALIDATOR" | head -n 1 | cut -d: -f1)"
if [[ -z "$scrub_line" || -z "$open_line" || -z "$lsof_line" || -z "$diagnostics_line" || -z "$cleanup_line" || -z "$runner_line" || \
      "$scrub_line" -ge "$open_line" || "$scrub_line" -ge "$runner_line" || \
      "$open_line" -ge "$lsof_line" || "$lsof_line" -ge "$diagnostics_line" || \
      "$diagnostics_line" -ge "$cleanup_line" || "$cleanup_line" -ge "$runner_line" ]]; then
  fail 'token scrub, exact PID launch check, diagnostics, cleanup, and validator launch are out of order'
fi

bash -n "$VALIDATOR"
printf 'macOS binary-only distribution contract checks passed.\n'
