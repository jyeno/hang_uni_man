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

const command_handles = std.ComptimeStringMap(fn (*Context, *const net.StreamServer.Connection, Parameters) void, .{
    .{ "player", handlePlayerCommand },
    .{ "room", handleRoomCommand },
    .{ "game", handleGameCommand },
});

fn handleConn(conn: *const net.StreamServer.Connection, ctx: *Context) !void {
    // new zeroed buffer
    while (true) {
        var cmd_string = std.mem.zeroes([100:0]u8);
        std.debug.print("return {}", .{try conn.stream.read(cmd_string[0..])});

        var tokenizer = std.mem.tokenize(u8, &cmd_string, " \n");
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
                });
            } else {
                try utils.sendJson(ctx.allocator, conn, .{ .@"error" = error.InvalidCommand });
            }
        } else {
            std.debug.print("closing connection with {}\n", .{conn});
            conn.stream.close();
            break;
        }
    }
}

// TODO error handling
fn handlePlayerCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) void {
    if (std.ascii.eqlIgnoreCase(params.action, "register")) {
        // allocate a new user
        // add new user to user database
        const player = ctx.createPlayer(params.first_arg) catch return;
        utils.sendJson(ctx.allocator, conn, .{ .name = player.name, .uid = player.uid }) catch return;
    } else if (std.ascii.eqlIgnoreCase(params.action, "logout")) {
        // removes user for user database
        const success = ctx.delPlayer(params.first_arg);
        utils.sendJson(ctx.allocator, conn, .{ .success = success }) catch return;
    }
}

fn handleRoomCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) void {
    if (std.ascii.eqlIgnoreCase(params.action, "create")) {
        const room_name = params.first_arg;
        const creator = ctx.getPlayer(params.second_arg.?).?;
        const room = ctx.createRoom(room_name, creator, .MEDIUM) catch return;
        utils.sendJson(ctx.allocator, conn, .{
            .creator = creator.name,
            .name = room_name,
            .uid = room.uid,
            .difficulty = "M",
            .max_players = room.players.len + 1,
        }) catch return;
    } else if (std.ascii.eqlIgnoreCase(params.action, "join")) {
        std.debug.print("room join {}\n", .{params});
    } else if (std.ascii.eqlIgnoreCase(params.action, "exit")) {
        std.debug.print("room exit {}\n", .{params});
    } else if (std.ascii.eqlIgnoreCase(params.action, "list")) {
        std.debug.print("room list all\n", .{});
    } else if (std.ascii.eqlIgnoreCase(params.action, "start")) {
        // removes user for user database
        std.debug.print("room start {s}\n", .{params});
    }
}

fn handleGameCommand(ctx: *Context, conn: *const net.StreamServer.Connection, params: Parameters) void {
    _ = ctx;
    _ = conn;
    _ = params;
}
// TODO some way to validate user (password maybe)
// TODO time limit per play, if player passes the time limit then his play is skipped, 3 times mean that player is no more
// TODO save to sqlite3
// TODO maybe check if it is on any rooms/matches and remove accordingly
// TODO things left: make Game work, finish Room
// TODO display on client qml
// nome (Dificuldade) membros_atuais/limite_membros
