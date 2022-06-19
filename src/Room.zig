const std = @import("std");
const utils = @import("utils.zig");
const Player = @import("Player.zig");
const Game = @import("Game.zig");

const uid_size = utils.uid_size;

pub const Difficulty = enum(u8) {
    HARD = 3,
    MEDIUM = 5,
    EASY = 7,

    pub fn toString(self: Difficulty) []const u8 {
        if (self == .EASY) {
            return "Facil";
        } else if (self == .MEDIUM) {
            return "Medio";
        } else if (self == .HARD) {
            return "Dificil";
        } else unreachable;
    }

    pub fn fromString(str: []const u8) ?Difficulty {
        if (std.mem.eql(u8, str, "facil")) {
            return .EASY;
        } else if (std.mem.eql(u8, str, "medio")) {
            return .MEDIUM;
        } else if (std.mem.eql(u8, str, "dificil")) {
            return .HARD;
        } else return null;
    }
};
const Room = @This();

name: []const u8,
uid: [uid_size]u8 = .{0} ** uid_size,
creator: *const Player,
players: [5:null]?*const Player = std.mem.zeroes([5:null]?*const Player),
player_count: u8 = 0,
difficulty: Difficulty,
buffer_players_out: [6][]const u8 = .{ undefined, undefined, undefined, undefined, undefined, undefined },

pub fn init(name: []const u8, creator: *const Player, difficulty: Difficulty) Room {
    var uid = std.mem.zeroes([uid_size]u8);
    utils.genUID(&uid);
    return .{
        .name = name,
        .uid = uid,
        .creator = creator,
        .difficulty = difficulty,
    };
}

pub fn deinit(self: *Room, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
}

pub fn addPlayer(self: *Room, player: *const Player) !void {
    if (self.player_count >= self.players.len) return error.RoomFull;

    self.players[self.player_count] = player;
    self.player_count += 1;
}

pub fn removePlayer(self: *Room, requester: *const Player, player_index: usize) !void {
    if (player_index > self.player_count) return error.InvalidIndex;
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
    if (requester == self.creator) {
        self.difficulty = difficulty;
    } else {
        return error.UnauthorizedRequest;
    }
}

pub fn listPlayersName(self: *Room) [][]const u8 {
    for (self.players) |player, index| {
        if (player) |p| {
            self.buffer_players_out[index] = p.name;
        }
    }
    self.buffer_players_out[self.player_count] = self.creator.name;

    return self.buffer_players_out[0 .. self.player_count + 1];
}

const Data = struct {
    name: []const u8,
    uid: []const u8,
    difficulty: []const u8,
    players: [][]const u8,
    max_players: usize,
};

pub fn data(self: *Room) Data {
    return .{
        .name = self.name,
        .uid = &self.uid,
        .difficulty = self.difficulty.toString(),
        .players = self.listPlayersName(),
        .max_players = self.players.len + 1,
    };
}
