# Vertical Slice Syntax Spec: The Tavern Heist

```
entity Guard, Bard, Cat, Cheese
relation Carries(holder, item)
relation CharmedBy(listener, musician)

remember Carries(Guard, Cheese)

routine Patrol(Guard):
  loop:
    walk Guard to Cellar
    wait 120 ticks
    walk Guard to Hearth
    wait 120 ticks

on cue PlayLute(Bard, target):
  if roll 2d6 >= 8:
    remember CharmedBy(target, Bard) for 180 ticks

when CharmedBy(listener, musician):
  interrupt listener with:
    face listener toward musician
    wait until not CharmedBy(listener, musician)

on cue Steal(Cat, victim) where CharmedBy(victim, _) and Carries(victim, loot):
  forget Carries(victim, loot)
  remember Carries(Cat, loot)
```

> **Implementation note (2026-11-13, D-072):** the `where` guard is evaluated when the cue fires. `victim` is bound to the cue's target, both clauses must hold for that same victim, and `loot` matches any entity the victim carries. If the guard fails, dispatch tries the next, less specific handler for the cue (such as `on cue Steal(thief, victim):`), and runs nothing if none is left. A guard pattern takes one argument (a state) or two (a fact), joined with `and`; up to eight distinct variables. The body does not see the bindings yet: inside the handler, `victim` and `loot` are still read as entity names, so the body above writes facts about entities called `victim` and `loot` (Claims vs. code in [docs/ARCHITECTURE.md](ARCHITECTURE.md)). The runnable form of this slice is [`scenarios/tavern_heist.bespoke`](../scenarios/tavern_heist.bespoke).

## Key Grammar Notes
1. **`remember` / `forget`:** Declarative database mutations. `remember ... for N ticks` automatically attaches an expiration tick to the relation row, handling temporary buffs and debuffs natively.
2. **`interrupt ... with`:** Pauses an active routine (like `Patrol`), executes the interruption behavior, and automatically restores the instruction pointer once the condition resolves.
3. **Cues & Commands:** External inputs arrive as events (`on cue`), and physical actions (`walk`, `face`) emit lightweight bytecode instructions back to the host display layer.

## Dialogue Choices

`choice "text" [if <condition>] [where <pattern>]` statements inside a cue handler compile into one set for that fiber. At runtime the VM evaluates every guard against World facts and records only the eligible options, up to nine.

- If no option is eligible, execution continues after the set in the same tick.
- Otherwise the fiber suspends. `VM.dialogue_view()` reconstructs the offered set from facts; `VM.choose(index)` clears it and resumes the fiber at the chosen body. The body can `say`, change facts, or call another routine; after it ends, execution continues after the whole set.
- The set is World state: `DialogueOpen`, `DialogueOption`, `DialogueBody`, `DialogueFiber`, `DialogueEnd`, `DialogueRevision`, and `DialogueChosen` facts survive snapshots and rewinds. Hosts that create choices at runtime use `VM.open_generated_dialogue`, whose options carry an opaque action id instead of a compiled body; `VM.choose` returns that action and no fiber is involved.
- A host presents an NPC as the speaker with `VM.set_dialogue_speaker(owner, npc)`. The set stays keyed by `owner`, the fiber's entity, so selection is unambiguous.

```bespoke
on cue TalksTo(Hero, Guide):
  choice "Ask about the gate.":
    say Guide: "It opens at dawn."
  choice "Show the sigil." if Carries(Hero, Sigil):
    say Guide: "Then you may pass."
```

## Stageplay Paths

A `path` block declares one operational approach. It owns the facts asserted when the route is selected and the routines that belong to it.

```bespoke
path Wits:
  remember ChosenWits(Hero)
  routine WitsSolution(Hero):
    say Hero: "I have a plan."
```

The host selects a path with `VM.select_path(compiled, "Wits")`. The path entity receives `PathActive(Wits)` immediately, and the block's fact statements run on the next tick. Scripts can test the active route with `if PathActive(Wits):`. Routines declared inside the block carry a generated guard: when another route is active they halt before their first body instruction. Selecting a different path returns `PathAlreadyChosen`; selecting the same path again is a no-op. Path routine names share the top-level routine namespace. Path facts are ordinary World facts, so saves and rewind restore them.

Path facts can change the route's topology and NPC repertoire. `WaypointBlocked` is a normal unary relation whose subject is the mark entity with the same name as a waypoint. Scripted walks plan around blocked waypoints. Existing obstacle predicates such as `Trapped` and `PortalBlocked` keep their usual meaning, and `PathActive`-guarded choices prune dialogue. Locks apply when a walk is planned; an in-flight walk keeps its path.

```bespoke
relation WaypointBlocked(mark)
path Wits:
  remember WaypointBlocked(BackAlley)
  remember Trapped(Hero)

on cue Talk(Hero, Guide):
  choice "Read the ledger" if PathActive(Wits):
    say Guide: "Only the wits route knows this."
```

## Mechanic Declarations

Scripts may carry immutable configuration for engine mechanics alongside executable routines and cues. A host selects a declaration from the compiled program and initializes the corresponding runtime module. Runtime progress remains in World facts.

```bespoke
society Hamlet:
  need Hunger high 100 3 1 55 trade Baker 5 50 5 80 60 10 "a meal"
  need Energy low 100 2 0 22 stay Cottages 14 90 sleeping true "tired" "sleep"
  member Baker 30 working:
    need Hunger 25 none none
    need Energy 85 none none
    routine working 1 Bakery
    work Bakery 5 1 true
    merchant Bakery Bread
    owns Bread
    carries Bread
  enforcer Constable
  holding Jail
  gathering Square
  flight Farm Cottages 4
  friend Baker Constable

duel RiddleContest:
  pair River:
    challenge "What runs but never walks?"
    reply "A river."
    variant 1 "What has a mouth but never speaks?"
  fallback "I do not know."
  win 3
  tier Sphinx 1
  fatigue Inquiries "calm":
    stage AnnoyedWith 2 100 "annoyed"

degradation ReactiveContainers:
  substance TestReagent
  stage Sound 120
  stage Etched 80
  stage Failed 0
  vessel TestVial 12 8 Sound
  spill 1
  relations Contains Volume ContainerStage ContainerExposure ContainerFailedAt
```

A duel may list several `fallback` lines. A fighter who knows no comeback is offered one of them, in order, one per fumbled round; the fighter's `DuelFumbles` count picks it (D-076).

Society `need` and `member` order is significant. It establishes need and roster indexes, including society tick evaluation order. Duel pairs and tier variants preserve source order. A degradation profile's stage order is its progression order; every nonterminal stage has a positive duration and the final stage has duration zero. Each vessel declares capacity, initial volume, and initial stage. `spill N` removes up to N volume per tick while the vessel or its `Carries` holder is moving. The optional `relations` line supplies five distinct names for contents, volume, stage, exposure, and failure location. Compilation rejects invalid capacities, stages, members, providers, activities, and waypoints. Package format version 6 added spill rates to the three declaration tables; version 7 (below) adds grids, and every earlier version remains readable.

### Grids

A room may carry one discrete grid overlay (P25-01, D-054). The grid complements the room's waypoints; it does not replace them.

```bespoke
scene: Great Hall
marks: HallDoor, HallStair

grid HallFloor in "Great Hall":
  size 8 4
  cell 20
  origin 0 0
  flammable 2 1 3 1
  liquid 0 3
  blocking 7 0 1 4
  place HallDoor 0 2
  place HallStair 6 0
```

`size W H` and `cell N` are required; `origin X Y` (non-negative in scripts) defaults to `0 0`. Cell (x, y) covers room coordinates from `origin + x*N` up to, not including, `origin + (x+1)*N`. An attribute line names one cell, or a rectangle when it adds a width and height. The attributes are `flammable`, `liquid`, and `blocking`. `place` moves a mark of the same room to the centre of a cell. A grid holds at most 4096 cells, and a room has at most one grid; quote multi-word room names.

Each set attribute is a fact on the grid entity: `CellFlammable(HallFloor, index)`, `CellLiquid`, or `CellBlocking`, where `index` is `y * W + x`. The host lifecycle writes the declared layout once, so later changes survive save, rewind, and re-initialisation. A mark standing in a `blocking` cell is treated like `WaypointBlocked`: scripted walks plan around it, and a walk to it is refused. Package format version 7 carries grids; versions 1 through 6 load without them.

### Scores (P28-03, D-062)

A `score` declares four-part music in Music Macro Language (D-060). Each part line holds one MML string; `drums` uses `k`, `s`, and `h`. A `scene` line makes the score that scene's default. The one-line form is a lead-only score.

```bespoke
score Calm:
  lead "t96 o5 l8 @1 e g a g e4 d4 L c4 e4 g2"
  bass "o3 l4 c g a e L f c g c"
  drums "l8 v10 k h h h L k h s h"
  scene Gatehouse

score Chase: "t160 o5 l16 @5 L [c d e d]2 [e f g f]2"

when Alarm(watch):
  play score Chase

when Warden forgets Alarm:
  stop score
```

`play score <Name>` overrides scene music in every scene until `stop score` or another `play score`. Parts loop together from their `L` once every part has ended (D-061). The choice is World state (`SceneScore` facts and the `PlayingScore` property of `Music`), so saves and rewinds restore it.

### Typed commands (P26-01, D-057)

A typed line such as `> pour the grog into the mug` is matched against sentence shapes (frames) and becomes a cue. The engine provides frames for looking, using, talking, and walking; a script adds its own, which are tried first.

```bespoke
command Pours: "pour <thing> into <thing>"
command Takes: "take <thing>"
alias ExposureSlip: "slip", "receipt"
```

- A frame is lowercase words and at most two `<thing>` slots, starting with a word and never with two slots side by side. Engine frames: `look at`, `examine`, `x` (`LooksAt`); `use <thing> with/on <thing>`, `use <thing>` (`Uses`); `ask <thing> about <thing>`, `talk to <thing>` (`TalksTo`); `go to`, `walk to` (`WalksTo`).
- Typed input ignores case, punctuation, and the articles `a`, `an`, `the`.
- An entity answers to the words of its name, split at capitals, spaces, and underscores (`ExposureSlip` answers to "exposure slip" and "slip"), and to the words of its `alias` phrases. Only what is in the actor's room or carried by the actor can be named. If two things match, the command is ambiguous and the game asks which.
- Package format version 10 carries commands and aliases.
- Hosts that enable the window's command bar let the player type these lines: Enter focuses the bar, Esc leaves, Up/Down recall history, Tab completes a word.
- What the player sees: a matched, resolved command fires its cue, whose handler speaks on the next tick; `go to <mark>` or `go to <person>` also walks there. Otherwise the reply is one of "I don't know the word \"x\".", "I don't understand that.", "You don't see that here.", "Which do you mean: the brass key or the iron key?" (answer with a noun such as "brass"), or "Nothing happens." when no handler answers.

### Agendas (P33-01, D-038, D-056)

An agenda is an actor's intention to intercept a target when its trigger lines hold.

```bespoke
relation Investigated(who, place)
relation Warned(who)

agenda WarnOff:
  actor Keeper
  target Hero
  priority 3
  cooldown 60
  requires Investigated(Hero, Boathouse)
  unless Warned(Hero)
```

- `actor` and `target` are required and must differ; `priority` (default 0) and `cooldown N` (ticks, default 0) are optional, and `once` ends the agenda for good after its first encounter.
- `requires Rel(A, B)` must hold and `unless Rel(A, B)` must not. Arguments are names or `_`; a one-argument line matches any object. There are no variables. An omission window is an expiring prerequisite: `remember Investigated(Hero, Boathouse) for 120 ticks`.
- Each agenda is an entity with `AgendaState(Agenda, Idle | Pursuing | Done)`, so scripts can test or react to it (`if AgendaState(WarnOff, Pursuing):`). A pursuing agenda whose trigger stops holding goes back to `Idle`.
- When several agendas target the same actor, one pursues: highest priority, then the actor with the shorter route, then the first declared. Package format version 9 carries agendas.
- A pursuing actor walks to the mark its target last reached and follows when the target moves on. When both stand still on the same mark, the agenda ends (with its cooldown, or for good if `once`) and the engine fires `Intercepts(Actor, Target, Agenda)`. While pursuing, the actor carries `Pursuing`, and society routines do not move it.

```bespoke
on cue Intercepts(Keeper, Hero, WarnOff):
  remember Warned(Hero)
  choice "I was only looking.":
    say Keeper: "Look elsewhere, then."
```

#### Fire, smoke, and water (P25-02, D-055)

A grid may also declare `burning` and `smoke` cells and four rates. Each rate is off unless declared.

```bespoke
grid HallFloor in "Great Hall":
  size 8 4
  cell 20
  flammable 1 1 6 1
  burning 0 1
  liquid 7 3
  burn 6
  spread 2
  dissipate 10
  flow 4

when Hero is InBurningCell:
  remember Scorched(Hero)
```

- `burn N`: a fire lasts N ticks, then the cell is spent and cannot relight. Without it, fires never go out.
- `spread N`: a fire that has burned N ticks lights its flammable, dry, unlit neighbours (up, down, left, right). An ignited cell stops being flammable.
- `dissipate N`: every fire keeps smoke in its cell; the smoke clears N ticks after the fire last fed it.
- `flow N`: on every tick divisible by N, liquid spreads into neighbouring cells that are not blocking. Liquid puts out any fire in its cell, and a wet cell cannot catch.

All decisions in a tick read the grid as it stood at the start of that tick, so the result never depends on cell order, and rewinds replay exactly. The engine marks each actor with `InBurningCell`, `InSmokeCell`, and `InLiquidCell` for the cell it stands in; `when Actor is InBurningCell:` and `when Actor stops being InBurningCell:` react to them on the following tick. Package format version 8 carries the rates and the two new cell kinds.
