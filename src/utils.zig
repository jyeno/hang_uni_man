const std = @import("std");
const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

pub const uid_size = 16;

pub const Event = enum {
    PlayerGroupChanged,
    LetterGuessed,
    WordGuessed,
    CurrentPlayerChanged,
};

pub fn genUID(buffer: *[uid_size]u8) void {
    var rng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp()));
    var i: u8 = 0;
    while (i < uid_size) : (i += 1) {
        buffer[i] = alphabet[rng.random().int(usize) % alphabet.len];
    }
}

// TODO analise the size, if less than 256 bytes, probably we could have a non-allocating jsonSendSmall
pub fn sendJson(
    allocator: std.mem.Allocator,
    conn: *const std.net.StreamServer.Connection,
    data: anytype,
) !void {
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try std.json.stringify(data, .{}, list.writer());

    _ = try conn.stream.write(list.items);
}

/// Notifies the address with `data` and Event
pub fn notifier(
    allocator: std.mem.Allocator,
    subs: []*const std.net.StreamServer.Connection,
    event: Event,
    data: anytype,
) !void {
    for (subs) |subscriber| {
        try sendJson(allocator, subscriber, .{ .event = event, .data = data });
    }
}
