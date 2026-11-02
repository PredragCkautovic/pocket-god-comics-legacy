# Pocket God Definitive — Comic-derived Content Bible
**Canonical planning reference · Revision 1 · 2 November 2026**

**Owner project:** Pocket God Definitive for Nintendo Switch  
**Scope:** content that may be inspired by *Pocket God Comics* **after** the original game has been ported faithfully through v1.48.2.  
**Status:** research/planning; no comic-only scene, character behavior, animation, or mechanic is yet certified for implementation.

This is the **single source of truth for comic-to-game adaptation**. It supersedes the separate `COMICS_SWITCH_IMPLEMENTATION_BACKLOG.md`. The [25-issue index](CANONICAL_PRINT_25_INDEX.md) owns the exact issue titles, chapter mapping and story image counts; the [63-chapter index](WEBTOON_63_CHAPTER_INDEX.md) owns the complete WEBTOON sequence. **Do not duplicate those tables here.**

## 1. Immutable source boundaries

| Source | What we actually have | Proper use |
| --- | --- | --- |
| Original Pocket God iOS IPAs, v1.0–v1.48.2 | Game source assets/features, plus actual device references where captured | Only authoritative source for **1:1 Classic** gameplay |
| Classic 25 comics | **25 original numbered issue story reconstructions**, **629 story images plus 25 owner-corrected front covers = 654 reader images** | Story/reference evidence; *not* bit-exact originally sold iVerse issue pages |
| WEBTOON 63 | **63 creator posts, 702 story/extra images**, a **different segmentation** | Supplementary chapter references and later material; not “63 print issues” |
| Original reader binaries (32-bit iVerse), modern iOS/Android readers | App UI, comic catalogs and verified portable reading content | Reader compatibility, **not evidence for game mechanics** |
| Definitive expansion | New content defined here and backed by evidence | Separately selectable additional story/play activities only |

The legacy comics and modern reader releases remain separate from Switch gameplay. Never rename a WEBTOON chapter as a numbered issue, count the new front covers as additional story events, invent an unavailable original printed page, or silently merge comic-only mechanics into an IPA-accurate episode.

**Rights:** keep raw pages, downloaded assets, proprietary sprites and private captures outside the public source tree. Original artwork does not become freely redistributable merely because it has been archived or adapted; obtain appropriate rights/authorization for any public Switch content pack.

## 2. Definitive modes and boundary

**Classic Mode:** the unmodified behavior and unlock timeline reconstructed from original iOS versions. No comic-only additions here; it is the permanent regression baseline.

**Comics Library (optional):** offline, touch-first reading of a locally authorized comic pack. A library is a viewer: original issue sequence, covers, page turning, zoom/pan, bookmarks, issue selection and progress. Pack is not part of the base game by default and must gracefully handle missing art.

**Comic Story Mode (optional):** interactive episodes inspired by verified story beats. Each story is explicitly labeled **comic-derived**, built as separate story scenes with touch inputs, reversible outcomes/replay and isolated save-state. It must not alter Classic Mode controls, actors, world geometry, sound mapping, physics or version flags. All new assets belong to a distinct `definitive/comics/` namespace.

**Definitive Freeplay (optional, later):** only after Comic Story Mode QA, allow independently toggleable props/actors/scenarios whose original provenance and permissions have been confirmed. No unconditional content injections.

**Timing gate:** target this work **after** verified parity across the owner's original update archive through **v1.48.2**. Comic research can proceed earlier; implementation may not be mistaken for completion of unfinished classic episodes.

## 3. Nine adaptation workstreams

Everything in the right column is **a proposed research question**, not an assertion that the original game or the comic definitively supports that mechanic.

| ID | Numbered issues | Story / arc | Research candidate to validate against pages | Priority |
| --- | --- | --- | --- | --- |
| COM-01 | 01–04 | The Gem of Life | Gem artifact appearance and continuity, named pygmy roles, temple/action scene order, cause/effect | 1 |
| COM-02 | 05 | Xmas Marks the Spot | Winter/holiday props, setting change, seasonal interactions | 6 |
| COM-03 | 06–08 | A Tale of Two Pygmies | Character-to-character cooperation/conflict; possible **Squidball** touch minigame (chapter #19) | 3 |
| COM-04 | 09 | Infestation | Encounter design and pygmy reactions, only if visual/entity evidence exists | 7 |
| COM-05 | 10–13 | A Quest Called Tribe | Scene-by-scene journey, underwater/tribe locations, objects, travel transitions; separate replayable chapters | 2 |
| COM-06 | 14 | Para-Abnormal Activity | Atmosphere, ghost/supernatural sequences and reversible effects | 8 |
| COM-07 | 15–19 | Gem-Cell Research | Research devices, gem transfers, laboratory scenes, sea encounters, actor states | 4 |
| COM-08 | 20 | The Ghost of Fishmas Past | Seasonal supernatural story; visual/audio timing | 9 |
| COM-09 | 21–25 | The Pygmies Strike Back! | Character conflict, location changes, finale state transitions and rewards | 5 |

**Later separately gated content:** WEBTOON #9–12 mini-stories; #33 recap; #53/#60/#63 creator updates; and #61–62 the **issue 26 continuation**, *not* numbered issues #26–63. Chapter #61–62 can inform a future optional follow-on pack **only after** COM-01–09 are validated. No playable story claims are drawn from update/apology posts.

## 4. Data and proof contract — mandatory before coding

For each new comic-derived action or art object, create a small `proposal.json` conforming to the [published proposal schema](comic-proposal.schema.json) (also mirrored at `switch-port/content/comics/proposal.schema.json` on Forge01). Minimum fields:

- `content_id` (e.g. `COM-03-SQUIDBALL-01`), `arc_id`, `print_issue` in 1–25, `webtoon_chapters` and `page_refs` (1-based page positions in the **correct source edition**).
- `story_beat`, `characters`, `props`, `location`, `continuity_before`, `continuity_after` — supported by page observations, not intuition.
- `player_action` (tap/drag/swipe/hold), `preconditions`, `event_states`, `animation_cues`, `audio_cues`, `outcomes`, `replay_reset`; if missing, record `unknown` and do not implement.
- `evidence` references **private** panel/source IDs and original asset SHA-256 hashes where applicable; add `game_ipa_overlap` as `original / comic_only / unknown` with iOS version evidence.
- `asset_rights`, `source_confidence` (`unreviewed / panel_verified / device_verified`), `implementation_status`, `switch_qa`. Do not use guessed sprite/scene IDs as if they came from the IPA.

**Approval gate:** panel evidence checked → chronology/character continuity checked → compare against every relevant original-game version → permission to use assets checked → independent playable prototype → Switch touchscreen/60 fps budget/performance review → hardware QA → mark available in optional mode.

## 5. Native Switch integration contract

| Layer | Contract |
| --- | --- |
| Resource loader | Optional `romfs:/definitive/comics/<content_id>/` packs with explicit versioned manifests, checksums and entitlement/rights status; missing pack must not crash Classic Mode |
| Scene engine | Story scenes are individually addressable, replayable, and separate from version-authentic environments |
| Input | Switch touch is the canonical first input; controller fallback is separate after touch QA |
| State | `save.comics.*` only; must never modify `save.classic.*`, original spawn cap, quest unlock flags or existing audio identifiers |
| Art | Source-game sprites may be referenced only with verified version/asset provenance; other materials require authorized expansion-specific resources |
| Audio | Separate sound event namespace, traceable to authorized files; do not infer sounds from a static panel |
| Reader | CBZ/issue-list and page zoom/pan progress use their own `reader.*` keys, independent of story gameplay |
| Tests | Content-specific storyboard and state-transition tests + Classic Mode original behavior regressions |
| Public release | Ship new derived content only where rights permit; optional download or module with clear comic-derived labeling |

## 6. Production sequence: concrete next actions

1. **Lock inventories** — preserve original 25 cover-first issue order, original WEBTOON 63 mapping, verified 654/702 counts and source hashes. Never edit master CBZs in-place.
2. **Annotate only the first arc** — audit issue 01–04 pages for precise gem design, actor names, props, locations and timeline; produce private page-evidence records with confidence flags. Do not generate scene art based on guessed story beats.
3. **Make one vertical slice** — a single COM-01 *optional* story scene backed by a complete evidence/proposal record, with touch actions and reset behavior; compare with game IPA for possible existing overlap.
4. **Implement one reusable system at a time** — comic pack loader, standalone story scene controller, isolated save-state, touch sequence runner, missing-asset fallback and QA harness.
5. **Validate on Switch** — compare shot-to-shot to authorized panels; test touch gestures, orientation/crops, memory and frame pacing. Classic v1.0 and later update regression must stay green.
6. **Expand arc by arc** — COM-05 journey, COM-03 relationships, COM-07 research, COM-09 finale, then lower-priority seasonal/supernatural variants. Order changes require evidence-driven justification.

## 7. What to keep / what to discard

**Keep permanently:** original IPAs and media, canonical CBZs, validated cover masters, exact issue/chapter indices, SHA-256 manifests, original iVerse UI/reader reference, user-tested Legacy v17 and modern IPA/APK release binaries, current source/build recipes, device QA evidence, and this bible + schema.

**Archive only if useful for reproducibility:** release-specific debug logs, past code patches, failed prototype notes and prior UI screenshots. These are **not** content specifications.

**Safe cleanup candidates once inspected:** old generated build logs, disposable Python/Gradle caches, compiled object/intermediate artifacts with reproducible inputs, and redundant narrative plans now folded into this bible. Never delete a source file, original, final release, source checksum, owner archive, or source-evidence image to save space.

**Do not assume** the current materials prove the existence of a specific named character model, comic prop sprite, minigame, setting, mechanic, audio recording or page-curl effect in any released Pocket God IPA. Work from page proof and version evidence, not from an appealing guess.

---

**Ownership:** Pocket God Definitive / Comics Expansion research  
**Authoritative companions:** [canonical numbered issue index](CANONICAL_PRINT_25_INDEX.md), [WEBTOON 63 chapter index](WEBTOON_63_CHAPTER_INDEX.md), original Pocket God game version bible, and the private reference asset register.  
**Superseded:** `COMICS_SWITCH_IMPLEMENTATION_BACKLOG.md`; its candidate workstreams and gates are consolidated above.