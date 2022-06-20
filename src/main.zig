const std = @import("std");
const net = std.net;
const Player = @import("Player.zig");
const Room = @import("Room.zig");
const Game = @import("Game.zig");
const Context = @import("Context.zig");
const utils = @import("utils.zig");

pub fn main() anyerror!void {
    // Initialize local IP address
    const port = 8080;
    const address = net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);

    // Initialize server
    // If `reuse_address` is not set to `true`, you should wait after running program
    // For more information read http://unixguide.net/network/socketfaq/4.5.shtml
    var server = net.StreamServer.init(.{ .reuse_address = true });
    defer server.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked) std.debug.print("Memory leaked.\n", .{});
    }
    // var stack_alloc = std.heap.stackFallback(2048, gpa.allocator());
    // var allocator = stack_alloc.get();
    var context = Context.init(gpa.allocator());
    defer context.deinit();

    std.debug.print("-- Server started at {} port --\n", .{port});

    try server.listen(address); // Start listening

    // Accepting incoming connections
    while (true) {
        const conn = server.accept() catch |err| {
            std.debug.print("Error accepting a connection: {}\n", .{err});
            continue;
        };

        var t = std.Thread.spawn(.{}, handleConn, .{ &conn, &context }) catch |err| {
            std.debug.print("Can't spawn thread to handle connection from {s}  err {}\n", .{ conn.address, err });
            conn.stream.close();
            continue;
        };
        t.detach();
    }
}

const Parameters = struct {
    action: []const u8,
    first_arg: []const u8,
    second_arg: ?[]const u8,
    third_arg: ?[]const u8,
};

// TODO figure out how to add errors here
const command_handles = std.ComptimeStringMap(fn (*Context, *const net.StreamServer.Connection, Parameters) error{
    InvalidRequest,
    InvalidPlay,
    InvalidIndex,
    InternalError,
    PlayerNotFound,
    PlayerOccupied,
    PlayerNotInTheRoom,
    RoomNotFound,
    RoomFull,
    UnauthorizedRequest,
    GameNotFound,
    LetterAlreadyGuessed,
}!void, .{
    .{ "player", handlePlayerCommand },
    .{ "room", handleRoomCommand },
    .{ "game", handleGameCommand },
});

fn handleConn(conn: *const net.StreamServer.Connection, ctx: *Context) !void {
    // new zeroed buffer
    while (true) {
        var cmd_string = std.mem.zeroes([100:0]u8);
        if ((try conn.stream.read(cmd_string[0..])) == 0) {
            conn.stream.close();
            break; // if connection returns nothing, then close the connection
        }

        var tokenizer = std.mem.tokenize(u8, &cmd_string, " \n\t\x00");
        if (tokenizer.next()) |cmd| {
            if (command_handles.get(cmd)) |handleCommand| {
                const action = tokenizer.next().?;
                const first_arg = tokenizer.next().?;
                const second_arg = tokenizer.next();
                const third_arg = tokenizer.next();
                handleCommand(ctx, conn, .{
                    .action = action,
                    .first_arg = first_arg,
                    .second_arg = second_arg,
                    .third_arg = third_arg,
                }) catch |err| try utils.sendJson(ctx.allocator, conn, .{ .@"error" = err });
            } else {
                try utils.sendJson(ctx.allocator, conn, .{ .@"error" = error.InvalidCommand });
            }
        }
    }
}

fn handlePlayerCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) !void {
    if (std.ascii.eqlIgnoreCase(params.action, "register")) {
        // add new user to user database
        const player = ctx.createPlayer(params.first_arg, conn) catch return error.InternalError;
        const data = .{ .name = player.name, .uid = player.uid };
        utils.sendJson(ctx.allocator, conn, .{ .event = "PlayerCreated", .data = data }) catch return;
    } else if (std.ascii.eqlIgnoreCase(params.action, "logout")) {
        // removes user for user database
        const success = ctx.delPlayer(params.first_arg);
        const data = .{ .success = success };
        utils.sendJson(ctx.allocator, conn, .{ .event = "PlayerLogout", .data = data }) catch return;
    }
}

fn handleRoomCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) !void {
    if (std.ascii.eqlIgnoreCase(params.action, "list")) { // special case, only needs the action
        const rooms = ctx.listRooms() catch return error.InternalError;
        defer ctx.allocator.free(rooms);

        utils.sendJson(ctx.allocator, conn, .{ .event = "RoomListChanged", .data = rooms }) catch return error.InternalError;
    }

    if (params.second_arg == null) return error.InvalidRequest;

    const player = ctx.getPlayer(params.second_arg.?) orelse return error.PlayerNotFound;

    if (std.ascii.eqlIgnoreCase(params.action, "create")) {
        const room_name = ctx.allocator.dupe(u8, params.first_arg) catch return error.InternalError;
        errdefer ctx.allocator.free(room_name);

        const difficulty = params.third_arg orelse return error.InvalidRequest;

        var room = ctx.createRoom(room_name, player, difficulty) catch return;
        utils.sendJson(ctx.allocator, conn, .{ .event = "RoomCreated", .data = room.data() }) catch return error.InternalError;
    } else {
        // actually, notify everyone in the room, TODO remove it
        if (ctx.getRoom(params.first_arg)) |room| {
            if (std.ascii.eqlIgnoreCase(params.action, "join")) {
                try ctx.joinRoom(room, player);
            } else if (std.ascii.eqlIgnoreCase(params.action, "exit")) {
                try ctx.exitRoom(room, player);
                const data = .{ .success = true };
                utils.sendJson(ctx.allocator, conn, .{ .event = "RoomExited", .data = data }) catch return;
            } else if (std.ascii.eqlIgnoreCase(params.action, "kick")) {
                const index_str = params.third_arg orelse return error.InvalidRequest;
                const index = std.fmt.parseInt(u8, index_str, 10) catch return error.InvalidRequest;

                try ctx.kickPlayerRoom(room, player, index);
            } else if (std.ascii.eqlIgnoreCase(params.action, "start_game")) {
                ctx.startGame(room, player) catch return error.InternalError;
            } else if (std.ascii.eqlIgnoreCase(params.action, "send_msg")) { // TODO fix, only fix word get sent, the rest is ignored
                ctx.roomSendMessage(room, player, params.third_arg.?);
            } else {
                return error.InvalidRequest;
            }
        } else {
            return error.RoomNotFound;
        }
    }
}

fn handleGameCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) !void {
    _ = conn;
    if (ctx.getGame(params.first_arg)) |game| {
        if (params.second_arg == null or params.third_arg == null) return error.InvalidRequest;
        const player = ctx.getPlayer(params.second_arg.?) orelse return error.PlayerNotFound;

        if (std.ascii.eqlIgnoreCase(params.action, "guess_letter")) {
            const letter = params.third_arg.?[0];
            try game.guessLetter(player, std.ascii.toUpper(letter));
            ctx.checkGameEnded(game);
        } else if (std.ascii.eqlIgnoreCase(params.action, "guess_word")) {
            try game.guessWord(player, params.third_arg.?);
            ctx.checkGameEnded(game);
        } else if (std.ascii.eqlIgnoreCase(params.action, "exit")) {
            // TODO
            // utils.sendJson(ctx.allocator, conn, .{ .@"error" = error.RoomNotFound }) catch return;
        }
        // TODO consider a exit
    } else {
        return error.GameNotFound;
    }
}

// TODO time limit per play, if player passes the time limit then his play is skipped, 3 times mean that player is no more
// TODO save to sqlite3
// TODO maybe check if it is on any rooms/matches and remove accordingly
// TODO close room and notify all when creator gives up
