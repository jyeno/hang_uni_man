const std = @import("std");
const Player = @import("Player.zig");
const utils = @import("utils.zig");

const Game = @This();

uid: [utils.uid_size]u8,
// TODO figure out how to use it with index, maybe use getIndex and/or make use of current_index
players: std.AutoArrayHashMap(*const Player, u8),
// current player index
current_index: u8 = 0,
word: []const u8,
letters: [26]u8 = .{' '} ** 26,
guessed_count: usize = 0,
buffer_word_out: [50]u8 = .{' '} ** 50,
buffer_players_out: [6]PlayerData = undefined,
allocator: std.mem.Allocator,
finished: bool = false,

pub fn init(allocator: std.mem.Allocator, word: []const u8, players: []*const Player, life_amount: u8) !Game {
    // TODO random player to start
    var uid = std.mem.zeroes([utils.uid_size]u8);
    utils.genUID(&uid);

    var hash_players = std.AutoArrayHashMap(*const Player, u8).init(allocator);
    try hash_players.ensureTotalCapacity(players.len);
    for (players) |player| {
        hash_players.putAssumeCapacity(player, life_amount);
    }
    return Game{ .uid = uid, .word = word, .players = hash_players, .allocator = allocator };
}

pub fn deinit(self: *Game) void {
    self.players.deinit();
}

pub fn guessLetter(self: *Game, player: *const Player, guessed: u8) !void {
    var current_entry = self.players.unmanaged.entries.get(self.current_index);
    if (current_entry.key != player) return error.InvalidPlay;

    if (std.ascii.indexOfIgnoreCase(self.letters[0..self.guessed_count], &.{guessed})) |_| {
        return error.LetterAlreadyGuessed;
    }

    if (std.ascii.indexOfIgnoreCase(self.word, &.{guessed}) == null) {
        self.decrementPlayerLife();
        self.goToNextPlayer();
    }
    self.letters[self.guessed_count] = guessed;
    self.guessed_count += 1;
    self.notifyChanged();
}

pub fn guessWord(self: *Game, player: *const Player, guessed: []const u8) !void {
    var current_entry = self.players.unmanaged.entries.get(self.current_index);
    if (current_entry.key != player) return error.InvalidPlay;

    if (std.ascii.eqlIgnoreCase(self.word, guessed)) {
        // populate guessed letters with remaining_letters
        for (guessed) |g| {
            if (std.ascii.indexOfIgnoreCase(self.letters[0..self.guessed_count], &.{g}) == null) {
                self.letters[self.guessed_count] = std.ascii.toUpper(g);
                self.guessed_count += 1;
            }
        }

        self.finished = true;
    } else {
        self.decrementPlayerLife();
        self.goToNextPlayer();
    }
    self.notifyChanged();
}

pub fn playerIndex(self: *Game, player: *const Player) !usize {
    return self.players.getIndex(player) orelse error.PlayerNotInTheGame;
}

pub fn removePlayer(self: *Game, player: *const Player) !void {
    const player_index = try self.playerIndex(player);
    const player_entry = self.players.unmanaged.entries.get(player_index);
    self.players.putAssumeCapacity(player_entry.key, 0);

    if (player_index == self.current_index) self.goToNextPlayer();

    utils.notifyEvent(self.allocator, &.{player}, "GameExited", .{}) catch |err| {
        std.debug.print("error {} game_changed\n", .{err});
    };

    self.notifyChanged();
}

const PlayerData = struct {
    player: []const u8,
    remaining_chances: u8,
};

const Data = struct {
    uid: []const u8,
    players: []const PlayerData,
    hidden_word: []const u8,
    letters_guessed: []const u8,
    current_player: usize,
    winner: ?[]const u8,
};

pub fn data(self: *Game) Data {
    return .{
        .uid = &self.uid,
        .players = self.listPlayers(),
        .hidden_word = self.hiddenWord(),
        .letters_guessed = self.letters[0..self.guessed_count],
        .current_player = self.current_index,
        .winner = if (self.finished) self.players.unmanaged.entries.get(self.current_index).key.name else null,
    };
}

fn decrementPlayerLife(self: *Game) void {
    var entry = self.players.unmanaged.entries.get(self.current_index);
    entry.value -= 1;
    self.players.putAssumeCapacity(entry.key, entry.value);
    if (entry.value == 0) {
        utils.sendJson(self.allocator, entry.key.conn, .{ .event = "PlayerEliminated", .data = .{} }) catch {};
    }
}

fn goToNextPlayer(self: *Game) void {
    self.current_index += 1;
    if (self.current_index >= self.players.count()) {
        self.current_index = 0;
    }
    var entry = self.players.unmanaged.entries.get(self.current_index);
    var count_players_lost: u8 = 0;
    while (entry.value == 0 and count_players_lost != self.players.count()) : (entry = self.players.unmanaged.entries.get(self.current_index)) {
        count_players_lost += 1;
        self.current_index += 1;
        if (self.current_index >= self.players.count()) {
            self.current_index = 0;
        }
    }
}

fn hiddenWord(self: *Game) []const u8 {
    for (self.word) |letter, index| {
        if (std.ascii.indexOfIgnoreCase(self.letters[0..self.guessed_count], &.{letter})) |_| {
            self.buffer_word_out[index] = std.ascii.toUpper(letter);
        } else {
            self.buffer_word_out[index] = ' ';
        }
    }
    return self.buffer_word_out[0..self.word.len];
}

fn listPlayers(self: *Game) []const PlayerData {
    var iterator = self.players.iterator();
    var index: u8 = 0;
    while (iterator.next()) |entry| : (index += 1) {
        self.buffer_players_out[index] = .{ .player = entry.key_ptr.*.name, .remaining_chances = entry.value_ptr.* };
    }
    return self.buffer_players_out[0..self.players.count()];
}

fn notifyChanged(self: *Game) void {
    var remaining_players: [6]*const Player = undefined;
    var iterator = self.players.iterator();
    var index: u8 = 0;
    while (iterator.next()) |entry| {
        if (entry.value_ptr.* != 0) {
            remaining_players[index] = entry.key_ptr.*;
            index += 1;
        }
    }
    if (index == 0) return; // no one to notify

    const event = if (self.finished) "GameFinished" else "GameChanged";
    utils.notifyEvent(self.allocator, remaining_players[0..index], event, self.data()) catch |err| {
        std.debug.print("error {} game_changed\n", .{err});
    };
}
// TODO
// Think event for winner at guess_letter
// maybe proibith last letter
