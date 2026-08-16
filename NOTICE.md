# Distribution repository notice

This repository is intentionally limited to public Windows distribution
metadata and validation infrastructure. It does not grant a license to the
prebuilt Voice Dictation application, its source, or its model assets. The
application's applicable terms and third-party attributions are carried with
the release and in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) plus the
complete self-contained-runtime notice in
[`DOTNET_THIRD_PARTY_NOTICES.txt`](DOTNET_THIRD_PARTY_NOTICES.txt).

The Inno Setup recipe and icon are copied release assets from the Voice Dictation
project. Do not modify or redistribute them independently of the applicable
project and third-party terms. The validation workflow is designed to consume
prebuilt binaries without receiving a private source-repository token.

No credentials, source files, PDBs, model payloads, or user data belong in this
repository.
