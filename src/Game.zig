// TODO
const std = @import("std");
const Player = @import("Player.zig");
const utils = @import("utils.zig");

const Game = @This();

const max_players = 6;

pub const Difficulty = enum {
    EASY,
    MEDIUM,
    HARD,
};

uid: [utils.uid_size]u8,
players: [max_players]*const Player,
// current player index
current_index: u8,
word: []const u8,
difficulty: Difficulty,
// color number, the indexes are equivalent to the players array
// arena: std.heap.ArenaAllocator,

pub fn init(players: []*const Player) Game {
    var uid = std.mem.zeroes([utils.uid_size]u8);
    utils.genUID(&uid);
    return .{ .uid = uid, .players = players, .difficulty = .MEDIUM };
}

pub fn deinit(self: *Game, allocator: std.mem.Allocator) void {
    _ = self;
    _ = allocator;
}

pub fn guessLetter(self: *Game, guessed: u8) bool {
    _ = self;
    _ = guessed;
}

pub fn guessWord(self: *Game, guessed: []const u8) bool {
    _ = self;
    _ = guessed;
}
