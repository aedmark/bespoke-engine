# Whitepaper: A Bespoke Whimsical Game Development Language

> Written 2026-11-04, before any code, and kept as written. Its performance phrases (sub-millisecond compiles, instant serialization) are goals that have not been measured. For what the engine does today, read [`README.md`](README.md); for the terms, [`docs/GLOSSARY.md`](docs/GLOSSARY.md).

## 1. Executive Summary
Most game-making languages are either rigid engines with scripting tacked on (RPG Maker, Unity) or general-purpose systems that force developers to build state machine scaffolding from scratch (C#, Odin, C++). 

We are building a bespoke language designed from the ground up for whimsy, systemic depth, and narrative games. Crucially, **the language runtime acts as the spine of the engine**, owning the main clock tick, entity IDs, and relational database, while rendering and audio act as dumb peripheral display screens.

## 2. Core Architectural Pillars
- **Custom Bytecode VM:** Hand-written compiler front-end in Zig that lowers source code straight into compact custom bytecode. Sub-millisecond compile times, lightweight runtime footprint, and instant serialization for save games and rewinds.
- **Relational State as First-Class Syntax:** No object graphs or nested pointers. Entities are integer IDs; facts are flat database rows (`subject, relation, object, expires_at`).
- **Temporal Control Flow as First-Class Syntax:** Built-in `wait` and `interrupt` primitives eliminate state machine boilerplate, frame timers, and cleanup callback spaghetti.
