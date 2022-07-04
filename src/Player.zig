const std = @import("std");
const utils = @import("utils.zig");

const Player = @This();

// owner
name: []const u8,
uid: [utils.uid_size]u8,
conn: *const std.net.StreamServer.Connection,

pub fn init(name: []const u8, conn: *const std.net.StreamServer.Connection) Player {
    var uid = std.mem.zeroes([utils.uid_size]u8);
    utils.genUID(&uid);
    return .{ .name = name, .uid = uid, .conn = conn };
}

pub fn deinit(self: *Player, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
}
