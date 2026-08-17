#!/usr/bin/env bash
set -euo pipefail

# Binary-only macOS release validation. This script intentionally consumes
# only assets from the public distribution repository; it never checks out or
# builds the private application source.
if [[ $# -ne 4 ]]; then
  echo "usage: $0 <version> <bootstrap-tag> <app-zip-sha256> <validation-zip-sha256>" >&2
  exit 64
fi

VERSION="$1"
BOOTSTRAP_TAG="$2"
APP_SHA256="$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]')"
VALIDATION_SHA256="$(printf '%s' "$4" | tr '[:upper:]' '[:lower:]')"
REPOSITORY="${GITHUB_REPOSITORY:-}"
TOKEN="${GITHUB_TOKEN:-}"
EXPECTED_ARCHITECTURE="${EXPECTED_ARCHITECTURE:-}"
MINIMUM_MACOS="${MINIMUM_MACOS:-15.6}"

fail() {
  echo "Mac distribution validation failed: $*" >&2
  exit 1
}

clear_workflow_tokens() {
  unset GITHUB_TOKEN GH_TOKEN GITHUB_API_TOKEN GH_ENTERPRISE_TOKEN GITHUB_APP_TOKEN ACTIONS_RUNTIME_TOKEN RUNNER_TOKEN TOKEN AUTH_HEADER
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool is missing: $1"
}

for tool in curl python3 unzip shasum plutil codesign lipo file open lsof; do
  require_tool "$tool"
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$ ]] || fail "invalid version: $VERSION"
[[ "$BOOTSTRAP_TAG" == "bootstrap-v$VERSION" ]] || fail "bootstrap tag must be bootstrap-v$VERSION"
[[ "$APP_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail 'app ZIP SHA-256 must be 64 lowercase hexadecimal characters'
[[ "$VALIDATION_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail 'validation ZIP SHA-256 must be 64 lowercase hexadecimal characters'
[[ "$REPOSITORY" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || fail 'GITHUB_REPOSITORY must be owner/name'
[[ -n "$TOKEN" ]] || fail 'GITHUB_TOKEN is required to read the exact bootstrap release'
if [[ -n "$EXPECTED_ARCHITECTURE" && "$EXPECTED_ARCHITECTURE" != "arm64" && "$EXPECTED_ARCHITECTURE" != "x86_64" ]]; then
  fail 'EXPECTED_ARCHITECTURE must be arm64 or x86_64'
fi

case "$MINIMUM_MACOS" in
  15.6|15.7|15.8|16|16.*) ;;
  *) fail "unsupported minimum macOS contract: $MINIMUM_MACOS" ;;
esac

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/voice-dictation-mac-validation.XXXXXX")"
cleanup() {
  local status=$?
  if [[ -d "$WORK_ROOT" ]]; then
    rm -rf -- "$WORK_ROOT"
  fi
  return "$status"
}
trap cleanup EXIT

APP_ASSET="Voice-Dictation-macOS-$VERSION.zip"
VALIDATION_ASSET="Voice-Dictation-macOS-Universal-Validation-$VERSION.zip"
RELEASE_JSON="$WORK_ROOT/release.json"
VALIDATED_ASSET_URLS="$WORK_ROOT/validated-asset-urls.json"
AUTH_HEADER="Authorization: Bearer $TOKEN"
API_HEADER='Accept: application/vnd.github+json'
API_VERSION_HEADER='X-GitHub-Api-Version: 2022-11-28'

release_url="https://api.github.com/repos/$REPOSITORY/releases/tags/$BOOTSTRAP_TAG"
if ! curl --fail --silent --show-error --location \
    -H "$AUTH_HEADER" -H "$API_HEADER" -H "$API_VERSION_HEADER" \
    -H 'User-Agent: voice-dictation-public-mac-validator' \
    "$release_url" -o "$RELEASE_JSON"; then
  release_list="$WORK_ROOT/releases.json"
  curl --fail --silent --show-error --location \
    -H "$AUTH_HEADER" -H "$API_HEADER" -H "$API_VERSION_HEADER" \
    -H 'User-Agent: voice-dictation-public-mac-validator' \
    "https://api.github.com/repos/$REPOSITORY/releases?per_page=100" -o "$release_list" \
    || fail "could not read bootstrap release $BOOTSTRAP_TAG"
  python3 - "$release_list" "$RELEASE_JSON" "$BOOTSTRAP_TAG" <<'PY'
import json
import sys

source, destination, expected_tag = sys.argv[1:]
with open(source, encoding='utf-8') as handle:
    releases = json.load(handle)
matches = [item for item in releases if item.get('tag_name') == expected_tag]
if len(matches) != 1:
    raise SystemExit(f'exactly one release with tag {expected_tag!r} is required; found {len(matches)}')
with open(destination, 'w', encoding='utf-8') as handle:
    json.dump(matches[0], handle)
PY
fi

python3 - "$RELEASE_JSON" "$BOOTSTRAP_TAG" "$APP_ASSET" "$VALIDATION_ASSET" "$REPOSITORY" "$VALIDATED_ASSET_URLS" <<'PY'
import json
import re
import sys
from urllib.parse import urlparse

path, expected_tag, app_name, validation_name, repository, validated_output = sys.argv[1:]
with open(path, encoding='utf-8') as handle:
    release = json.load(handle)
if release.get('tag_name') != expected_tag:
    raise SystemExit('release tag did not match the requested bootstrap tag')
if release.get('draft') is not True:
    raise SystemExit('the macOS bootstrap release must remain a draft during validation')
assets = release.get('assets') or []
validated_asset_urls = {}
for expected in (app_name, validation_name):
    matches = [asset for asset in assets if asset.get('name') == expected]
    if len(matches) != 1:
        raise SystemExit(f'release must contain exactly one asset named {expected!r}')
    raw_url = matches[0].get('url')
    if not isinstance(raw_url, str) or not raw_url:
        raise SystemExit(f'asset {expected!r} has no URL')
    try:
        parsed = urlparse(raw_url)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError as error:
        raise SystemExit(f'asset {expected!r} has an invalid URL authority: {error}') from error
    expected_path = rf'/repos/{re.escape(repository)}/releases/assets/[1-9][0-9]*'
    if (
        parsed.scheme != 'https'
        or parsed.netloc not in {'api.github.com', 'api.github.com:443'}
        or hostname != 'api.github.com'
        or parsed.username is not None
        or parsed.password is not None
        or port not in (None, 443)
        or parsed.params
        or parsed.query
        or parsed.fragment
        or '?' in raw_url
        or '#' in raw_url
        or re.fullmatch(expected_path, parsed.path) is None
    ):
        raise SystemExit(f'asset {expected!r} did not resolve to an exact same-repository GitHub release-asset URL')
    validated_asset_urls[expected] = raw_url
with open(validated_output, 'w', encoding='utf-8') as handle:
    json.dump(validated_asset_urls, handle, sort_keys=True)
PY

download_asset() {
  local asset_name="$1"
  local destination="$2"
  local asset_url
  asset_url="$(python3 - "$VALIDATED_ASSET_URLS" "$asset_name" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as handle:
    asset_urls = json.load(handle)
asset_url = asset_urls.get(sys.argv[2])
if not isinstance(asset_url, str) or not asset_url:
    raise SystemExit(f'no validated URL exists for asset {sys.argv[2]!r}')
print(asset_url)
PY
)"
  curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
    -H "$AUTH_HEADER" -H 'Accept: application/octet-stream' -H "$API_VERSION_HEADER" \
    -H 'User-Agent: voice-dictation-public-mac-validator' \
    "$asset_url" -o "$destination"
}

assert_sha256() {
  local path="$1"
  local expected="$2"
  local label="$3"
  local actual
  actual="$(shasum -a 256 "$path" | awk '{print tolower($1)}')"
  [[ "$actual" == "$expected" ]] || fail "$label SHA-256 mismatch: expected $expected, got $actual"
  [[ -s "$path" ]] || fail "$label is empty"
}

APP_ZIP="$WORK_ROOT/$APP_ASSET"
VALIDATION_ZIP="$WORK_ROOT/$VALIDATION_ASSET"
download_asset "$APP_ASSET" "$APP_ZIP" || fail "could not download $APP_ASSET"
download_asset "$VALIDATION_ASSET" "$VALIDATION_ZIP" || fail "could not download $VALIDATION_ASSET"
assert_sha256 "$APP_ZIP" "$APP_SHA256" "$APP_ASSET"
assert_sha256 "$VALIDATION_ZIP" "$VALIDATION_SHA256" "$VALIDATION_ASSET"
unzip -tqq "$APP_ZIP" || fail "$APP_ASSET failed ZIP integrity validation"
unzip -tqq "$VALIDATION_ZIP" || fail "$VALIDATION_ASSET failed ZIP integrity validation"
clear_workflow_tokens

validate_archive_entries() {
  local archive="$1"
  local kind="$2"
  python3 - "$archive" "$kind" <<'PY'
from pathlib import PurePosixPath
from zipfile import ZipFile
import sys

archive, kind = sys.argv[1:]
with ZipFile(archive) as z:
    infos = z.infolist()
    if not infos:
        raise SystemExit(f'{archive} is empty')
    seen = set()
    for info in infos:
        name = info.filename.replace('\\', '/')
        if name in seen:
            raise SystemExit(f'{archive} contains duplicate entry {name!r}')
        seen.add(name)
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or '__MACOSX' in path.parts or '.DS_Store' in path.parts:
            raise SystemExit(f'{archive} contains unsafe or macOS metadata entry {name!r}')
        if any(part in {'.git', '.build'} for part in path.parts):
            raise SystemExit(f'{archive} contains source/build metadata entry {name!r}')
        if kind == 'app' and any(name.lower().endswith(suffix) for suffix in ('.swift', '.xcodeproj', '.dsym')):
            raise SystemExit(f'{archive} contains source/debug entry {name!r}')
    if kind == 'app':
        roots = {name.split('/', 1)[0] for name in seen if name and not name.endswith('/')}
        if roots != {'Voice Dictation.app'}:
            raise SystemExit(f'app archive must contain exactly one Voice Dictation.app root, got {sorted(roots)!r}')
        required = {'Voice Dictation.app/Contents/Info.plist'}
        if not required.issubset(seen):
            raise SystemExit(f'app archive is missing required app entries: {sorted(required - seen)!r}')
        sparkle_binaries = [
            name for name in seen
            if name.startswith('Voice Dictation.app/Contents/Frameworks/Sparkle.framework/')
            and name.endswith('/Sparkle')
        ]
        if not sparkle_binaries:
            raise SystemExit('app archive is missing the Sparkle framework executable')
    else:
        roots = {name.split('/', 1)[0] for name in seen if name and not name.endswith('/')}
        if roots != {'Voice-Dictation-MacValidation'}:
            raise SystemExit(f'validation archive must contain exactly one runner root, got {sorted(roots)!r}')
        required = {
            'Voice-Dictation-MacValidation/VoiceDictationMacValidation',
            'Voice-Dictation-MacValidation/run-mac-validation.sh',
        }
        if not required.issubset(seen):
            raise SystemExit(f'validation archive is missing required runner entries: {sorted(required - seen)!r}')
        bad = [name for name in seen if any(name.lower().endswith(suffix) for suffix in ('.swift', '.m', '.mm', '.h', '.xcodeproj', '.dsym'))]
        if bad:
            raise SystemExit(f'validation archive contains source/debug entries: {bad!r}')
PY
}

validate_archive_entries "$APP_ZIP" app
validate_archive_entries "$VALIDATION_ZIP" validation

APP_ROOT="$WORK_ROOT/app"
VALIDATION_ROOT="$WORK_ROOT/validation"
mkdir -p "$APP_ROOT" "$VALIDATION_ROOT"
unzip -q "$APP_ZIP" -d "$APP_ROOT"
unzip -q "$VALIDATION_ZIP" -d "$VALIDATION_ROOT"
APP_PATH="$APP_ROOT/Voice Dictation.app"
APP_PLIST="$APP_PATH/Contents/Info.plist"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$APP_PLIST" 2>/dev/null || true
}

APP_EXECUTABLE="$(plist_value CFBundleExecutable)"
[[ "$APP_EXECUTABLE" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'CFBundleExecutable is missing or unsafe'
APP_MAIN="$APP_PATH/Contents/MacOS/$APP_EXECUTABLE"
[[ -f "$APP_MAIN" ]] || fail "app executable is missing: $APP_MAIN"
[[ "$(plist_value CFBundleShortVersionString)" == "$VERSION" ]] || fail 'app version does not match the requested version'
[[ -n "$(plist_value CFBundleVersion)" ]] || fail 'app build version is missing'
[[ "$(plist_value LSMinimumSystemVersion)" == "$MINIMUM_MACOS" ]] || fail "app minimum OS must be $MINIMUM_MACOS"
[[ "$(plist_value LSUIElement | tr '[:upper:]' '[:lower:]')" == 'true' ]] || fail 'app launch policy must be a menu-bar LSUIElement app'
background_only="$(plist_value LSBackgroundOnly | tr '[:upper:]' '[:lower:]')"
[[ -z "$background_only" || "$background_only" == 'false' ]] || fail 'app must not declare LSBackgroundOnly'
[[ "$(plist_value SURequireSignedFeed | tr '[:upper:]' '[:lower:]')" == 'true' ]] || fail 'Sparkle signed-feed requirement is missing'
[[ "$(plist_value SUAutomaticallyUpdate | tr '[:upper:]' '[:lower:]')" == 'false' ]] || fail 'Sparkle automatic installation must remain disabled'
[[ "$(plist_value SUAllowsAutomaticUpdates | tr '[:upper:]' '[:lower:]')" == 'false' ]] || fail 'Sparkle automatic updates must remain disabled'

assert_universal2() {
  local path="$1"
  local label="$2"
  local info
  info="$(lipo -info "$path" 2>/dev/null)" || fail "$label is not a readable Mach-O binary"
  if ! grep -Eq 'x86_64.*arm64|arm64.*x86_64' <<<"$info"; then
    fail "$label is not Universal 2: $info"
  fi
}

assert_universal2 "$APP_MAIN" 'app executable'
SPARKLE_ROOT="$APP_PATH/Contents/Frameworks/Sparkle.framework"
sparkle_macho_count=0
while IFS= read -r -d '' candidate; do
  description="$(file -b "$candidate")"
  if [[ "$description" == *Mach-O* ]]; then
    assert_universal2 "$candidate" "Sparkle binary $candidate"
    sparkle_macho_count=$((sparkle_macho_count + 1))
  fi
done < <(find "$SPARKLE_ROOT" -type f -print0)
[[ "$sparkle_macho_count" -gt 0 ]] || fail 'Sparkle.framework contains no Mach-O binaries to validate'

codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1 || fail 'app code signature verification failed'

# Complete the source-free validation bundle before launching the app. The app
# can populate the shared model cache during startup; doing this first avoids
# racing model preload and leaves a complete cache for the LaunchServices gate.
VALIDATION_DIR="$VALIDATION_ROOT/Voice-Dictation-MacValidation"
VALIDATION_EXE="$VALIDATION_DIR/VoiceDictationMacValidation"
VALIDATION_RUNNER="$VALIDATION_DIR/run-mac-validation.sh"
assert_universal2 "$VALIDATION_EXE" 'Swift validation entrypoint'
chmod +x "$VALIDATION_EXE" "$VALIDATION_RUNNER"

validation_log="$WORK_ROOT/mac-validation.log"
set +e
(cd "$VALIDATION_DIR" && ./run-mac-validation.sh --max-latency-seconds 5 --max-wer 0.35) 2>&1 | tee "$validation_log"
validation_status=${PIPESTATUS[0]}
set -e
[[ "$validation_status" -eq 0 ]] || fail "Swift validation bundle exited with $validation_status"

python3 - "$validation_log" "${EXPECTED_ARCHITECTURE:-$(uname -m)}" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding='utf-8').read()
expected_architecture = sys.argv[2]
compute_units_by_architecture = {
    'x86_64': 'cpuAndGPU',
    'arm64': 'cpuAndNeuralEngine',
}
encoder_precision_by_architecture = {
    'x86_64': 'fp16',
    'arm64': 'int8',
}
begin_lines = re.findall(r'(?m)^VD_MAC_VALIDATION_BEGIN[^\r\n]*$', text)
if len(begin_lines) != 1:
    raise SystemExit(
        f'validation output must contain exactly one VD_MAC_VALIDATION_BEGIN line; '
        f'found {len(begin_lines)}'
    )
begin = re.fullmatch(
    r'VD_MAC_VALIDATION_BEGIN\s+architecture=(?P<architecture>[^\s]+)\s+'
    r'compute_units=(?P<compute_units>[^\s]+)\s+'
    r'encoder_precision=(?P<encoder_precision>[^\s]+)',
    begin_lines[0],
)
if begin is None:
    raise SystemExit(
        'validation output begin marker must contain exactly architecture, compute_units, and encoder_precision'
    )
preload = re.search(r'VD_MAC_VALIDATION_MODEL_PRELOAD\s+seconds=([0-9]+(?:\.[0-9]+)?)', text)
cases = re.findall(r'VD_MAC_VALIDATION_CASE\s+label=([^\s]+).*?latency_seconds=([0-9]+(?:\.[0-9]+)?)\s+wer=([0-9]+(?:\.[0-9]+)?)', text)
silence = re.search(r'VD_MAC_VALIDATION_SILENCE\s+result=no_audio', text)
summary = re.search(r'VD_MAC_VALIDATION_SUMMARY\s+status=pass\b', text)
reported_architecture = begin.group('architecture')
reported_compute_units = begin.group('compute_units')
reported_encoder_precision = begin.group('encoder_precision')
if expected_architecture not in compute_units_by_architecture:
    raise SystemExit(f'unsupported expected architecture: {expected_architecture}')
if reported_architecture not in compute_units_by_architecture:
    raise SystemExit(f'validation reported unsupported architecture: {reported_architecture}')
if reported_architecture != expected_architecture:
    raise SystemExit(f'validation ran as {reported_architecture}, expected {expected_architecture}')
expected_compute_units = compute_units_by_architecture[expected_architecture]
if reported_compute_units != expected_compute_units:
    raise SystemExit(
        f'validation ran with compute_units={reported_compute_units}, '
        f'expected {expected_compute_units} for {expected_architecture}'
    )
expected_encoder_precision = encoder_precision_by_architecture[expected_architecture]
if reported_encoder_precision != expected_encoder_precision:
    raise SystemExit(
        f'validation ran with encoder_precision={reported_encoder_precision}, '
        f'expected {expected_encoder_precision} for {expected_architecture}'
    )
if preload is None:
    raise SystemExit('validation output is missing model preload seconds')
if len(cases) < 6:
    raise SystemExit(f'validation output contains only {len(cases)} phrase cases; six cold/warm cases are required')
if silence is None:
    raise SystemExit('validation output is missing the no-audio silence check')
if summary is None:
    raise SystemExit('validation output is missing a passing summary')
preload_seconds = float(preload.group(1))
maximum_wer = 0.35
maximum_latency = 5.0
worst_wer = max(float(row[2]) for row in cases)
worst_latency = max(float(row[1]) for row in cases)
if preload_seconds <= 0 or worst_latency <= 0:
    raise SystemExit('validation timings must be positive')
if worst_wer > maximum_wer:
    raise SystemExit(f'synthesized phrase WER {worst_wer:.3f} exceeds maximum {maximum_wer:.3f}')
if worst_latency > maximum_latency:
    raise SystemExit(f'synthesized phrase latency {worst_latency:.3f}s exceeds maximum {maximum_latency:.3f}s')
print(f'Mac validation measurements: model_preload_seconds={preload_seconds:.3f} cases={len(cases)} worst_wer={worst_wer:.3f} worst_latency_seconds={worst_latency:.3f} silence=no_audio')
PY

# Exercise LaunchServices only after the validation bundle has completed and
# populated the shared model cache.
launch_log="$WORK_ROOT/app-launch.log"
redact_diagnostics() {
  sed -E \
    -e 's/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g' \
    -e 's/((GITHUB_TOKEN|GH_TOKEN|GITHUB_API_TOKEN|ACTIONS_RUNTIME_TOKEN|RUNNER_TOKEN|TOKEN|AUTH_HEADER)=)[^[:space:]]+/\1[REDACTED]/g'
}
show_launch_diagnostics() {
  {
    echo 'LaunchServices process diagnostics:'
    ps -axo pid,ppid,comm,args 2>/dev/null |
      awk -v app_main="$APP_MAIN" 'index($0, app_main) { print }' |
      head -n 20 |
      redact_diagnostics || true
    echo 'Recent LaunchServices output (redacted):'
    tail -n 40 "$launch_log" 2>/dev/null | redact_diagnostics || true
  } >&2
}
open -n "$APP_PATH" >"$launch_log" 2>&1 &
open_pid=$!
sleep 8
app_pids="$(lsof -t -a -d txt -- "$APP_MAIN" 2>/dev/null | awk '/^[0-9]+$/ { print }' | sort -n -u || true)"
if [[ -z "$app_pids" ]]; then
  wait "$open_pid" 2>/dev/null || true
  show_launch_diagnostics
  fail 'app did not remain running after LaunchServices start; see bounded diagnostics above'
fi
while IFS= read -r app_pid; do
  [[ "$app_pid" =~ ^[0-9]+$ ]] && kill "$app_pid" 2>/dev/null || true
done <<<"$app_pids"
wait "$open_pid" 2>/dev/null || true
echo "macOS app launch policy and runtime start passed for $(uname -m)."

echo "Native macOS $(uname -m) binary-only validation passed for $VERSION."
