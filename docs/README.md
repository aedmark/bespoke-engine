# Documentation Map

This directory stores durable project knowledge for the BeSpoke Engine. Each fact has one authoritative home; other documents link to it instead of copying it.

## Audiences and Ownership

| Document | Primary audience | Owns | Does not own |
| --- | --- | --- | --- |
| [`../README.md`](../README.md) | Users and newcomers | Purpose, vision, and quick entry points | Internal workflow or session state |
| [`../AGENTS.md`](../AGENTS.md) | Coding agents and maintainers | Standing working rules and repository conventions | Feature history or design rationale |
| [`../ROADMAP.md`](../ROADMAP.md) | Maintainers and contributors | Planned scope and status | Detailed implementation notes |
| [`HANDOFF.md`](HANDOFF.md) | The next work session | Current state, active context, immediate next steps | Permanent design rules |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Developers | System shape, interfaces, invariants, data flow | Chronological history |
| [`DECISIONS.md`](DECISIONS.md) | Future decision-makers | Rationale and alternatives for durable choices, plus held tensions | Routine implementation detail |
| [`TESTING.md`](TESTING.md) | Contributors and release owners | Verification commands, coverage boundaries, known pitfalls | A duplicate of current test results |
| [`SECURITY.md`](SECURITY.md) | Users and developers | Sensitive assets, trust boundaries, reporting, secure defaults | Full operational incident history |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Contributors | Setup, change, review, and submission workflow | Agent-only instructions |
| [`CHANGELOG.md`](CHANGELOG.md) | Users | Released and unreleased user-visible changes | Commit-by-commit history |
| [`SEPARATION.md`](SEPARATION.md) | Developers and auditors | Engine / proof separation rule, classification rubric, audit and extraction method, checks, baseline inventory | Decision rationale (DECISIONS) or task status (ROADMAP) |
| [`manual.html`](manual.html) | Developers and agents | Standalone 3x interactive manual & developer guide (What, How, Why) | Raw Markdown sources |

## Update Triggers

Update documents because a relevant fact changed, not merely because a session ended.

| Change | Required documentation |
| --- | --- |
| User-visible behaviour | README if onboarding changed; CHANGELOG |
| Component, interface, dependency, or data-flow change | ARCHITECTURE |
| Durable tradeoff or reversal, or a tension held or resolved | DECISIONS; mark the old decision superseded, or resolve the held tension |
| Test command, coverage, fixture, or environment change | TESTING |
| Secret, trust boundary, sensitive data, or reporting-path change | SECURITY |
| Work pauses with context another session needs | HANDOFF |
| Contribution or release workflow change | CONTRIBUTING and, if agents are affected, AGENTS |
| New planned work | ROADMAP, with origin and acceptance evidence |

## Optional Documents

Create these only when the project needs them, and add them to the tables above:

- `docs/api/` for stable public interfaces, preferably generated from executable schemas where practical.
- `docs/runbooks/` for repeatable operational procedures, each with prerequisites, rollback, and verification.
- `docs/data/` for schemas, retention, migrations, and compatibility guarantees.
- `docs/incidents/` for sanitized incident reviews and follow-up actions.
- `docs/GLOSSARY.md` when domain vocabulary outgrows the table in `AGENTS.md`.
- `SUPPORT.md`, `CODE_OF_CONDUCT.md`, or licensing/contributor policy for public projects.

## Style and Evidence

- Lead with the reader's task or the current truth.
- Use exact commands and repository-relative paths; avoid screenshots for procedures when text will remain searchable.
- Label examples as examples. Do not make sample credentials, hosts, or IDs look real.
- Date volatile observations and identify the environment or commit when it affects reproducibility.
- Link to the source of truth instead of restating it. If duplication is necessary, identify which copy is canonical.
- Keep secrets, personal information, private URLs, and raw production data out of documentation and fixtures.
