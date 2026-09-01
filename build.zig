const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const rill_dep = b.dependency("rill", .{ .target = target, .optimize = optimize });
    const common_dep = b.dependency("common", .{ .target = target, .optimize = optimize });
    const struple_dep = b.dependency("struple", .{ .target = target, .optimize = optimize });
    const rill_mod = rill_dep.module("rill");
    const common_mod = common_dep.module("common");
    const struple_mod = struple_dep.module("struple");

    // The public library module — depend on this as `spindrift`.
    const mod = b.addModule("spindrift", .{
        .root_source_file = b.path("src/spindrift.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("rill", rill_mod);
    mod.addImport("common", common_mod);
    mod.addImport("struple", struple_mod);
    // The words manual rides into the test build so the parity gate can
    // @embedFile it: every registered word is named in it, both ways —
    // rill's precedent, and for rill's reason (a manual nothing executes
    // drifts until it contradicts a gate you already have).
    mod.addAnonymousImport("drift-words.md", .{ .root_source_file = b.path("docs/drift-words.md") });
    // The first kernel, embedded: drift-run mounts it when no --kernel is
    // given, and the gates mount it so the shipped text is the tested text.
    mod.addAnonymousImport("embers.rill", .{ .root_source_file = b.path("kernels/embers.rill") });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "spindrift",
        .root_module = mod,
    });
    b.installArtifact(lib);

    // drift-run: mount an emitter on rill's mock plane over the mock floor
    // World, feed it fixed ticks, and dump the population. rill-run's shape
    // (seeds, ticks, a fixed dt), with a population instead of a slot table.
    // It lives here and not in rill because rill does not depend on spindrift.
    const run_mod = b.createModule(.{
        .root_source_file = b.path("src/run.zig"),
        .target = target,
        .optimize = optimize,
    });
    run_mod.addImport("spindrift", mod);
    run_mod.addImport("rill", rill_mod);
    run_mod.addImport("struple", struple_mod);
    run_mod.addImport("common", common_mod);
    run_mod.addAnonymousImport("embers.rill", .{ .root_source_file = b.path("kernels/embers.rill") });
    const runner = b.addExecutable(.{ .name = "drift-run", .root_module = run_mod });
    b.installArtifact(runner);
    const runner_cmd = b.addRunArtifact(runner);
    runner_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| runner_cmd.addArgs(args);
    b.step("run", "Run drift-run: zig build run -- [opts]").dependOn(&runner_cmd.step);

    // row-legal: walk rill's registry and print which operators pass the
    // row-legality test as it stands (recon R-a). An executed list, not a
    // prose one — the registry is the source and this derives from it.
    const rl_mod = b.createModule(.{
        .root_source_file = b.path("tools/row_legal.zig"),
        .target = target,
        .optimize = optimize,
    });
    rl_mod.addImport("rill", rill_mod);
    const rl = b.addExecutable(.{ .name = "row-legal", .root_module = rl_mod });
    const rl_cmd = b.addRunArtifact(rl);
    b.step("row-legal", "Walk rill's registry and list row-legal operators").dependOn(&rl_cmd.step);

    // verify-dump: the cross-language half of the dump gate. drift-run
    // writes a population, and the struple PYTHON port reads it back with no
    // spindrift code on that side — a format only Zig can read has one
    // witness, and one witness is prose.
    const vd_run = b.addRunArtifact(runner);
    vd_run.addArgs(&.{ "--rate", "40", "--speed", "3", "--spread", "1", "--gravity", "-9.8", "--life", "800", "--fixed-dt", "50", "--ticks", "30", "--every", "0", "--dump" });
    const vd_dump = vd_run.addOutputFileArg("verify.struple");
    const vd_read = b.addSystemCommand(&.{ "python3", "tools/read_dump.py" });
    vd_read.addFileArg(vd_dump);
    vd_read.step.dependOn(&vd_run.step);
    b.step("verify-dump", "Dump a population with drift-run and read it back from Python").dependOn(&vd_read.step);

    // Tests: src/spindrift.zig pulls in the gates from src/tests.zig.
    // `-Dtest-filter=<substring>` runs only matching tests — the cheap loop
    // while iterating; the full set before a commit.
    const tests = b.addTest(.{ .root_module = mod });
    if (b.option([]const u8, "test-filter", "Only run tests whose name contains this")) |f| {
        tests.filters = b.allocator.dupe([]const u8, &.{f}) catch @panic("OOM");
    }
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the gates");
    test_step.dependOn(&run_tests.step);
    // The runner's own module too: its argument grammar is code that only
    // running it would otherwise exercise.
    const run_tests_exe = b.addTest(.{ .root_module = run_mod });
    test_step.dependOn(&b.addRunArtifact(run_tests_exe).step);
}
