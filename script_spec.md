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

## Key Grammar Notes
1. **`remember` / `forget`:** Declarative database mutations. `remember ... for N ticks` automatically attaches an expiration tick to the relation row, handling temporary buffs and debuffs natively.
2. **`interrupt ... with`:** Pauses an active routine (like `Patrol`), executes the interruption behavior, and automatically restores the instruction pointer once the condition resolves.
3. **Cues & Commands:** External inputs arrive as events (`on cue`), and physical actions (`walk`, `face`) emit lightweight bytecode instructions back to the host display layer.
