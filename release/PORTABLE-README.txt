Voice Dictation for Windows — portable beta

This archive is a self-contained Windows x64 or ARM64 build. It does not install a
startup entry or write audio/transcripts to disk. The included
vc_redist.x64.exe is the official Microsoft Visual C++ v14 x64 runtime needed
by the native Whisper dependency on a clean PC. Run it once if Windows reports
that a runtime DLL is missing; Microsoft may show a normal UAC prompt.
The bundled runtime is pinned to SHA-256
cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b,
25,635,768 bytes, file version 14.44.35211.0, and a valid Microsoft
Authenticode signature. VCREDIST-PROVENANCE.txt records this release evidence.

The x64 archive includes optimized and NoAvx Whisper DLLs under
runtimes\win-x64 and runtimes\noavx\win-x64. The ARM64 archive includes
genuine AArch64 optimized DLLs under runtimes\win-arm64. Both include
THIRD_PARTY_NOTICES.md and DOTNET_THIRD_PARTY_NOTICES.txt (the pinned
self-contained .NET runtime notice).

Portable copies never overwrite themselves. Use the universal Setup download
for one-click updates and automatic relaunch.

Supported hosts: Windows 10 version 22H2 or newer (build 19045+) and Windows 11,
native x64 or ARM64. 32-bit Windows is not supported by this beta.
