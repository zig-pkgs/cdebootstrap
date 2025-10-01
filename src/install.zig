const std = @import("std");
const mem = std.mem;
const c = @import("c");
const posix_ext = @import("posix_ext.zig");

const Target = enum {
    proc,
};

export fn install_mount(what: ?[*:0]const u8) c_int {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    if (std.meta.stringToEnum(Target, mem.span(what.?))) |target| {
        const full_path = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ c.target_root, @tagName(target) }) catch return -1;
        switch (target) {
            .proc => {
                posix_ext.mountZ("proc", full_path.ptr, "proc", 0, 0) catch |err| {
                    c.log_text(c.DI_LOG_LEVEL_ERROR, "Failed to mount /%s: %s", what, @errorName(err).ptr);
                    return -1;
                };
                return 0;
            },
        }
    } else {
        c.log_text(c.DI_LOG_LEVEL_WARNING, "Unknown target for mount action: %s", what);
        return -1;
    }
}
