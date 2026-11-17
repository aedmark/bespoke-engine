# Compatibility Fixtures

These binary files were written by BeSpoke Engine 0.1.0 on 2026-11-17 and are immutable test inputs for P38-02 and D-106.

- `v0.1.0-package-v14.bspk` is a package-format version 14 script with `FixtureHero`, the `Ready` relation, and the `Idle` routine.
- `v0.1.0-save-v2.sav` is a save-format version 2 world with `FixtureHero`, a `Ready` fact, and the description `P38-02 compatibility fixture`. It has no temporal branch payload.

Do not regenerate these files when a writer changes. Add new fixtures with the release and format versions in their filenames, then keep loading every version the compatibility policy still supports.
