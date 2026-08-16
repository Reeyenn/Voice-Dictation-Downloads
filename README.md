# Voice Dictation Windows distribution

This repository is a small, public distribution and validation surface for the
Voice Dictation Windows beta. It contains release metadata, the redistributable
Inno Setup recipe, the application icon, and the portable-package prerequisite
notice. It deliberately contains no application source, debug symbols, private
repository credentials, or build outputs.

The application is distributed as a prebuilt Windows 11 x64 beta. The source
build remains private; a maintainer uploads versioned bootstrap archives to a
draft or published release in this repository, then manually dispatches the
validation workflow with the exact SHA-256 values. The workflow downloads only
those assets from this repository with its automatically scoped `GITHUB_TOKEN`,
validates them, compiles the installer, and uploads a short-lived Actions
artifact. The workflow has only the repository `contents: write` permission
because GitHub's draft-release asset endpoint requires that scope; the script
uses it for GET requests only and clears both token environment variables
before launching any downloaded app, test host, compiler, or installer. It
does not run on pushes or pull requests and it cannot access the private source
repository.

## Supported product

- Windows 11 x64, build 22621 or newer.
- Windows 10, Windows on ARM64, Microsoft Store/MSIX packaging, accounts, and
  cloud sync are outside this beta.
- The portable package keeps microphone audio and transcripts in memory. The
  included `vc_redist.x64.exe` is the official Microsoft Visual C++ v14 x64
  runtime used by the native speech-recognition dependency on clean machines.
- The beta is not code-signed or notarized. Windows SmartScreen may require the
  user to choose **More info** and **Run anyway**.
- The 0.7.1 bootstrap pins the bundled official VC++ redist to SHA-256
  `cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b`, file
  version `14.44.35211.0`. It is intentionally the Microsoft PE32 bootstrap
  executable; the app and Whisper runtime payload remain x64.

See [`release/PORTABLE-README.txt`](release/PORTABLE-README.txt) for the
end-user prerequisite note and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
for component and model attribution.

## Bootstrap release contract

Create a private draft bootstrap release tagged `bootstrap-v<version>` in this
repository and attach the following prebuilt assets. Keep the final
user-facing release tag `v<version>` reserved for the validated setup,
portable, and checksum artifacts; it should not need to expose the compiled
test archive. The names below are examples; the
workflow dispatch accepts explicit names and checks that they contain the
selected version.

1. `Voice-Dictation-Windows-x64-<version>-Portable.zip` (required). The root
   of the archive must contain `VoiceDictation.exe`, the official signed
   `vc_redist.x64.exe`, `VCREDIST-PROVENANCE.txt`, `README.txt`,
   `THIRD_PARTY_NOTICES.md`, and the separate `DOTNET_THIRD_PARTY_NOTICES.txt`
   runtime notice. It must also
   contain exactly the four Whisper DLLs under each of
   `runtimes/win-x64/` and `runtimes/noavx/win-x64/`:
   `ggml-base-whisper.dll`, `ggml-cpu-whisper.dll`, `ggml-whisper.dll`, and
   `whisper.dll`. It must not contain source files, PDB/XML files, or an
   unrelated executable. ARM64 and x86 runtime directories are rejected.
2. `Voice-Dictation-Windows-x64-<version>-Platform.Tests.zip` (required by the
   default workflow setting). This is a compiled test output containing
   `VoiceDictation.Platform.Tests.dll` and its runtime/test dependencies, with
   no source files or PDBs. The validator requires a TRX result with at least
   the current 58-test baseline, every discovered test executed and passed,
   and zero failed/not-executed tests. Set the dispatch input
   `run_platform_tests` to `false` only for a deliberate bootstrap check that
   has no test archive.

Record the exact lowercase SHA-256 of each uploaded asset. In **Actions →
Windows distribution validation → Run workflow**, supply the version, the
`bootstrap-v<version>` tag, asset names, and corresponding hashes. The
workflow validates the tag against the exact version, resolves the matching
draft/release through the repository API, downloads the assets with the
workflow's own same-repository `GITHUB_TOKEN`, and refuses a missing,
mismatched, or cross-version asset.

## What the workflow validates

On a Windows runner it installs the pinned .NET 10 SDK and Inno Setup, checks
the caller-supplied hashes, rejects source/debug material, verifies the
Microsoft Authenticode signature and pinned metadata/hash on the VC++ runtime,
and independently parses the PE headers of `VoiceDictation.exe` plus all eight
Whisper DLLs, requiring AMD64 machine `0x8664`. The VC++ bootstrap is explicitly
excluded from that architecture check because Microsoft's signed installer is
PE32. The workflow runs the precompiled Platform tests with `dotnet vstest`,
runs the app self-tests, and performs a silent install/startup-registry,
self-test/uninstall smoke test. It downloads the pinned Whisper model and JFK
sample, verifies their byte counts and hashes, then runs the known-phrase and
silence inference checks. The output artifact contains the original portable
ZIP, the freshly compiled setup executable, and text/JSON SHA-256 manifests.

The hosted runner cannot prove every physical microphone, global shortcut,
foreground editor, UI Automation, or user security-policy combination. This
repository therefore keeps the product claim at **Windows 11 x64 beta**.

## Repository boundaries

The validation script and workflow are release infrastructure only. Do not
commit application source, PDBs, model files, user data, access tokens, or
private-repository URLs. The copied Inno script, icon, portable note, and
third-party notices are release metadata/assets; their upstream terms remain
applicable. See [`NOTICE.md`](NOTICE.md) for the distribution boundary.
