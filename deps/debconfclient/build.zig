const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "debconfclient",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    lib.addCSourceFile(.{
        .file = b.path("src/debconfclient.c"),
    });
    lib.installHeader(b.path("src/debconfclient.h"), "cdebconf/debconfclient.h");
    b.installArtifact(lib);
}
