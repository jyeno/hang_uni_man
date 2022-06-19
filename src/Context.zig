const std = @import("std");
const net = std.net;
const Player = @import("Player.zig");
const Room = @import("Room.zig");
const Game = @import("Game.zig");
const utils = @import("utils.zig");

const Context = @This();
// TODO have list of words in a file and append it here, also separate it into lines and make a list of those

allocator: std.mem.Allocator,
players: std.ArrayList(Player),
rooms: std.ArrayList(Room),
// Game dont need a uid as the others, it maybe could be a hashmap
matches: std.ArrayList(Game),

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{
        .allocator = allocator,
        .players = std.ArrayList(Player).init(allocator),
        .rooms = std.ArrayList(Room).init(allocator),
        .matches = std.ArrayList(Game).init(allocator),
    };
}

pub fn deinit(self: *Context) void {
    self.players.deinit();
    self.rooms.deinit();
}

pub fn createPlayer(self: *Context, name: []const u8, conn: *const std.net.StreamServer.Connection) !*Player {
    var player = Player.init(try self.allocator.dupe(u8, name), conn);
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

pub fn createRoom(self: *Context, name: []const u8, requester: *const Player, difficulty_str: []const u8) !Room {
    if (self.isPlayerOccupied(requester)) return error.PlayerOccupied;

    if (Room.Difficulty.fromString(difficulty_str)) |difficulty| {
        const room = Room.init(name, requester, difficulty);
        try self.rooms.append(room);
        return room;
    }
    return error.InvalidDifficulty;
}

fn removeRoom(self: *Context, room: *Room) void {
    for (self.rooms.items) |r, i| {
        if (std.mem.eql(u8, &r.uid, &room.uid)) {
            room.deinit(self.allocator);
            _ = self.rooms.orderedRemove(i);
            break;
        }
    }
}

pub fn joinRoom(self: *Context, room: *Room, player: *const Player) !void {
    if (self.isPlayerOccupied(player)) return error.PlayerOccupied;

    try room.addPlayer(player);
    try self.roomChanged(room);
}

pub fn exitRoom(self: *Context, room: *Room, player: *const Player) !void {
    const index: usize = blk: {
        for (room.players) |p, i| {
            if (p == player) {
                break :blk i;
            }
        }
        return error.PlayerNotInTheRoom;
    };
    try room.removePlayer(player, index);
    try self.roomChanged(room);
}

pub fn kickPlayerRoom(self: *Context, room: *Room, requester: *const Player, player_index: usize) !void {
    if (player_index >= room.player_count) return error.InvalidIndex;

    try room.removePlayer(requester, player_index);
    try self.roomChanged(room);
}

pub fn getRoom(self: *Context, room_uid: []const u8) ?*Room {
    for (self.rooms.items) |*room| {
        if (std.mem.eql(u8, &room.uid, room_uid)) {
            return room;
        }
    }
    return null;
}

fn isPlayerOccupied(self: *Context, player: *const Player) bool {
    for (self.rooms.items) |room| {
        if (room.creator == player) return true;
        for (room.players) |room_player| {
            if (room_player == player) return true;
        }
    }
    return false;
}

const DisplayRoom = struct {
    name: []const u8,
    uid: [16]u8,
    difficulty: []const u8,
    max_players: usize,
    current_count: usize,
};

// wants room name, uid, max_members, current_count, difficulty
pub fn listRooms(self: *Context) ![]const DisplayRoom {
    var list = try std.ArrayList(DisplayRoom).initCapacity(self.allocator, self.rooms.items.len);
    for (self.rooms.items) |room| {
        list.appendAssumeCapacity(.{
            .name = room.name,
            .uid = room.uid,
            .difficulty = room.difficulty.toString(),
            .max_players = room.players.len + 1,
            .current_count = room.player_count + 1,
        });
    }
    return list.toOwnedSlice();
}

pub fn roomSendMessage(self: *Context, room: *Room, player: *const Player, message: []const u8) !void {
    var room_players: [6]*const Player = .{ undefined, undefined, undefined, undefined, undefined, undefined };
    for (room.players[0..room.player_count]) |p, i| {
        std.debug.print("player: {}\n", .{p});
        room_players[i] = p.?;
    }
    room_players[room.player_count] = room.creator;
    try utils.notifyEvent(self.allocator, room_players[0 .. room.player_count + 1], "RoomMessageReceived", .{ .owner = player.name, .message = message });
}

fn roomChanged(self: *Context, room: *Room) !void {
    var room_players: [6]*const Player = .{ undefined, undefined, undefined, undefined, undefined, undefined };
    for (room.players[0..room.player_count]) |p, i| {
        std.debug.print("player: {}\n", .{p});
        room_players[i] = p.?;
    }
    room_players[room.player_count] = room.creator;
    try utils.notifyEvent(self.allocator, room_players[0 .. room.player_count + 1], "RoomChanged", room.data());
}

pub fn startGame(self: *Context, room: *Room, requester: *const Player) !void {
    if (room.creator != requester) return error.UnathorizedRequest;

    const life_amount = 5;
    var members_game = try std.ArrayList(*const Player).initCapacity(self.allocator, room.player_count + 1);
    defer members_game.deinit();

    for (room.players[0..room.player_count]) |p| {
        members_game.appendAssumeCapacity(p.?);
    }
    members_game.appendAssumeCapacity(room.creator);
    // TODO get word from wordlist make it upper always
    var game = try Game.init(self.allocator, "HELLOWORLD", members_game.items, life_amount);
    try self.matches.append(game);
    try utils.notifyEvent(self.allocator, members_game.items, "GameStarted", game.data());
    self.removeRoom(room); // room has made its task so it should be deleted
}

pub fn checkGameEnded(self: *Context, game: *Game) void {
    // TODO history somehow here
    if (game.finished or game.players.count() == 0) {
        game.deinit();

        for (self.matches.items) |*g, index| {
            if (g == game) {
                _ = self.matches.orderedRemove(index);
                break;
            }
        }
    }
}

pub fn getGame(self: *Context, game_uid: []const u8) ?*Game {
    for (self.matches.items) |*game| {
        if (std.mem.eql(u8, &game.uid, game_uid)) {
            return game;
        }
    }
    return null;
}
