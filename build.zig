const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
        .openssl = false,
    });

    const exe = b.addExecutable(.{
        .name = "website",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zap", zap.module("zap"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const coverage_dir_path = "coverage/";

    std.fs.cwd().makeDir(coverage_dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const current_time = std.time.milliTimestamp();
    const url_prefix = "file://";

    var output_location_buf = (try b.allocator.alloc(u8, 1024)).ptr[0..1024];
    @memcpy(output_location_buf[0..url_prefix.len], url_prefix);
    const current_dir_path = try std.fs.cwd().realpath(".", output_location_buf[url_prefix.len..]);
    output_location_buf[url_prefix.len + current_dir_path.len] = '/';
    const output_location = try std.fmt.bufPrint(
        output_location_buf[url_prefix.len + 1 + current_dir_path.len ..],
        coverage_dir_path ++ "kcov-{d}/index.html",
        .{current_time},
    );
    const output_dir = output_location[0 .. output_location.len - "/index.html".len];
    const output_url = output_location_buf[0 .. url_prefix.len + 1 + current_dir_path.len + output_location.len];

    // For some reason, using b.addTest adds "--listen=-" to the end of the command,
    // which causes it to not work for some reason. This fixes it
    const run_tests_with_coverage = b.addSystemCommand(&[_][]const u8{
        "zig",
        "test",
        "-ODebug",
        "-Mroot=src/main.zig",
        "--cache-dir",
        ".zig-cache",
        "--name",
        "test",
        "--test-cmd",
        "kcov",
        "--test-cmd",
        "--include-path=src",
        "--test-cmd",
        output_dir,
        "--test-cmd-bin",
    });

    const test_with_coverage = PrintOutputLocation.create(b, output_url);
    test_with_coverage.step.dependOn(&run_tests_with_coverage.step);

    const coverage_step = b.step("coverage", "Run unit tests and generate a coverage report");
    coverage_step.dependOn(&test_with_coverage.step);

    const run_with_perf = b.addSystemCommand(&.{ "perf", "record", "-g", "zig-out/bin/website" });
    run_with_perf.step.dependOn(b.getInstallStep());

    const perf_step = b.step(
        "perf",
        "Runs the webserver with `perf`. Follow with `perf report` to view the results",
    );
    perf_step.dependOn(&run_with_perf.step);

    const run_with_perf_stat = b.addSystemCommand(&.{ "perf", "stat", "zig-out/bin/website" });
    run_with_perf_stat.step.dependOn(b.getInstallStep());

    const perf_stat_step = b.step(
        "stat",
        "Runs the webserver with `perf stat` which gives immedate but less information than `zig build perf`",
    );
    perf_stat_step.dependOn(&run_with_perf_stat.step);
}

const PrintOutputLocation = struct {
    step: std.Build.Step,
    output_url: []const u8,

    pub fn create(b: *std.Build, output_url: []const u8) *PrintOutputLocation {
        const print = b.allocator.create(PrintOutputLocation) catch unreachable;
        print.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "print the given output url",
                .owner = b,
                .makeFn = make,
            }),
            .output_url = output_url,
        };
        return print;
    }

    fn make(step: *std.Build.Step, prog_node: std.Progress.Node) !void {
        _ = prog_node;

        const print: *PrintOutputLocation = @fieldParentPtr("step", step);

        try std.io.getStdOut().writer().print(
            "Test coverage can be viewed at: {s}\n",
            .{print.output_url},
        );
    }
};
