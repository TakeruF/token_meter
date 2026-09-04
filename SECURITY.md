# Security policy

## Supported versions

Security fixes are provided only for the latest published macOS Token Meter
release. Windows development is frozen: the archived Windows source and any
historical Windows builds are unsupported and will not receive security fixes,
updates, maintenance, or support.

| Version | Supported |
|---|---|
| Latest macOS release | Yes |
| Older macOS releases | No; update to the latest macOS release first |
| Any Windows version or archived Windows source | No; Windows development is frozen |

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository:

<https://github.com/TakeruF/token_meter/security/advisories/new>

Include the affected version and platform, reproduction steps, impact, and any
relevant logs after removing prompts, responses, credentials, and personal
information. Do not open a public issue for an unpatched vulnerability and do
not attach real CLI logs or authentication files.

For supported macOS releases, the maintainer will acknowledge a report within 7
days, provide a status update within 14 days, and coordinate disclosure after a
fix is available. These are response targets rather than guarantees. Windows
reports may be submitted for awareness, but Windows is unsupported and no fix,
update, or response commitment is made.

For a suspected malicious or improperly signed historical Windows artifact,
also include its SHA-256 hash, signature details, and download URL. Token Meter
does not distribute or support Windows artifacts.
