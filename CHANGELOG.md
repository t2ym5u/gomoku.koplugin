# Changelog

All notable changes to this project will be documented in this file.

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
