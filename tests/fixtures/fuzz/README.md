# Input fuzzing corpus

`zig build test-fuzz --test-timeout 10s` starts from the valid text inputs here and the released binary inputs in [compat](../compat/). Each harness verifies its seeds before mutating them with a fixed PRNG seed. Every input gets fresh engine state.

Keep minimized inputs that exposed a crash in a regression test that asserts the corrected behavior. The incomplete quoted string regression lives in `src/compiler.zig`.
