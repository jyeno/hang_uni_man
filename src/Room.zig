const std = @import("std");
const utils = @import("utils.zig");
const Player = @import("Player.zig");
const Game = @import("Game.zig");

const uid_size = utils.uid_size;

const Room = @This();

name: []const u8,
uid: [uid_size]u8,
creator: *const Player,
players: [5]*const Player = .{ undefined, undefined, undefined, undefined, undefined },
player_count: u8 = 0,
difficulty: Game.Difficulty,

// remove uid
pub fn init(name: []const u8, creator: *const Player, difficulty: Game.Difficulty) Room {
    var uid = std.mem.zeroes([uid_size]u8);
    utils.genUID(&uid);
    return .{ .name = name, .creator = creator, .uid = uid, .difficulty = difficulty };
}

pub fn deinit(self: *Room, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
}

pub fn addPlayer(self: *Room, player: *const Player) !void {
    // TODO event notify
    if (self.player_count > self.players_arr.len - 1) return error.RoomFull;

    self.players[self.player_count] = player;
    self.player_count += 1;
}

pub fn removePlayer(self: *Room, requester: *const Player, player_index: u8) !void {
    if (self.player_count >= self.players_arr.len) return error.InvalidIndex;
    // TODO event notify
    // kick or user exiting
    if (requester == self.creator or requester == self.players[player_index]) {
        _ = player_index;
        // swap until end
        // TODO analise usage of stdlib std.mem.swap
        self.player_count -= 1;
    } else {
        return error.UnauthorizedRequest;
    }
}

pub fn setDifficulty(self: *Room, requester: *const Player, difficulty: Game.Difficulty) void {
    // TODO event notify
    if (requester == self.creator) {
        self.difficulty = difficulty;
    } else {
        return error.UnauthorizedRequest;
    }
}

pub fn startGame(self: *Room) Game {
    _ = self;
    return .{};
}
