const std = @import("std");
const net = std.net;

pub fn main() anyerror!void {
    // Initialize local IP address
    // You can also change the port number or use IPv6
    const port = 8080;
    const address = net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);

    // Initialize server
    // If `reuse_address` is not set to `true`, you should wait after running program
    // For more information read http://unixguide.net/network/socketfaq/4.5.shtml
    var server = net.StreamServer.init(.{ .reuse_address = true });
    defer server.deinit();
    std.debug.print("-- Server started at {} port --\n", .{port});

    try server.listen(address); // Start listening

    // Accepting incoming connections
    while (true) {
        const conn = server.accept() catch |err| {
            std.debug.print("Error accepting a connection: {}\n", .{err});
            continue;
        };
        defer conn.stream.close();
        const child = try std.os.fork();
        if (child == 0) {
            defer {
                conn.stream.close();
                std.os.exit(0);
            }

            // new zeroed buffer
            var buf = std.mem.zeroes([100:0]u8);
            _ = try conn.stream.read(buf[0..]);

            try handleConn(&conn, &buf);
            std.debug.print("entry: {s}\n", .{buf});

            const message = "HTTP/1.1 200 OK\n\r\nHello world!";
            _ = try conn.stream.write(message);
        }
    }
}

// TODO return JSON with data
fn handleConn(conn: *const net.StreamServer.Connection, cmd_string: []const u8) !void {
    std.debug.print("connection: {}\n", .{conn});
    var tokenizer = std.mem.tokenize(u8, cmd_string, " \n");
    if (tokenizer.next()) |cmd| {
        if (std.mem.eql(u8, cmd, "user")) {
            handleUserCommand(tokenizer.rest()) catch |err| {
                std.debug.print("error: {}\n", .{err});
            };
        } else if (std.mem.eql(u8, cmd, "user")) {
            std.debug.print("room request\n", .{});
        } else if (std.mem.eql(u8, cmd, "game")) {
            std.debug.print("game request\n", .{});
        } else {
            return error.InvalidCommand;
        }
    } else {
        return error.EmptyCommand;
    }
}

fn handleUserCommand(cmd_string: []const u8) !void {
    var tokenizer = std.mem.tokenize(u8, cmd_string, " \n");
    if (tokenizer.next()) |action| {
        if (std.ascii.eqlIgnoreCase(action, "register")) {
            // allocate a new user
            // add new user to user database
            std.debug.print("user register {s}\n", .{tokenizer.next()});
        } else if (std.ascii.eqlIgnoreCase(action, "logout")) {
            // removes user for user database
            std.debug.print("user logout {s}\n", .{tokenizer.next()});
        } else {
            return error.InvalidCommand;
        }
    } else {
        return error.EmptyCommand;
    }
}

fn handleRoomCommand(cmd_string: []const u8) !void {
    var tokenizer = std.mem.tokenize(u8, cmd_string, " \n");
    if (tokenizer.next()) |action| {
        if (std.ascii.eqlIgnoreCase(action, "create")) {
            // allocate a new user
            // add new user to user database
            std.debug.print("user register {s}\n", .{tokenizer.next()});
        } else if (std.ascii.eqlIgnoreCase(action, "join")) {
            std.debug.print("room join {s}\n", .{tokenizer.next()});
        } else if (std.ascii.eqlIgnoreCase(action, "exit")) {
            std.debug.print("room exit {s}\n", .{tokenizer.next()});
        } else if (std.ascii.eqlIgnoreCase(action, "list")) {
            std.debug.print("room list\n", .{});
        } else if (std.ascii.eqlIgnoreCase(action, "start")) {
            // removes user for user database
            std.debug.print("room start {s}\n", .{tokenizer.next()});
        } else {
            return error.InvalidCommand;
        }
    } else {
        return error.EmptyCommand;
    }
}

fn handleGameCommand(cmd_string: []const u8) !void {
    _ = cmd_string;
}

// TODO some way to validate user (password maybe)
// TODO time limit per play, if player passes the time limit then his play is skipped, 3 times mean that player is no more
// TODO improve uuids probably
