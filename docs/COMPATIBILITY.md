# File Compatibility

BeSpoke Engine reads released `.bspk` packages and `.sav` saves according to their file-format versions. These versions are independent of the engine's semantic release version.

## Current formats

| File | Writer emits | Reader accepts | Unsupported error |
| --- | ---: | ---: | --- |
| `.bspk` package | 20 | 1 through 20 | Names the file's version and the supported range |
| `.sav` save | 1 without a temporal branch; 2 with one | 1 through 2 | Names the file's version and the supported range |

Package version 16 adds the count and points condition opcodes (P44-02); versions 1 through 15 hold bytecode that cannot contain them and load unchanged. Package version 17 appends spellbooks with their words and combinations (P44-04); versions 1 through 16 load with no spellbook. Package version 18 appends decisions with their trigger lines and scored options (P44-05); versions 1 through 17 load with no decisions. Package version 19 appends value axes with their poles (P45-01); versions 1 through 18 load with no axes. Package version 20 appends each character's red lines (P45-02); versions 1 through 19 load with none. The package writer emits only the current format. Save format 1 remains the active plain-world profile; format 2 adds the optional temporal envelope and is emitted by the temporal writer. A reader in the 1.x release line keeps support for every format version that an earlier 1.x release could read. Format version numbers are never reused.

## Changing a format

An additive, defaultable change increments the affected file-format version. Its reader defines the old-file default and continues to accept every earlier supported version. Package and save versions advance separately.

A change that cannot interpret old bytes without ambiguity does not reuse the existing magic or version. It requires a new format generation, an explicit migration path, and a semantic major release unless the old reader remains available beside it.

Removing or renaming a script-language or supported host API name follows the [deprecation policy](CONTRIBUTING.md#deprecation-policy) (P38-04, D-108). Retiring source syntax leaves existing package and save reader guarantees in force. A language change that alters serialized package meaning must also follow this file policy.

## Failures

Readers reject versions outside the supported range before allocating for or mutating decoded state. The programmatic result remains `UnsupportedPackageVersion` or `UnsupportedSaveVersion`; user-facing diagnostics state the found version and the complete supported range.

A file whose version is supported but whose magic, checksum, bounds, or payload is invalid is corrupt, not incompatible, and retains its specific validation error.

Save format version 1 has no temporal envelope. Plain save restore accepts versions 1 and 2. A temporal restore requires the version 2 temporal payload; `MissingTemporalState` is a capability mismatch, not an unsupported-format error.

## Compatibility fixtures

Released bytes live in `tests/fixtures/compat/`. Tests embed and load them without rewriting them. When either writer advances, add a fixture named with the engine release and format version; do not replace prior fixtures while their versions remain supported.

Decision D-106 owns the policy and rationale. `src/package.zig` and `src/save.zig` own the executable version ranges.
