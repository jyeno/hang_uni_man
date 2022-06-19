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
const command_handles = std.ComptimeStringMap(fn (*Context, *const net.StreamServer.Connection, Parameters) void, .{
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
                // TODO read until \0
                handleCommand(ctx, conn, .{
                    .action = action,
                    .first_arg = first_arg,
                    .second_arg = second_arg,
                    .third_arg = third_arg,
                });
            } else {
                try utils.sendJson(ctx.allocator, conn, .{ .@"error" = error.InvalidCommand });
            }
        }
    }
}

// TODO error handling
fn handlePlayerCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) void {
    if (std.ascii.eqlIgnoreCase(params.action, "register")) {
        // add new user to user database
        const player = ctx.createPlayer(params.first_arg, conn) catch return;
        const data = .{ .name = player.name, .uid = player.uid };
        utils.sendJson(ctx.allocator, conn, .{ .event = "PlayerCreated", .data = data }) catch return;
    } else if (std.ascii.eqlIgnoreCase(params.action, "logout")) {
        // removes user for user database
        const success = ctx.delPlayer(params.first_arg);
        const data = .{ .success = success };
        utils.sendJson(ctx.allocator, conn, .{ .event = "PlayerLogout", .data = data }) catch return;
    }
}

fn handleRoomCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) void {
    if (std.ascii.eqlIgnoreCase(params.action, "create")) {
        const room_name = ctx.allocator.dupe(u8, params.first_arg) catch return;
        const creator = ctx.getPlayer(params.second_arg.?).?;
        const difficulty = params.third_arg.?;

        var room = ctx.createRoom(room_name, creator, difficulty) catch return;
        utils.sendJson(ctx.allocator, conn, .{ .event = "RoomCreated", .data = room.data() }) catch return;
    } else if (std.ascii.eqlIgnoreCase(params.action, "list")) {
        const rooms = ctx.listRooms() catch return;
        defer ctx.allocator.free(rooms);

        utils.sendJson(ctx.allocator, conn, .{ .event = "RoomListChanged", .data = rooms }) catch return;
    } else {
        // actually, notify everyone in the room, TODO remove it
        if (ctx.getRoom(params.first_arg)) |room| {
            if (std.ascii.eqlIgnoreCase(params.action, "join")) {
                const player = ctx.getPlayer(params.second_arg.?).?;
                ctx.joinRoom(room, player) catch return;
            } else if (std.ascii.eqlIgnoreCase(params.action, "exit")) {
                const player = ctx.getPlayer(params.second_arg.?).?;

                ctx.exitRoom(room, player) catch |err| utils.sendJson(ctx.allocator, conn, .{ .@"error" = err }) catch return;
                const data = .{ .success = true };
                utils.sendJson(ctx.allocator, conn, .{ .event = "RoomExited", .data = data }) catch return;
            } else if (std.ascii.eqlIgnoreCase(params.action, "kick")) {
                const player = ctx.getPlayer(params.second_arg.?).?;
                const index = std.fmt.parseInt(u8, params.third_arg.?, 10) catch return;

                ctx.kickPlayerRoom(room, player, index) catch return;
            } else if (std.ascii.eqlIgnoreCase(params.action, "start_game")) {
                const player = ctx.getPlayer(params.second_arg.?).?;
                ctx.startGame(room, player) catch return;
            } else if (std.ascii.eqlIgnoreCase(params.action, "send_msg")) { // TODO fix, only fix word get sent, the rest is ignored
                const player = ctx.getPlayer(params.second_arg.?).?;
                ctx.roomSendMessage(room, player, params.third_arg.?) catch return;
            }
        } else {
            utils.sendJson(ctx.allocator, conn, .{ .@"error" = error.RoomNotFound }) catch return;
        }
    }
}

fn handleGameCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) void {
    if (ctx.getGame(params.first_arg)) |game| {
        if (std.ascii.eqlIgnoreCase(params.action, "guess_letter")) {
            const player = ctx.getPlayer(params.second_arg.?).?;
            const letter = params.third_arg.?[0];
            game.guessLetter(player, std.ascii.toUpper(letter)) catch |err| std.debug.print("error {}\n", .{err});
            ctx.checkGameEnded(game);
        } else if (std.ascii.eqlIgnoreCase(params.action, "guess_word")) {
            const player = ctx.getPlayer(params.second_arg.?).?;
            game.guessWord(player, params.third_arg.?) catch return;
            ctx.checkGameEnded(game);
        } else if (std.ascii.eqlIgnoreCase(params.action, "exit")) {
            // TODO
        }
        // TODO consider a exit
    } else {
        utils.sendJson(ctx.allocator, conn, .{ .@"error" = error.RoomNotFound }) catch return;
    }
}
// TODO some way to validate user (password maybe)
// TODO time limit per play, if player passes the time limit then his play is skipped, 3 times mean that player is no more
// TODO save to sqlite3
// TODO maybe check if it is on any rooms/matches and remove accordingly
// TODO close room and notify all when creator gives up
//
// TODO have { "event" : "something", data: {...} } returns, to help situate the client on what happened
//
//
// Events:
//   PlayerLogged
