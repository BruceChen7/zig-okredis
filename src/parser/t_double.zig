const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const InStream = std.io.InStream;

/// Parses RedisDouble values (e.g. ,123.45)
pub const DoubleParser = struct {
    // 实现trait
    pub fn isSupported(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Float => true,
            else => false,
        };
    }

    // 实现trait
    pub fn parse(comptime T: type, comptime _: type, msg: anytype) !T {
        // TODO: write real implementation
        var buf: [100]u8 = undefined;
        var end: usize = 0;
        for (buf) |*elem, i| {
            const ch = try msg.readByte();
            elem.* = ch;
            if (ch == '\r') {
                end = i;
                break;
            }
        }
        try msg.skipBytes(1, .{});
        return switch (@typeInfo(T)) {
            else => unreachable,
            .Float => try fmt.parseFloat(T, buf[0..end]),
        };
    }

    // 实现trait
    pub fn isSupportedAlloc(comptime T: type) bool {
        return isSupported(T);
    }

    // 实现trait
    pub fn parseAlloc(comptime T: type, comptime rootParser: type, allocator: std.mem.Allocator, msg: anytype) !T {
        _ = allocator;
        return parse(T, rootParser, msg);
    }
};
