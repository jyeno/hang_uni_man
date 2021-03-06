const std = @import("std");
const Player = @import("Player.zig");
const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

pub const uid_size = 16;

pub fn genUID(buffer: *[uid_size]u8) void {
    var rng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp()));
    var i: u8 = 0;
    while (i < uid_size) : (i += 1) {
        buffer[i] = alphabet[rng.random().int(usize) % alphabet.len];
    }
}

pub fn sendJson(
    allocator: std.mem.Allocator,
    conn: *const std.net.StreamServer.Connection,
    data: anytype,
) !void {
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    std.json.stringify(data, .{}, list.writer()) catch return error.InternalError;

    _ = conn.stream.write(list.items) catch return error.InternalError;
}

/// Notifies the address with `data` and Event
pub fn notifyEvent(
    allocator: std.mem.Allocator,
    subs: []*const Player,
    event: []const u8,
    data: anytype,
) !void {
    for (subs) |subscriber| {
        sendJson(allocator, subscriber.conn, .{ .event = event, .data = data }) catch {}; // ignore error, as it could lead to others players not being notified
    }
}
