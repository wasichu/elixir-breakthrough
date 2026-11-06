---
target: playing page
total_score: 21
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "file:/Users/knightmoves/src/slowinput/elixir-breakthrough/lib/breakthrough_web/live/game_live.ex"
target_fingerprint: "sha256:552f0d28d3248dbf6f1c1c537ee161c618d7f7c47bf7f062048d1a5e39582fbc"
target_path: /Users/knightmoves/src/slowinput/elixir-breakthrough/lib/breakthrough_web/live/game_live.ex
timestamp: 2026-11-06T17-13-26Z
slug: lib-breakthrough-web-live-game-live-ex
---
Method: dual-agent (playing_design_review · playing_detector_review).

# Playing-page design critique

Source-based assessment in Operate mode. Neither independent reviewer had verified browser access. The initial review preceded fixes made in this pass; the 21/40 score is a baseline, not a rescoring of the current implementation or a measured accessibility result.

## Design specificity

The wooden board, pawn assets, legal-target feedback, and player-oriented view fit Breakthrough. The surrounding interface resembles a general status dashboard. The strongest direction is a state-aware playing table: invitation while waiting, player/turn context during play, and a clear result plus next action at completion.

## Initial heuristic assessment

| Heuristic | Score | Finding |
|---|---:|---|
| Visibility of status | 3/4 | Status exists but is fragmented |
| Match with the real world | 2/4 | Visible and spoken coordinates disagreed |
| User control | 2/4 | Immediate resignation and limited recovery |
| Consistency | 2/4 | Multiple competing forms of turn information |
| Error prevention | 2/4 | Legal moves constrained; resignation needed protection |
| Recognition over recall | 2/4 | Shared-link arrivals lacked rules and guidance |
| Efficiency | 2/4 | Drag/click alternatives; no spatial keyboard navigation |
| Minimalist design | 3/4 | Dominant board with excess surrounding metadata |
| Error recovery | 2/4 | Plain messages but abrupt expiration recovery |
| Help | 1/4 | Rules confined to lobby at review time |
| Total | 21/40 | Baseline source-review score; all ten apply |

## Strengths

The board is the largest region and uses actual game assets. Legal destinations and selection provide immediate feedback. Presence, spectators, reconnect feedback, rematches, and reduced-motion support already exist. Preserve this behavior while reorganizing presentation.

## Priority issues and repairs during this run

1. P1 OPEN: Match context is fragmented across the board prompt, repeated prompt below the board, phase, role, turn, share form, and player panel. On phones the sidebar follows the entire board. Move compact player/turn information around the board; emphasize invitations while waiting; quiet sharing during active play. Spectators need explicit watching and turn announcements.
2. P1 FIXED DURING RUN: Shared-link newcomers had no rules entry point. Extracted the illustrated rules into RulesComponents and added How to play to GameLive, preserving Escape/focus-wrap behavior and adding interaction coverage.
3. P1 PARTIALLY FIXED: Coordinate labels disagreed with accessible names. White top-left was visibly a8 but announced a1; Black top-left was visibly a8 but announced h8. Canonical visible/spoken coordinates now agree, with tests for both orientations. Spatial arrow-key navigation, destination announcements, and off-turn/spectator board exploration remain OPEN.
4. P1 FIXED IN SOURCE, BROWSER CHECK OPEN: Resign immediately ended the match. Added a native data-confirm safeguard. Its placement and actual browser behavior still need interaction review. Waiting games now have cancellation and a tested path back to creating a match.
5. P2 OPEN: Completion repeats generic win/loss status without explaining the decisive event. Add a compact outcome area explaining a breakthrough, elimination, or resignation; preserve the final board; distinguish requesting from accepting a rematch. Consider a short recent-move trail before analysis features.

## Cognitive load

Moderate extraneous load: rules rely on recall, sharing/metadata remain permanently exposed, and role/presence are separate from the board. The board's many choices are intrinsic strategic complexity, not a reason to hide pieces or build a wizard. Selecting a pawn narrows the action to at most three destinations; strengthen that feedback.

## Emotional journey

Arrival offers immediate play but needs clear side, movement direction, and goal. Waiting should pair reassurance with inviting a friend. During play the interface should recede. Interruptions need nearby presence/reconnect context. Completion should explain and emphasize the decisive result before offering the next game.

## Persona red flags

- Invited newcomer: chess assumptions can be wrong; rules must remain available without leaving the match. The new rules control addresses access; contextual guidance remains a design choice.
- Distracted phone player: role/presence and invitation controls may fall below the board. Small target sizing is a prediction requiring rendered verification. Touch dragging is intentionally disabled; teach tapping accurately.
- Keyboard/screen-reader player: basic button activation exists, but 64 linear targets lack spatial navigation. Coordinates were fixed; legal moves and last moves still need richer announcements and exploration when not moving.
- Strategy enthusiast: consistent notation and a concise move trail would add more than extra status framing.
- Spectator: make watching and whose turn explicit, without implying seat or rematch privileges.

## Minor observations

Claimed describes seat allocation rather than presence. Move no counts individual moves and may be confused with full turns. The match lacks a useful heading hierarchy. A green users badge is decorative rather than tied to presence. Black-pawn contrast needs rendered low-vision verification. Reclaim nested framing before shrinking a phone board or introducing horizontal scrolling. GitHub access supports the LiveView audience but should not outrank rules during play.

## Evidence

Assessment A: independent source review by playing_design_review. Assessment B: independent detector/browser assessment by playing_detector_review. Initial CLI scan of game_live.ex exited 0 with JSON []. A final scan after source repairs included the shared rules component, home and match LiveViews, and also returned []. The scanner uses regex analysis for .ex sources; it is not a rendered HEEx, responsive, contrast, or assistive-technology audit.

No ignore list existed. Tidewave had no connected browser. CUA reported unavailable browser access. Native Firefox attempts timed out, so no game page, screenshot, overlay, or console result was verified. No detector live server was started. No browser tests should be described as passing.

## Provocative questions

Could the sidebar disappear during active play, leaving player rows, the board, and a compact move trail? What would an invited newcomer understand without seeing the lobby? Could the far edge and the actual breakthrough carry the product character instead of surrounding cards?

## Implementation follow-up — 2026-11-06

The subsequent full pass implemented the state-aware playing table, spatial
keyboard navigation, accurate move announcements, off-turn exploration,
confirmation dialogs, contextual sharing, completion reasons, and rematches.
Playwright now verifies the desktop and mobile flows with separate player
contexts, axe scans, screenshots, and failure traces. The browser limitations
above describe the initial critique, not the final implementation. The original
21/40 score remains a historical baseline; no new score is claimed.
