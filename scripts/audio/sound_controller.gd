extends Node

# ---------------------------------------------------------------------------
# SoundController — global audio backend for WormCraft
# Provides music and SFX playback that is safe when audio files are missing.
# Music and SFX use fully separate AudioStreamPlayer pools.
# ---------------------------------------------------------------------------

# --- Signals -----------------------------------------------------------------
signal music_started(track_name: String)
signal music_stopped()
signal sfx_played(sfx_name: String)

# --- Music Registry ----------------------------------------------------------
const MUSIC_TRACKS := {
	"Burrow Hum": "res://assets/audio/music/burrow_hum.ogg",
	"Damp Circuit Waltz": "res://assets/audio/music/damp_circuit_waltz.ogg",
	"Nocturne for Brutes": "res://assets/audio/music/nocturne_for_brutes.ogg"
}

# --- SFX Registry ------------------------------------------------------------
const SFX_TRACKS := {
	"ui_toggle": "res://assets/audio/sfx/ui_toggle.wav",
	"dig": "res://assets/audio/sfx/dig.wav",
	"scan_success": "res://assets/audio/sfx/scan_success.wav",
	"prototype_built": "res://assets/audio/sfx/prototype_built.wav",
	"death": "res://assets/audio/sfx/death.wav"
}

# --- State -------------------------------------------------------------------
var _current_track_name: String = ""
var _music_player: AudioStreamPlayer = null
var _sfx_players: Array[AudioStreamPlayer] = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Initialize both music and SFX systems immediately on game start.
	# This ensures SFX players exist before any music is played.
	_ensure_music_player()
	_ensure_sfx_players()

	if _music_player:
		_music_player.stop()
		_music_player.stream = null

	print("SoundController ready. SFX players: %d" % _sfx_players.size())


# ---------------------------------------------------------------------------
# Public API — Music
# ---------------------------------------------------------------------------

## Play a music track by name. Returns true if playback started.
func play_music(track_name: String) -> bool:
	_ensure_music_player()

	if not MUSIC_TRACKS.has(track_name):
		push_warning("Music track unknown: %s" % track_name)
		return false

	# Prevent restarting the same already-playing track.
	if _current_track_name == track_name and _music_player != null and _music_player.playing:
		return true

	var path: String = MUSIC_TRACKS[track_name]

	if not ResourceLoader.exists(path):
		push_warning("Music track file missing: %s" % track_name)
		return false

	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		push_warning("Music track could not be loaded: %s" % track_name)
		return false

	if _music_player == null:
		push_warning("SoundController: MusicPlayer not available.")
		return false

	# Stop any current playback — only affects _music_player.
	_music_player.stop()

	_music_player.stream = stream
	_music_player.play()
	_current_track_name = track_name
	music_started.emit(track_name)
	return true


## Stop the currently playing music.
## Never touches SFX players.
func stop_music() -> void:
	_ensure_music_player()

	if _music_player:
		_music_player.stop()
		_music_player.stream = null
	_current_track_name = ""
	music_stopped.emit()


## Return the name of the currently playing music track, or empty string.
func get_current_track_name() -> String:
	return _current_track_name


## Return a list of music track names whose audio files actually exist.
func get_available_tracks() -> Array:
	var available: Array[String] = []
	for track_name: String in MUSIC_TRACKS:
		var path: String = MUSIC_TRACKS[track_name]
		if ResourceLoader.exists(path):
			available.append(track_name)
	return available


# ---------------------------------------------------------------------------
# Public API — SFX
# ---------------------------------------------------------------------------

## Play a sound effect by name.
## Never touches _music_player. Uses only dedicated SFX player pool.
func play_sfx(sfx_name: String) -> void:
	# Defensive: ensure SFX players exist even if _ready() hasn't run yet.
	_ensure_sfx_players()

	if not SFX_TRACKS.has(sfx_name):
		push_warning("SFX unknown: %s" % sfx_name)
		return

	var path: String = SFX_TRACKS[sfx_name]

	if not ResourceLoader.exists(path):
		# Silent skip — missing SFX files must not crash the game.
		print("SFX file missing: %s — skipping." % sfx_name)
		return

	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		print("Failed to load SFX: %s" % sfx_name)
		return

	var player := _get_available_sfx_player()
	if player == null:
		push_warning("No SFX player available for: %s" % sfx_name)
		return

	player.stop()
	player.stream = stream
	player.play()
	sfx_played.emit(sfx_name)


# ---------------------------------------------------------------------------
# Internal helpers — Music
# ---------------------------------------------------------------------------

## Ensure MusicPlayer node exists and is in _music_player.
## Safe to call multiple times; returns immediately if already set up.
func _ensure_music_player() -> void:
	if _music_player != null and is_instance_valid(_music_player):
		return

	_music_player = get_node_or_null("MusicPlayer") as AudioStreamPlayer
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "MusicPlayer"
		add_child(_music_player)


# ---------------------------------------------------------------------------
# Internal helpers — SFX
# ---------------------------------------------------------------------------

## Ensure exactly 4 SFX player nodes (SFXPlayer1–4) exist and are in _sfx_players.
## Safe to call multiple times; does not re-create existing players.
## Never adds MusicPlayer to _sfx_players.
func _ensure_sfx_players() -> void:
	if _sfx_players.size() > 0:
		return

	for i in range(4):
		var player_name := "SFXPlayer%d" % (i + 1)
		var sfx_player := get_node_or_null(player_name) as AudioStreamPlayer

		if sfx_player == null:
			sfx_player = AudioStreamPlayer.new()
			sfx_player.name = player_name
			add_child(sfx_player)

		_sfx_players.append(sfx_player)


## Return an available (non-playing) SFX player from _sfx_players,
## or the first one if all are busy. Never returns _music_player.
func _get_available_sfx_player() -> AudioStreamPlayer:
	# Try to find a player that is not currently playing.
	for player: AudioStreamPlayer in _sfx_players:
		if not player.playing:
			return player

	# All players are busy; return the first one (will interrupt oldest SFX).
	if _sfx_players.size() > 0:
		return _sfx_players[0]

	return null


# ---------------------------------------------------------------------------
# Internal helpers — legacy (kept for compatibility)
# ---------------------------------------------------------------------------

## Legacy helper: find an AudioStreamPlayer child by name, or create one.
## Used by older code paths; new code should use _ensure_music_player()
## and _ensure_sfx_players() instead.
func _find_or_create_player(player_name: String) -> AudioStreamPlayer:
	for child: Node in get_children():
		if child is AudioStreamPlayer and child.name == player_name:
			return child
	# Not found — create one.
	var player := AudioStreamPlayer.new()
	player.name = player_name
	add_child(player)
	return player


# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

## Print current audio state to console for debugging.
func debug_audio_state() -> void:
	print("--- SoundController Debug ---")
	print("Music player valid: ", _music_player != null and is_instance_valid(_music_player))
	print("Music playing: ", _music_player != null and _music_player.playing)
	print("Current track: ", _current_track_name)
	print("SFX player count: ", _sfx_players.size())
	for i in range(_sfx_players.size()):
		var p := _sfx_players[i]
		print("SFX ", i, " valid: ", p != null and is_instance_valid(p), " playing: ", p.playing)
