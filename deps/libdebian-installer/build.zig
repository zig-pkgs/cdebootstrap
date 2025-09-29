const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const config_h = b.addConfigHeader(.{
        .style = .{
            .autoconf_undef = b.path("include/debian-installer/config.h.in"),
        },
        .include_path = "config.h",
    }, .{
        .LIBDI_VERSION = "0.125",
        .LIBDI_VERSION_MAJOR = 0,
        .LIBDI_VERSION_MINOR = 125,
        .LIBDI_VERSION_REVISION = 0,
    });

    const lib = b.addLibrary(.{
        .name = "debian-installer",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    lib.addConfigHeader(config_h);
    lib.addCSourceFiles(.{
        .root = b.path("src/system"),
        .files = &system_sources,
    });
    lib.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &debian_installer_sources,
    });
    lib.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &debian_installer_extra_sources,
    });
    lib.addIncludePath(b.path("include"));
    lib.installHeader(config_h.getOutput(), "debian-installer/config.h");
    lib.installHeadersDirectory(b.path("include"), "", .{});
    b.installArtifact(lib);
}

const system_sources = [_][]const u8{
    "devfs.c",
    "dpkg.c",
    "efi.c",
    "packages.c",
    "prebaseconfig.c",
    "utils.c",
    "subarch-generic.c",
    "subarch-arm-linux.c",
    "subarch-arm64-linux.c",
    "subarch-armeb-linux.c",
    "subarch-armel-linux.c",
    "subarch-armhf-linux.c",
    "subarch-loong64-linux.c",
    "subarch-m68k-linux.c",
    "subarch-mips-linux.c",
    "subarch-mipsel-linux.c",
    "subarch-mips64el-linux.c",
    "subarch-powerpc-linux.c",
    "subarch-ppc64-linux.c",
    "subarch-ppc64el-linux.c",
    "subarch-riscv64-linux.c",
    "subarch-sh4-linux.c",
    "subarch-sparc-linux.c",
    "subarch-sparc64-linux.c",
    "subarch-x86-linux.c",
    "subarch-x86-kfreebsd.c",
};

const debian_installer_sources = [_][]const u8{
    "exec.c",
    "hash.c",
    "log.c",
    "mem.c",
    "mem_chunk.c",
    "package.c",
    "package_parser.c",
    "packages.c",
    "packages_parser.c",
    "parser.c",
    "parser_rfc822.c",
    "slist.c",
    "string.c",
    "tree.c",
    "utils.c",
};

const debian_installer_extra_sources = [_][]const u8{
    "list.c",
    "release.c",
};
