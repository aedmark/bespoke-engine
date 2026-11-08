# Contributing

Workflow for contributing to the BeSpoke Engine. Agent-specific standing instructions are in [`AGENTS.md`](../AGENTS.md).

## Before Changing Code

1. Read [`../README.md`](../README.md), the relevant roadmap item in [`../ROADMAP.md`](../ROADMAP.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), and test guidance. Verify the repository's actual conventions rather than importing training-distribution or external defaults (fore-conceptions).
2. Check `git status` to confirm your working directory is clean and will not overlap unrelated work.
3. Surface unstated assumptions. For ambiguous requirements or a large or irreversible change, ask clarifying questions (or record an open question in [`DECISIONS.md`](DECISIONS.md)) and agree on scope and rollback before implementation.
4. For changes introducing new language syntax, runtime opcodes, or architectural primitives, record an entry in [`DECISIONS.md`](DECISIONS.md) before writing code.

## Make the Change

- Keep each change reviewable, focused, and scoped to one outcome.
- If implementation or testing invalidates the agreed scope or exposes an unexpected architectural dependency, pause and re-scope before continuing.
- Preserve deterministic tick semantics and contiguous memory-arena snapshot invariants (D-001, D-003).
- Add or update tests for changed behaviour. Make a new test fail for the intended reason before trusting it.
- Update documentation according to [the documentation triggers](README.md#update-triggers).
- Keep the core runtime and compiler self-contained with zero external dependencies.
- Do not include credentials, personal data, generated caches, or local configuration.

## Verify

```bash
python3 tools/check_docs.py
zig build test
```

Follow [TESTING.md](TESTING.md) for prerequisites and suite limitations. Report the exact checks run and any checks skipped; a partial pass is not a full pass.

## Submit and Review

- Default branch: `main`. Working branch pattern: `feature/<topic>`.
- Commit format: Imperative present tense, referencing roadmap IDs where applicable.
- A change is ready when its scope is clear, relevant checks pass, user and migration impact is described, sensitive data is absent, and the documentation it invalidated has been updated.

## Compatibility and Migrations

For bytecode packages (`.bspk`) or save files (`.sav`), binary format changes must increment the container version header, provide backward compatibility where possible, or reject unsupported legacy versions with clean diagnostics.

## Reporting Security Issues

Do not open a public issue for a suspected vulnerability. Follow [SECURITY.md](SECURITY.md).
