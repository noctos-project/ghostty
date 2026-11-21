const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("highway", .{});

    const module = b.addModule("highway", .{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "highway",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    linkCxx(b, lib);
    lib.addIncludePath(upstream.path(""));
    module.addIncludePath(upstream.path(""));

    if (target.result.os.tag.isDarwin()) {
        const apple_sdk = @import("apple_sdk");
        try apple_sdk.addPaths(b, lib);
    }

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();
    try flags.appendSlice(&.{
        // Avoid changing binaries based on the current time and date.
        "-Wno-builtin-macro-redefined",
        "-D__DATE__=\"redacted\"",
        "-D__TIMESTAMP__=\"redacted\"",
        "-D__TIME__=\"redacted\"",

        // Optimizations
        "-fmerge-all-constants",

        // Warnings
        "-Wall",
        "-Wextra",

        // These are not included in Wall nor Wextra:
        "-Wconversion",
        "-Wsign-conversion",
        "-Wvla",
        "-Wnon-virtual-dtor",

        "-Wfloat-overflow-conversion",
        "-Wfloat-zero-conversion",
        "-Wfor-loop-analysis",
        "-Wgnu-redeclared-enum",
        "-Winfinite-recursion",
        "-Wself-assign",
        "-Wstring-conversion",
        "-Wtautological-overlap-compare",
        "-Wthread-safety-analysis",
        "-Wundefined-func-template",

        "-fno-cxx-exceptions",
        "-fno-slp-vectorize",
        "-fno-vectorize",
    });
    if (target.result.os.tag != .windows) {
        try flags.appendSlice(&.{
            "-fmath-errno",
            "-fno-exceptions",
        });
    }

    lib.addCSourceFiles(.{ .flags = flags.items, .files = &.{"bridge.cpp"} });
    lib.addCSourceFiles(.{
        .root = upstream.path(""),
        .flags = flags.items,
        .files = &.{
            "hwy/abort.cc",
            "hwy/aligned_allocator.cc",
            "hwy/nanobenchmark.cc",
            "hwy/per_target.cc",
            "hwy/print.cc",
            "hwy/targets.cc",
            "hwy/timer.cc",
        },
    });
    lib.installHeadersDirectory(
        upstream.path("hwy"),
        "hwy",
        .{ .include_extensions = &.{".h"} },
    );

    b.installArtifact(lib);

    {
        const test_exe = b.addTest(.{
            .name = "test",
            .root_module = b.createModule(.{
                .root_source_file = b.path("main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_exe.linkLibrary(lib);

        var it = module.import_table.iterator();
        while (it.next()) |entry| test_exe.root_module.addImport(entry.key_ptr.*, entry.value_ptr.*);
        const tests_run = b.addRunArtifact(test_exe);
        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&tests_run.step);
    }
}

/// Zig's bundled libc++ has no illumos port (no thread API, no locale
/// layer), so on illumos C++ is compiled against the system libstdc++.
/// The header directories come from ILLUMOS_CXX_INCLUDE (colon-separated),
/// defaulting to pkgsrc gcc13. They must be -I rather than -isystem so
/// libstdc++'s #include_next finds libc's headers after them.
fn linkCxx(b: *std.Build, step: *std.Build.Step.Compile) void {
    if (step.rootModuleTarget().os.tag != .illumos) {
        step.linkLibCpp();
        return;
    }
    const dirs = b.graph.env_map.get("ILLUMOS_CXX_INCLUDE") orelse
        "/opt/local/gcc13/include/c++/13.4.0:" ++
            "/opt/local/gcc13/include/c++/13.4.0/x86_64-sun-solaris2.11:" ++
            "/opt/local/gcc13/include/c++/13.4.0/backward";
    var it = std.mem.tokenizeScalar(u8, dirs, ':');
    while (it.next()) |d| step.addIncludePath(.{ .cwd_relative = d });
}
