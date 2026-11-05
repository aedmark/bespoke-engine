# Contributing

Workflow for contributing to the BeSpoke Engine. Agent-specific standing instructions are in [`AGENTS.md`](../AGENTS.md).

## Before Changing Code

1. Read [`../README.md`](../README.md), the relevant roadmap item in [`../ROADMAP.md`](../ROADMAP.md), and [`ARCHITECTURE.md`](ARCHITECTURE.md).
2. Check `git status` to confirm your working directory is clean.
3. For changes introducing new language syntax or runtime primitives, record an entry in [`DECISIONS.md`](DECISIONS.md) before writing code.

## Make the Change

- Keep each change reviewable, focused, and scoped.
- Preserve deterministic tick semantics and memory-arena snapshot invariants.
- Update documentation according to [the documentation triggers](README.md#update-triggers).
- Keep the core runtime and compiler self-contained with zero external dependencies.

## Verify

```bash
python3 tools/check_docs.py
zig build test
```
