const std = @import("std");
const net = std.net;
const Player = @import("Player.zig");
const Room = @import("Room.zig");
const Game = @import("Game.zig");

const Context = @This();

allocator: std.mem.Allocator,
rng: std.rand.DefaultPrng,
players: std.ArrayList(Player),
rooms: std.ArrayList(Room),
// matches: std.ArrayList(Game),

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{
        .allocator = allocator,
        .rng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp())),
        .players = std.ArrayList(Player).init(allocator),
        .rooms = std.ArrayList(Room).init(allocator),
        // .matches = std.ArrayList(Game).init(allocator),
    };
}

pub fn deinit(self: *Context) void {
    _ = self;
}

pub fn createPlayer(self: *Context, name: []const u8) !*Player {
    var player = Player.init(try self.allocator.dupe(u8, name));
    errdefer self.allocator.free(player.name);

    try self.players.append(player);
    return &player;
}

pub fn delPlayer(self: *Context, player_uid: []const u8) bool {
    for (self.players.items) |*player, index| {
        if (std.mem.eql(u8, &player.uid, player_uid)) {
            player.deinit(self.allocator);
            _ = self.players.orderedRemove(index);
            return true;
        }
    }
    return false;
}

pub fn getPlayer(self: *Context, player_uid: []const u8) ?*Player {
    for (self.players.items) |*player| {
        if (std.mem.eql(u8, &player.uid, player_uid)) {
            return player;
        }
    }
    return null;
}

pub fn createRoom(self: *Context, name: []const u8, requester: *const Player, difficulty: Game.Difficulty) !Room {
    const room = Room.init(name, requester, difficulty);
    try self.rooms.append(room);
    return room;
}

pub fn joinRoom(self: *Context, room_uid: []const u8, player: *const Player) !void {
    for (self.rooms.items) |*room| {
        if (std.mem.eql(u8, room.uid, room_uid)) {
            return try room.addPlayer(player);
        }
    }
    return error.RoomNotFound;
}

pub fn exitRoom(self: *Context, room_uid: []const u8, player: *const Player) !void {
    for (self.rooms.items) |*room| {
        if (std.mem.eql(u8, room.uid, room_uid)) {
            const index: u8 = blk: {
                for (room.players.items) |p, i| {
                    if (p == player) {
                        break :blk i;
                    }
                }
                return error.PlayerNotInTheRoom;
            };
            return try room.removePlayer(player, index);
        }
    }
}

pub fn kickPlayerRoom(self: *Context, room_uid: []const u8, requester: *const Player, player: *const Player) !void {
    if (self.getRoom(room_uid)) |room| {
        const index: u8 = blk: {
            for (room.players.items) |p, i| {
                if (p == player) {
                    break :blk i;
                }
            }
            return error.PlayerNotInTheRoom;
        };
        return try room.removePlayer(requester, index);
    } else {
        return error.InvalidRoom;
    }
}

pub fn getRoom(self: *Context, room_uid: []const u8) ?*Room {
    for (self.rooms.items) |*room| {
        if (std.mem.eql(u8, room.uid, room_uid)) {
            return room;
        }
    }
    return null;
}

// pub fn genUID(self: *Context) [16]u8 {
//     var slug: [16]u8 = undefined;
//     var i: u8 = 0;
//     while (i < 16) : (i += 1) {
//         slug[i] = alphabet[self.rng.random().int(usize) % alphabet.len];
//     }
//     return slug;
// }
