# Suite Configuration

The suite configuration is defined in ZON (Zig Object Notation) files. The configuration is split into two files: `suites.zon` and `generic.zon`.

## `suites.zon`

This file defines properties for different distribution suites. It is a list of suite configuration entries.

Each suite entry has the following fields:

- `match_origin`: (Optional) The origin to match. Must be one of the `Origin` enum values.
- `set_origin`: (Optional) The origin to set. Must be one of the `Origin` enum values.
- `match_codename`: (Optional) A string to match the codename.
- `set_codename`: (Optional) A string to set the codename.
- `config`: (Optional) A string specifying a config to use.
- `mirror`: (Optional) The mirror URL for the suite.
- `keyring`: (Optional) The keyring file for the suite.

The `Origin` enum has the following possible values: `.undefined`, `.debian`, `.kali`, `.ubuntu`.

Example:

```zon
.{
    .{
        .match_origin = .undefined,
        .set_origin = .debian,
    },
    .{
        .match_origin = .debian,
        .mirror = "http://deb.debian.org/debian",
        .keyring = "debian-archive-keyring.gpg",
    },
    .{
        .match_origin = .kali,
        .mirror = "http://http.kali.org",
        .keyring = "kali-archive-keyring.gpg",
    },
    .{
        .match_origin = .ubuntu,
        .mirror = "http://archive.ubuntu.com/ubuntu",
        .keyring = "ubuntu-archive-keyring.gpg",
    },
}
```

## `generic.zon`

This file defines sections, packages, and actions.

### Sections

Sections are defined under the `.sections` field. Each field in this struct is a section name (e.g., `.base`, `.build`, `.standard`).

Each section has the following fields:

- `flavour`: A list of `Flavour` enum values where this section is applied.
- `packages`: A list of packages to install for this section.

The `Flavour` enum has the following possible values: `.build`, `.minimal`, `.standard`.

### Packages

Packages are defined within a section's `packages` list.

- `names`: A list of package names to install.
- `flags`: (Optional) A list of `PackageFlag` enum values.
- `arch`: (Optional) A list of architectures this applies to.

The `PackageFlag` enum has one value: `.essential`.

### Actions

Actions are defined as a list under the `.actions` field.

- `action`: The `ActionType` enum value for the action to perform.
- `what`: (Optional) The target of the action (e.g., a package name).
- `flags`: (Optional) A list of `ActionFlag` enum values.
- `flavour`: (Optional) A list of `Flavour` enum values for which the action is run.

The `ActionType` enum values are: `.@"essential-configure"`, `.@"essential-extract"`, `.@"essential-install"`, `.@"essential-unpack"`, `.@"helper-install"`, `.@"helper-remove"`, `.install`, `.mount`.

The `ActionFlag` enum values are: `.force`, `.only`.

Example:

```zon
.{
    .sections = .{
        .base = .{
            .flavour = .{ .build, .minimal, .standard },
            .packages = .{
                .{ .names = .{"apt"}, .flags = .{ .essential } },
            },
        },
    },
    .actions = .{
        .{ .action = .@"essential-extract" },
        .{ .action = .mount, .what = "proc" },
        .{ .action = .@"essential-install", .what = "dpkg", .flags = .{ .force, .only } },
    },
}
```
