# Changelog

## 0.2.0 — 2026-11-06

- Refresh the lobby and playing page with responsive match states, player
  presence, move history, clearer results, sharing, and rematches.
- Add spatial keyboard board navigation, accessible dialogs, and reliable
  click, tap, drag, and clipboard interactions.
- Enforce one unfinished created game per browser session. Explain duplicate
  creation attempts and allow waiting invitations to be cancelled from either
  the lobby or match page.
- Expire waiting invitations after 15 minutes, require a first move within one
  minute of both seats being claimed, and clean up finished games and dead lobby
  entries. Ignore stale timer messages and handle concurrent expiry safely.
- Update Elixir, OTP, Phoenix, LiveView, dependencies, and asset tooling. Pin the
  development toolchain with mise and expose routine commands through Just.
- Add GitHub Actions, weekly Dependabot updates, and isolated desktop/mobile
  Playwright coverage with accessibility scans and failure artifacts.
- Update repository and coding-agent guidance. Correct production origins for
  the custom domain and keep the in-memory deployment on one application machine.

Deployment restarts clear existing games. This release does not add persistence
or multi-node game routing.
