const std = @import("std");
const utils = @import("utils.zig");

const Player = @This();

// owner
name: []const u8,
uid: [utils.uid_size]u8,
// notify_address: std.net.Address,
// TODO implement later and analyze a good way of doing it
// password: []const u8 = "",

pub fn init(name: []const u8) Player {
    var uid = std.mem.zeroes([utils.uid_size]u8);
    utils.genUID(&uid);
    return .{ .name = name, .uid = uid };
}

pub fn deinit(self: *Player, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
}
