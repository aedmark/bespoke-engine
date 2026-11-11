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

> **Implementation note (2026-11-08):** `where` guards on `on cue` handlers are parsed but not yet evaluated by the VM, and cue parameters such as `victim` and `loot` match literal entity names rather than binding variables. `when` rule patterns and dialogue-choice `where` guards are evaluated. See Claims vs. code in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The runnable form of this slice is [`scenarios/tavern_heist.bespoke`](scenarios/tavern_heist.bespoke).

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
