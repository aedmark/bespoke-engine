# File Compatibility

BeSpoke reads two kinds of file: packages (`.bspk`, a compiled program) and saves (`.sav`, a run in progress). This page states what each 1.x release reads. The promise starts at 1.0: no 1.x release reads a package or save written before 1.0 (D-174), and each one names such a file rather than misreading it.

## Current formats

| File | Magic | Writer emits | Reader accepts | Refused with |
| --- | --- | ---: | ---: | --- |
| `.bspk` package | `BSP1` | format 1 | format 1 | `UnsupportedPackageVersion` (another format), `PackageFromBeforeOne` (`BSPB`, before 1.0) |
| `.sav` save | `BSV1` | version 1 | version 1 | `UnsupportedSaveVersion` (another version), `SaveFromBeforeOne` (`BSAV`, before 1.0) |

The command line turns these into a sentence: an unsupported format names the format it found and the one it reads, and a file from before 1.0 says to rebuild the package from its script.

## Packages are sections

A package is a 16-byte header (magic, format, a CRC32 of the payload, and the payload's length) followed by sections (P48-17, D-172, D-187). Each section is a four-character tag, a flags byte, its length, and its bytes. Bit 0 of the flags marks the section required; no other bit is defined, and a set one is corrupt.

| Tag | Holds |
| --- | --- |
| `NAME` | entities, and relations with their type and object kind |
| `PLAC` | marks, walkways, and hotspots |
| `CODE` | bytecode, the first statement, routine and cue handler entries, the handler chain (D-160), the save version and fingerprint (D-162), `rewinds reroll` (D-184), and the clock (D-188) |
| `RULE` | `when` rules, with each rule's `each` flag and owner (D-186) |
| `DRFT`, `SOCI`, `DUEL`, `DGRD`, `GRID`, `AGND`, `CMND`, `SCOR`, `CAST`, `GURD`, `GOAL`, `SPEL`, `DCSN`, `AXIS`, `REDL`, `DLMA` | one subsystem each: drafts, societies, duels, degradation, grids, agendas, commands and aliases, scores, cast places, cue guards, goals, spellbooks, decisions, axes, red lines, and dilemmas |
| `IMGS` | images, as QOI streams (D-182) |
| `ARTB` | backdrops, sprites, areas, looks, and parts |
| `TEXT` | display names and phrase overrides (D-179) |
| `CYCL` | optional (`flags = 0`): palette colour cycles (P49-01, D-190); 1.0 readers skip it and render static QOI art |
| `EXIT` | required: a script's room-block exits (P47-11, D-199); a reader without it refuses the package by name rather than play a game with its doors shut. Written only when a script declares exits, so every earlier package is unchanged |

- A package writes only the sections its program uses; `NAME` and `CODE` are always present. Every 1.0 section is required.
- A reader refuses a package with an unknown required section (`UnknownRequiredSection`) and skips an unknown optional one, so a later 1.x adds what it needs as a new section, optional where an older reader may safely ignore it, without a new format.
- A known section may appear once; its reader must use every byte of it.
- A browser build reads the packages its decks embed when it is built and links only the readers of the sections they hold (`package.sections_in`, `load_package_linked`).

## Saves

A 1.0 save holds its metadata and program identity (D-162), the temporal envelope when a branch is involved, the world, the walking agents, and the VM: fibers with their local bases, rule edges, the run's dice (D-168), and each `when each` rule's rows (D-186). A save is tied to the build that wrote it: a different build refuses it unless both declare the same `save version`, and then its facts load by name and its routines restart (D-162). A later 1.x that changes the save layout adds a version and still reads every earlier 1.x version.

## Changing a format

Every 1.x reader loads every earlier 1.x package and save (D-172 point 3). A package change is a new section; a save change is a new save version whose reader keeps the older ones. A change that cannot be expressed that way needs a new format number, which no 1.x release will make.

Removing or renaming a script-language or supported host API name follows the [deprecation policy](CONTRIBUTING.md#deprecation-policy) (P38-04, D-108).

## Failures

Readers reject a file they cannot read before allocating for or changing decoded state. A file in a format the reader knows whose checksum, bounds, section table, or contents are invalid is corrupt, not incompatible, and keeps its specific validation error.

## Compatibility fixtures

The 1.0 files live in `tests/fixtures/compat/` (`format-1-package.bspk` with its script `format-1.bespoke`, `format-1-save-dice.sav`, and `format-1-save-each.sav`), joined in 1.x by `format-1-cycles.bspk` (`format-1-cycles.bespoke`, `CYCL`, P49-01) and, in 1.2, `format-1-exits.bspk` (`format-1-exits.bespoke`, `EXIT`, P47-11). Tests and the fuzzer load them without rewriting them. When a 1.x release adds a section or a save version, add a fixture that uses it, and keep every earlier one. The fixtures from before 1.0 were retired with their readers (D-174); git history keeps them.

Decisions D-172, D-174, and D-187 own the policy. `src/package.zig` and `src/save.zig` own the executable checks.
