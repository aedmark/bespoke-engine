# Input fuzzing corpus

`zig build test-fuzz --test-timeout 10s` starts from the valid text inputs here and the released binary inputs in [compat](../compat/). Each harness verifies its seeds before mutating them with a fixed PRNG seed. Every input gets fresh engine state.

Keep minimized inputs that exposed a crash in a regression test that asserts the corrected behavior. The incomplete quoted string regression lives in `src/compiler.zig`.

The `image-*.bspk` files are the version 24 package fixture with one art field broken each (P46-01): a palette of 300 colours, a million images, a control byte in a name, a frame that does not tile its sheet, a sheet past the side limit, and a pixel index past the palette. The loader must refuse each with the error its test names before mutation starts from it. `src/package.zig` checks that each file is still the fixture with its one break.
