Voice Dictation for Windows — portable beta

This archive is a self-contained Windows 11 x64 build. It does not install a
startup entry or write audio/transcripts to disk. The included
vc_redist.x64.exe is the official Microsoft Visual C++ v14 x64 runtime needed
by the native Whisper dependency on a clean PC. Run it once if Windows reports
that a runtime DLL is missing; Microsoft may show a normal UAC prompt.

The archive also includes the optimized and NoAvx Whisper DLLs under
runtimes\win-x64 and runtimes\noavx\win-x64, plus THIRD_PARTY_NOTICES.md and
DOTNET_THIRD_PARTY_NOTICES.txt (the pinned self-contained .NET runtime notice).

Supported hosts: Windows 11 x64, build 22621 or newer. ARM64 and Windows 10
are not supported by this beta.
