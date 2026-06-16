const std = @import("std");
const Allocator = std.mem.Allocator;

const font = @import("font/main.zig");
const Canvas = font.sprite.Canvas;
const Metrics = font.Metrics;

const DrawFn = fn (cp: u32, canvas: *Canvas, width: u32, height: u32, metrics: Metrics) anyerror!void;
const Range = struct { min: u32, max: u32, draw: *const DrawFn };

/// When upstream adds a new range file, add the corresponding `@import` here.
const structs = [_]type{
    @import("font/sprite/draw/block.zig"),
    @import("font/sprite/draw/box.zig"),
    @import("font/sprite/draw/braille.zig"),
    @import("font/sprite/draw/branch.zig"),
    @import("font/sprite/draw/geometric_shapes.zig"),
    @import("font/sprite/draw/powerline.zig"),
    @import("font/sprite/draw/symbols_for_legacy_computing.zig"),
    @import("font/sprite/draw/symbols_for_legacy_computing_supplement.zig"),
};

const ranges: []const Range = ranges: {
    @setEvalBranchQuota(1_000_000);

    var range_count = 0;
    for (structs) |s| {
        for (@typeInfo(s).@"struct".decls) |decl| {
            if (!std.mem.startsWith(u8, decl.name, "draw")) continue;
            range_count += 1;
        }
    }

    var r: [range_count]Range = undefined;
    var names: [range_count][:0]const u8 = undefined;
    var i = 0;
    for (structs) |s| {
        for (@typeInfo(s).@"struct".decls) |decl| {
            if (!std.mem.startsWith(u8, decl.name, "draw")) continue;

            const sep = std.mem.indexOfScalar(u8, decl.name, '_') orelse decl.name.len;
            const min = std.fmt.parseInt(u21, decl.name[4..sep], 16) catch unreachable;
            const max = if (sep == decl.name.len)
                min
            else
                std.fmt.parseInt(u21, decl.name[sep + 1 ..], 16) catch unreachable;

            r[i] = .{ .min = min, .max = max, .draw = &@field(s, decl.name) };
            names[i] = decl.name;
            i += 1;
        }
    }

    std.mem.sortUnstableContext(0, r.len, struct {
        r: []Range,
        names: [][:0]const u8,
        pub fn lessThan(self: @This(), a: usize, b: usize) bool {
            return self.r[a].min < self.r[b].min;
        }
        pub fn swap(self: @This(), a: usize, b: usize) void {
            std.mem.swap(Range, &self.r[a], &self.r[b]);
            std.mem.swap([:0]const u8, &self.names[a], &self.names[b]);
        }
    }{ .r = &r, .names = &names });

    var prev: u32 = 0;
    for (r, 0..) |n, k| {
        if (k > 0 and n.min <= prev) {
            @compileError(std.fmt.comptimePrint(
                "Codepoint range for {s} overlaps range for {s}, {X} <= {X} <= {X}",
                .{ names[k], names[k - 1], r[k - 1].min, n.min, r[k - 1].max },
            ));
        }
        prev = n.max;
    }

    const fixed = r;
    break :ranges &fixed;
};

fn getDrawFn(cp: u32) ?*const DrawFn {
    inline for (ranges) |range| {
        if (cp >= range.min and cp <= range.max) return range.draw;
    }
    return null;
}

pub fn hasCodepoint(cp: u32) bool {
    return getDrawFn(cp) != null;
}

pub fn renderSprite(
    alloc: Allocator,
    cp: u32,
    buf: []u8,
    buf_w: i32,
    buf_h: i32,
    x0: i32,
    cw: i32,
    ch: i32,
    box_thickness: u32,
) bool {
    const draw = getDrawFn(cp) orelse return false;
    if (cw <= 0 or ch <= 0) return false;

    const w: u32 = @intCast(cw);
    const h: u32 = @intCast(ch);

    const metrics: Metrics = .{
        .cell_width = w,
        .cell_height = h,
        .box_thickness = @max(1, box_thickness),
    };

    var canvas = Canvas.init(alloc, w, h, 0, 0) catch return false;
    defer canvas.deinit();

    draw(cp, &canvas, w, h, metrics) catch return false;

    const src: []const u8 = @ptrCast(canvas.sfc.image_surface_alpha8.buf);
    var y: i32 = 0;
    while (y < ch) : (y += 1) {
        if (y >= buf_h) break;
        var x: i32 = 0;
        while (x < cw) : (x += 1) {
            const dx = x0 + x;
            if (dx < 0 or dx >= buf_w) continue;
            const si: usize = @intCast(y * cw + x);
            if (si >= src.len) continue;
            const di: usize = @intCast((y * buf_w + dx) * 4);
            if (di >= buf.len) continue;
            buf[di] = src[si];
        }
    }

    return true;
}
