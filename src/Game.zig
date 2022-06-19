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
    }
    self.letters[self.guessed_count] = guessed;
    self.guessed_count += 1;

    try utils.notifyEvent(self.allocator, self.players.keys(), "GameChanged", self.data());
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
        try utils.notifyEvent(self.allocator, self.players.keys(), "GameFinished", self.data());
    } else {
        self.decrementPlayerLife();
        try utils.notifyEvent(self.allocator, self.players.keys(), "GameChanged", self.data());
    }
}

fn decrementPlayerLife(self: *Game) void {
    var entry = self.players.unmanaged.entries.get(self.current_index);
    entry.value -= 1;
    self.players.putAssumeCapacity(entry.key, entry.value);
    if (entry.value == 0) {
        _ = self.players.orderedRemove(entry.key);
        utils.sendJson(self.allocator, entry.key.conn, .{ .event = "PlayerEliminated", .data = .{} }) catch {};
    } else {
        self.current_index += 1;
    }
    if (self.current_index >= self.players.count()) {
        self.current_index = 0;
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
// TODO
// Think event for winner at guess_letter
// maybe proibith last letter
