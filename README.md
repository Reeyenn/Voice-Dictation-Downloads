# Voice Dictation Windows distribution

This repository is a small, public distribution and validation surface for the
Voice Dictation Windows beta. It contains release metadata, the redistributable
Inno Setup recipe, the application icon, and the portable-package prerequisite
notice. It deliberately contains no application source, debug symbols, private
repository credentials, or build outputs.

The application is distributed as prebuilt Windows 10 22H2 x64/ARM64
(build 19045+) and Windows 11 x64/ARM64 beta archives. The source
build remains private; a maintainer uploads versioned bootstrap archives to a
draft or published release in this repository, then manually dispatches the
validation workflow with the exact SHA-256 values. The workflow downloads only
those assets from this repository with its automatically scoped `GITHUB_TOKEN`,
validates them, compiles the installer, and uploads a short-lived Actions
artifact. Both validation workflows have only the repository `contents: write`
permission because GitHub's draft-release asset endpoint requires that scope;
the scripts use it for GET requests only and clear token environment variables
before launching any downloaded app, test host, compiler, or installer. It
does not run on pushes or pull requests and it cannot access the private source
repository.

## Supported product

- Windows 10 22H2 x64/ARM64 (build 19045+) and Windows 11 x64/ARM64 are supported beta targets.
- The native hosted proof covers Windows 11 x64/ARM64 plus Windows Server 2022 x64 build 20348. Server 2022 is compatibility evidence from the pre-Windows-11 server line, not literal Windows 10 hardware proof.
- The product and installer floor is Windows build 19045 or newer. The native validator records the exact host build and rejects lower builds.
- Microsoft Store/MSIX packaging, accounts, and cloud sync are outside this beta.
- The portable package keeps microphone audio and transcripts in memory. The
  included `vc_redist.x64.exe` is the official Microsoft Visual C++ v14 x64
  runtime used by the native speech-recognition dependency on clean machines.
- The beta is not code-signed or notarized. Windows SmartScreen may require the
  user to choose **More info** and **Run anyway**.
- The 0.8.0 and 0.9.0 bootstrap releases pin the bundled official VC++ redist to SHA-256
  `cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b`, file
  version `14.44.35211.0`. It is intentionally the Microsoft PE32 bootstrap
  executable; the app and Whisper runtime payload remain native to the archive label.

See [`release/PORTABLE-README.txt`](release/PORTABLE-README.txt) for the
end-user prerequisite note and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
for component and model attribution.

## Bootstrap release contract

Create a draft bootstrap release tagged `bootstrap-v<version>` in this
repository and attach the following prebuilt assets. Keep the final
user-facing release tag `v<version>` reserved for the validated setup,
portable, and checksum artifacts; it should not need to expose the compiled
test archive. The filenames below are exact for the selected version; the
workflow derives them from the version and does not accept arbitrary asset-name
inputs.

1. `Voice-Dictation-Windows-x64-<version>-Portable.zip` and
   `Voice-Dictation-Windows-arm64-<version>-Portable.zip` (both required). Each root
   must contain `VoiceDictation.exe`, the official signed
   `vc_redist.x64.exe`, `VCREDIST-PROVENANCE.txt`, `README.txt`,
   `THIRD_PARTY_NOTICES.md`, and the separate `DOTNET_THIRD_PARTY_NOTICES.txt`
   runtime notice. The x64 archive must also contain exactly the four Whisper DLLs under each of
   `runtimes/win-x64/` and `runtimes/noavx/win-x64/`:
   `ggml-base-whisper.dll`, `ggml-cpu-whisper.dll`, `ggml-whisper.dll`, and
   `whisper.dll`. It must not contain source files, PDB/XML files, or an
   unrelated executable. The ARM64 archive contains the same four DLL names under
   `runtimes/win-arm64/`. Wrong-architecture and x86 runtime directories are rejected.
2. `Voice-Dictation-Windows-x64-<version>-Platform.Tests.zip` and
   `Voice-Dictation-Windows-arm64-<version>-Platform.Tests.zip` (both required).
   These are compiled test outputs containing
   `VoiceDictation.Platform.Tests.dll` and its runtime/test dependencies, with
   no source files or PDBs. The validator requires a TRX result with at least
   the current test baseline, every discovered test executed and passed,
   and zero failed/not-executed tests.

Record the exact lowercase SHA-256 of each uploaded asset. In **Actions →
Windows distribution validation → Run workflow**, supply the version, the
exact `bootstrap-v<version>` tag, and these four hash inputs:
`x64_portable_sha256`, `arm64_portable_sha256`, `x64_platform_tests_sha256`,
and `arm64_platform_tests_sha256`. Do not supply asset names: the workflow
derives and requires the exact versioned names above, validates the tag against
the version, resolves the matching draft/release through the repository API,
downloads the assets with the workflow's own same-repository `GITHUB_TOKEN`,
and refuses a missing, mismatched, or cross-version asset.

## What the workflow validates

The packaging job runs natively on GitHub's x64 `windows-2025` image, builds one
universal installer, and validates archive hashes/structure plus native PE metadata
without executing candidate files. Separate jobs download that immutable candidate
and validate it natively on `windows-2025` x64, Windows Server 2022 x64, and the official Windows 11 ARM64
`windows-11-arm` image. The jobs install the pinned .NET 10 SDK; the packaging job installs Inno Setup and checks
the caller-supplied hashes, rejects source/debug material, verifies the
Microsoft Authenticode signature and pinned metadata/hash on the VC++ runtime,
and independently parses the PE headers of `VoiceDictation.exe` and Whisper DLLs,
requiring AMD64 `0x8664` or ARM64 `0xAA64` as labeled. The VC++ bootstrap is explicitly
excluded from that architecture check because Microsoft's signed installer is
PE32. The workflow runs the precompiled Platform tests with `dotnet vstest`,
runs the app self-tests, and performs a silent install/startup-registry,
self-test/uninstall smoke test. It downloads the pinned Whisper model and JFK
sample, verifies their byte counts and hashes, then runs the known-phrase and
silence inference checks while emitting elapsed phrase/silence measurements. The output artifact contains the original portable
ZIP, the freshly compiled setup executable, and text/JSON SHA-256 manifests.

The hosted runners cannot prove every physical microphone, global shortcut,
foreground editor, UI Automation, or user security-policy combination. This
repository therefore keeps the product claim at **Windows 10 22H2 x64/ARM64 and Windows 11 x64/ARM64 beta**; Server 2022 is separately reported as compatibility evidence.

## macOS binary-only validation

The manually dispatched **macOS distribution validation** workflow runs on both
native `macos-15-intel` and Apple-silicon `macos-15` hosts. It downloads only
these exact assets from the draft `bootstrap-v<version>` release in this public
repository:

- `Voice-Dictation-macOS-<version>.zip`, containing one `Voice Dictation.app`.
- `Voice-Dictation-macOS-Universal-Validation-<version>.zip`, containing the
  precompiled Universal 2 `VoiceDictationMacValidation` executable and its
  host-checking launcher.

The app ZIP must contain a Universal 2 app and Universal 2 Mach-O binaries for
every nested Sparkle executable/library. The validator checks ZIP paths and
metadata, app version/build/minimum macOS 15.6, menu-bar launch policy,
Sparkle signed-feed and manual-install settings, deep code signing, and an
actual LaunchServices start on each host.

The validation ZIP must contain the root
`Voice-Dictation-MacValidation/VoiceDictationMacValidation` executable and
`run-mac-validation.sh`. The packaged launcher invokes the executable on each
native host with fixed WER/latency gates, and it must emit the validator
machine-readable records before exiting successfully:

```text
VD_MAC_VALIDATION_BEGIN architecture=x86_64 compute_units=cpuAndGPU encoder_precision=streaming_fp16 model=streaming_70_13_13
VD_MAC_VALIDATION_BEGIN architecture=arm64 compute_units=cpuAndNeuralEngine encoder_precision=streaming_int8 model=streaming_70_13_13
VD_MAC_VALIDATION_MODEL_PRELOAD seconds=<positive> mode=streaming cache=compiled
VD_MAC_VALIDATION_MODEL encoder_file=<architecture-specific streaming encoder>
VD_MAC_VALIDATION_CASE label=<cold-0|warm-0|cold-1|warm-1|cold-2|warm-2> audio_seconds=<positive> session_load_seconds=<positive> processing_seconds=<positive> final_model_seconds=<positive> post_stop_seconds=<positive> rss_megabytes=<positive> wer=<0..0.35>
VD_MAC_VALIDATION_SILENCE result=no_audio latency_seconds=<positive>
VD_MAC_VALIDATION_CANCEL result=cancelled fresh_session=ready fresh_wer=<0..0.35> [post_stop_seconds=<positive>]
VD_MAC_VALIDATION_SUMMARY status=pass gated_rows=6 max_latency_seconds=5 max_wer=0.35 streaming_chunk_seconds=1 streaming_overlap_seconds=0
```

The public parser requires exactly six phrase records in the shown cold/warm
order, parses their key/value fields independent of field order, and rejects
duplicates, unknown fields, non-finite numbers, and unknown validation
markers. It requires Intel to report `compute_units=cpuAndGPU` with
`streaming_fp16` and `parakeet_unified_encoder_streaming_70_13_13.mlmodelc`;
Apple silicon must report `compute_units=cpuAndNeuralEngine` with
`streaming_int8` and `parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc`.
Every phrase has positive finite audio, load, processing, final-model, and
memory measurements; session load and `post_stop_seconds` must each be <= 5
seconds on every case, while WER must be <= 0.35. This post-stop gate measures the final tail after a
real-time-paced recording rather than incorrectly failing a healthy recording
whose full audio processing necessarily exceeds five seconds. Silence must
report `no_audio` within the same latency gate, and cancellation must leave a
ready fresh session with a passing WER (and a passing post-stop value when
emitted). The summary must report six gated rows with 1-second chunks and zero
overlap. The workflow also rejects
source, debug, `.git`, `.build`, and macOS metadata entries. It never invokes
SwiftPM, Xcode, or a private source checkout; the precompiled validation
executable owns model preload, local phrase synthesis, phrase WER, and no-audio
checks.

## Repository boundaries

The validation script and workflow are release infrastructure only. Do not
commit application source, PDBs, model files, user data, access tokens, or
private-repository URLs. The copied Inno script, icon, portable note, and
third-party notices are release metadata/assets; their upstream terms remain
applicable. See [`NOTICE.md`](NOTICE.md) for the distribution boundary.
