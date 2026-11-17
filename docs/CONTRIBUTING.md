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

## Releases

Version tags, release notes, and downloadable artifacts are published through GitHub Releases on the existing repository (D-105). Release notes come from the Unreleased section of [`CHANGELOG.md`](CHANGELOG.md). The showcase remains a separate hand upload (D-074).

For each release, update the semantic version in `build.zig.zon` and `build.zig`, run `zig build version-check` and the full release checks in [`TESTING.md`](TESTING.md), then move the Unreleased entries under a dated version heading. Tag the release commit as `v<version>` and publish that changelog section as the GitHub Release notes.

When advancing the starter project's CI pin, select a published tag and verify a generated project against that tag. Update the workflow template and its generation test together (P39-03, D-110).

## Compatibility and Migrations

Follow the versioning and reader guarantees in [COMPATIBILITY.md](COMPATIBILITY.md) for bytecode packages and saves.

### Deprecation policy

This policy applies to documented [script syntax](script_spec.md) and the [supported Zig host API](API.md) (P38-04, D-108).

1. **Ship a warning release.** Keep the old spelling or signature working with its existing behavior and ship its replacement when one exists. The warning names the deprecated item, the migration or replacement, and the earliest removal release. Report deprecated script syntax with a source location when checking or compiling source. For Zig declarations, mark the declaration in the API reference and its source documentation. Announce both kinds in the changelog so the warning reaches users through the release notes.
2. **Remove in a later breaking release.** At least one tagged, non-prerelease warning release must ship first. Before 1.0, removal can ship in the next minor release or at 1.0. From 1.0 onward, removal waits for the next major release. Patch releases preserve deprecated names. Update the reference and the changelog with the migration. For removed script syntax, give a located error with migration guidance where the old spelling can still be recognized unambiguously.

When introducing a deprecation, test that the old and replacement forms retain the intended behavior and that a script warning appears without failing compilation. When removing one, test the replacement and the removal diagnostic when applicable. A source retirement leaves the file reader's supported range and serialized meanings subject to [D-106](COMPATIBILITY.md).

## Reporting Security Issues

Do not open a public issue for a suspected vulnerability. Follow [SECURITY.md](SECURITY.md).
