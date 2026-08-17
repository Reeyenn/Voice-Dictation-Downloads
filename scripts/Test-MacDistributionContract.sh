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
  'VD_MAC_VALIDATION_BEGIN' \
  'VD_MAC_VALIDATION_MODEL' \
  'VD_MAC_VALIDATION_CASE' \
  'VD_MAC_VALIDATION_SILENCE' \
  'VD_MAC_VALIDATION_CANCEL' \
  'parse_validation_log' \
  '--parse-validation-log' \
  'compute_units' \
  'cpuAndGPU' \
  'cpuAndNeuralEngine' \
  'encoder_precision' \
  'fp16' \
  'streaming_int8' \
  'capture_mode' \
  'rolling' \
  'streaming_70_13_13' \
  'offline_15_2' \
  'parakeet_unified_encoder.mlmodelc' \
  'parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc' \
  'session_load_seconds' \
  'processing_seconds' \
  'final_model_seconds' \
  'post_stop_seconds' \
  'rss_megabytes' \
  'minimum_rss_megabytes' \
  'maximum_rss_megabytes' \
  'at least four decimal places' \
  'fresh_session' \
  'fresh_wer' \
  'capture_chunk_seconds' \
  'capture_overlap_seconds' \
  'VALIDATION_MAX_LATENCY_SECONDS=10' \
  'VALIDATION_MAX_LATENCY_SECONDS=5' \
  'assert_universal2' \
  'codesign --verify --deep --strict'; do
  require_text "$VALIDATOR" "$required"
done
require_text "$VALIDATOR" 'clear_workflow_tokens'
require_text "$VALIDATOR" 'unset GITHUB_TOKEN GH_TOKEN'
require_text "$VALIDATOR" 'TOKEN AUTH_HEADER'
require_text "$VALIDATOR" "(cd \"\$VALIDATION_DIR\" && ./run-mac-validation.sh"
require_text "$VALIDATOR" 'PIPESTATUS[0]'
require_text "$VALIDATOR" 'for tool in curl python3 unzip shasum plutil codesign lipo file open lsof sysctl; do'
require_text "$VALIDATOR" 'HOST_ARCHITECTURE="$(uname -m)"'
require_text "$VALIDATOR" 'sysctl.proc_translated'
require_text "$VALIDATOR" 'must not run under Rosetta translation'
require_text "$VALIDATOR" 'open -n "$APP_PATH"'
require_text "$VALIDATOR" 'lsof -t -a -d txt -- "$APP_MAIN"'
require_text "$VALIDATOR" 'ps -axo pid,ppid,comm,args'
require_text "$VALIDATOR" 'tail -n 40 "$launch_log"'
require_text "$VALIDATOR" 'redact_diagnostics'
require_text "$VALIDATOR" 'Complete the source-free validation bundle before launching the app.'

python3 - "$VALIDATOR" <<'PY'
import subprocess
import sys
import tempfile

validator = sys.argv[1]
labels = ["cold-0", "warm-0", "cold-1", "warm-1", "cold-2", "warm-2"]

def valid_log(architecture):
    intel = architecture == "x86_64"
    compute_units = "cpuAndGPU" if intel else "cpuAndNeuralEngine"
    encoder_precision = "fp16" if intel else "streaming_int8"
    model = "offline_15_2" if intel else "streaming_70_13_13"
    capture_mode = "rolling" if intel else "streaming"
    chunk_seconds = "15.000000" if intel else "1.040000"
    overlap_seconds = "2.000000" if intel else "0.000000"
    maximum_latency = "10.000000" if intel else "5.000000"
    encoder_file = (
        "parakeet_unified_encoder.mlmodelc"
        if intel
        else "parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc"
    )
    lines = [
        "diagnostic output before markers",
        f"VD_MAC_VALIDATION_BEGIN model={model} capture_mode={capture_mode} encoder_precision={encoder_precision} compute_units={compute_units} architecture={architecture}",
        f"VD_MAC_VALIDATION_MODEL_PRELOAD cache=compiled mode={capture_mode} seconds=0.500000",
        f"VD_MAC_VALIDATION_MODEL encoder_file={encoder_file}",
    ]
    for label in labels:
        lines.append(
            f"VD_MAC_VALIDATION_CASE wer=0.000000 rss_megabytes=1024.000000 post_stop_seconds=0.300000 "
            f"final_model_seconds=0.200000 processing_seconds=0.100000 session_load_seconds=0.200000 "
            f"audio_seconds=1.000000 label={label}"
        )
    lines.extend(
        [
            "VD_MAC_VALIDATION_SILENCE latency_seconds=0.010000 result=no_audio",
            "VD_MAC_VALIDATION_CANCEL post_stop_seconds=0.400000 fresh_wer=0.000000 fresh_session=ready result=cancelled",
            f"VD_MAC_VALIDATION_SUMMARY capture_mode={capture_mode} capture_overlap_seconds={overlap_seconds} capture_chunk_seconds={chunk_seconds} max_wer=0.35 max_latency_seconds={maximum_latency} gated_rows=6 status=pass",
        ]
    )
    return "\n".join(lines) + "\n"

def assert_parser(log, architecture, expected_success):
    with tempfile.NamedTemporaryFile("w", encoding="utf-8") as handle:
        handle.write(log)
        handle.flush()
        result = subprocess.run(
            [validator, "--parse-validation-log", handle.name, architecture],
            capture_output=True,
            text=True,
            check=False,
        )
    actual_success = result.returncode == 0
    if actual_success != expected_success:
        detail = (result.stdout + result.stderr).strip()
        raise SystemExit(
            f"parser fixture expected success={expected_success}, got {actual_success}: {detail}"
        )

for architecture in ("x86_64", "arm64"):
    assert_parser(valid_log(architecture), architecture, True)

base = valid_log("x86_64")
negative_fixtures = {
    "duplicate label": base.replace("label=cold-2", "label=warm-2", 1),
    "missing case": "\n".join(line for line in base.splitlines() if "label=warm-2" not in line) + "\n",
    "unknown marker": base.replace("VD_MAC_VALIDATION_MODEL encoder_file", "VD_MAC_VALIDATION_UNKNOWN encoder_file", 1),
    "extra field": base.replace("audio_seconds=1.000000 label=cold-0", "audio_seconds=1.000000 extra=1 label=cold-0", 1),
    "wrong compute units": base.replace("compute_units=cpuAndGPU", "compute_units=cpuOnly", 1),
    "wrong encoder precision": base.replace("encoder_precision=fp16", "encoder_precision=streaming_int8", 1),
    "wrong model": base.replace("model=offline_15_2", "model=offline", 1),
    "wrong capture mode": base.replace("capture_mode=rolling", "capture_mode=streaming", 1),
    "wrong encoder": base.replace("parakeet_unified_encoder.mlmodelc", "parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc", 1),
    "missing WER": base.replace(" fresh_wer=0.000000", "", 1),
    "duplicate key": base.replace("wer=0.000000 rss_megabytes", "wer=0.000000 wer=0.000000 rss_megabytes", 1),
    "non-finite RSS": base.replace("rss_megabytes=1024.000000", "rss_megabytes=NaN", 1),
    "low RSS": base.replace("rss_megabytes=1024.000000", "rss_megabytes=511.999999", 1),
    "high RSS": base.replace("rss_megabytes=1024.000000", "rss_megabytes=6144.000001", 1),
    "low precision timing": base.replace("session_load_seconds=0.200000", "session_load_seconds=0.200", 1),
    "negative timing": base.replace("session_load_seconds=0.200000", "session_load_seconds=-0.001000", 1),
    "session load gate": base.replace("session_load_seconds=0.200000", "session_load_seconds=10.000001", 1),
    "non-finite processing": base.replace("processing_seconds=0.100000", "processing_seconds=Infinity", 1),
    "negative processing": base.replace("processing_seconds=0.100000", "processing_seconds=-0.001000", 1),
    "post-stop gate": base.replace("post_stop_seconds=0.300000", "post_stop_seconds=10.000001", 1),
    "wrong silence": base.replace("result=no_audio", "result=audio", 1),
    "silence latency gate": base.replace("VD_MAC_VALIDATION_SILENCE latency_seconds=0.010000", "VD_MAC_VALIDATION_SILENCE latency_seconds=10.000001", 1),
    "wrong cancellation": base.replace("fresh_session=ready", "fresh_session=stale", 1),
    "wrong capture overlap": base.replace("capture_overlap_seconds=2.000000", "capture_overlap_seconds=1.000000", 1),
    "wrong capture chunk": base.replace("capture_chunk_seconds=15.000000", "capture_chunk_seconds=1.000000", 1),
}
for name, fixture in negative_fixtures.items():
    assert_parser(fixture, "x86_64", False)

arm_base = valid_log("arm64")
for name, fixture in {
    "arm wrong compute units": arm_base.replace("compute_units=cpuAndNeuralEngine", "compute_units=cpuAndGPU", 1),
    "arm wrong precision": arm_base.replace("encoder_precision=streaming_int8", "encoder_precision=fp16", 1),
    "arm wrong model": arm_base.replace("model=streaming_70_13_13", "model=offline_15_2", 1),
    "arm wrong capture mode": arm_base.replace("capture_mode=streaming", "capture_mode=rolling", 1),
    "arm wrong encoder": arm_base.replace("parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc", "parakeet_unified_encoder.mlmodelc", 1),
    "arm wrong capture chunk": arm_base.replace("capture_chunk_seconds=1.040000", "capture_chunk_seconds=15.000000", 1),
}.items():
    assert_parser(fixture, "arm64", False)

print("macOS architecture-specific validation parser mock fixtures passed")
PY

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
marker_parse_line="$(grep -n '^parse_validation_log \"\$validation_log\"' "$VALIDATOR" | head -n 1 | cut -d: -f1)"
if [[ -z "$scrub_line" || -z "$open_line" || -z "$lsof_line" || -z "$diagnostics_line" || -z "$cleanup_line" || -z "$runner_line" || -z "$marker_parse_line" || \
      "$scrub_line" -ge "$runner_line" || "$runner_line" -ge "$marker_parse_line" || \
      "$marker_parse_line" -ge "$open_line" || \
      "$open_line" -ge "$lsof_line" || "$lsof_line" -ge "$diagnostics_line" || \
      "$diagnostics_line" -ge "$cleanup_line" ]]; then
  fail 'token scrub, model validation, marker parsing, exact PID launch check, diagnostics, and cleanup are out of order'
fi

bash -n "$VALIDATOR"
printf 'macOS binary-only distribution contract checks passed.\n'
