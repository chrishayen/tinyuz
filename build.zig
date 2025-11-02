const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a module for the library (for use as dependency)
    _ = b.addModule("tinyuz", .{
        .root_source_file = b.path("tinyuz.zig"),
    });

    // Example executable
    const example_module = b.createModule(.{
        .root_source_file = b.path("example.zig"),
        .target = target,
        .optimize = optimize,
    });
    const example = b.addExecutable(.{
        .name = "example",
        .root_module = example_module,
    });
    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_example.step);

    // Test suite
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const tinyuz_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tinyuz.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const utilities_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("utilities.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const run_tinyuz_tests = b.addRunArtifact(tinyuz_tests);
    const run_utilities_tests = b.addRunArtifact(utilities_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_tinyuz_tests.step);
    test_step.dependOn(&run_utilities_tests.step);
}
