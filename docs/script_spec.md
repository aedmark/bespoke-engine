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

## Declarations and Facts

`entity A, B` declares names. `relation R(subject, object)` declares a set relation; `property P(subject, value)` declares a single-value relation, so remembering a new value replaces the old one. Argument names in declarations are descriptive only. A fact pattern is `Relation(A)` or `Relation(A, B)`; square brackets (`Relation[A, B]`) are an accepted equivalent. `_` is a wildcard in guards and triggers.

`remember Fact(...)` asserts a fact. `remember Fact(...) for N ticks` gives it an expiry tick, and `forget Fact(...)` removes it. The stageplay forms `now Actor is State`, `Actor is State`, and their `is not` / `are not` variants assert or remove unary state facts. `in the scene` and `with` may follow a state phrase for readable stage directions; they do not add another fact. A declaration sentence such as `DoorStatus is a state, which can be open or shut.` declares `DoorStatus` as a relation; text after `state` on that line is descriptive.

## Scenes and Execution Blocks

```bespoke
scene: Harbour Office
cast: Hero, Clerk
props: Ledger
marks: Door, Counter

routine Queue(Hero):
  wait 10 ticks

during Crowd:
  wait 1 ticks
```

`scene`, `cast`, `props`, and `marks` describe stages. A scene heading may put the colon before or after its name (`scene: Harbour Office` or `scene Harbour Office:`); the other three use `cast:`, `props:`, and `marks:`. Their visual indentation is optional. Each later `cast`, `props`, or `marks` line belongs to the most recent scene. `routine Name(Actor)` declares a fiber owned by that actor. `during Name` is the stageplay spelling of a routine whose name and owner are both `Name`. A top-level `transition to scene Name` seeds an initial transition; the same statement in a body changes scene when that fiber reaches it.

`on cue Name(parameters)` and its synonym `verb Name(parameters)` declare externally fired handlers. Parameters beginning with an uppercase letter match that entity; lowercase parameters match any entity. An optional `where` clause contains fact patterns joined by `and`. See the D-072 limitation above for body bindings.

## Statements and Conditions

Routine, cue, rule, dialogue-choice, and `during` bodies accept these statements:

| Syntax | Effect |
| --- | --- |
| `remember`, `forget`, `now X is Y`, `X is Y` | Mutate facts as described above. |
| `walk Actor to Mark`, `face Actor toward Target` | Emit spatial actions for the host. `towards` is also accepted. |
| `wait N ticks`, `wait until condition` | Suspend for time or until a condition holds. |
| `loop:` | Repeat its indented body. |
| `if condition:` | Run its indented body when true. There is no `else` form. |
| `interrupt Actor with:` | Push its indented body over the actor's current routine. |
| `say Speaker: "text"`, `say Speaker to Listener: "text"` | Emit speech; the listener phrase is narrative and does not change dispatch. Parenthesized or unquoted text is also accepted. |
| `animate Clip`, `animate(Target, Clip)`, `stop animate Clip` | Emit animation cues. The one-name forms target `Scene`. |
| `transition to scene Name` | Change the active scene. A colon after `scene` is optional. |
| `choice ...` | Open the consecutive choice set described below. |
| `resume ...`, `done` | End an interruption body and resume the interrupted routine; words after `resume` are descriptive. |
| `weave Draft on Target` | Cast a declared musical draft. |
| `play score Name`, `stop score` | Override or clear script music. |

A condition is a fact (`Carries(Hero, Key)` or `Carries[Hero, Key]`), its negation (`not Carries(Hero, Key)`), a unary state phrase (`Hero is Ready`, `Hero is not Ready`), a speech fact (`Hero says "Ready"`), a deterministic dice threshold (`roll 2d6 >= 8`), or an evidence threshold (P44-02).

An evidence threshold counts matching facts or sums their third slot: `2 of Clue(_)` holds when at least two facts match, and `6 points of Clue(_)` holds when the matched facts' third slots total at least six. `_` is a wildcard in either argument, so `2 of Clue(_)` counts every subject and `2 of Clue(Hero, _)` counts the Hero's. A weighted condition reads the third slot as points, so `remember Clue(Diary, 3)` contributes three. Aggregates are conditions in `if`, `wait until`, and choice guards; `when` triggers and `where` guards keep their existing forms. Package format version 16 carries the count and points opcodes, and versions 1 through 15 load unchanged.

## Reactive Rules

```bespoke
when Ready(Hero) and Carries(Hero, Key):
  say Hero: "Ready."

when Hero is Ready:
  say Hero: "Now."

when Hero stops being Ready:
  say Hero: "Not yet."

when Hero forgets Ready:
  say Hero: "It expired."

when Hero arrives at Door:
  say Hero: "Here."
```

`when` is edge-triggered. It accepts one or more fact patterns joined by `and`, a rising state phrase (`when currently X is Y` is equivalent), a falling state phrase (`stops being`; `being` is optional), an expiry rule (`forgets`), or arrival at a declared mark. A bare `when Ready:` is the unary pattern `Ready(Ready)` and exists only for compatibility; prefer an explicit fact or state phrase.

## Musical Drafts

`draft Name(C, D, E, F)` declares exactly four note names from C through B. `reverse OtherName` optionally names the reversed sequence. Draft names and note sequences must be unambiguous. `weave Name on Target` is valid only in an executable body and the draft may be declared later in the file.

## Key Grammar Notes
1. **`remember` / `forget`:** Declarative database mutations. `remember ... for N ticks` automatically attaches an expiration tick to the relation row, handling temporary buffs and debuffs natively.
2. **`interrupt ... with`:** Pauses an active routine (like `Patrol`), executes the interruption behavior, and automatically restores the instruction pointer once the condition resolves.
3. **Cues & Commands:** External inputs arrive as events (`on cue`), and physical actions (`walk`, `face`) emit lightweight bytecode instructions back to the host display layer.
4. **Names:** A name in `scene:`, `cast:`, `props:`, `marks:`, or `transition to scene:` is one or more words joined by single spaces (`scene: Charter Yard`). A name that needs a character a word cannot hold, such as an apostrophe, is written in double quotes and taken whole: `scene: "Brine's Boarding House"`, `transition to scene: "Brine's Boarding House"` (D-101).

## Dialogue Choices

`choice "text" [if <condition>] [where <pattern>]` statements in an executable body compile into one set for that fiber. A top-level choice set is also accepted and runs during initialisation. At runtime the VM evaluates every guard against World facts and records only the eligible options, up to nine.

- If no option is eligible, execution continues after the set in the same tick.
- Otherwise the fiber suspends. `VM.dialogue_view()` reconstructs the offered set from facts; `VM.choose(index)` clears it and resumes the fiber at the chosen body. The body can `say`, change facts, or call another routine; after it ends, execution continues after the whole set.
- The set is World state: `DialogueOpen`, `DialogueOption`, `DialogueBody`, `DialogueFiber`, `DialogueEnd`, `DialogueRevision`, and `DialogueChosen` facts survive snapshots and rewinds. Hosts that create choices at runtime use `VM.open_generated_dialogue`, whose options carry an opaque action id instead of a compiled body; `VM.choose` returns that action and no fiber is involved.
- A host presents an NPC as the speaker with `VM.set_dialogue_speaker(owner, npc)`. The set stays keyed by `owner`, the fiber's entity, so selection is unambiguous.
- Keep each spoken line and choice within 60 characters (`dialogue_panel.MAX_COLUMNS`, D-084); a choice's `[n] ` number counts toward it. The panel fits its width to the text and wraps longer lines, so a short line reads at a glance.

```bespoke
on cue TalksTo(Hero, Guide):
  choice "Ask about the gate.":
    say Guide: "It opens at dawn."
  choice "Show the sigil." if Carries(Hero, Sigil):
    say Guide: "Then you may pass."
```

## Stageplay Paths

A `path` block declares one operational approach. It owns the facts changed when the route is selected (`remember`, `forget`, `now`, or a state phrase) and the routines that belong to it.

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

The complete society directive set is:

| Scope | Directive |
| --- | --- |
| Society | `need Name high|low Max Rate RestingRate Seek trade Provider|none Price Relief Floor Critical|none TheftRelief TheftFloor Item` |
| Society | `need Name high|low Max Rate RestingRate Seek stay Place Restore Until Activity Unaware State Verb` |
| Society | `member Name Gold IdleActivity:`; nested `need Name Value Rate|none Provider|none`, `routine Activity|none Period [Stops...]`, `work Place Every Earn Restock`, `merchant Post Goods`, `broadcaster`, `owns [Items...]`, and `carries [Items...]` |
| Society | `enforcer Name|none`, `holding Place|none`, required `gathering Place`, required `flight FirstPlace SecondPlace|none Every`, and repeatable `friend A B` |
| Society tuning | `radii Witness Gossip Warrant Arrest`, `grudges WitnessTicks TheftTicks`, `priority N`, `currency Unit`, and `relations Gold Activity Tending Friend Rival Grudge Owns Carries StolenFrom CrimeScene Witnessed KnowsRumor WarrantFor Arrested` |

`true` and `false` are the boolean values in society declarations. A positional optional value uses `none`.

The complete duel directive set is `pair Name:` with required `challenge` and `reply` strings plus contiguous `variant 1`, `variant 2`, and so on; repeatable `fallback` strings; `win N|none`; `tier Opponent N`; `fatigue CountRelation "calm label":` with one or more `stage Relation At TTL "label"` lines; and `relations HeardChallenge MasteredReply Counters VariantOf DuelTier Advantage DuelsWon`.

The complete degradation directive set is one `substance Name`, two or more ordered `stage Name Duration` lines, one or more `vessel Name Capacity InitialVolume InitialStage` lines, optional `spill N`, and optional `relations Contains Volume Stage Exposure FailedAt`.

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

`size W H` and `cell N` are required; non-negative `origin X Y` defaults to `0 0`. Cell (x, y) covers room coordinates from `origin + x*N` up to, not including, `origin + (x+1)*N`. An attribute line names one cell, or a rectangle when it adds a width and height. The attributes are `flammable`, `liquid`, `blocking`, `burning`, and `smoke`. `place` moves a mark of the same room to the centre of a cell. A grid holds at most 4096 cells, and a room has at most one grid; quote multi-word room names.

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
- Hosts that enable the window's command bar let the player type these lines: Enter focuses the bar, Esc leaves, Up/Down recall history, Tab completes a word. A browser deck turns on the same bar with `command_bar`, and the page made by `bespoke init` has it on.
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

### Goals and hints (P44-01, D-134)

A goal declares what the player has to make true, and a query reports the next need as a hint, in the story's voice while the character can reason about it.

```bespoke
relation Carries(holder, item)
relation Read(who, item)
relation Investigated(who, place)

remember Knows(Ines, Archive)
remember Knows(Ines, ExposureSlip)

goal RecoverThePlate:
  need TakeTheSlip:
    met Carries(Ines, ExposureSlip)
    room Archive
  need ReadTheLog after TakeTheSlip:
    met Read(Ines, TelescopeLog)
    room TelescopeFloor
    hint 3 "The log names the plate once you hold the slip."
```

- `need <Name> [after <Need>, <Need>]:` opens one need. `met <Fact>` is required and takes one or two arguments, with `_` as a wildcard. `after` lists needs of the same goal that must hold first.
- `room <Name>` is the place the room tier names. Without it, the need inherits the scene that declares the prop or mark it names. A proof whose rooms are finer than its scenes names the room.
- `hint <tier> "text"` replaces one generated tier: 1 names the room, 2 the thing, and 3 the relation. Each tier at most once per need.
- Declaration order is the search's order. A goal is done when every need holds; a need is on the frontier when it is unmet and every `after` need holds.
- The query takes the tier and the player entity, and reports the first frontier need whose entities the player knows, together with `holmesian` or `doylian` and whether the text was authored. Knowledge is `Knows` or `Believes` about the player, and `Rejects` cancels either, so a script asserts knowledge when a scene shows the character something.
- When no frontier need is one the character could reason about, the query reports the first unmet need in declaration order as the author: it may name a room or a thing the character has not met.
- The query reads facts and writes none, so a save, a rewind, or a replay reports the same hint for the same world. Cycles in `after`, duplicate need names, an unknown prerequisite, and a missing or invalid tier are compile errors. Package format version 15 carries goals; versions 1 through 14 load none.

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

## Test Coverage

P38-01 audits the accepted grammar against this document. Exact Zig test names are listed so a renamed or removed test makes the table visibly stale. Codegen tests parse their source before compiling it; the parser-coverage column names focused AST tests where one exists and the compiling test otherwise.

| Spec section | Parser coverage | Codegen or integration test |
| --- | --- | --- |
| Opening vertical slice; cue parameters and `where` | `P4-02: parser parses complete tavern heist AST` | `D-072: cue where guards bind cue parameters and fall through to the next handler` (`src/compiler.zig`) |
| Declarations and Facts | `P4-02: parser parses complete tavern heist AST`; `P10-01: parser parses stageplay taxonomy, state declarations, and falling-edge/expiration rules` | `P4-03: end-to-end compilation from source text to bytecode chunk`; `P38-01: documented core statements parse and compile` |
| Scenes and Execution Blocks | `P12-02: parser groups multiple scenes with scoped cast, props, and marks`; `D-101: a quoted name keeps characters a word cannot, in scene, cast, props, marks, and transitions` | `P12-01: codegen compiles multi-scene transitions and registers scoped marks`; `P38-01: documented core statements parse and compile` |
| Statements and Conditions | `P4-02: parser parses complete tavern heist AST`; `P10-01: parser parses stageplay taxonomy, state declarations, and falling-edge/expiration rules`; `P38-01: parser rejects undocumented top-level text and body statements`; `P44-02: parser recognizes count and points conditions` | `P38-01: documented core statements parse and compile`; `P44-02: count and points conditions compile and read the fact table`; `P44-02: a wait-until aggregate counts facts and sums their third slots` (`src/vm.zig`) |
| Reactive Rules | `P8-01: multi-clause when rule parsing`; `P10-01: parser parses stageplay taxonomy, state declarations, and falling-edge/expiration rules` | `P8-02: codegen compiles multi-clause when rules into reactive rules executed on VM`; `P32-18: an arrival rule fires once per completed walk, not while resting or when placed` (`src/compiler.zig`) |
| Musical Drafts | `P22-01: parser parses draft declarations with reverse and weave statements` | `P22-01: weaving by notes, reversed notes, in-script weaves, and fizzles end to end` |
| Key Grammar Notes | `P4-02: parser parses complete tavern heist AST`; `D-101: a quoted name keeps characters a word cannot, in scene, cast, props, marks, and transitions` | `P7-02: codegen compiles verb declarations and say statements into cue emitters`; `P38-01: documented core statements parse and compile` |
| Dialogue Choices | `P13-01: parser parses conditionally guarded dialogue choice blocks`; `P13-01: parser parses relational where-clause guarded dialogue choices` | `P32-30: a scripted choice set suspends, prunes, and resumes at the chosen body` |
| Stageplay Paths | `P24-01: parser parses path declarations with locked facts and path-owned routines` | `P24-01: selecting a path asserts its facts and mutes inactive routines`; `P24-02: active path mutates obstacle facts and prunes rival dialogue choices` |
| Mechanic Declarations | `P32-22/P32-24: society and duel declarations compile into executable program data`; `P23-01: degradation declarations compile into executable container profiles` | The same compiling tests exercise parsing and code generation for each declaration family. |
| Grids; Fire, smoke, and water | `P25-01: grid declarations compile into overlays, layouts, and placed marks` | `P25-01: grid declarations compile into overlays, layouts, and placed marks`; grid automata tests in `src/grid.zig` |
| Goals and hints | `P44-01: goal declarations compile and reject malformed goals` | `P44-01: goal declarations compile and reject malformed goals`; `P44-01: a goal with no hint text yields room, thing, and relation tiers` and `P44-01: a need waits behind its prerequisite, and Rejects beats Knows` (`src/hint.zig`); `P44-01: package version 15 round-trips goals and loads a version 14 payload with none` (`src/package.zig`) |
| Scores | `P28-03: score declarations compile, seed scene facts, and play and stop by World facts` | `P28-03: score declarations compile, seed scene facts, and play and stop by World facts`; `P28-03: score errors name the script position, the part, and the rule broken` |
| Typed commands | `P26-01: command and alias declarations compile and reject malformed ones` | `P26-01: command and alias declarations compile and reject malformed ones` |
| Agendas | `P33-01: agenda declarations compile and reject malformed agendas` | `P33-01: agenda declarations compile and reject malformed agendas` |
