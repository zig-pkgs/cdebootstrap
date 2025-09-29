const std = @import("std");
const c = @import("c");

const gpa = std.heap.c_allocator;

const Context = struct {
    limit: std.Io.Limit,
    read_buffer: [8 * 1024]u8 = undefined,
    flate_buffer: [std.compress.flate.max_window_len]u8 = undefined,
    reader: std.fs.File.Reader,
    decompress: std.compress.flate.Decompress,

    pub fn init(file: std.fs.File, limit: std.Io.Limit) !*Context {
        const context = try gpa.create(Context);
        errdefer gpa.destroy(context);
        context.reader = file.reader(&context.read_buffer);
        context.decompress = .init(&context.reader.interface, .gzip, &context.flate_buffer);
        context.limit = limit;
        return context;
    }

    pub fn deinit(self: *Context) void {
        gpa.destroy(self);
    }

    pub fn decompressGz(self: *Context, file_out: std.fs.File) !c_int {
        const data = try self.decompress.reader.allocRemaining(gpa, self.limit);
        defer gpa.free(data);
        try file_out.writeAll(data);
        return @intCast(data.len);
    }
};

export fn decompress_gz_new(fd: c_int, len: usize) ?*c.struct_decompress_gz {
    const ctx = Context.init(
        .{ .handle = fd },
        if (len > 0) .limited(len) else .unlimited,
    ) catch return null;
    return @ptrCast(ctx);
}

export fn decompress_gz(gz_ctx: ?*c.struct_decompress_gz, fd: c_int) c_int {
    var ctx: *Context = @ptrCast(@alignCast(gz_ctx));
    const amt = ctx.decompressGz(.{ .handle = fd }) catch return -1;
    return amt;
}

export fn decompress_gz_free(gz_ctx: ?*c.struct_decompress_gz) void {
    var ctx: *Context = @ptrCast(@alignCast(gz_ctx));
    ctx.deinit();
}
