# Authoring Guide

This guide teaches you to write a BeSpoke game: scenes, dialogue, and reactive puzzles, and the Zig host API underneath them. It assumes you can run a shell command. [`script_spec.md`](../script_spec.md) is the complete syntax reference; this guide is the order to learn it in.

Every ```` ```bespoke ```` block below is a whole script, and `zig build test` compiles each one and plays the three walkthroughs (`src/authoring_guide_test.zig`, D-064). Fragments are fenced as `text`.

## 1. Start a project

Build the engine once, then generate a project beside it:

```bash
zig build
./zig-out/bin/bespoke init harbour
cd harbour
zig build test
zig build run
```

`bespoke init` writes a standalone Zig project (D-063):

| Path | What it is |
| --- | --- |
| `scripts/main.bespoke` | The starter story; edit it |
| `src/main.zig` | A host that runs the script in a window, or headless with `--headless` |
| `src/game_test.zig` | Tests that compile the script and check its story; add one per puzzle |
| `src/web.zig`, `web/` | The browser version and its smoke check |
| `.github/workflows/build.yml` | CI: tests and release builds on Linux, macOS, and Windows, and the browser build |
| `build.zig`, `build.zig.zon` | The build; the engine is a relative path dependency |

The loop while writing is: edit the script, `bespoke check` it for syntax, run it headless to read what happens, then add a test for anything the story depends on.

```bash
bespoke check scripts/main.bespoke
zig build run -- --headless --ticks 80
```

A headless run prints each line spoken, each change of scene and music, and each set of choices offered, with its tick. The window runs the same script at 20 ticks a second.

To share the game, `zig build -Dbundle -Doptimize=ReleaseSafe` builds one executable with the compiled script inside, and `zig build web` builds a browser version into `zig-out/web/` (D-066). The project's README lists the platform requirements.

## 2. The model in five terms

| Term | What it is | Written as |
| --- | --- | --- |
| Entity | A named thing: a person, a prop, a mark, a scene | `entity Lamp`, or listed in a `scene` block |
| Fact | A row `(subject, relation, object, expires_at_tick)` in the World | `remember Carries(Hero, Key)`, `forget Carries(Hero, Key)` |
| Routine | An actor's script, paused by `wait` and `walk` | `routine Patrol(Guard):` |
| Cue | An event with an actor and up to two targets, answered by a handler | `on cue TalksTo(Hero, Pilot):` |
| Rule | A handler that runs when facts start or stop holding | `when Lit(Lantern):`, `when Lantern forgets Lit:` |

Everything a game remembers is a fact, including the open dialogue, the chosen music, and agenda progress. Saving, rewinding, and the state inspector therefore cover the whole story with no extra work.

Time is a whole-number tick. `wait 20 ticks` and `remember X for 20 ticks` count ticks; nothing in a script reads a clock. A cue fired during a tick is handled on the next one, and a rule sees facts as they stood at the end of the previous tick, so order of declaration never changes an outcome.

Names start with a capital letter. A relation declares its argument names only for the reader; `relation Carries(holder, item)` and `relation Carries(a, b)` are the same relation.

```bespoke
# Facts: plain, timed, and property relations.
entity Hero, Lamp, Key
relation Carries(holder, item)
relation Lit(lamp)
property Mood(who, feeling)
entity Calm, Wary

remember Carries(Hero, Key)
remember Lit(Lamp) for 40 ticks
remember Mood(Hero, Calm)

routine Day(Hero):
  wait 10 ticks
  # A property holds one object per subject: this replaces Calm.
  remember Mood(Hero, Wary)
  if Carries(Hero, Key):
    say Hero: "Still have the key."
  wait until not Lit(Lamp)
  say Hero: "Dark already."
```

## 3. Walkthrough: a scene

A `scene` block declares a room and what is in it. `cast` are people, `props` are things to look at and use, and `marks` are the places people stand and walk between. Each cast member starts on the first mark of the first scene that lists it; an actor no scene lists starts on the script's first mark. `transition to scene X` changes the room the window shows.

<!-- example: scene -->
```bespoke
# Walkthrough 1: two scenes, a wandering keeper, and an arrival rule.
scene Quay:
  cast: Hero, Pilot
  props: Bollard, Lantern
  marks: Steps, Pier, Office

scene Ferry:
  marks: Deck, Wheelhouse

relation Boarded(who)

transition to scene Quay

routine Errands(Pilot):
  loop:
    walk Pilot to Office
    wait 6 ticks
    walk Pilot to Pier
    wait 6 ticks

routine Arrive(Hero):
  walk Hero to Pier
  remember Boarded(Hero)

when Hero arrives at Pier:
  say Pilot: "Mind the gap."

when Boarded(Hero):
  transition to scene Ferry
```

What happens, tick by tick:

1. The top-level `transition` runs first, so the window opens on the Quay.
2. Every routine starts on its actor. `Errands` loops forever; `Arrive` walks the Hero to the Pier, which takes a few ticks, and then records `Boarded(Hero)`.
3. `when Hero arrives at Pier` fires on arrival. `say` shows its line in the window's banner and in the headless log.
4. `when Boarded(Hero)` fires once, when the fact starts holding, and changes scene.

Run it headless to read the story:

```text
[Tick   1] Scene: Quay
[Tick   4] Pilot: "Mind the gap."
[Tick   6] Scene: Ferry
```

To build out a scene:

- `walk X to Mark` plans a route over the marks and finishes when the actor arrives. `face X toward Y` turns one actor to another.
- `wait N ticks`, `wait until <condition>`, and `loop:` shape a routine. A routine that ends simply stops.
- `when X arrives at Mark:` reacts to any arrival; it is the usual way to make a place do something.
- A `grid` gives a room cells with fire, smoke, and water ([Grids](../script_spec.md#grids)). An `agenda` sends one actor after another (section 6).

## 4. Walkthrough: a dialogue

A conversation is a cue handler. The player starts it with a typed command or a click, the handler speaks with `say`, and a run of `choice` statements offers options. Each `choice` may carry an `if` condition; an option whose condition fails is not offered, and when none is eligible the handler simply carries on.

<!-- example: dialogue -->
```bespoke
# Walkthrough 2: a conversation whose options depend on what the hero carries.
scene Quay:
  cast: Hero, Pilot
  props: Ticket
  marks: Steps, Pier

relation Carries(holder, item)
relation Paid(who)
relation Refused(who)

routine Wait(Hero):
  wait 1 ticks

on cue TalksTo(Hero, Pilot):
  say Pilot: "Crossing tonight?"
  choice "Show the ticket." if Carries(Hero, Ticket):
    remember Paid(Hero)
    say Pilot: "Step aboard."
  choice "I have no ticket." if not Carries(Hero, Ticket):
    remember Refused(Hero) for 20 ticks
    say Pilot: "Then come back with one."
  choice "Not yet.":
    say Pilot: "Suit yourself."

on cue TalksTo(Hero, Pilot, Ticket):
  say Pilot: "The office sells them."

on cue Takes(Hero, Ticket):
  remember Carries(Hero, Ticket)
  say Hero: "One ticket."

command Takes: "take <thing>"
```

How a player reaches it:

- **Typing.** The window's command bar opens with Enter. `talk to pilot` fires `TalksTo(Hero, Pilot)`, `ask pilot about ticket` fires `TalksTo(Hero, Pilot, Ticket)`, and `take ticket` fires `Takes(Hero, Ticket)` through the script's own `command` line. Articles and case are ignored, and only things in the player's room or carried by the player can be named.
- **Choosing.** The window draws the offered options; click one or press its number key. The chosen body runs on the next tick, and the handler then continues after the whole set of choices.
- **The player** is the actor of the first routine in the script, here the Hero (D-064). Clicks on marks walk the player; typed commands act for the player.
- **The Pilot needs no routine.** Every cast member starts on the first mark of its scene, so a person who only talks can simply stand there (D-065).

Things to know:

- A handler runs for the exact names in its signature. `TalksTo(Hero, Pilot)` and `TalksTo(Hero, Pilot, Ticket)` are two handlers; the engine tries the most specific match first.
- `remember Refused(Hero) for 20 ticks` is a short memory: the Pilot forgets the refusal after 20 ticks.
- An option's `if` condition is read when the set is offered. Conditions may use `not`, `and`, and `or`.
- The open set of choices is World state, so a save or rewind in the middle of a conversation restores it.
- A headless run prints the offered options but cannot answer them; tests answer with `VM.choose` (section 7).

An agenda starts a conversation from the other side: the Keeper walks to the Hero, and the engine fires `Intercepts`, which a handler answers like any cue.

```bespoke
scene Lighthouse:
  cast: Hero, Keeper
  marks: Door, Gallery

relation Investigated(who, place)
relation Warned(who)

agenda WarnOff:
  actor Keeper
  target Hero
  requires Investigated(Hero, Gallery)
  unless Warned(Hero)

routine Explore(Hero):
  walk Hero to Gallery
  remember Investigated(Hero, Gallery)

on cue Intercepts(Keeper, Hero, WarnOff):
  remember Warned(Hero)
  say Keeper: "The gallery is no place for visitors."
```

## 5. Walkthrough: a reactive puzzle

A reactive puzzle is a few facts and the rules that watch them. The player acts through cues; cues change facts; rules notice combinations of facts and move the story on. Here the Hero must light the lantern and ring the bell while it still burns.

<!-- example: puzzle -->
```bespoke
# Walkthrough 3: light the lantern, then ring the bell while it still burns.
scene Quay:
  cast: Hero, Pilot
  props: Lantern, Bell, Matches
  marks: Steps, Pier, Office

relation Carries(holder, item)
relation Lit(lamp)
relation Rung(bell)
relation Signalled(quay)

entity Fog

alias Matches: "match", "matchbox"

score Waiting: "t80 o4 l4 @4 v8 L e2 d2 c1"
score Arrival: "t132 o5 l8 @1 L c e g e c e g4"

remember Carries(Hero, Matches)
play score Waiting

routine Wait(Hero):
  wait 1 ticks

routine Errands(Pilot):
  loop:
    walk Pilot to Office
    wait 8 ticks
    walk Pilot to Pier
    wait 8 ticks

on cue Uses(Hero, Matches, Lantern):
  remember Lit(Lantern) for 30 ticks
  say Hero: "The wick takes."

on cue Uses(Hero, Bell):
  remember Rung(Bell) for 3 ticks
  say Hero: "Clang."
  if not Lit(Lantern):
    say Pilot: "Nobody sees a bell in the fog."

when Rung(Bell) and Lit(Lantern):
  remember Signalled(Quay)

when Lantern forgets Lit:
  say Hero: "The lantern is out."

when Signalled(Quay):
  play score Arrival
  interrupt Pilot with:
    face Pilot toward Hero
    say Pilot: "The ferry has seen you."
    wait 4 ticks
```

How it works:

1. `use match on lantern` fires `Uses(Hero, Matches, Lantern)`. The word "match" names the Matches through the `alias` line. The lantern burns for 30 ticks.
2. `use bell` fires `Uses(Hero, Bell)`, which rings for 3 ticks. Rung alone draws a remark from the `if not` check in the handler.
3. `when Rung(Bell) and Lit(Lantern)` notices the two facts holding together and records the solution as a fact, `Signalled(Quay)`. Another rule reacts to that fact: it changes the music and interrupts the Pilot's errands to speak. After the interruption the Pilot's routine resumes where it paused.
4. `when Lantern forgets Lit` reacts to the light expiring, so the player learns the window has closed.

Patterns that keep puzzles honest:

- **Record outcomes as facts.** `Signalled(Quay)` is something other rules, tests, and the state inspector can see. A puzzle solved only by a side effect cannot be tested.
- **Use timed facts for windows.** `remember ... for N ticks` expires by itself; there is no timer to cancel.
- **`when` triggers list facts that must hold, joined by `and`.** A trigger cannot say `not`; put negative checks inside the body with `if not`, as the bell handler does.
- **Prefer facts over flags in routines.** A routine that waits with `wait until Signalled(Quay)` resumes correctly after a rewind; a counter in the host does not.

Music follows the same idea. A score declared with `scene` is that scene's default; `play score X` overrides it everywhere until `stop score` ([Scores](../script_spec.md#scores-p28-03-d-062)).

```bespoke
scene Quay:
  marks: Steps

relation Alarm(who)
entity Watch

score Calm:
  lead "t96 o5 l8 @1 e g a g e4 d4 L c4 e4 g2"
  bass "o3 l4 @0 c g a e L f c g c"
  scene Quay

score Chase: "t160 o5 l16 @5 L [c d e d]2"

when Alarm(Watch):
  play score Chase

when Watch forgets Alarm:
  stop score

routine Sound(Watch):
  wait 5 ticks
  remember Alarm(Watch) for 20 ticks
```

## 6. More mechanics

Each of these is a declaration a script carries; [`script_spec.md`](../script_spec.md) gives the full syntax.

| Mechanic | Declaration | Use it for |
| --- | --- | --- |
| Typed commands | `command Pours: "pour <thing> into <thing>"`, `alias` | New verbs and nouns for the command bar |
| Agendas | `agenda` | An actor who pursues and intercepts another |
| Paths | `path` | Mutually exclusive approaches to a scene, chosen by the host |
| Grids | `grid` | Room cells that burn, smoke, flood, or block |
| Society | `society` | Needs, work, trade, and routines for a population |
| Duels | `duel` | Insult or riddle contests with tiers and fatigue |
| Degradation | `degradation` | Containers whose contents age, spill, and fail |
| Scores | `score` | Four-part music in Music Macro Language |

## 7. Test the story

`src/game_test.zig` in a generated project compiles the script and runs it headless. Its `Game` helper starts routines, ticks, and asks whether a fact holds. Test what the story depends on, not every line:

```text
test "the bell only counts while the lantern burns" {
    var game: Game = undefined;
    try game.init();
    defer game.deinit();
    try game.start("Wait", "Hero");
    const hero = game.world.lookup_entity("Hero").?;
    const bell = game.world.lookup_entity("Bell").?;
    _ = try game.vm.fire_cue(&game.compiled, "Uses", hero, bell, null);
    try game.run(3);
    try testing.expect(!game.holds("Signalled", "Quay", null));
}
```

To fire what a player types, use `host.run_command` with a `command.Interpreter`. To answer a dialogue, call `vm.choose(index)` and tick. `src/authoring_guide_test.zig` drives this guide's walkthroughs exactly that way and is a working reference.

## 8. Host API

A host is the Zig program that owns the window, the clock, and the player's input. The stock runner (`bespoke run`) and a generated project's `src/main.zig` are hosts; write your own when the game needs its own controls. Import the engine as the `bespoke` module.

| Call | Contract |
| --- | --- |
| `bespoke.compile_source(allocator, &world, &spatial, source)` | Compiles a script into a `CompiledProgram`, interning its entities and marks |
| `bespoke.check_source(allocator, source)` | Syntax and semantic check; `.diagnostic()` gives line, column, and message |
| `bespoke.load_package(allocator, reader, &world, &spatial)` | Loads a `.bspk` package written by `bespoke compile` |
| `bespoke.run_file(allocator, path, config, writer)` | The stock runner: window, or headless with `config.is_headless` |
| `host.initialize_subsystems(&world, &compiled)` | Seeds declared grids, agendas, and containers; safe to repeat |
| `host.start_script(&world, &spatial, &vm, &compiled)` | Starts a script as every stock host does: top-level statements, the cast, every routine; returns the player |
| `bespoke.run_bytes(allocator, name, data, config, writer)` | The stock runner on a script or package already in memory, such as an embedded one |
| `bespoke.wasm.script_deck(title, program)` | A browser deck that runs an embedded script or package |
| `host.run_initial_statements(&world, &vm, &compiled)` | Runs the script's top-level statements |
| `host.place_cast(&spatial, &compiled)` | Puts each cast member on its scene's first mark, unless already placed; call before starting routines |
| `host.tick(&vm, &compiled)` | One lifecycle tick: VM, containers, grids, agendas, weaves. Never call `vm.step_tick` alone (D-033) |
| `host.speech_this_tick(&world, &vm, buf)` / `host.SpeechLog` | What `say` produced on the latest tick; read it after every tick |
| `host.run_command(&vm, &compiled, &interp, actor, line, buf)` | Interprets a typed line and fires its cue; returns a reply to show |
| `host.command_words(&vm, &compiled, actor, &words)` | Words the command bar may complete |
| `vm.fire_cue(&compiled, cue, actor, target, target2)` | Fires a cue; the handler runs on the next tick |
| `bespoke.dialogue.view(&world)` / `vm.choose(index)` | The offered choices, and answering one |
| `vm.select_path(&compiled, name)` | Chooses a `path` |
| `host.Session` | The interactive loop: timeline, rewind, scrub, saves, pause, single step |
| `host.ScriptSoundtrack` | The script's scores as a soundtrack for the window's audio |

A window host follows the loop documented on `host.Session` in [`src/host.zig`](../src/host.zig): poll an action, let `handle_common` take pause, step, rewind, and save, handle the game's own actions, and `advance` when a tick is due. Engine code never names a game (D-031); everything specific to your story lives in your script and your host.

## 9. Known limits

These are recorded under Claims vs. code in [`ARCHITECTURE.md`](ARCHITECTURE.md):

- A cue handler parameter written in lowercase (`on cue Shows(Hero, item):`) matches any entity but is not bound; the body cannot use `item`. Write one handler per concrete name.
- `where` guards on `on cue` handlers are parsed but not evaluated. Put the check inside the body with `if`.
- The stock window answers dialogue and typed commands, but clicking a person does not talk to them; type `talk to <name>`.
