# Windows beta third-party notices

Voice Dictation for Windows is distributed as self-contained x64 and ARM64 beta
packages. The installer and portable archive include native runtime components from the
projects below. Their licenses remain with their authors.

## NAudio 2.3.0

Copyright (c) Mark Heath. Licensed under the MIT License.

Source: https://github.com/naudio/NAudio/tree/v2.3.0

## Whisper.net 1.9.1

Copyright (c) Sandro Hanea and contributors. Licensed under the MIT License.
Whisper.net is the .NET binding used to run the local Whisper model. The
Windows package includes its x64 CPU runtime and the matching `Runtime.NoAvx`
fallback for Windows x64 machines without AVX support.

Source: https://github.com/sandrohanea/whisper.net/releases/tag/1.9.1

## OpenAI Whisper model and code

The pinned `ggml-small.en.bin` model is derived from OpenAI Whisper and is
downloaded on first run from the public model repository at revision
`c521a4b02f422512d734391fdf08bb08c0862f68`. Voice Dictation verifies the exact
487,614,201-byte payload and SHA-256
`c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d` before
making it available. Model and code licensing information is available from:

- https://github.com/openai/whisper
- https://huggingface.co/ggerganov/whisper.cpp/tree/c521a4b02f422512d734391fdf08bb08c0862f68

## Microsoft Visual C++ runtime

Whisper native dependencies may use Microsoft's Visual C++ runtime. The
installer does not silently fetch third-party components from arbitrary hosts;
the release workflow documents and verifies the official Microsoft runtime
dependency when one is required by the selected native package.

Source: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist

## Inno Setup

The Windows setup executable is built with Inno Setup by Jordan Russell and
contributors. Inno Setup is licensed under its own license and is not bundled
as an end-user runtime.

Source: https://jrsoftware.org/isinfo.php

## .NET 10 self-contained runtime

The application includes the .NET runtime selected by the locked .NET 10 SDK
and published self-contained. The runtime is built from the official
dotnet/runtime repository; packaging does not fetch an unverified runtime at
artifact time. The complete pinned runtime third-party notice is shipped
separately as `DOTNET_THIRD_PARTY_NOTICES.txt` and included in both packages.

Source: https://github.com/dotnet/runtime

## MIT License

The MIT License text below applies to NAudio, Whisper.net and its native
runtime packages, the OpenAI Whisper code used by the model family, and the
Microsoft .NET runtime included in the self-contained publish where their
respective repositories identify MIT licensing.

Copyright (c) their respective copyright holders.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
