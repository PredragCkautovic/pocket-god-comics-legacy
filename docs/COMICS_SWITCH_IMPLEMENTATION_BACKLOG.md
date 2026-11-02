# Pocket God Comics → Switch port: deferred implementation notes

Status: RESEARCH ONLY. This is a future content planning document. No comics-inspired behavior should be merged into the 1:1 IPA conversion.

## Rules for the port

- Gate A: Complete and certify the original Pocket God v1.0 gameplay, artwork, audio, touch mechanics and release behavior.
- Gate B: Progress source-authentic versions from the complete owner IPA archive; record per-version feature unlocks in the version bible.
- Gate C: When all source-based gameplay is complete, add a separately switchable **Comics Expansion** namespace. Never retroactively misrepresent comics-only material as gameplay from original episodes.
- Use comic titles, arcs and WEBTOON-to-print mapping from `CANONICAL_PRINT_25_INDEX.md`; avoid numbered chapter/issue confusion.
- Verify proposed events against individual story panels before building; this plan is not a panel-verified feature specification.

## Epic groups

| Priority after IPA parity | Print issues | Arc | Candidate feature research | Evidence required | Status |
|---|---|---|---|---|---|
| 1 | 01–04 | Gem of Life | Gem object and narrative action/reaction states, character roster and interactions | Private panels, actor/object IDs, IPA overlap check | Research |
| 2 | 05 | Xmas Marks the Spot | Seasonal scenery, music cues, unique objects | Scene-by-scene visual and audio provenance | Research |
| 3 | 06–08 | A Tale of Two Pygmies | Two-character interactions and relationship-driven scripts | Sequential panel breakdown and state transitions | Research |
| 4 | 09 | Infestation | Creature presence, pygmy response and environment changes | Entity designs and per-frame action reference | Research |
| 5 | 10–13 | A Quest Called Tribe | Quests, exploration, scene transitions and tribe interactions | Geography/storyboard and touch input specification | Research |
| 6 | 14 | Para-Abnormal Activity | Supernatural environment effects | Specific panel evidence and animation references | Research |
| 7 | 15–19 | Gem-Cell Research | Research equipment, gem effects, possible transformation chains | Artifact and character continuity checks | Research |
| 8 | 20 | Ghost of Fishmas Past | Seasonal ghost atmosphere and reactions | Timeline and visual references | Research |
| 9 | 21–25 | The Pygmies Strike Back! | Story finale scenarios, conflicts and cast interactions | Panel storyboard, continuity, game design validation | Research |

## Required per-mechanic record

Each implementation proposal must include `PRINT-ISSUE`, `WEBTOON-CHAPTER`, `PAGE-INDEX`, `EVIDENCE-IMAGE-ID` (private), `ACTOR`, `ACTION`, `TRIGGER`, `INPUT-GESTURE`, `OUTPUT-ANIMATION`, `SOUND`, `WORLD-STATE`, `FAIL/RESET`, `ORIGINAL-IOS-EQUIVALENT`, `CONTENT-LICENSE`, `QA-CASE`.

## Production checkpoints

1. Archive issue-specific panels as read-only research references, never in public code or source commits unless separately authorized.
2. Build scene/storyboard evidence sheets before assigning assets or animation systems.
3. Reuse original IPA assets only if the episode already includes them; otherwise produce separate authorized expansion resources.
4. Implement in an isolated feature branch and keep an original-game-only build for parity regression checks.
5. Compare Switch hardware playback and touchscreen gestures against source references, then publish separately as an expansion.

## Modern comics reader relationship

The modern iOS reader is a distinct offline-comics app, not the game port. Its 25 issues must have the legacy v17 same page order and new front covers, with a 64-bit touch reader for iPhone SE 2016 and iPad 5. Test independent layout, memory and persistence on both devices.
