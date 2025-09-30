const std = @import("std");

/// Represents the contents of config/suites.zon
/// It is a slice of Suite structs.
pub const Suites = []const Suite;

pub const Origin = enum {
    undefined,
    debian,
    kali,
    ubuntu,
};

pub const Suite = struct {
    match_origin: ?Origin = null,
    set_origin: ?Origin = null,
    match_codename: ?[:0]const u8 = null,
    set_codename: ?[:0]const u8 = null,
    config: ?[:0]const u8 = null,
    mirror: ?[:0]const u8 = null,
    keyring: ?[:0]const u8 = null,
};
/// Represents the contents of config/generic.zon
pub const GenericConfig = struct {
    sections: Sections,
    actions: []const Action,

    pub const Sections = struct {
        base: Section,
        build: Section,
        standard: Section,
    };

    pub const Flavour = enum {
        build,
        minimal,
        standard,
    };

    pub const Section = struct {
        flavour: []const Flavour,
        packages: []const Package,
    };

    pub const Package = struct {
        names: []const [:0]const u8,
        flags: ?[]const PackageFlag = null,
        arch: ?[]const [:0]const u8 = null,
    };

    pub const PackageFlag = enum(u8) {
        essential = 1,
    };

    pub const Action = struct {
        action: ActionType,
        what: ?[:0]const u8 = null,
        comment: ?[:0]const u8 = null,
        flags: ?[]const ActionFlag = null,
        flavour: ?[]const Flavour = null,
    };

    pub const ActionType = enum {
        @"essential-configure",
        @"essential-extract",
        @"essential-install",
        @"essential-unpack",
        @"helper-install",
        @"helper-remove",
        install,
        mount,
    };

    pub const ActionFlag = enum(u8) {
        force = 1,
        only,
    };
};
