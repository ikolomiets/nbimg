const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const install_optimize: std.builtin.OptimizeMode = .ReleaseSafe;
    const execution_optimize: std.builtin.OptimizeMode = .Debug;
    const live_api_tests = b.option(
        bool,
        "live-api-tests",
        "Enable live Gemini API tests; use with -Dtest-filter to run one target API check",
    ) orelse false;
    const test_filter = b.option(
        []const u8,
        "test-filter",
        "Only run tests matching this filter",
    );
    if (live_api_tests and test_filter == null) {
        @panic("-Dlive-api-tests requires -Dtest-filter; use a dedicated live API test step for known checks");
    }
    const test_filters: []const []const u8 = if (test_filter) |filter| b.dupeStrings(&.{filter}) else &.{};

    const install_exe = addNbimgExecutable(b, target, install_optimize);
    b.installArtifact(install_exe);

    const run_exe = addNbimgExecutable(b, target, execution_optimize);

    const run_step = b.step("run", "Run nbimg");
    const run_cmd = b.addRunArtifact(run_exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");
    addTestRoot(b, test_step, target, execution_optimize, live_api_tests, test_filters, "api", "src/api.zig");
    addTestRoot(b, test_step, target, execution_optimize, live_api_tests, test_filters, "batch", "src/batch.zig");
    addTestRoot(b, test_step, target, execution_optimize, live_api_tests, test_filters, "gen", "src/gen.zig");
    addTestRoot(b, test_step, target, execution_optimize, live_api_tests, test_filters, "edit", "src/edit.zig");
    addTestRoot(b, test_step, target, execution_optimize, live_api_tests, test_filters, "files", "src/files.zig");
    addTestRoot(b, test_step, target, execution_optimize, live_api_tests, test_filters, "cli", "src/cli.zig");
    addTestRoot(b, test_step, target, execution_optimize, live_api_tests, test_filters, "package-api", "src/public_api_test.zig");
    addTestRoot(b, test_step, target, execution_optimize, live_api_tests, test_filters, "internal-module-api", "src/internal_module_api_test.zig");

    addLiveApiTestStep(
        b,
        target,
        execution_optimize,
        "test-live-api-batch-list",
        "List recent Gemini Batch jobs without content generation",
        "src/batch.zig",
        "live API batch list succeeds",
    );
    addLiveApiTestStep(
        b,
        target,
        execution_optimize,
        "test-live-api-batch-submit-status",
        "BILLABLE and non-idempotent: submit, inspect, and cancel one Gemini Batch job",
        "src/batch.zig",
        "live API batch submit status and cancel succeeds",
    );
    addLiveApiTestStep(
        b,
        target,
        execution_optimize,
        "test-live-api-generate-content-request-validity",
        "Validate the generateContent request shape via Gemini countTokens",
        "src/gen.zig",
        "live API generateContent request shape is valid",
    );
    addLiveApiTestStep(
        b,
        target,
        execution_optimize,
        "test-live-api-edit-request-validity",
        "Validate the edit generateContent request shape via Gemini countTokens",
        "src/cli.zig",
        "live API edit request shape is valid",
    );
    addLiveApiTestStep(
        b,
        target,
        execution_optimize,
        "test-live-api-files-upload-list",
        "Run live Gemini Files API upload/list test",
        "src/files.zig",
        "live API files upload is visible in file list",
    );
    addLiveApiTestStep(
        b,
        target,
        execution_optimize,
        "test-live-api-files-get",
        "Run live Gemini Files API get test",
        "src/files.zig",
        "live API files get returns uploaded file metadata",
    );
    addLiveApiTestStep(
        b,
        target,
        execution_optimize,
        "test-live-api-files-delete",
        "Run live Gemini Files API delete test",
        "src/files.zig",
        "live API files delete removes uploaded file and reports missing files",
    );
}

fn addNbimgExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const nbimg = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    addBuildOptions(b, nbimg, false);

    return b.addExecutable(.{
        .name = "nbimg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nbimg", .module = nbimg },
            },
        }),
    });
}

fn testModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    live_api_tests: bool,
    root_source_file: []const u8,
) *std.Build.Module {
    const options = b.addOptions();
    options.addOption(bool, "live_api_tests", live_api_tests);

    const module = b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .target = target,
        .optimize = optimize,
    });
    module.addOptions("build_options", options);
    return module;
}

fn addBuildOptions(b: *std.Build, module: *std.Build.Module, live_api_tests: bool) void {
    const options = b.addOptions();
    options.addOption(bool, "live_api_tests", live_api_tests);
    module.addOptions("build_options", options);
}

fn addTestRoot(
    b: *std.Build,
    step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    live_api_tests: bool,
    test_filters: []const []const u8,
    name: []const u8,
    root_source_file: []const u8,
) void {
    const tests = b.addTest(.{
        .name = name,
        .root_module = testModule(b, target, optimize, live_api_tests, root_source_file),
        .filters = test_filters,
    });

    const run_tests = if (live_api_tests)
        addDirectTestRun(b, tests, b.fmt("run {s} live tests", .{name}))
    else
        b.addRunArtifact(tests);
    step.dependOn(&run_tests.step);
}

fn addLiveApiTestStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    description: []const u8,
    root_source_file: []const u8,
    test_filter: []const u8,
) void {
    const tests = b.addTest(.{
        .root_module = testModule(b, target, optimize, true, root_source_file),
        .filters = &.{test_filter},
    });

    const run_tests = addDirectTestRun(b, tests, b.fmt("run {s}", .{name}));

    const step = b.step(name, description);
    step.dependOn(&run_tests.step);
}

fn addDirectTestRun(b: *std.Build, tests: *std.Build.Step.Compile, name: []const u8) *std.Build.Step.Run {
    const run_tests = std.Build.Step.Run.create(b, name);
    run_tests.addArtifactArg(tests);
    run_tests.addPrefixedDirectoryArg("--cache-dir=", .{
        .cwd_relative = b.cache_root.path orelse ".",
    });
    run_tests.addArg(b.fmt("--seed=0x{x}", .{b.graph.random_seed}));
    run_tests.stdio = .inherit;
    run_tests.has_side_effects = true;
    return run_tests;
}
