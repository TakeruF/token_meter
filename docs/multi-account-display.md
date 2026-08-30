# Idea note: displaying multiple Claude Code accounts

Status: **idea only — not started.** Parked for a possible future feature. Nothing
below is implemented.

## The ask

Some users switch between multiple Claude accounts in Claude Code (`/login`) and
want Token Meter to show *which* account the numbers belong to — ideally both
accounts at once.

## Hard constraint: Claude Code is single-account at any instant

Switching accounts **overwrites** the previous account's state. There is no
supported store of "all accounts."

| Source | Content | On switch |
|---|---|---|
| Keychain `Claude Code-credentials` (macOS) / `~/.claude/.credentials.json` (Windows) | **live OAuth token**, current account only | overwritten; previous token is gone |
| `~/.claude.json` → `oauthAccount` | current account identity (email / accountUuid / orgUuid / displayName …) | overwritten; current account only |
| `~/.claude/projects/**/*.jsonl` | token-consumption logs | persist forever, but **carry no account tag** (verified against real logs) |

Consequences:

- **Live quota windows** (`GET /api/oauth/usage`, the 5h / 7d windows) need a live
  token. The non-active account's token no longer exists → **live fetch for the
  inactive account is impossible.**
- **Local token counts** (JSONL) have no account identifier → **past usage cannot
  be split by account retroactively.**

### Off the table

Storing multiple tokens / background-polling inactive accounts / refreshing tokens.
Token Meter must never refresh or rotate Claude's OAuth token — doing so breaks
Claude Code (see the project's OAuth-refresh-risk note). So a true "both accounts
live, simultaneously" view is not achievable unless Claude Code itself exposes
multi-account tokens.

## Relationship to current data policy

Today the app **intentionally does not read `oauthAccount`** — `docs/data-sources.md`
(~line 255) states `~/.claude.json` is not read precisely because it contains
`oauthAccount`. Any account-labeling feature crosses that line, so it should be:

- opt-in,
- local-only storage,
- and offer masked display (e.g. `tha…@gmail.com`).

## What account fields are actually available

From `~/.claude.json` → `oauthAccount` (read-only, no extra API call):

| Field | Example | Use |
|---|---|---|
| `emailAddress` | `user@example.com` | primary label — unique, reliable |
| `displayName` | `Probmkr` | human-readable, not guaranteed unique |
| `organizationName` | `…'s Organization` | org name (auto-generated for personal) |
| `organizationType` | `claude_max` | plan tier (Max / Pro …) |
| `organizationRateLimitTier` | `default_claude_max_5x` | rate tier — good for a badge |
| `accountUuid` | `cc02058d-…` | **switch-detection key** (keep out of the UI) |

Example label: `Probmkr (user@example.com) · Max 5x`. Detect switches via
`accountUuid` (email / displayName can change; the UUID is the stable identity).

## Phased approach (if we ever build it)

1. **Account label only (small, recommended start).** Read just the `oauthAccount`
   identity block; show which account the current numbers reflect; detect switches
   via `accountUuid` and reset/annotate. No change to token handling. Document the
   data-policy change; make it opt-in.
2. **Per-account local attribution + last-known quota snapshots.** Keep a small
   local store keyed by `accountUuid`: `{ email, displayName, cumulative local
   tokens, last-seen quota windows + timestamp }`. Tag incrementally-parsed usage
   events with the account active *at parse time* (forward-only split). UI: account
   switcher; active account shows live data, inactive shows forward-only local
   counts + a stale ("as of HH:MM") last-known quota with a staleness badge. Be
   explicit in the UI about the limits (pre-feature history can't be split; inactive
   quota is stale).
3. **(Optional) opportunistic refresh at switch moments.** When a switch is
   detected, capture the freshly-active account's live quota so each snapshot stays
   as fresh as possible. Still never refreshes tokens.
