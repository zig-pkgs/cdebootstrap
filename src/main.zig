const std = @import("std");
const c = @import("c");
const posix = std.posix;

pub fn main() !void {
    setupSigHanlders();

    const argv = std.os.argv;
    if (c.frontend_main(@intCast(argv.len), @ptrCast(argv.ptr), null) != 0) {
        c.log_text(c.DI_LOG_LEVEL_ERROR, "Internal error: frontend died");
    }
}

fn setupSigHanlders() void {
    posix.sigaction(posix.SIG.HUP, &.{
        .flags = posix.SA.RESTART,
        .mask = posix.sigemptyset(),
        .handler = .{ .handler = cleanupSignal },
    }, null);
    posix.sigaction(posix.SIG.INT, &.{
        .flags = posix.SA.RESTART,
        .mask = posix.sigemptyset(),
        .handler = .{ .handler = cleanupSignal },
    }, null);
    posix.sigaction(posix.SIG.PIPE, &.{
        .flags = posix.SA.RESTART,
        .mask = posix.sigemptyset(),
        .handler = .{ .handler = posix.SIG.IGN },
    }, null);
    posix.sigaction(posix.SIG.TERM, &.{
        .flags = posix.SA.RESTART,
        .mask = posix.sigemptyset(),
        .handler = .{ .handler = cleanupSignal },
    }, null);
}

fn cleanupSignal(signum: i32) callconv(.c) void {
    c.log_text(c.DI_LOG_LEVEL_CRITICAL, "Got signal: %d, cleaning up", signum);
    posix.exit(c.EXIT_FAILURE);
}
