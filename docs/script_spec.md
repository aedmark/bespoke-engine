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

when CharmedBy(Guard, Bard):
  interrupt Guard with:
    face Guard toward Bard
    wait until not CharmedBy(Guard, Bard)

on cue Steal(Cat, victim) where CharmedBy(victim, _) and Carries(victim, loot):
  forget Carries(victim, loot)
  remember Carries(Cat, loot)
```

> **Implementation note (D-072, D-161):** the `where` guard is evaluated when the cue fires. `victim` is bound to the cue's target, both clauses must hold for that same victim, and `loot` matches any entity the victim carries. If the guard fails, dispatch tries the next handler (D-160), then a less specific one (such as `on cue Steal(thief, victim):`), and runs nothing if none is left. A guard pattern takes one argument (a state) or two (a fact), joined with `and`; up to eight distinct variables. The body reads the bindings: above, `victim` is the entity robbed and `loot` the thing the guard found it carrying. The runnable form of this slice is [`scenarios/tavern_heist.bespoke`](../scenarios/tavern_heist.bespoke).

## Declarations and Facts

Names are case-sensitive, and the first letter decides what a name is (D-161). A name that starts with a capital letter is a thing: an entity, relation, routine, scene, or any other declared name. A name that starts with a lowercase letter, where a thing could stand, is a variable, and something must bind it: a cue handler's parameter, its `where` guard, or a `when` trigger pattern. An unbound one is a compile error whose help offers the capitalised name, and declaring a thing with a lowercase name (`entity hero`) is an error. `_` is the wildcard, and numbers and `true`/`false` are values.

`save version N` (a whole number from 1, at most once; 1 when absent) names which saves this build can load (P48-08, D-162). Every save records the build that wrote it; a save from the same build loads as it was. A save from another build with the same save version loads its facts, entities matched by name, and every routine restarts from its beginning, while `when` rules that already hold count as fired; any other save is refused. A relation's object is always an entity or always a number (D-178): the compiler infers which from how the script writes and tests it, and using one relation both ways is an error.

`entity A, B` declares names. `relation R(subject, object)` declares a set relation; `property P(subject, value)` declares a single-value relation, so remembering a new value replaces the old one. Argument names in declarations are descriptive only. A fact pattern is `Relation(A)` or `Relation(A, B)`; square brackets (`Relation[A, B]`) are an accepted equivalent. `_` is a wildcard in guards and triggers.

`remember Fact(...)` asserts a fact. `remember Fact(...) for N ticks` gives it an expiry tick, and `forget Fact(...)` removes it. The stageplay forms `now Actor is State`, `Actor is State`, and their `is not` / `are not` variants assert or remove unary state facts. A state word names the relation with its first letter capitalised, so `now Lamp is lit`, `if Lamp is lit`, and `when Lamp is lit` mean `Lit(Lamp)` (D-161). `in the scene` and `with` may follow a state phrase for readable stage directions; they do not add another fact. A declaration sentence such as `DoorStatus is a state, which can be open or shut.` declares `DoorStatus` as a relation; text after `state` on that line is descriptive.

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

`scene`, `cast`, `props`, and `marks` describe stages. A scene heading may put the colon before or after its name (`scene: Harbour Office` or `scene Harbour Office:`); the other three use `cast:`, `props:`, and `marks:`. Their visual indentation is optional. Each later `cast`, `props`, or `marks` line belongs to the most recent scene. `routine Name(Actor)` declares a fiber owned by that actor, and the name and the actor may be names with spaces. `during Name` is the stageplay shorthand for `routine Name(Name)`. Routine names are unique across top-level, path, and `during` declarations; a repeated name is a compile error at the second declaration. A top-level `transition to scene Name` seeds an initial transition; the same statement in a body changes scene when that fiber reaches it.

`on cue Name(parameters)` and its synonym `verb Name(parameters)` declare externally fired handlers. Parameters beginning with an uppercase letter match that entity; lowercase parameters match any entity. An optional `where` clause contains fact patterns joined by `and`. The body reads each lowercase parameter as the entity the cue was fired with, and each variable the guard binds as the entity it matched (D-161), in `remember`, `forget`, conditions, `wait until`, `say`, `face`, `walk`, `animate`, and `interrupt`. A statement that takes a fixed name, such as `transition to scene` or `weave`, refuses a parameter. A `when` rule body cannot use its trigger's variables yet; name the entity instead.

Several handlers may share a signature (P48-01, D-160). They are tried in source order: a handler whose guard fails passes the cue to the next one with the same signature, and only when all of them decline does dispatch move to a less specific signature. Write the guarded handlers first and an unguarded default last; a handler after an unguarded one of the same signature can never run and is a compile error naming both lines. Parameters declared as variables share one signature whatever they are called, so `Uses(Hero, thing)` and `Uses(Hero, item)` are the same.

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

A condition is a fact (`Carries(Hero, Key)` or `Carries[Hero, Key]`), its negation (`not Carries(Hero, Key)`), a unary state phrase (`Hero is Ready`, `Hero is not Ready`), a speech fact (`Hero says "Ready"`), a dice threshold (`roll 2d6 >= 8`), or an evidence threshold (P44-02).

Dice (P48-14, D-168, D-184). Every `roll` in a run draws from one generator. A script never seeds it: a headless run starts from seed 42, `bespoke run --seed N` or a host chooses another, and a new game in the desktop window or a browser page takes one from the clock. A save keeps the seed and the generator's state, and so does each rewind snapshot, together with every routine where it stood, so a load or a rewind followed by the same action rolls the same. A script whose dice are for variety rather than risk declares `rewinds reroll` once, at the top level: a rewind then restores everything but the generator, which keeps going, so the same action may roll differently. Loads still restore it. A branch world rolls from dice of its own, seeded from the run's seed and the tick the branch opened, so nothing in a branch changes what the present rolls. `rewinds` and `reroll` stay usable as names.

An evidence threshold counts matching facts or sums their third slot: `2 of Clue(_)` holds when at least two facts match, and `6 points of Clue(_)` holds when the matched facts' third slots total at least six. `_` is a wildcard in either argument, so `2 of Clue(_)` counts every subject and `2 of Clue(Hero, _)` counts the Hero's. A weighted condition reads the third slot as points, so `remember Clue(Diary, 3)` contributes three. Aggregates are conditions in `if`, `wait until`, and choice guards; `when` triggers and `where` guards keep their existing forms.

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

A plain `when` rule fires once when its trigger starts to hold, however many rows match, so its body cannot read the trigger's variables (D-161, D-170). `when each` fires once for each matching row as that row starts to hold, and its body reads the row's variables as a cue handler reads its parameters (P48-16, D-170, D-186):

```bespoke
when each Holds(who, Sword):
  remember Armed(who)
  say Hero: "Someone has a sword."
```

- Only the rising form takes `each`; `when each X stops being ...` and `when each X forgets ...` are compile errors.
- A row that stops holding and starts again fires again. Rows that start on the same tick run in the order of their bound values' names, first trigger variable first.
- A row's body runs on the entity its first trigger pattern's subject binds: it interrupts that entity's routine, or runs as a fiber of its own when the entity has none. An `interrupt X with:` body names its own target.
- The rows each rule holds are saved, and rewinds restore them, so a load or a rewind fires only rows that start afterwards.

## Musical Drafts

`draft Name(C, D, E, F)` declares exactly four note names from C through B. `reverse OtherName` optionally names the reversed sequence. Draft names and note sequences must be unambiguous. `weave Name on Target` is valid only in an executable body and the draft may be declared later in the file.

## Includes (P48-15, D-169, D-185)

A game may span files. The main script names the others with `include`, and each is read as if pasted at its line:

```bespoke
scene: Tallow Lane
cast: Nell, Hobb
include "art.bespoke"
include "acts/one.bespoke"
```

- An `include` line starts at column 0, between declarations, with one quoted path; an indented one is a compile error.
- Every path, in the main script and in every file it includes, is relative to the main script's folder, uses `/`, and has no `..` part, the rule PNG paths follow (D-156). So are the PNG paths inside included files.
- An included file may include others. A file already included is skipped, so including a common file twice, or two files that include each other, reads each once.
- Source order is the order after expansion: a handler in an included file stands where its include line does (D-160).
- A diagnostic names the file it is in and that file's line, such as `acts/one.bespoke:3:14: error: ...`.
- Only a compile from the command line reads includes. A package holds the expanded program, so a browser page or a host loading it never reads the other files; the browser compiles no script with an include.

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

The host selects a path with `VM.select_path(compiled, "Wits")`. The path entity receives `PathActive(Wits)` immediately, and the block's fact statements run on the next tick. Scripts can test the active route with `if PathActive(Wits):`. Routines declared inside the block carry a generated guard: when another route is active they halt before their first body instruction. Selecting a different path returns `PathAlreadyChosen`; selecting the same path again is a no-op. Path routine names share the top-level routine namespace, and a name already declared anywhere else is a compile error at the second declaration. Path facts are ordinary World facts, so saves and rewind restore them.

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

Society `need` and `member` order is significant. It establishes need and roster indexes, including society tick evaluation order. Duel pairs and tier variants preserve source order. A degradation profile's stage order is its progression order; every nonterminal stage has a positive duration and the final stage has duration zero. Each vessel declares capacity, initial volume, and initial stage. `spill N` removes up to N volume per tick while the vessel or its `Carries` holder is moving. The optional `relations` line supplies five distinct names for contents, volume, stage, exposure, and failure location. Compilation rejects invalid capacities, stages, members, providers, activities, and waypoints.

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

Each set attribute is a fact on the grid entity: `CellFlammable(HallFloor, index)`, `CellLiquid`, or `CellBlocking`, where `index` is `y * W + x`. The host lifecycle writes the declared layout once, so later changes survive save, rewind, and re-initialisation. A mark standing in a `blocking` cell is treated like `WaypointBlocked`: scripted walks plan around it, and a walk to it is refused.

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

`play score <Name>` overrides scene music in every scene until `stop score` or another `play score`. Parts loop together from their `L` once every part has ended (D-061). The choice is World state (`#SceneScore` facts and the `#PlayingScore` property of `Music`), so saves and rewinds restore it.

### Typed commands (P26-01, D-057)

A typed line such as `> pour the grog into the mug` is matched against sentence shapes (frames) and becomes a cue. The engine provides frames for looking, using, talking, presenting, and walking; a script adds its own, which are tried first.

```bespoke
command Pours: "pour <thing> into <thing>"
command Takes: "take <thing>"
alias ExposureSlip: "slip", "receipt"
```

- A frame is lowercase words and at most two `<thing>` slots, starting with a word and never with two slots side by side. Engine frames: `look at`, `examine`, `x` (`LooksAt`); `appeal to` (`Appeals`, P45-05); `use <thing> with/on <thing>`, `use <thing>` (`Uses`); `ask <thing> about <thing>`, `talk to <thing>` (`TalksTo`); `present <thing> to <thing>`, `show <thing> to <thing>` (`Presents`); `go to`, `walk to` (`WalksTo`).
- Typed input ignores case, punctuation, and the articles `a`, `an`, `the`.
- An entity answers to the words of its name, split at capitals, spaces, and underscores (`ExposureSlip` answers to "exposure slip" and "slip"), and to the words of its `alias` phrases. Only what is in the actor's room or carried by the actor can be named. If two things match, the command is ambiguous and the game asks which.
- Hosts that enable the window's command bar let the player type these lines: Enter focuses the bar, Esc leaves, Up/Down recall history, Tab completes a word. A browser deck turns on the same bar with `command_bar`, and the page made by `bespoke init` has it on.
- What the player sees: a matched, resolved command fires its cue, whose handler speaks on the next tick; `go to <mark>` or `go to <person>` also walks there. Otherwise the reply is one of "I don't know the word \"x\".", "I don't understand that.", "You don't see that here.", "Which do you mean: the brass key or the iron key?" (answer with a noun such as "brass"), or "Nothing happens." when no handler answers.

### Presenting evidence (P44-03)

`present <thing> to <thing>` and `show <thing> to <thing>` are engine frames for `Presents`. The first noun is the evidence and the second is the character, matching the cue's roles: `on cue Presents(Ines, Pell, ExposureSlip):`.

The engine records `Presented(person, evidence)` before dispatching, so the presentation is World state whether or not a handler answers. `Presented` is a set relation: it keeps one row per distinct piece of evidence, so `1 of Presented(Pell, _)` counts what the character has been shown, and showing the same thing again runs the handler without adding a row. A routine or readout can follow that count, which lets a character's composure react to evidence as it arrives rather than to a fixed story beat.

The script decides what the character reveals, usually by branching on `Knows(person, evidence)`; `Believes` counts as knowledge and `Rejects` cancels it (D-134). A host calls `host.present(vm, compiled, actor, evidence, person)`, which records the fact and fires the cue. Its parameters take the evidence before the person, the reverse of the cue's target order. No statement or package format change is needed: `Presents` is an ordinary three-argument cue, with the person second.

Cue dispatch still tries the two target arguments in either order, as it does for `Uses`. The typed frames and `host.present` are what fix person-second, so a handler should declare that order: `Presents(Ines, Pell, ExposureSlip)`.

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
- When several agendas target the same actor, one pursues: highest priority, then the actor with the shorter route, then the first declared.
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
- `hint <tier> "text"` replaces one generated tier: 1 names the room, 2 the thing, and 3 the relation. Each tier at most once per need. A need may also write tiers above 3, which have no generated text (P48-13, D-183); past 3 the script needs `limit hints N` covering its highest tier, up to 24. Asking for a tier a need lacks answers with its highest tier below the one asked, and the result names the tier it gave, so one hint control can step through any number of tiers.
- Declaration order is the search's order. A goal is done when every need holds; a need is on the frontier when it is unmet and every `after` need holds.
- The query takes the tier and the player entity, and reports the first frontier need whose entities the player knows, together with `holmesian` or `doylian` and whether the text was authored. Knowledge is `Knows` or `Believes` about the player, and `Rejects` cancels either, so a script asserts knowledge when a scene shows the character something.
- When no frontier need is one the character could reason about, the query reports the first unmet need in declaration order as the author: it may name a room or a thing the character has not met.
- The query reads facts and writes none, so a save, a rewind, or a replay reports the same hint for the same world. Cycles in `after`, duplicate need names, an unknown prerequisite, and a missing or invalid tier are compile errors.

### Spellbooks (P44-04, D-136)

A spellbook declares three kinds of words and the combinations that spell something. A combination resolves to the cue named after the spell.

```bespoke
relation Lit(thing)

spellbook Grimoire:
  power Spark, Forge
  element Ember, Water
  form Bolt, Ward
  spell Kindle: Forge, Ember, Bolt
  spell Douse: Spark, Water, Ward

on cue Kindle(Maren, Crucible):
  remember Lit(Crucible)
```

- `power`, `element`, and `form` each take a comma-separated list of words. A word's tier is its position within its kind, counted from one; the tier orders the author's vocabulary and does not gate a cast.
- `spell <Name>: <Power>, <Element>, <Form>` names a combination. The commas are optional. Each word must be declared in the position it occupies, and the spell's name becomes the cue that fires when it resolves.
- One book per script. A word or spell name declared twice, a spell that names an undeclared or misplaced word, two spells over the same triple, and a fourth word in a row are compile errors.
- `spell.cast(book, world, caster, name)` and `spell.combine(book, world, caster, power, element, form)` resolve through `src/spell.zig`, which is program data and reads the fact table without writing any. `host.cast(vm, compiled, caster, name, target)` fires the cue for a resolved spell.
- Each word is gated by discovery: the caster knows a word through `Knows` or `Believes`, and `Rejects` cancels either. An unknown word refuses the combination before any cue fires, so a fizzle changes no state. The Word Foundry (`--word-foundry`) teaches the words through three clues and shows two spells and one refusal; its headless transcript is checked against a golden.

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

All decisions in a tick read the grid as it stood at the start of that tick, so the result never depends on cell order, and rewinds replay exactly. The engine marks each actor with `InBurningCell`, `InSmokeCell`, and `InLiquidCell` for the cell it stands in; `when Actor is InBurningCell:` and `when Actor stops being InBurningCell:` react to them on the following tick.

### Decisions (P44-05, D-137)

A decision offers an actor the options it knows and fires one cue with the winner.

```bespoke
relation Chose(decision, option)

decision LeadAtTable:
  actor Maren
  fires CardPlayed
  requires Turn(Maren)
  unless Closed(Trick)
  option SaltTwo:
    picks 4 when SuitLed(Salt)
    drops 2 when High(SaltThree)
  option ReedOne:
    picks 1 when SuitLed(Salt)
```

- `actor` and `fires` are required. `requires` and `unless` are the trigger lines, the same shape agendas use, with `_` as a wildcard and no variables.
- An option is offered only when its actor knows the option's entity: `Knows` or `Believes`, with `Rejects` overriding. A hand is the set of cards its seat knows, so another seat's cards are never candidates.
- `picks N when <clause>` adds N when the clause holds, `drops N when <clause>` subtracts, and `unless` inverts the clause. Each line's magnitude is 1 to 100.
- The highest total wins and an equal total keeps the earlier option. A decision whose options are all unoffered resolves to nothing and fires nothing.
- A decision point is a rising edge: the engine chooses once while the trigger holds and re-arms when it falls. The choice is the set fact `Chose(Decision, Option)`, which a script reads by declaring that relation; it clears on re-arm.
- The cue fires with the actor and the winning option. A handler can name the option exactly (`on cue CardPlayed(Maren, SaltTwo):`) or take it as a parameter its body reads (`on cue CardPlayed(Maren, card):`, D-161).
- Scoring reads facts and draws no random number, so a replay makes the same choice.

#### Red lines (P45-02, D-145)

```bespoke
red lines Valerius: Execute, BurnGranary
```

- A red line is an option the character never takes, in any decision where it is the actor. The engine removes a vetoed option before scoring, so it is never chosen, even when it would score highest.
- Each name must be an option that some decision offers that character. A misspelling is a compile error, and so is a decision whose every option is vetoed, since it could never choose.
- A character's red lines are declared once, name each option once, and hold at most 16 options.
- Red lines are fixed when the script compiles: they are not facts, so no `remember`, `forget`, save, rewind, or value drift changes them. A decision point whose offered options are all vetoed chooses nothing and fires nothing, as an empty hand does.
- Red lines veto decision options only; agendas, cues, and typed commands are unaffected.

### Value axes (P45-01, D-144)

An axis is a virtue a character holds from -10 to +10. The script names every axis; the engine names none.

```bespoke
axis Justice between Cruelty and Leniency
axis Mercy between Vengeance and "Condoning Harm"

remember Justice(Valerius, 8)
remember Mercy(Valerius, -3)
```

- `axis <Virtue> between <Pole> and <Pole>` declares the axis. The virtue names it; the two poles name the ways it fails, and a pole may be quoted or run to the end of its phrase. The two poles differ, and neither repeats the virtue.
- The axis is a property relation named after the virtue, so `Justice(Valerius, 8)` is one fact per character and a later `remember Justice(Valerius, 2)` replaces it (D-007). +10 is the virtue held fully; lower values lean toward failure.
- A character holds no value on an axis until a `remember` gives it one; there is no implicit zero.
- A value on an axis must be a whole number from -10 to +10, in a `remember` and in a condition such as `if Mercy(Valerius, -3):`. Anything else is a compile error, and so is `Mercy(Valerius)` without a value. A negative number is a compile error everywhere except on an axis.
- An axis cannot reuse the name of a declared `relation` or `property`, and each axis is declared once.
- At run time every write is clamped into the range, so a host call, a loaded save, or later drift stores -10 or +10 rather than a value past it. The state inspector lists the value as a signed number on its character.
- `drift step N`, indented under the axis, sets how many drift points move a value on this axis one step (P48-13, D-183): 1 to 20, and 5 when omitted. It belongs to the axis because a character's points on it add up across every dilemma that drifts it.
- Scoring a decision by value is not part of this item: `picks` and `drops` lines still read facts, and dilemmas that compare two axes arrive with P45-03.

### Dilemmas (P45-03, D-146)

A dilemma weighs one value axis against another and answers by tier.

```bespoke
axis Justice between Cruelty and Leniency
axis Mercy between Vengeance and "Condoning Harm"

dilemma StolenBread:
  actor Valerius
  fires Judged
  requires Accused(Thief)
  weighs Justice against Mercy
  leans 3 toward Justice when Criminal(Thief)
  leans 4 toward Mercy when Famine(Town)
  strong Justice: "The law is the law." -> Hang
  moderate Justice: "A night in the cells." -> Jail
  neutral: "Show me why I should spare him." -> Wait
  moderate Mercy: "Pay for the loaf." -> Fine
  strong Mercy: "Feed him and let him go." -> Pardon
```

- `actor`, `fires`, `weighs`, at least one `requires` or `unless` line, and all five tier lines are required. Both axes must be declared with `axis`, and they differ.
- The delta is the actor's value on the first axis minus its value on the second, plus each `leans` line that holds (`unless` inverts the fact). A value the actor does not hold counts as 0. Each lean is 1 to 10, at most 8 lines, and leans toward one of the two weighed axes.
- By default 7 or more is strong toward the first axis, 3 to 6 moderate, -2 to 2 neutral, -6 to -3 moderate toward the second, -7 or less strong toward it. `tiers <strong> and <moderate>` sets the two boundaries, mirrored around zero (P48-13, D-183): `tiers 8 and 4` makes 8 or more strong and 4 to 7 moderate. The moderate boundary is from 1 and below the strong one, which is at most 100. A missing or repeated tier is a compile error that names it, such as `dilemma 'StolenBread' has no line for the strong Mercy tier`.
- When the trigger rises, the actor says the tier's line, the engine records `Chose(StolenBread, Jail)`, and the cue fires with the actor and the action: `on cue Judged(Valerius, Jail):`. The dilemma weighs once while the trigger holds and re-arms when it falls.
- A neutral result waits for evidence: each tick on which something new has been presented to the actor (`present <thing> to <person>`), the dilemma weighs again, speaking and firing again. Evidence that turns a `leans` line on can move it to another tier.
- A tier action on the actor's red lines is a compile error. A dilemma may not share a decision's name.

#### Value drift (P45-04, D-148)

```bespoke
  drifts 3 toward Mercy when Repaid(Thief)
  drifts 4 away from Loyalty when Robbed(Baker)
```

- A `drifts` line in a dilemma adds points toward or away from an axis each time its fact becomes true, once the dilemma has been weighed at least once. `unless` inverts the fact. Points are 1 to 10, at most 8 lines, and the axis may be any declared axis.
- Every 5 points move the character's value one step, or the axis's `drift step`. One dilemma moves each axis at most 2 steps over the whole game, or the number its `drift cap N` line gives (1 to 20, P48-13, D-183); further points from it are dropped.
- Drift stops at -10 and +10, and points that would push past the end are discarded rather than saved up. Drift never changes red lines.
- Drift is facts: `Mercy drift(Valerius, 1)` holds the points not yet spent and `Mercy drift steps(StolenBread, 2)` the steps a dilemma has used, so saves and rewinds keep it and a replay reproduces it.

#### Persuasion (P45-05, D-149)

```bespoke
dilemma StolenBread:
  ...
  weighs Justice against Mercy
  appeals 4 to Mercy
  appeals 3 to Justice

on cue TalksTo(Ines, Valerius, Mercy):
  say Valerius: "I was a hungry boy once."
  remember Knows(Ines, "Mercy of Valerius")
```

- `appeals <N> to <Axis>` says the player may appeal to one of the two weighed values, and how far the appeal moves the next weighing toward it (1 to 10). `appeals <N> to <Value> toward <Axis>` lets the player appeal to any declared value, moving the weighing toward one of the two weighed axes: `appeals 8 to Loyalty toward Mercy` (D-150). Each value has at most one appeal line, and a dilemma at most 4.
- The player types `appeal to mercy`, or a host calls `host.appeal`. The appeal reaches the first character in the room whose open dilemma lists that value. It counts at the next weighing and is then spent; while the dilemma waits in neutral, the appeal weighs it again.
- The player must know the value first: `Knows(Ines, "Mercy of Valerius")`. Otherwise the reply is "You don't know what moves them." and nothing changes. A weighing that lands outside neutral teaches everyone in the character's room the value it leaned toward; a script teaches the rest, usually when the player asks (`ask valerius about mercy` fires `TalksTo`).
- An accepted appeal records `Appealed(Valerius, Mercy)` and fires `on cue Appeals(Ines, Valerius, Mercy):`. A goal need `met Appealed(Valerius, Mercy)` is a Holmesian hint once the player knows `Mercy of Valerius`, and a Doylian one before.

### Limits (P48-13, D-167, D-183)

Some counts have a ceiling that is only a sanity check. A script that needs more raises it with one line, anywhere in the script:

```bespoke
limit decisions 48
limit hints 6
```

| Name | Counts | Default | Most |
| --- | --- | --- | --- |
| `goals` | goals | 16 | 128 |
| `needs` | needs in one goal | 16 | 128 |
| `decisions` | decisions | 32 | 256 |
| `options` | options in one decision | 8 | 64 |
| `dilemmas` | dilemmas | 32 | 256 |
| `axes` | axes | 64 | 512 |
| `spells` | spells in the spellbook | 16 | 128 |
| `words` | words of one kind in the spellbook | 12 | 96 |
| `hints` | hint tiers in one need | 3 | 24 |

- A limit is at least its default and at most eight times it; anything else, a name not in the table, or a second line for one name is a compile error. Going past a limit is a compile error on the first item past it, and its help names the `limit` line the script needs.
- A limit is a compile-time rule: the package does not carry it, and the loader holds every package to the most in the table.
- Other bounds are part of the engine's shape and have no `limit`: three cue parameters, eight guard variables, eight leans and eight drift lines a dilemma, four appeals, one spellbook (D-177), and the three generated hint tiers.

### The engine's relations (P48-10, D-164, D-180)

The engine keeps its own bookkeeping in the World under names that start with `#` (`#DialogueOpen`, `#SceneScore`, `#Mercy drift`), which no script can type, so a script's relations never collide with it. The State drawer and the debug console leave them out until the State tab's `E` key shows them after the story's facts.

These engine relations are reserved words with fixed meanings, which scripts may test and, where this document says, write: `AgendaState`, `DecisionState`, `DilemmaState`, `Knows`, `Believes`, `Rejects`, `Presented`, `Chose`, `Appealed`, `PathActive`, `Pursuing`, `CellFlammable`, `CellLiquid`, `CellBlocking`, `CellBurning`, `CellSmoke`, `InBurningCell`, `InSmokeCell`, `InLiquidCell`, `ConvergenceReady`, `LoopClosed`, and `Looks`. All date from 1.0. If a later release adds one that a script already declares with `relation`, the script keeps its own, the engine feature of that name is off for the game, and `bespoke check` prints a warning.

### What players read (P48-09, D-163, D-179)

```bespoke
name ExposureSlip: "the slip from the darkroom"
phrase HintRoom: "Seek out the {room}."
```

- `name <Thing>: "<text>"` sets what players read for an entity: on screen, in speech, in hints, and in replies. Without it the name is derived from the identifier (`HarbourClerk` reads "Harbour Clerk", D-093). A name for something the script never mentions, or a second name for the same thing, is an error. Typed commands still match the identifier's words and `alias` phrases; `name` changes only what is shown.
- `phrase <Key>: "<text>"` replaces one sentence the engine writes. The text may use the key's placeholders, in any order, and no others; an unknown key is refused with a suggestion. A build has one language.
- Text may be any UTF-8. The window's font draws printable ASCII, and any other character as one `?` until a wider font lands (P48-21).
- Window chrome (save and load messages, cancellations, key hints, debug) stays fixed English. The desktop window's own "You can't get there from here." when a click's walk is blocked is window feedback and does not read `CannotGetThere`.
- `name` and `phrase` are not reserved words.

| Key | English | Placeholders |
| --- | --- | --- |
| `HintRoom` | Look in the {room}. | `{room}` |
| `HintThing` | You need the {thing}. | `{thing}` |
| `HintFact` | You need {relation}({subject}, {object}). | `{relation}`, `{subject}`, `{object}` |
| `HintState` | You need {relation}({subject}). | `{relation}`, `{subject}` |
| `UnknownWord` | I don't know the word "{word}". | `{word}` |
| `NotUnderstood` | I don't understand that. | none |
| `NotHere` | You don't see that here. | none |
| `WhichDoYouMean` | Which do you mean: {choices}? | `{choices}` |
| `ChoiceItem` | the {thing} | `{thing}` |
| `ChoiceJoin` | ,  | none |
| `ChoiceJoinLast` |  or  | none |
| `NothingHappens` | Nothing happens. | none |
| `CannotGetThere` | You can't get there from here. | none |
| `AppealUnknownValue` | You don't know what moves them. | none |
| `AppealNobody` | Nobody here would be moved by that. | none |
| `NarrateWalk` | {actor} walks to {target}. | `{actor}`, `{target}` |
| `NarrateLook` | {actor} looks at {target}. | `{actor}`, `{target}` |
| `NarrateTalk` | {actor} talks to {target}. | `{actor}`, `{target}` |
| `NarrateTake` | {actor} takes {target}. | `{actor}`, `{target}` |
| `NarrateUse` | {actor} uses {target}. | `{actor}`, `{target}` |
| `NarrateUseOn` | {actor} uses {thing} on {target}. | `{actor}`, `{thing}`, `{target}` |
| `ArriveScene` | {scene}. | `{scene}` |
| `WalkingTo` | Walking to {mark}... | `{mark}` |
| `Someone` | Someone | none |
| `PlayerFallback` | You | none |
| `ThingFallback` | it | none |

### Pixel art (P46-03, D-152, D-155, D-166)

A script can declare its own pixel art: images in full colour from PNG files or written as rows of palette codes, a backdrop per scene, and a sprite sheet for a person or prop with its animations. Art pixels are opaque or fully transparent.

```
scene: Lamp Room
cast: Lamplighter
props: Lantern
marks: Door, Window
backdrop: LampRoom

palette:
  "." transparent
  "b" 176 128 56
  "l" 250 214 96

image LanternSheet frames 12x20:
  "....bb..........bb......"
  ...

sprite Lantern: LanternSheet
  idle: 1 for 50, 0 for 4

sprite Lamplighter: LamplighterSheet
  idle: 0 for 40, 1 for 20
  walk right: 2 for 8, 3 for 8
  walk left: 4 for 8, 5 for 8
```

- `palette:` lists up to 256 colours, one per line: a quoted code and three numbers from 0 to 255 for red, green, and blue. The first line is the transparent code (`"." transparent`), palette index 0, which is never drawn. Every code is one or two printable characters, all of the same width. `#` starts a comment, so colours are numbers rather than `#rrggbb`. A game has at most one palette, and it is a style rule (D-166): once declared, every colour in the game's art, rows and PNG files alike, must be one of its colours. A game whose art all comes from PNG files may declare none and use any colours.
- `image <Name>:` lists the image's rows below it, one quoted row per line, each code naming a palette colour. Every row is the same width. `frames <W>x<H>` cuts the image into a grid of equal frames, numbered from 0 left to right, then top to bottom; without it the whole image is one frame. A frame is at most 320x180, the art resolution, and is drawn 4x in the 1280x720 frame.
- `backdrop: <Image>` under a scene draws that image as the room. It must be one 320x180 frame. Over a backdrop the walkways and resting mark discs are hidden; hovering a mark still shows its prompt, and every click target is unchanged.
- `sprite <Person or Prop>: <Image>` draws that cast member or prop from the image, its frame's bottom edge on the spot and centred across it. Indented lines give animations: `idle:` and `walk up:`, `walk down:`, `walk left:`, `walk right:`, each a list of frames, with `for N` showing a frame for N display frames at 60 Hz (6 when omitted, ten a second). A walking person plays the walk toward the mark it is heading to; with no walk for that direction, or standing still, it idles; with no idle it shows frame 0.
- Animation is presentation only. The display counts its own frames, and nothing is written to the world, so a save, rewind, or replay is unchanged by it.
- `image <Name> from "<file>.png" [frames <W>x<H>]` reads a PNG instead of rows (P46-04, D-156). Each pixel keeps its colour: fully transparent pixels are transparent, opaque ones keep their red, green, and blue, and a partly transparent pixel is an error. With a declared `palette:`, a colour the palette lacks is an error naming the pixel and its colour. A script whose art all comes from files needs no `palette:` block. Only a compile from the command line (`bespoke run`, `compile`, or `check` on a file) reads files, from the script's own folder: the path is relative, uses `/`, and has no `..`. The browser compiles no such script; `bespoke import` writes the rows inline for it.
- `bespoke import <art.png> --name <Image> [--frames WxH] [--script <script.bespoke>]` prints an inline `image` block and the palette lines it needs. With `--script`, the script's codes are kept and only new colours are listed, with codes it does not use; without it, a whole `palette:` block is written. `-o <file>` writes to a file instead.
- `area <Prop>: x y w h` marks where a prop is on the art, in art pixels (P46-05, D-158): a window or door painted on the backdrop, or a lamp a theme draws. A click anywhere inside acts on the prop, hovering shows its prompt (the debug overlay also outlines it), and the player walks to the mark nearest its foot. A prop with an area and no sprite draws nothing of its own. People and props drawn as sprites are clicked anywhere in their frame.
- `look <Name>: <Image>` names one way of showing a sheet, with its own indented animations, the same lines a sprite takes (P48-11, D-181). A look's name is not an image's name. `sprite <Thing>: <Look>` shows that look until a script says otherwise; such a sprite takes no animation lines of its own, since the look carries them.
- `Looks(<Thing>, <Look>)` is the look a thing shows: a property, so a new fact replaces the last, and a script writes it like any other (`remember Looks(Lamp, LampLit)`). The display reads it each frame, so a save, rewind, or replay shows the same look; a thing with no `Looks` fact shows its sprite's own look or image. The compiler refuses a `Looks` fact that names no declared look (`UnknownLook`, with a suggestion).
- `part <Thing> of <Host> at <dx> <dy>` attaches a cast member or prop to another: its sprite is drawn above the host, its frame's bottom centre at the host's bottom centre plus the offset in art pixels (each at most 320 either way), and a click on it acts on the host. A part that is also cast or a prop is drawn only there, never on its own spot. A part may not be its own host, and a thing has at most one part line.
- A thing with a sprite and an area draws its frame at the area's top-left, so a lamp a script owns sits where the backdrop paints it.
- `palette`, `image`, `sprite`, `look`, `part`, `backdrop`, and `area` are not reserved words: each starts an art declaration only when followed by its colon or a name on the same line.
- The compiler names the line of an unknown image, a frame past the end of a sheet, a code the palette lacks, a ragged row, frames that do not tile, a backdrop of the wrong size, a sprite for something no scene lists, and art past the limits: 1,024 images, 2,048 pixels on a side and 1,048,576 pixels per sheet, and 2,097,152 pixels across all images (D-182).

## Test Coverage

The language conformance suite (P48-18, D-173) pins each frozen rule as runnable scripts, independent of engine internals:

| Rule | Conformance cases (`tests/conformance/`) |
| --- | --- |
| Engine relations (D-180) | `src/compiler.zig`: `P48-10: engine bookkeeping cannot be named in a script, and a plain name is the script's own`; `P48-10: a script declaring a relation a later release adopted keeps it, with a warning` |
| What players read (D-179) | `d179-player-text/`: a name and a phrase reach the player, an unknown phrase key and a name for nothing are refused |
| Relation object kinds (D-178) | `d178-object-kinds/`: one kind per relation runs, an entity relation tested with a number is refused |
| Save version (D-162) | `d162-save-version/`: declared once, a whole number from 1, and adds no facts |
| Cue signatures and defaults (D-037) | `d037-cue-signatures/`: specific beats variable, actor-only default, unmatched cue runs nothing |
| `where` guards (D-072) | `d072-cue-guards/`: a failed guard falls to a broader signature, a holding guard runs, a guard binds its parameter |
| Handlers sharing a signature (D-160) | `d160-ordered-handlers/`: first holding guard wins, fall-through within a signature, unguarded default last, a handler after an unguarded one is refused |
| Case decides role; bound bodies (D-161) | `d161-case-and-binding/`: a body reads parameters and guard variables, a state word is the relation, lowercase declarations, unbound lowercase names, and `when` body variables are refused |

Each later Phase 48 item adds the cases for the rule it builds.

P38-01 audits the accepted grammar against this document. Exact Zig test names are listed so a renamed or removed test makes the table visibly stale. Codegen tests parse their source before compiling it; the parser-coverage column names focused AST tests where one exists and the compiling test otherwise.

| Spec section | Parser coverage | Codegen or integration test |
| --- | --- | --- |
| Opening vertical slice; cue parameters and `where` | `P4-02: parser parses complete tavern heist AST` | `D-072: cue where guards bind cue parameters and fall through to the next handler` (`src/compiler.zig`) |
| Case decides role; bound handler bodies (P48-02) | `P48-02: lowercase names of things and unbound variables are refused where they are written`; `P48-02: a state word and its capitalised relation are one fact` (`src/compiler.zig`) | `P48-02: a cue handler body reads the entities its cue was fired with` (`src/compiler.zig`); `P48-02: a cue handler saved while it waits still reads its arguments after a load` (`src/save.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`) |
| Handlers sharing a signature (P48-01) | `P48-01: a handler after an unguarded one of the same signature is refused, naming both lines` (`src/compiler.zig`) | `P48-01: handlers that share a signature run in source order, each failed guard falling through` (`src/compiler.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`) |
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
| Spellbooks (P44-04) | `P44-04: a spellbook declaration reads words in three kinds and the rows that combine them`; `P44-04: parser rejects a misplaced or undeclared word, a repeated name, and a fourth word` | `P44-04: a spellbook compiles into tiered words and a resolvable spell`; `P44-04: a valid triple resolves, and an invalid one is refused` and `P44-04: each word is gated by discovery, and Rejects overrides Knows` (`src/spell.zig`); `P44-04: a cast fires the spell's cue only when the caster knows every word` (`src/host.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`); The Word Foundry's `word_foundry.txt` transcript |
| Decisions (P44-05) | `P44-05: a decision declaration reads its actor, cue, trigger lines, and scored options`; `P44-05: parser rejects a decision without a cue, an option without scores, and a repeated option` | `P44-05: a decision compiles into trigger lines and scored options`; `P44-05: the highest-scoring offered option wins, and an equal score keeps the earlier one`, `P44-05: an option the actor does not know is never offered, and Rejects overrides`, and `P44-05: a decision fires its cue with the winning option, once per rising trigger` (`src/decision.zig`, `src/host.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`); The Cinder Table's `cinder_table.txt` transcript |
| Value axes (P45-01) | `P45-01: axis declarations and values are range-checked at compile time` (`src/compiler/codegen.zig`) | `P45-01: an author-declared axis compiles into a bounded property with signed values`; `P45-01: an axis bounds its property and reads signed values` (`src/value.zig`); `P45-01: a bounded property clamps writes, restores, and clones` (`src/world.zig`); `P45-01: the inspector lists an axis value as a signed number, not an entity` (`src/display.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`) |
| Red lines (P45-02) | `P45-02: red lines compile per character and are checked against its decisions` (`src/compiler/codegen.zig`) | `P45-02: a vetoed option is never chosen, even when it would score highest` and `P45-02: red lines must name an option offered to that character and leave one open` (`src/decision.zig`); `P45-02: a red line vetoes the highest-scoring option through host.tick` (`src/host.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`) |
| Dilemmas (P45-03) | `P45-03: a dilemma compiles its axes, leans, and five tiers, and refuses a gap` (`src/compiler/codegen.zig`) | `P45-03: tier boundaries are fixed and mirrored`, `P45-03: each tier boundary selects its line and action`, `P45-03: lean lines read world facts and move the tier`, `P45-03: a neutral weighing waits for evidence and weighs again when it arrives`, and `P45-03: a tier action on the actor's red lines is refused` (`src/dilemma.zig`); `P45-03: a dilemma speaks its tier's line and fires the action through host.tick` (`src/host.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`) |
| Value drift (P45-04) | `P45-04: drift lines compile to signed points on a declared axis` (`src/compiler/codegen.zig`) | `P45-04: drift accumulates whole points and moves a value one step per 5` and `P45-04: one dilemma moves an axis at most two steps, and drift stops at the range` (`src/dilemma.zig`); `P45-04: drift is identical after a save, a rewind, and a replay` (`src/host.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`) |
| Persuasion (P45-05) | `P45-05: appeal lines compile toward a weighed axis and refuse any other` (`src/compiler/codegen.zig`) | `P45-05: one dilemma resolves differently under two appeals the player learns` and `P45-05: watching a weighing teaches the value it leaned toward to those in the room` (`src/host.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`) |
| Prop areas (P46-05) | `P46-03: art mistakes are reported on their own line` (`src/compiler.zig`, the area cases) | `P46-05: a sprite is clicked anywhere in its frame, and an area anywhere in its rectangle` (`src/display/renderer.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`); `P46-05: clicks in the window act and their replies reach the banner` (`proofs/lamplighter.zig`) |
| PNG import (P46-04) | `P46-04: a script compiled from its file reads the PNGs beside it in their own colours`; `P46-04: a script cannot read a file outside its folder, and a missing or bad file is named` (`src/runner.zig`) | `P46-04: import writes an indexed and a true-colour PNG as inline blocks, joining a script's palette` (`src/runner.zig`); decoder tests in `src/png.zig` |
| Looks and parts (P48-11) | `P48-11: looks and parts compile, and their mistakes are named` (`src/compiler.zig`); `tests/conformance/d181-looks/` | `P48-11: a Looks fact picks what a thing shows, and a part is drawn above and clicked as its host` (`src/display/renderer.zig`); `P48-11: a package carries looks and parts, and refuses a part hosted by itself` (`src/package.zig`); the Lamplighter's lamps and the `lamplighter` render golden lines (`proofs/`) |
| Pixel art (P46-03) | `P46-03: art declarations compile into the program with their bindings`; `P46-03: art mistakes are reported on their own line` (`src/compiler.zig`) | `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`); `P46-03: the image stage's script declares its art and compiles it into the program` and the `image_stage/replay` render golden lines (`proofs/`) |
| Goals and hints | `P44-01: goal declarations compile and reject malformed goals` | `P44-01: goal declarations compile and reject malformed goals`; `P44-01: a goal with no hint text yields room, thing, and relation tiers` and `P44-01: a need waits behind its prerequisite, and Rejects beats Knows` (`src/hint.zig`); `P48-17: every part of a program round-trips through its own section, byte for byte` (`src/package.zig`) |
| Scores | `P28-03: score declarations compile, seed scene facts, and play and stop by World facts` | `P28-03: score declarations compile, seed scene facts, and play and stop by World facts`; `P28-03: score errors name the script position, the part, and the rule broken` |
| Typed commands | `P26-01: command and alias declarations compile and reject malformed ones` | `P26-01: command and alias declarations compile and reject malformed ones`; `P26-02: the interpreter resolves commands, asks which, and explains failures` (`src/command.zig`, including the `Presents` frames) |
| Presentation (P44-03) | Existing three-argument cue grammar; the item adds no statement | `P44-03: a presentation records Presented and reveals only what the character knows` (`src/host.zig`); the Observatory's headless run presents the glove, the slip, and the slip to Moss |
| Agendas | `P33-01: agenda declarations compile and reject malformed agendas` | `P33-01: agenda declarations compile and reject malformed agendas` |
