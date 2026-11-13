# Glossary

The words BeSpoke uses, in plain language, and which word to use where. This is the one home for engine and language terms; the process terms (Zone, Fore-conception, Held tension) stay in [`AGENTS.md`](../AGENTS.md).

**Use** is the word for READMEs, the site, the manual, the authoring guide, and messages a player or author reads. **In code** is the name the source uses, when it differs. **Avoid** lists words that drifted into the docs and mean the same thing less clearly; do not add new uses of them in user-facing copy.

## The engine

| Use | Meaning | In code | Avoid |
| --- | --- | --- | --- |
| engine | The program that runs a game: compiler, virtual machine, clock, world, map, and the hooks that windows and tests call | `src/`, the `bespoke` module | runtime spine (except when naming the Engine-as-Spine idea) |
| Engine-as-Spine | The design rule that the engine owns the clock and the world, and windows and audio only show what it reports | D-001 | "the VM is `main()`" as a slogan without explanation |
| script | A game written in the BeSpoke language, in a `.bespoke` file | source | DSL (fine in architecture docs; explain it once) |
| package | A compiled, checked script in a `.bspk` file | `CompiledProgram`, `src/package.zig` | bytecode binary |
| host | The program that starts a script and asks the engine for ticks: the desktop window, a headless test, the browser page, or a game's own `main.zig` | `src/host.zig` (the host kit) | runner, harness (except for the stock runner `src/runner.zig`) |
| tick | One step of the game clock. Everything that happens, happens on a tick. One tick per second by default, adjustable while playing | `world.current_tick`, `host.tick` | frame (a frame is a redraw, at 60 per second, unrelated to ticks) |
| peripheral | Anything that only shows or plays the world: the window, the canvas, audio. It sends player input to the host as actions and never changes facts | `DisplayBridge`, `AudioBridge` | display bridge (in user copy) |

## The world

| Use | Meaning | In code | Avoid |
| --- | --- | --- | --- |
| world | Everything the game currently knows, stored as facts | `World` | arena (the arena is the memory block the World lives in; say "arena" only about memory) |
| entity | A named thing: a character, a prop, a place, an idea. Just a number with a name | `EntityId` | object |
| fact | One row of knowledge: `(subject, relation, object, expires_at_tick)`, such as "the Guard carries the Cheese" | `Fact` | tuple, 4-tuple (in user copy) |
| relation | The verb of a fact, declared with `relation Carries(holder, item)` | `RelationKind` | predicate (except D-043) |
| property | A relation that holds one value per subject; remembering a new value replaces the old one | `.property` relations | functional relation (in user copy) |
| state | A fact with no object, such as `Lit(Lantern)`, true while present | predicate presence (D-043) | flag |
| expiry tick | The tick at which a fact disappears on its own; set with `remember ... for N ticks` | `expires_at_tick` | TTL, decay, lifetime (TTL is a duration; the fact stores an absolute tick) |
| snapshot | A copy of the world's fact columns and name tables at one tick, kept in memory | `World.save_state`, `host.Timeline` | memcpy (a snapshot is a serialized copy with a checksum, not one `memcpy`) |
| rewind | Restoring an earlier snapshot | `restore_state` | time travel (fine for the player-facing feature; say rewind for the mechanism) |
| save | A snapshot written to disk with the map and routine state, in a `.sav` file with a backup | `src/save.zig` | |
| branch world | A temporary copy of the world that runs on a countdown, then merges back or is discarded | `TemporalHypervisor`, `fork_branch` (D-044) | tangent universe, tangent world, singularity, black hole |

## Behaviour

| Use | Meaning | In code | Avoid |
| --- | --- | --- | --- |
| routine | A character's script that runs over time: walk, wait, speak, repeat. It pauses with `wait` without stopping anything else | `routine`; runs as a fiber in the VM | fiber (an implementation word; fine in architecture docs) |
| cue | Something that happened and that a script can answer: a player action such as `UsedOn`, or an event fired by a script | `on cue`, `fire_cue` | signal, event (in script docs) |
| handler | The block of script that answers a cue | `on cue ...:` | callback |
| rule | A `when` block that fires once on the tick its condition becomes true, and again only after it becomes false and true again | reactive rule, edge-triggered (D-010) | trigger (except "falling-edge trigger" in the spec) |
| arrival rule | A rule that fires when a character finishes walking to a mark | `when X arrives at M:` (D-036) | |
| interrupt | A rule or cue pausing a routine to run other script; the routine resumes where it paused | `interrupt ... with` | |
| agenda | A goal a character pursues on its own when its conditions hold, such as chasing the player | `agenda` (D-056) | |
| society | Characters with needs, jobs, rumours, and justice, declared in a script and run by the engine | `society`, `src/society.zig` | |

## Stage, dialogue, and play

| Use | Meaning | In code | Avoid |
| --- | --- | --- | --- |
| scene | A room or location, with its cast, props, and marks | `scene` | room (fine in the map code) |
| cast | The characters in a scene | `cast:` | actors (fine in code) |
| prop | An object in a scene the player can look at or use | `props:`; a hotspot in the map code | hotspot (in user copy) |
| mark | A named spot in a scene where characters stand and walk to | `marks:`; a waypoint in the map code | waypoint (in user copy) |
| verb | A player action from the verb bar: Walk, Look, Talk, Take, Use | `verb` | |
| choice | A dialogue option, shown only while its `if` or `where` condition holds | `choice` (D-046) | dialogue tree, flag |
| path | One of several alternative routes through a puzzle; choosing one locks the others | `path` (D-052) | stageplay path (in user copy) |
| command | A typed instruction such as `open the door`, matched against the script's words | `command`, `alias` (D-057) | parser |
| draft | A four-note tune that acts as a spell when woven | `draft` (D-029) | |
| weave | Playing a draft on a target | `weave` | cast (a spell); clashes with the scene's cast |
| distaff | The on-screen musical staff where the player plays notes | `DistaffInput` (D-030) | |
| score | Background music written in MML, set per scene or played by a script | `score`, `play score` (D-062) | soundtrack (the host's music list) |
| state inspector | The paused view of the facts around one entity, the dialogue options and why each is hidden, and what expires next | D-058, D-059 | debugger |

## The repository

| Use | Meaning | In code | Avoid |
| --- | --- | --- | --- |
| proof | A Zig program in `proofs/` that drives the engine through one playable scene to show a feature works, with checks | `bespoke-proofs` (D-031) | vertical slice (older name), demo, scenario |
| scenario | A sample script in `scenarios/` that the stock engine CLI runs | `bespoke run` | proof |
| deck | One playable entry in the browser runtime; each proof deck runs its proof's script | `proofs/wasm_deck.zig` (D-069) | |
| golden | A saved transcript, render hash, or audio hash that tests compare against, so a change in behaviour fails a test | `proofs/golden/` | snapshot (a snapshot is a world copy) |
| manual | The What/How/Why reference in `docs/manual.html`, built from `scheme/` | `tools/manual.py` | 3x manual (name the scheme once, then say manual) |
