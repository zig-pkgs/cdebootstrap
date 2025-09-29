const std = @import("std");
const c = @import("c");
const mem = std.mem;

const gpa = std.heap.c_allocator;

const Context = struct {
    limit: std.Io.Limit,
    read_buffer: [8 * 1024]u8 = undefined,
    reader: std.fs.File.Reader,
    decompress: std.compress.xz.Decompress,

    pub fn init(file: std.fs.File, limit: std.Io.Limit) !*Context {
        const context = try gpa.create(Context);
        errdefer gpa.destroy(context);
        context.reader = file.reader(&context.read_buffer);
        context.decompress = try .init(&context.reader.interface, gpa, &.{});
        context.limit = limit;

        return context;
    }

    pub fn deinit(self: *Context) void {
        gpa.destroy(self);
    }

    pub fn decompressXz(self: *Context, file_out: std.fs.File) !c_int {
        const data = try self.decompress.reader.allocRemaining(gpa, self.limit);
        defer gpa.free(data);
        try file_out.writeAll(data);
        return @intCast(data.len);
    }
};

export fn decompress_xz_new(fd: c_int, len: usize) ?*c.struct_decompress_xz {
    const ctx = Context.init(
        .{ .handle = fd },
        if (len > 0) .limited(len) else .unlimited,
    ) catch |err| {
        std.log.err("failed to init xz ctx: {t}", .{err});
        return null;
    };
    return @ptrCast(ctx);
}

export fn decompress_xz(xz_ctx: ?*c.struct_decompress_xz, fd: c_int) c_int {
    var ctx: *Context = @ptrCast(@alignCast(xz_ctx));
    const amt = ctx.decompressXz(.{ .handle = fd }) catch return -1;
    return amt;
}

export fn decompress_xz_free(xz_ctx: ?*c.struct_decompress_xz) void {
    var ctx: *Context = @ptrCast(@alignCast(xz_ctx));
    ctx.decompress.deinit();
    ctx.deinit();
}
