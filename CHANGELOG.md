# Changelog

All notable changes to this project will be documented in this file.

## [1.4.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.4.0] - 2026-11-04

### Changed
- The AI thinks about ten times faster and plays exactly the same moves as
  before: the board evaluation is now updated only along the four lines
  through each stone instead of rescanning the whole board. Hard's slowest
  move went from about 1 s to 0.06 s on a desktop (roughly 24 s to 1.5 s on
  a Kobo), Medium's from 0.08 s to 0.006 s.
- Each level also has a time limit (Hard 2.5 s, Medium 1.5 s, Easy 0.5 s on
  an e-reader): if a move would take longer, the AI plays the best move of
  the deepest search it finished instead of keeping you waiting.

## [1.3.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.3.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.3.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.3.0] - 2026-10-30

### Added
- "New game" once the game is over (five in a row or a full board): the
  action bar shows it in place of Undo, so the next game no longer needs the
  menu.

### Changed
- Redesigned play screen, in line with the other games: a full-width action
  bar, a larger board that fills the available room, and one frame around
  it. The status line reads "15×15 · difficulty · Black to move" and wraps in
  landscape instead of being cut off.
- Title-bar menu in the same order as every other game, with the current
  values shown: New game (was "New"), "Difficulty: Medium", "Players: 1"
  (was "1 player"), Rules.
- New README screenshot.

### Fixed
- The thick board border was notched wherever a grid line crossed it, and
  its right and bottom edges spilled just past the board. The border is now
  drawn last, inside the board.

## [1.2.2] - 2026-10-02

### Fixed
- Aligned `1 player (vs AI)` on "1 joueur (contre l'IA)" and the German `AI is
  thinking...` on "KI denkt nach...". `package.loaded` is keyed by module name
  alone, so every `require("i18n")` on the device resolves to one module and
  the first plugin loaded wins it. Every plugin's `i18n_fr.lua` merges into
  that one shared table, where plugins silently overwrite each other's
  translations. This plugin and chess disagreed on both strings, so whichever
  merged last decided them for both.

## [1.2.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.2.0] - 2026-09-30

### Changed
- The AI plays the same strength in roughly a third of the time (measured over
  60 games at matching depth against the previous engine: 31-29, i.e. even,
  at 0.11s per move against 0.31s). On an e-ink CPU that is the difference
  between "hard" being usable and being a wait.
- Candidates inside the search are now ordered before they are tried, by a
  cheap proximity count rather than a full-board evaluation. Ordering is what
  makes alpha-beta prune at all, but ordering the expensive way cost more than
  the cutoffs it bought.

### Fixed
- The root search restarted alpha at minus infinity for every candidate, which
  threw away every cutoff between siblings — most of what alpha-beta is for.
  It now carries the best score found so far into each subsequent search.
- The five-in-a-row test was written out three times, in three slightly
  different forms. There is one copy now.
- A stale comment claimed the search had no alpha-beta pruning. It always did.
