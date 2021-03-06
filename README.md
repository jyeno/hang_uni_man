# HANG_UNI_MAN

Server for the local multiplayer hangman, a toy network project

## Run

To run this project you only need to have installed the programming language [zig](https://github.com/ziglang/zig) and run:

`zig build run`

## Rules

The player must get the word right, the first to do so will be the winner.
The player has a limited number of tries before he loses, the amount of tries depends on the difficulty
If player guess word wrong then he loses, if he guess it right he wins

## Commands:

 * `user register player_name` register a player, checks if `player_name` is unique and returns a `player_uuid`
 * `user logout player_uuid` unregister a player
 * `room create room_name player_uuid difficulty` returns the `room_uuid` the difficulty is defined by `D`, the creator is automatically inserted into the room
 * `room exit room_uuid player_uuid` player exist the room, if it is the creator then the room is deleted
 * `room list all` returns all the available rooms waiting
 * `room join room_uuid player_uuid` join given room
 * `room send_msg room_uuid player_uuid message` player sends message to all players in given room
 * `room kick room_uuid player_uuid player_index` creator can kick player at player_index
 * `room start_game room_uuid player_uuid` creator of the room starts a game, notify the players that the game started `game_uuid`
 * `game guess_letter game_uuid player_uuid L` player guess letter `L`, if successful continues to play, otherwise loses a life and another player gets his chance
 * `game player_index game_uuid player_uuid` get `player_index` at given `game_uuid`
 * `game exit game_uuid player_uuid` signalizes that `player_uuid` of game `game_uuid`
 * `game guess_word game_uuid player_uuid WORD` player guess the `WORD`, if successful player wins, otherwise loses all his tries and stays as spectator

 <!-- * `history`  returns the data of all games and its winners -->

## Game events emitted

Clients must receive those

 * game ended
 * player state changed
 * player joined a room, signal sent to the members of the rooms
 * current player changed
 * player guessed letter/word
