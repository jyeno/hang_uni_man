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

        var t = std.Thread.spawn(.{}, handleConn, .{ conn, &context }) catch |err| {
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

const command_handles = std.ComptimeStringMap(fn (*Context, *const net.StreamServer.Connection, Parameters) error{
    InvalidDifficulty,
    InvalidRequest,
    InvalidPlay,
    InvalidIndex,
    InternalError,
    PlayerNotFound,
    PlayerOccupied,
    PlayerNotInTheRoom,
    PlayerNotInTheGame,
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

fn handleConn(conn: net.StreamServer.Connection, ctx: *Context) !void {
    while (true) {
        // new zeroed buffer
        var cmd_string = std.mem.zeroes([100:0]u8);
        const bytes_read = conn.stream.read(cmd_string[0..]) catch break;
        if (bytes_read == 0) {
            break; // if connection returns nothing, then close the connection
        }

        var tokenizer = std.mem.tokenize(u8, &cmd_string, " \n\t\x00");
        if (tokenizer.next()) |cmd| {
            if (command_handles.get(cmd)) |handleCommand| {
                const action = tokenizer.next().?;
                const first_arg = tokenizer.next().?;
                const second_arg = tokenizer.next();
                const third_arg = tokenizer.next();
                handleCommand(ctx, &conn, .{
                    .action = action,
                    .first_arg = first_arg,
                    .second_arg = second_arg,
                    .third_arg = third_arg,
                }) catch |err| switch (err) {
                    error.InternalError => return,
                    else => {
                        std.debug.print("cmd: {s}\nerror: {}", .{ cmd, err });
                        utils.sendJson(ctx.allocator, &conn, .{ .@"error" = err }) catch return;
                    },
                };
            } else {
                try utils.sendJson(ctx.allocator, &conn, .{ .@"error" = error.InvalidCommand });
            }
        }
    }
}

fn handlePlayerCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) !void {
    if (std.ascii.eqlIgnoreCase(params.action, "register")) {
        const player = ctx.createPlayer(params.first_arg, conn) catch return error.InternalError;
        const data = .{ .name = player.name, .uid = player.uid };
        try utils.sendJson(ctx.allocator, conn, .{ .event = "PlayerCreated", .data = data });
    } else if (std.ascii.eqlIgnoreCase(params.action, "logout")) {
        _ = ctx.delPlayer(params.first_arg);
    }
}

fn handleRoomCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) !void {
    if (std.ascii.eqlIgnoreCase(params.action, "list")) { // special case, only needs the action
        const rooms = ctx.listRooms() catch return error.InternalError;
        defer ctx.allocator.free(rooms);

        try utils.sendJson(ctx.allocator, conn, .{ .event = "RoomListChanged", .data = rooms });
        return;
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
        const room = ctx.getRoom(params.first_arg) orelse return error.RoomNotFound;

        if (std.ascii.eqlIgnoreCase(params.action, "join")) {
            try ctx.joinRoom(room, player);
        } else if (std.ascii.eqlIgnoreCase(params.action, "exit")) {
            try ctx.exitRoom(room, player);
            const data = .{ .success = true };
            try utils.sendJson(ctx.allocator, conn, .{ .event = "RoomExited", .data = data });
        } else if (std.ascii.eqlIgnoreCase(params.action, "kick")) {
            const index_str = params.third_arg orelse return error.InvalidRequest;
            const index = std.fmt.parseInt(u8, index_str, 10) catch return error.InvalidRequest;

            try ctx.kickPlayerRoom(room, player, index);
        } else if (std.ascii.eqlIgnoreCase(params.action, "start_game")) {
            ctx.startGame(room, player) catch return error.InternalError;
        } else if (std.ascii.eqlIgnoreCase(params.action, "send_msg")) {
            try ctx.roomNotifyEvent(room, "RoomMessageReceived", .{ .owner = player.name, .message = params.third_arg.? }, .{});
        } else {
            return error.InvalidRequest;
        }
    }
}

fn handleGameCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) !void {
    if (params.second_arg == null) return error.InvalidRequest;
    var game = ctx.getGame(params.first_arg) orelse return error.GameNotFound;
    const player = ctx.getPlayer(params.second_arg.?) orelse return error.PlayerNotFound;

    if (std.ascii.eqlIgnoreCase(params.action, "player_index")) {
        const index_data = .{ .player_index = try game.playerIndex(player) };
        try utils.sendJson(ctx.allocator, conn, .{ .event = "PlayerIndexFound", .data = index_data });
        return;
    } else if (std.ascii.eqlIgnoreCase(params.action, "exit")) {
        try game.removePlayer(player);
    } else {
        if (params.third_arg == null) return error.InvalidRequest;

        if (std.ascii.eqlIgnoreCase(params.action, "guess_letter")) {
            const letter = params.third_arg.?[0];
            try game.guessLetter(player, std.ascii.toUpper(letter));
        } else if (std.ascii.eqlIgnoreCase(params.action, "guess_word")) {
            try game.guessWord(player, params.third_arg.?);
        } else {
            return error.InvalidRequest;
        }
    }
    ctx.checkGameEnded(game);
}
