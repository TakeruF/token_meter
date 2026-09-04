# Archived Windows code-signing policy

> [!WARNING]
> **Windows development is frozen.** Token Meter will not publish, sign, update,
> maintain, support, submit to Microsoft Store, or directly distribute Windows
> binaries. This document is retained only as historical reference and does not
> authorize or describe a current release path.

## Historical status

SignPath Foundation approval was never completed. No Token Meter Windows release
is represented as being signed by SignPath Foundation. The attribution and
procedures below are obsolete and must not be used for a future Windows release.

## Team roles

Token Meter is currently maintained by one person. The role assignments are
public so that a future team expansion can preserve the same controls.

| Role | Member | Responsibility |
|---|---|---|
| Authors / committers | [TakeruF](https://github.com/TakeruF) | Maintains the source, build scripts, and release configuration. |
| Reviewer | [TakeruF](https://github.com/TakeruF) | Reviews changes from non-committers before merge. |
| Signing approver | [TakeruF](https://github.com/TakeruF) | Confirms the source tag, test results, version, and artifact provenance before every signing request. |

Repository and SignPath accounts used by these roles must have multi-factor
authentication enabled. A signing approval is separate from authoring a change
and is performed for every release.

## Privacy

[Token Meter's privacy policy](docs/privacy.md) describes all local data access
and optional network communication. This program will not transfer any
information to other networked systems unless specifically requested by the
user or the person installing or operating it. Claude usage lookup is disabled
by default and can be enabled or withdrawn in Settings.

## Artifact and approval controls

- Release artifacts are built by the public Windows GitHub Actions workflow
  from a version tag that points to the selected commit on `main`.
- NuGet dependencies are restored from committed lock files in locked mode.
- Third-party GitHub Actions are pinned to full commit SHAs.
- The checkout must be clean, the tag must match the Windows version metadata,
  and all automated tests must pass before packaging.
- Direct distribution consists of the x64 MSIX and `TokenMeterSetup.exe`; both
  artifacts must carry a valid signature and the same `Token Meter` product
  name and `1.3.0.0` file/product version metadata for the first Windows release.
- A maintainer must manually start and approve each release build. After
  SignPath onboarding, the signing request will also require approval in
  SignPath before a signature is issued.
- Only artifacts produced by the public workflow from this repository may be
  submitted for project signing. Locally built or modified binaries are not
  eligible.
- SHA-256 checksums and the source tag are published with direct-download
  releases.

Compromise, a suspicious signature, or a policy violation should be reported
using the private process in [SECURITY.md](SECURITY.md). The signing approver
will stop distribution, investigate, and request certificate revocation when
appropriate.
