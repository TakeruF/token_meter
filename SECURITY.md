# Security policy

## Supported versions

Security fixes are provided for the latest published Token Meter release. The
Windows port is supported from its first public `1.3.x` release onward.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Older releases | No; update to the latest release first |

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository:

<https://github.com/TakeruF/token_meter/security/advisories/new>

Include the affected version and platform, reproduction steps, impact, and any
relevant logs after removing prompts, responses, credentials, and personal
information. Do not open a public issue for an unpatched vulnerability and do
not attach real CLI logs or authentication files.

The maintainer will acknowledge a report within 7 days, provide a status update
within 14 days, and coordinate disclosure after a fix is available. These are
response targets rather than guarantees.

For suspected malicious or improperly signed Windows artifacts, also include
the file's SHA-256 hash, signature details, and download URL. Distribution will
be paused while the artifact provenance is investigated.
