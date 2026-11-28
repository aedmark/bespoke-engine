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
| include | A line that reads another script file in place, once, so a game can span files | `include "art.bespoke"`, `compiler/includes.zig` (D-169) | import, module (an include shares one namespace) |
| host | The program that starts a script and asks the engine for ticks: the desktop window, a headless test, the browser page, or a game's own `main.zig` | `src/host.zig` (the host kit) | runner, harness (except for the stock runner `src/runner.zig`) |
| tick | One step of the game clock. Everything that happens, happens on a tick. One tick per second by default, adjustable while playing; in a game with `clock: turns`, one tick per player action (D-188) | `world.current_tick`, `host.tick` | frame (a frame is a redraw, at 60 per second, unrelated to ticks) |
| peripheral | Anything that only shows or plays the world: the window, the canvas, audio. It sends player input to the host as actions and never changes facts | `DisplayBridge`, `AudioBridge` | display bridge (in user copy) |
| Studio | BeSpoke Studio, the one-page browser workspace that edits a project's scripts and art, plays the game, and exports it as one page | `studio/`, `site/studio.html` (D-192) | IDE, editor app |

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
| rewind | Restoring an earlier snapshot of the whole run: facts, routines, walking people, and dice | `Timeline.restore_run` (D-184) | time travel (fine for the player-facing feature; say rewind for the mechanism) |
| seed | The number a run's dice start from; the host chooses it and a save keeps it, so a script never does | `VM.set_seed`, `bespoke run --seed` (D-184) | random seed (in user copy, just "the dice") |
| save | A snapshot written to disk with the map and routine state, in a `.sav` file with a backup | `src/save.zig` | |
| branch world | A temporary copy of the world that runs on a countdown, then merges back or is discarded | `TemporalHypervisor`, `fork_branch` (D-044) | tangent universe, tangent world, singularity, black hole |

## Behaviour

| Use | Meaning | In code | Avoid |
| --- | --- | --- | --- |
| routine | A character's script that runs over time: walk, wait, speak, repeat. It pauses with `wait` without stopping anything else | `routine`; runs as a fiber in the VM | fiber (an implementation word; fine in architecture docs) |
| cue | Something that happened and that a script can answer: a player action such as `UsedOn`, or an event fired by a script | `on cue`, `fire_cue` | signal, event (in script docs) |
| handler | The block of script that answers a cue | `on cue ...:` | callback |
| rule | A `when` block that fires once on the tick its condition becomes true, and again only after it becomes false and true again; a `when each` rule does this once per matching row, with the row bound (D-170) | reactive rule, edge-triggered (D-010) | trigger (except "falling-edge trigger" in the spec) |
| arrival rule | A rule that fires when a character finishes walking to a mark | `when X arrives at M:` (D-036) | |
| interrupt | A rule or cue pausing a routine to run other script; the routine resumes where it paused | `interrupt ... with` | |
| agenda | A goal a character pursues on its own when its conditions hold, such as chasing the player | `agenda` (D-056) | |
| decision | A choice point where a character picks one of the options a script offers. The engine offers only the options the character knows, scores each against the facts, and fires the cue with the highest-scoring one | `decision`, `src/decision.zig` (P44-05, D-137) | choice menu (a decision is script data, not a screen), dialogue choice (that is the separate branching-dialogue feature) |
| value axis | A virtue a character holds from -10 to +10, declared by the script with the two ways it fails, such as Mercy between Vengeance and Condoning Harm; +10 is the virtue held fully | `axis`, `src/value.zig` (P45-01, D-144) | stat, attribute, alignment (an axis is script data with a fixed range, and the engine names none) |
| red line | An option a character never takes in any decision, removed before scoring whatever its values say; fixed when the script compiles | `red lines`, `src/decision.zig` (P45-02, D-145) | veto rule, taboo (in user copy, prefer "red line") |
| dilemma | A choice where a character weighs one of its values against another, plus what the world says, and answers with the line and action of one of five tiers; the middle tier asks to be shown evidence | `dilemma`, `src/dilemma.zig` (P45-03, D-146) | moral choice (in user copy, prefer "dilemma"), decision (that is the option-scoring feature) |
| drift | A slow change in a character's value caused by what happens after a dilemma: points add up, and every 5 (or the axis's `drift step`) move the value one step, at most 2 steps per dilemma (or its `drift cap`) | `drifts`, `src/dilemma.zig` (P45-04, D-148) | growth, learning (in user copy, prefer "drift" or "change of heart") |
| appeal | Asking a character to weigh a dilemma by one of its values, such as mercy; it works only once the player has learned that the character holds that value, and it moves one weighing | `appeals`, `appeal to`, `host.appeal` (P45-05, D-149) | persuasion check, charisma roll (an appeal is deterministic and needs knowledge, not a number) |
| society | Characters with needs, jobs, rumours, and justice, declared in a script and run by the engine | `society`, `src/society.zig` | |
| goal | A line of investigation the player has to finish, declared as needs with the fact each one requires | `goal`, `src/hint.zig` (P44-01, D-134) | quest log (a goal is script data, not a screen) |
| hint | The nearest unmet need reported as help: the character's own deduction while she could reason about it, the author's direction otherwise | `hint.query()` (D-126) | walkthrough |
| limit | A script's line raising a count that is only a sanity check, such as `limit decisions 48`, up to eight times the default | `src/limits.zig` (P48-13, D-183) | quota, cap (the cap is the most a limit may say) |
| evidence threshold | A condition that counts the facts a pattern matches, or sums their third slot, and holds when the total reaches a number: `2 of Clue(_)`, `6 points of Clue(_)` | `count_at_least`, `points_at_least`, `query_count`, `query_points` (P44-02) | aggregate expression |
| presentation | Showing a character a piece of evidence, with what that character knows deciding the response. The engine records `Presented(person, evidence)` and fires `Presents(actor, person, evidence)` | `host.present`, `Presented` (P44-03) | show item (in user copy, present is the action) |

## Stage, dialogue, and play

| Use | Meaning | In code | Avoid |
| --- | --- | --- | --- |
| scene | A room or location, with its cast, props, and marks | `scene` | room (fine in the map code) |
| cast | The characters in a scene | `cast:` | actors (fine in code) |
| prop | An object in a scene the player can look at or use | `props:`; a hotspot in the map code | hotspot (in user copy) |
| mark | A named spot in a scene where characters stand and walk to | `marks:`; a waypoint in the map code | waypoint (in user copy) |
| room block | A scene's layout in art pixels: where each mark and prop stands, the walkways between marks, and the exits to other scenes | `room <Scene>:` (D-199) | layout file, room script |
| verb | A player action from the verb bar: Walk, Look, Talk, Take, Use | `verb` | |
| choice | A dialogue option, shown only while its `if` or `where` condition holds | `choice` (D-046) | dialogue tree, flag |
| dialogue block | A named conversation of `say`, `choice`, and `talk` lines, run from any handler or routine with `talk <Name>`; it plays exactly as the same lines written inline | `dialogue <Name>:` (D-206) | sub-dialogue, dialogue file |
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
