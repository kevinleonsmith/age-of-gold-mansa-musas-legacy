# Sound effects and music (res://autoload/AudioManager.gd)
# Public API (shared contract): play_sfx(name, at = null), play_music(track), reset().
# Unknown sound / track names are ignored silently, so any system may call it.
#
# - SFX: a fixed pool of AudioStreamPlayer2D on the "SFX" bus. Positional sounds
#   (`at` is a Vector2 in world coordinates) fade out linearly to silence at
#   HEAR_RADIUS px from the listener (camera centre) and are panned; the others
#   play centred at full volume. Identical sounds are rate-limited and capped at
#   MAX_PER_NAME concurrent voices; when the pool is full the oldest voice is reused.
# - Music: two AudioStreamPlayers on the "Music" bus, crossfaded over CROSSFADE s.
#   The loops are set to LOOP_FORWARD in their .import files (and here as a fallback).
# - Hooks: age/tech/dilemma/ingot/victory signals, plus get_tree().node_added for
#   button clicks, new buildings, caravan deliveries and enemy conversions.
# - The M key toggles mute of the Master bus (raw key event in _unhandled_input).
# Runs with PROCESS_MODE_ALWAYS so music continues in menus and while paused.
extends Node

signal sfx_played(sfx_name: String)
signal music_changed(track_name: String)

const SFX_NAMES := ["hit", "death", "build_place", "research_done", "age_up", "coin",
	"caravan_deliver", "dilemma_open", "convert", "click", "victory", "defeat", "horn", "error"]
const TRACK_NAMES := ["menu", "sand_chiefdoms", "mali_ascendancy", "golden_hajj"]
# Music per AgeManager.AGES value.
const AGE_TRACKS := ["sand_chiefdoms", "mali_ascendancy", "golden_hajj"]
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"

const POOL_SIZE := 12
const MAX_PER_NAME := 4
# Minimum gap between two plays of the same sound (ms). The default also
# collapses a sound triggered twice in one frame (e.g. a direct call + a hook).
const MIN_INTERVAL_MS := {"hit": 60, "click": 40, "coin": 50}
const DEFAULT_MIN_INTERVAL_MS := 35
const HEAR_RADIUS := 900.0
const CROSSFADE := 1.5
const SILENT_DB := -60.0
# Per-sound trim (dB) on top of the normalized files.
const SFX_TRIM_DB := {"click": -6.0, "hit": -3.0, "coin": -3.0, "death": -2.0}
# Frames after a scene change during which new buildings are scene setup, not placements.
const SCENE_SETTLE_FRAMES := 10

var music_volume_db := 0.0 # level of the active music player (bus volume is separate)
var last_sfx := "" # debug: the last sound actually started
var current_track := ""
var muted := false

var _sfx_streams := {}
var _music_streams := {}
var _pool: Array[AudioStreamPlayer2D] = []
var _voice_name: Array[String] = []
var _voice_end_ms: Array[int] = []
var _voice_start_ms: Array[int] = []
var _last_play_ms := {}
var _music_players: Array[AudioStreamPlayer] = []
var _active_music := 0
var _music_tween: Tween
var _last_age := 0
var _last_ingots := 0
var _known_scene: Node = null
var _scene_frame := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load_streams()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.name = "Sfx%d" % i
		p.bus = &"SFX"
		p.max_distance = HEAR_RADIUS
		p.attenuation = 1.0
		p.finished.connect(_on_voice_finished.bind(i))
		add_child(p)
		_pool.append(p)
		_voice_name.append("")
		_voice_end_ms.append(0)
		_voice_start_ms.append(0)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.name = "Music%d" % i
		m.bus = &"Music"
		m.volume_db = SILENT_DB
		add_child(m)
		_music_players.append(m)
	get_tree().node_added.connect(_on_node_added)
	_connect_hooks.call_deferred()

# --- Public API ---------------------------------------------------------------

func reset() -> void:
	_last_play_ms.clear()
	_last_age = 0
	var gd := get_node_or_null("/root/GameData")
	_last_ingots = int(gd.ingots) if gd else 0
	play_music(AGE_TRACKS[0])

func play_sfx(sfx_name: String, at: Variant = null) -> void:
	var stream: AudioStream = _sfx_streams.get(sfx_name)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	var gap: int = MIN_INTERVAL_MS.get(sfx_name, DEFAULT_MIN_INTERVAL_MS)
	if _last_play_ms.has(sfx_name) and now - int(_last_play_ms[sfx_name]) < gap:
		return
	if count_playing(sfx_name) >= MAX_PER_NAME:
		return
	var listener := _listener_position()
	var positional := at is Vector2
	if positional and listener.distance_to(at) >= HEAR_RADIUS:
		return
	var slot := _free_voice(now)
	var p := _pool[slot]
	p.stop()
	p.stream = stream
	p.volume_db = SFX_TRIM_DB.get(sfx_name, 0.0)
	if positional:
		p.global_position = at
		p.max_distance = HEAR_RADIUS
		p.panning_strength = 1.0
	else:
		p.global_position = listener
		p.max_distance = 1.0e7
		p.panning_strength = 0.0
	p.pitch_scale = randf_range(0.96, 1.04) if sfx_name in ["hit", "coin", "click", "death"] else 1.0
	p.play()
	_voice_name[slot] = sfx_name
	_voice_start_ms[slot] = now
	_voice_end_ms[slot] = now + int(stream.get_length() * 1000.0 / p.pitch_scale) + 20
	_last_play_ms[sfx_name] = now
	last_sfx = sfx_name
	sfx_played.emit(sfx_name)

func play_music(track_name: String) -> void:
	var stream: AudioStream = _music_streams.get(track_name)
	if stream == null:
		return
	if track_name == current_track and _music_players[_active_music].playing:
		return
	current_track = track_name
	var old := _music_players[_active_music]
	_active_music = 1 - _active_music
	var incoming := _music_players[_active_music]
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	incoming.stop()
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	_music_tween = create_tween()
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", music_volume_db, CROSSFADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if old.playing:
		_music_tween.tween_property(old, "volume_db", SILENT_DB, CROSSFADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_music_tween.chain().tween_callback(_stop_if_inactive.bind(old))
	music_changed.emit(track_name)

func stop_music() -> void:
	current_track = ""
	for m in _music_players:
		m.stop()

func set_music_volume(db: float) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)

func set_sfx_volume(db: float) -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)

func toggle_mute() -> void:
	set_muted(not muted)

func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(0, muted)

func has_sfx(sfx_name: String) -> bool:
	return _sfx_streams.has(sfx_name)

func get_sfx_stream(sfx_name: String) -> AudioStream:
	return _sfx_streams.get(sfx_name)

func get_music_stream(track_name: String) -> AudioStream:
	return _music_streams.get(track_name)

# Voices of `sfx_name` currently sounding (own bookkeeping: works headless too).
func count_playing(sfx_name: String) -> int:
	var now := Time.get_ticks_msec()
	var n := 0
	for i in _pool.size():
		if _voice_name[i] == sfx_name and now < _voice_end_ms[i]:
			n += 1
	return n

func get_pool_size() -> int:
	return _pool.size()

func get_busy_voices() -> int:
	var now := Time.get_ticks_msec()
	var n := 0
	for i in _pool.size():
		if _voice_name[i] != "" and now < _voice_end_ms[i]:
			n += 1
	return n

# Music track for the current age.
func get_age_track() -> String:
	var am := get_node_or_null("/root/AgeManager")
	var age := int(am.current_age) if am else 0
	return AGE_TRACKS[clampi(age, 0, AGE_TRACKS.size() - 1)]

# --- Input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and (key.keycode == KEY_M or key.physical_keycode == KEY_M):
		toggle_mute()
		get_viewport().set_input_as_handled()

# --- Internals -------------------------------------------------------------------

func _process(_delta: float) -> void:
	_check_scene()

func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")

func _load_streams() -> void:
	for n in SFX_NAMES:
		var s := _load_wav(SFX_DIR + n + ".wav")
		if s:
			_sfx_streams[n] = s
	for n in TRACK_NAMES:
		var s := _load_wav(MUSIC_DIR + n + ".wav")
		if s:
			# Loop points normally come from the .import file (edit/loop_mode=2);
			# enforce them here too in case the import settings were reset.
			if s is AudioStreamWAV and s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_begin = 0
				s.loop_end = int(round(s.get_length() * s.mix_rate))
			_music_streams[n] = s

func _load_wav(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream

func _free_voice(now: int) -> int:
	var oldest := 0
	for i in _pool.size():
		if _voice_name[i] == "" or now >= _voice_end_ms[i]:
			return i
		if _voice_start_ms[i] < _voice_start_ms[oldest]:
			oldest = i
	return oldest # steal the oldest voice

func _on_voice_finished(slot: int) -> void:
	_voice_name[slot] = ""
	_voice_end_ms[slot] = 0

func _stop_if_inactive(player) -> void:
	if is_instance_valid(player) and player != _music_players[_active_music]:
		player.stop()

func _listener_position() -> Vector2:
	var vp := get_viewport()
	if vp:
		var cam := vp.get_camera_2d()
		if cam and cam.is_inside_tree():
			return cam.get_screen_center_position()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		return player.global_position
	if vp:
		return vp.get_visible_rect().size / 2.0
	return Vector2.ZERO

func _connect_hooks() -> void:
	var am := get_node_or_null("/root/AgeManager")
	if am:
		_last_age = int(am.current_age)
		am.age_changed.connect(_on_age_changed)
	var tm := get_node_or_null("/root/TechManager")
	if tm and tm.has_signal("tech_researched"):
		tm.tech_researched.connect(_on_tech_researched)
	var dm := get_node_or_null("/root/DilemmaManager")
	if dm and dm.has_signal("dilemma_started"):
		dm.dilemma_started.connect(_on_dilemma_started)
	var gd := get_node_or_null("/root/GameData")
	if gd and gd.has_signal("ingots_changed"):
		_last_ingots = int(gd.ingots)
		gd.ingots_changed.connect(_on_ingots_changed)
	var vm := get_node_or_null("/root/VictoryManager")
	if vm:
		if vm.has_signal("game_won"):
			vm.game_won.connect(_on_game_won)
		if vm.has_signal("game_lost"):
			vm.game_lost.connect(_on_game_lost)
	_check_scene()

func _on_age_changed(new_age) -> void:
	var age := int(new_age)
	if age > _last_age:
		play_sfx("age_up")
	_last_age = age
	play_music(AGE_TRACKS[clampi(age, 0, AGE_TRACKS.size() - 1)])

func _on_tech_researched(_tech_id) -> void:
	play_sfx("research_done")

func _on_dilemma_started(_dilemma_id) -> void:
	play_sfx("dilemma_open")

func _on_ingots_changed(new_value) -> void:
	if int(new_value) > _last_ingots:
		play_sfx("coin")
	_last_ingots = int(new_value)

func _on_game_won(_a = null, _b = null, _c = null) -> void:
	play_sfx("victory")

func _on_game_lost(_a = null, _b = null, _c = null) -> void:
	play_sfx("defeat")

# Picks the music when the current scene changes: the age track in a gameplay
# scene (one with a "player" node), the menu track otherwise.
func _check_scene() -> void:
	var tree := get_tree()
	var scene := tree.current_scene
	if scene == null or scene == _known_scene or not scene.is_inside_tree():
		return
	_known_scene = scene
	_scene_frame = Engine.get_process_frames()
	if tree.get_first_node_in_group("player") != null:
		play_music(get_age_track())
	else:
		play_music("menu")

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		if not node.pressed.is_connected(_on_button_pressed):
			node.pressed.connect(_on_button_pressed)
	elif node is Node2D and node.get_parent() != self:
		# Groups and signals are set up in _ready(): inspect once it has run.
		_inspect_node.call_deferred(node)

func _inspect_node(node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	_check_scene()
	if node.is_in_group("buildings"):
		# Buildings present when a scene loads are scenery, not placements.
		if Engine.get_process_frames() - _scene_frame > SCENE_SETTLE_FRAMES:
			play_sfx("build_place", node.global_position)
	if node.is_in_group("caravans") and node.has_signal("cargo_delivered"):
		_connect_once(node, "cargo_delivered", _on_caravan_delivered)
	if node.has_signal("converted"):
		_connect_once(node, "converted", _on_unit_converted.bind(node))

# Connects `callable` to `signal_name` whatever the signal's argument count
# (extra arguments are dropped).
func _connect_once(obj: Object, signal_name: String, callable: Callable) -> void:
	var argc := 0
	for s in obj.get_signal_list():
		if s.name == signal_name:
			argc = s.args.size()
			break
	var c := callable.unbind(argc) if argc > 0 else callable
	for conn in obj.get_signal_connection_list(signal_name):
		if conn.callable.get_method() == callable.get_method():
			return
	obj.connect(signal_name, c)

func _on_button_pressed() -> void:
	play_sfx("click")

func _on_caravan_delivered() -> void:
	play_sfx("caravan_deliver")

func _on_unit_converted(unit) -> void:
	if is_instance_valid(unit) and unit is Node2D:
		play_sfx("convert", unit.global_position)
	else:
		play_sfx("convert")
