const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
/// Stack for the wasm modules; see the note at `wasm_exe.stack_size`.
const WASM_STACK_BYTES: u64 = 8 * 1024 * 1024;

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "bespoke",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "bespoke",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the engine CLI (bespoke run/compile/check)");
    run_step.dependOn(&run_cmd.step);

    // --- Proofs of concept (D-031) ---
    // The engine is exported as the `bespoke` module. Proofs import it by name and live outside
    // src/, so the compiler rejects any attempt by engine code to import a proof: the boundary is
    // enforced by module paths, not by convention.
    const bespoke_mod = b.addModule("bespoke", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    bespoke_mod.linkSystemLibrary("SDL2", .{});

    const proofs_exe = b.addExecutable(.{
        .name = "bespoke-proofs",
        .root_source_file = b.path("proofs/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    proofs_exe.root_module.addImport("bespoke", bespoke_mod);
    proofs_exe.linkLibC();
    proofs_exe.linkSystemLibrary("SDL2");

    const install_proofs = b.addInstallArtifact(proofs_exe, .{});
    const proofs_step = b.step("proofs", "Build the proofs-of-concept binary (bespoke-proofs)");
    proofs_step.dependOn(&install_proofs.step);

    const run_proof_cmd = b.addRunArtifact(proofs_exe);
    run_proof_cmd.step.dependOn(&install_proofs.step);
    if (b.args) |args| {
        run_proof_cmd.addArgs(args);
    }
    const run_proof_step = b.step("run-proof", "Run a proof of concept, e.g. `zig build run-proof -- --loom --headless`");
    run_proof_step.dependOn(&run_proof_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.linkLibC();
    lib_unit_tests.linkSystemLibrary("SDL2");

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.linkLibC();
    exe_unit_tests.linkSystemLibrary("SDL2");

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const proofs_unit_tests = b.addTest(.{
        .root_source_file = b.path("proofs/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    proofs_unit_tests.root_module.addImport("bespoke", bespoke_mod);

    // Characterization goldens (P32-07): proofs/golden_test.zig compares each proof's headless
    // transcript with proofs/golden/<proof>.txt. `-Dupdate-goldens` rewrites them deliberately.
    const golden_opts = b.addOptions();
    golden_opts.addOption(bool, "update_goldens", b.option(bool, "update-goldens", "Rewrite proofs/golden/*.txt from current proof output (P32-07)") orelse false);
    golden_opts.addOption([]const u8, "golden_dir", b.pathFromRoot("proofs/golden"));
    proofs_unit_tests.root_module.addOptions("golden_options", golden_opts);
    proofs_unit_tests.linkLibC();
    proofs_unit_tests.linkSystemLibrary("SDL2");
    const run_proofs_unit_tests = b.addRunArtifact(proofs_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run engine and proof tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_proofs_unit_tests.step);

    const test_engine_step = b.step("test-engine", "Run engine tests only (src/)");
    test_engine_step.dependOn(&run_lib_unit_tests.step);
    test_engine_step.dependOn(&run_exe_unit_tests.step);

    const test_proofs_step = b.step("test-proofs", "Run proof-of-concept tests only (proofs/)");
    test_proofs_step.dependOn(&run_proofs_unit_tests.step);

    // Phase 19 (P19-01): Zero-dependency WebAssembly (wasm32-freestanding) target
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_exe = b.addExecutable(.{
        .name = "bespoke",
        .root_source_file = b.path("src/wasm_engine.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;
    // The runtime is about 1.2 MB and `WasmRuntime.init` returns it by value, so the default
    // 1 MB wasm stack overflows on the first `wasm_init` (found in P32-04, D-042).
    wasm_exe.stack_size = WASM_STACK_BYTES;

    const install_wasm = b.addInstallArtifact(wasm_exe, .{});
    const wasm_step = b.step("wasm", "Build the engine's WebAssembly module with its neutral demo deck");
    wasm_step.dependOn(&install_wasm.step);

    // P32-04 (D-042): the proofs' decks in their own module, against the engine built for wasm.
    // No SDL here: the wasm build references none of the display code.
    const wasm_bespoke = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    const wasm_proofs_exe = b.addExecutable(.{
        .name = "bespoke-proofs",
        .root_source_file = b.path("proofs/wasm_main.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    wasm_proofs_exe.root_module.addImport("bespoke", wasm_bespoke);
    wasm_proofs_exe.entry = .disabled;
    wasm_proofs_exe.rdynamic = true;
    wasm_proofs_exe.stack_size = WASM_STACK_BYTES;
    const install_wasm_proofs = b.addInstallArtifact(wasm_proofs_exe, .{});
    const wasm_proofs_step = b.step("wasm-proofs", "Build the proofs' WebAssembly module (bespoke-proofs.wasm)");
    wasm_proofs_step.dependOn(&install_wasm_proofs.step);
}
