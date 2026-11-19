# Compatibility Fixtures

These binary files are immutable test inputs for P38-02 and D-106.

- `v0.1.0-package-v14.bspk` is a package-format version 14 script with `FixtureHero`, the `Ready` relation, and the `Idle` routine. Written by BeSpoke Engine 0.1.0 on 2026-11-17.
- `v0.1.0-save-v2.sav` is a save-format version 2 world with `FixtureHero`, a `Ready` fact, and the description `P38-02 compatibility fixture`. It has no temporal branch payload. Written by BeSpoke Engine 0.1.0 on 2026-11-17.
- `v0.2.0-package-v15.bspk` is a package-format version 15 script with `FixtureHero`, the `Ready` relation, the `Idle` routine, and the `FinishShift` goal with its single need `Sit` (P44-01, D-134). Written by BeSpoke Engine 0.2.0 on 2026-11-19.

Do not regenerate these files when a writer changes. Add new fixtures with the release and format versions in their filenames, then keep loading every version the compatibility policy still supports.
