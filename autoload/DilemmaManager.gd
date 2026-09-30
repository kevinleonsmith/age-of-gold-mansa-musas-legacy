# Dilemma events (res://autoload/DilemmaManager.gd)
# Data-driven historical dilemmas taken from the event scripts in ../:
# Salt Famine, Inflation Debate, Mosque Crisis and Tuareg Negotiation.
# Each fires at most once per session, with a gap between dilemmas.
# ui/DilemmaDialog shows the active dilemma; ui/Toasts (group "toasts") shows side messages.
extends Node

signal dilemma_started(dilemma_id: String)
signal dilemma_resolved(dilemma_id: String, option_index: int)
# Emitted right after dilemma_resolved with the speaker's reply to the choice.
signal dilemma_response(dilemma_id: String, speaker: String, text: String)

const RESOURCE_NODE_SCENE := "res://systems/ResourceNode.tscn"
const CAMEL_LANCER_SCENE := "res://entities/CamelLancer.tscn"
const ENEMY_SCENE := "res://entities/EnemyAI.tscn"
const SPAWN_KEY := "enemy_spawn_rate_mult"

const ORDER := ["salt_famine", "inflation_debate", "mosque_crisis", "tuareg_negotiation"]

# Gameplay durations in seconds (multiplied by duration_scale).
const SALT_A_DURATION := 120.0
const SALT_B_DELAY := 60.0
const SALT_C_DURATION := 60.0
const MOSQUE_A_INTERVAL := 30.0
const MOSQUE_B_DURATION := 90.0
const TUAREG_A_DURATION := 180.0

const COLOR_GOOD := Color(0.6, 1.0, 0.6)
const COLOR_BAD := Color(1.0, 0.55, 0.45)
const COLOR_INFO := Color(1.0, 0.9, 0.6)

# --- Tunables (tests shorten these) ---------------------------------------
var check_interval := 2.0
var min_gap := 90.0
var mosque_gap := 120.0
var mosque_chance := 0.25
var salt_threshold := 20
var salt_min_time := 180.0
var inflation_threshold := 1.75
var duration_scale := 1.0
var auto_triggers_enabled := true

# Unpaused seconds since the session started.
var game_time := 0.0
var rng := RandomNumberGenerator.new()
# {"id", "speaker", "text", "option"} of the last choice.
var last_response := {}

var _dilemmas := {}
var _active_id := ""
var _fired := {}
var _last_resolved_time := -1.0e9
var _check_left := 0.0
var _neutral_active := false
var _spawn_saved := 1.0
var _manuscript_timer: Timer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_build_dilemmas()
	_check_left = check_interval

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	game_time += delta
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = check_interval
		_evaluate_triggers()

# Clears session state: fired dilemmas, timers and pending effects.
func reset() -> void:
	_active_id = ""
	_fired.clear()
	last_response = {}
	game_time = 0.0
	_last_resolved_time = -1.0e9
	_check_left = check_interval
	_neutral_active = false
	_spawn_saved = 1.0
	if _manuscript_timer != null:
		_manuscript_timer.queue_free()
		_manuscript_timer = null

# --- Public API -----------------------------------------------------------

func is_active() -> bool:
	return _active_id != ""

func has_fired(dilemma_id: String) -> bool:
	return _fired.has(dilemma_id)

func get_dilemma_ids() -> Array:
	return ORDER.duplicate()

# Starts a dilemma now if none is active. Returns true if it started.
# Forcing ignores the cooldown and the once-per-session rule (debug / tests).
func trigger(dilemma_id: String) -> bool:
	if is_active() or not _dilemmas.has(dilemma_id):
		return false
	_build_dilemmas()
	_active_id = dilemma_id
	_fired[dilemma_id] = true
	dilemma_started.emit(dilemma_id)
	return true

# The active dilemma as display data, or {} if none. Options carry
# label, tag, cost, cost_text, summary, response, available and reason.
func get_active() -> Dictionary:
	if not is_active():
		return {}
	var d: Dictionary = _dilemmas[_active_id]
	var options := []
	for i in d.options.size():
		var opt: Dictionary = d.options[i]
		var reason := get_option_block_reason(i)
		options.append({
			"label": opt.label,
			"tag": opt.tag,
			"cost": opt.cost,
			"cost_text": _cost_text(opt),
			"summary": opt.summary,
			"response": opt.response,
			"available": reason == "",
			"reason": reason,
		})
	return {
		"id": _active_id,
		"title": d.title,
		"speaker": d.speaker,
		"line": d.line,
		"color": d.color,
		"options": options,
	}

# "" if the option can be chosen now, otherwise why not.
func get_option_block_reason(option_index: int) -> String:
	if not is_active():
		return "No active dilemma"
	var d: Dictionary = _dilemmas[_active_id]
	if option_index < 0 or option_index >= d.options.size():
		return "No such option"
	var opt: Dictionary = d.options[option_index]
	if opt.has("requires"):
		var req: String = (opt.requires as Callable).call()
		if req != "":
			return req
	if not opt.cost.is_empty() and not GameData.can_afford(opt.cost):
		return "Need " + GameData.format_cost(opt.cost)
	return ""

# Validates, pays, applies the option and emits dilemma_resolved + dilemma_response.
func choose(option_index: int) -> bool:
	if not is_active():
		return false
	var reason := get_option_block_reason(option_index)
	if reason != "":
		_toast(reason, COLOR_BAD)
		return false
	var d: Dictionary = _dilemmas[_active_id]
	var opt: Dictionary = d.options[option_index]
	if not opt.cost.is_empty() and not GameData.spend(opt.cost):
		return false
	var id := _active_id
	_active_id = ""
	_last_resolved_time = game_time
	(opt.effect as Callable).call()
	last_response = {"id": id, "speaker": d.speaker, "text": opt.response, "option": option_index}
	dilemma_resolved.emit(id, option_index)
	dilemma_response.emit(id, d.speaker, opt.response)
	if get_tree().get_first_node_in_group("dilemma_dialog") == null:
		_toast("%s: \"%s\"" % [d.speaker, opt.response], COLOR_INFO)
	return true

# --- Triggers -------------------------------------------------------------

func _evaluate_triggers() -> void:
	if not auto_triggers_enabled or is_active():
		return
	if game_time - _last_resolved_time < min_gap:
		return
	for id in ORDER:
		if _fired.has(id):
			continue
		if _condition_met(id):
			trigger(id)
			return

func _condition_met(id: String) -> bool:
	match id:
		"salt_famine":
			return GameData.salt < salt_threshold and game_time > salt_min_time
		"inflation_debate":
			var econ := _econ()
			return econ != null and float(econ.get("price_index")) >= inflation_threshold
		"mosque_crisis":
			if get_tree().get_nodes_in_group("building_mosque").is_empty():
				return false
			if game_time - maxf(_last_resolved_time, 0.0) < mosque_gap:
				return false
			return rng.randf() < mosque_chance
		"tuareg_negotiation":
			return AgeManager.is_unlocked(AgeManager.AGES.MALI_ASCENDANCY) \
				or not get_tree().get_nodes_in_group("caravans").is_empty()
	return false

# --- Dilemma data (wording from the event scripts) ------------------------

func _build_dilemmas() -> void:
	_dilemmas = {
		"salt_famine": {
			"title": "Salt Famine",
			"speaker": "Starving Villager",
			"color": Color(0.55, 0.45, 0.35),
			"line": "Great Mansa, our meat rots and children weaken!",
			"options": [
				{
					"label": "Raid coastal tribes", "tag": "Military", "cost": {},
					"summary": "+500 Salt; unhappy villagers: harvest -25%% for %d s" % _dur(SALT_A_DURATION),
					"response": "We survive... but at what cost?",
					"effect": _salt_a,
				},
				{
					"label": "Discover new mines", "tag": "Research", "cost": {},
					"summary": "Surveyors find a salt mine near you in %d s" % _dur(SALT_B_DELAY),
					"response": "Hope is salt to the soul...",
					"effect": _salt_b,
				},
				{
					"label": "Sell manuscripts", "tag": "Trade", "cost": {"manuscripts": 1},
					"summary": "1 Manuscript -> 100 Salt; cultural penalty: harvest -10%% for %d s" % _dur(SALT_C_DURATION),
					"response": "Trading wisdom for survival... a bitter meal.",
					"effect": _salt_c,
				},
			],
		},
		"inflation_debate": {
			"title": "Inflation Debate",
			"speaker": "Treasurer",
			"color": Color(0.85, 0.65, 0.15),
			"line": "The markets panic at our wealth! Prices spiral like desert winds!",
			"options": [
				{
					"label": "Flood the markets", "tag": "Lose Ingots", "cost": {},
					"cost_text": "Up to 20 Ingots",
					"summary": "Reset prices; unlock \"Economic Stabilization\" tech",
					"response": "The scales balance... for now.",
					"effect": _inflation_a,
				},
				{
					"label": "Let them starve", "tag": "Keep hoarding", "cost": {},
					"summary": "Rival treasuries lose 2500 gold; gain their gold mine; prices stay high",
					"response": "Their weakness becomes our strength!",
					"effect": _inflation_b,
				},
				{
					"label": "Build the Salt Cathedral", "tag": "Requires Age III", "cost": {"salt": 1000},
					"summary": "Convert 1000 Salt -> 1 Ingot; stabilize economy",
					"response": "Taghaza's might shall anchor the world!",
					"effect": _inflation_c,
					"requires": _requires_age_three,
				},
			],
		},
		"mosque_crisis": {
			"title": "Mosque Crisis",
			"speaker": "Advisor",
			"color": Color(0.2, 0.5, 0.35),
			"line": "Great Mansa, the infidels defile Allah's house! How shall we answer?",
			"options": [
				{
					"label": "Rebuild grander", "tag": "Diplomacy", "cost": {"gold": 300},
					"summary": "+1 Manuscript every %d s; 2 zealots (Camel Lancers) join your army" % _dur(MOSQUE_A_INTERVAL),
					"response": "Truly, from destruction comes divine renewal!",
					"effect": _mosque_a,
				},
				{
					"label": "Take their temples", "tag": "Military focus", "cost": {},
					"summary": "Griot conversion +15%%; enemy cities revolt: raids x1.5 for %d s" % _dur(MOSQUE_B_DURATION),
					"response": "Let their false gods tremble before the One!",
					"effect": _mosque_b,
				},
				{
					"label": "Send scholars, not soldiers", "tag": "Diplomacy", "cost": {},
					"summary": "Each enemy has a 50% chance to convert peacefully",
					"response": "The pen conquers where the sword fails, wise one!",
					"effect": _mosque_c,
				},
			],
		},
		"tuareg_negotiation": {
			"title": "Tuareg Negotiation",
			"speaker": "Chieftain",
			"color": Color(0.2, 0.3, 0.6),
			"line": "Your gold means nothing in the deep desert, Mansa. What can Mali offer the Sons of the Veil?",
			"options": [
				{
					"label": "Salt from Taghaza", "tag": "Trade", "cost": {"salt": 200},
					"summary": "Tuareg neutral: no raids for %d s; unlock hidden oasis" % _dur(TUAREG_A_DURATION),
					"response": "The white gold opens all paths. May your camels never thirst!",
					"effect": _tuareg_a,
				},
				{
					"label": "A share in Timbuktu's manuscripts", "tag": "Alliance", "cost": {"manuscripts": 1},
					"summary": "Tuareg allies: gain 2 Camel Lancers; caravans take 50% damage",
					"response": "Words outlive kings. We will guard your caravans.",
					"effect": _tuareg_b,
				},
				{
					"label": "The edge of my sword!", "tag": "Triggers combat", "cost": {},
					"summary": "5 Tuareg raiders attack; permanent -10% caravan speed",
					"response": "The sands will drink your blood as they did your wisdom!",
					"effect": _tuareg_c,
				},
			],
		},
	}

func _cost_text(opt: Dictionary) -> String:
	if opt.has("cost_text"):
		return opt.cost_text
	if opt.cost.is_empty():
		return "Free"
	return GameData.format_cost(opt.cost)

func _dur(seconds: float) -> int:
	return int(round(seconds * duration_scale))

func _requires_age_three() -> String:
	if not AgeManager.is_unlocked(AgeManager.AGES.GOLDEN_HAJJ):
		return "Requires Age III (Golden Hajj)"
	return ""

# --- Effects --------------------------------------------------------------

func _salt_a() -> void:
	GameData.add_resources({"salt": 500})
	_temp_mult("harvest_mult", 0.75, SALT_A_DURATION)
	_toast("+500 Salt. The villages grow restless: harvest -25%.", COLOR_BAD)

func _salt_b() -> void:
	_toast("Surveyors set out in search of new salt mines...", COLOR_INFO)
	_after(SALT_B_DELAY, _salt_b_discover)

func _salt_b_discover() -> void:
	_spawn_resource(1, 100, _near_player(220.0))
	_toast("New salt mine discovered nearby!", COLOR_GOOD)

func _salt_c() -> void:
	GameData.add_resources({"salt": 100})
	_temp_mult("harvest_mult", 0.9, SALT_C_DURATION)
	_toast("+100 Salt. Scholars mourn the lost wisdom: harvest -10%.", COLOR_BAD)

func _inflation_a() -> void:
	var lost := mini(GameData.ingots, 20)
	if lost > 0:
		GameData.spend({"ingots": lost})
	var econ := _econ()
	if econ != null and econ.has_method("reset_inflation"):
		econ.reset_inflation()
	var tech := get_node_or_null("/root/TechManager")
	if tech != null and tech.has_method("grant_tech"):
		tech.grant_tech("economic_stabilization")
	_toast("Markets flooded (-%d Ingots). Prices reset; Economic Stabilization unlocked." % lost, COLOR_GOOD)

func _inflation_b() -> void:
	var econ := _econ()
	if econ != null and econ.has_method("drain_rival_gold"):
		econ.drain_rival_gold(2500)
	_spawn_resource(0, 100, _near_player(260.0))
	_toast("Rival treasuries crumble. Their gold mine is ours!", COLOR_GOOD)

func _inflation_c() -> void:
	GameData.add_resources({"ingots": 1})
	var econ := _econ()
	if econ != null and econ.has_method("reset_inflation"):
		econ.reset_inflation()
	_toast("The Salt Cathedral anchors the economy: +1 Ingot, prices reset.", COLOR_GOOD)

func _mosque_a() -> void:
	if _manuscript_timer == null:
		_manuscript_timer = Timer.new()
		_manuscript_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
		_manuscript_timer.wait_time = maxf(MOSQUE_A_INTERVAL * duration_scale, 0.05)
		_manuscript_timer.timeout.connect(func() -> void: GameData.manuscripts += 1)
		add_child(_manuscript_timer)
		_manuscript_timer.start()
	for i in 2:
		_spawn_unit(CAMEL_LANCER_SCENE, _near_player(90.0), "")
	_toast("The mosque rises grander. Zealots join your army!", COLOR_GOOD)

func _mosque_b() -> void:
	GameData.multiply_modifier("conversion_speed_mult", 1.15)
	_temp_mult(SPAWN_KEY, 1.5, MOSQUE_B_DURATION)
	_toast("Conversion +15%. Enemy cities revolt: raids intensify!", COLOR_BAD)

func _mosque_c() -> void:
	var converted := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("convert_to_ally"):
			continue
		if rng.randf() < 0.5:
			enemy.convert_to_ally()
			converted += 1
	_toast("Scholars won over %d enemies peacefully." % converted, COLOR_GOOD)

func _tuareg_a() -> void:
	_start_neutral(TUAREG_A_DURATION)
	var oasis := _near_player(320.0)
	_spawn_resource(0, 100, oasis)
	_spawn_resource(1, 100, oasis + Vector2(90, 30))
	_toast("The Tuareg stand aside. A hidden oasis is revealed!", COLOR_GOOD)

func _tuareg_b() -> void:
	for i in 2:
		_spawn_unit(CAMEL_LANCER_SCENE, _near_player(90.0), "")
	GameData.multiply_modifier("caravan_damage_taken_mult", 0.5)
	_toast("Tuareg Camel Lancers guard your caravans.", COLOR_GOOD)

func _tuareg_c() -> void:
	var center := _player_pos()
	for i in 5:
		var pos := center + Vector2.RIGHT.rotated(TAU * i / 5.0) * 350.0
		_spawn_unit(ENEMY_SCENE, pos, "Enemies")
	GameData.multiply_modifier("caravan_speed_mult", 0.9)
	_toast("Tuareg raiders attack! Desert trade slows by 10%.", COLOR_BAD)

# --- Modifier helpers -----------------------------------------------------

# Multiplies a modifier now and undoes it after `seconds` of unpaused time.
func _temp_mult(key: String, factor: float, seconds: float) -> void:
	_mult(key, factor)
	_after(seconds, _mult.bind(key, 1.0 / factor))

# While the Tuareg are neutral the spawn modifier is pinned at 0; other
# multiplications of it go to the saved value and apply when neutrality ends.
func _mult(key: String, factor: float) -> void:
	if key == SPAWN_KEY and _neutral_active:
		_spawn_saved *= factor
	else:
		GameData.multiply_modifier(key, factor)

func _start_neutral(seconds: float) -> void:
	if not _neutral_active:
		_neutral_active = true
		_spawn_saved = GameData.get_modifier(SPAWN_KEY, 1.0)
		GameData.set_modifier(SPAWN_KEY, 0.0)
	_after(seconds, _end_neutral)

func _end_neutral() -> void:
	if not _neutral_active:
		return
	_neutral_active = false
	GameData.set_modifier(SPAWN_KEY, _spawn_saved)
	_toast("The Tuareg truce has ended.", COLOR_INFO)

# Calls `callback` after `seconds` (scaled) of unpaused game time.
# Skipped if a new game started in the meantime (GameData.reset()).
func _after(seconds: float, callback: Callable) -> void:
	var generation := GameData.generation
	get_tree().create_timer(maxf(seconds * duration_scale, 0.01), false).timeout.connect(
		func() -> void:
			if generation == GameData.generation:
				callback.call())

# --- World helpers --------------------------------------------------------

func _econ() -> Node:
	return get_node_or_null("/root/EconomyManager")

func _player_pos() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	return player.global_position if player != null else Vector2(576, 324)

func _near_player(distance: float) -> Vector2:
	return _player_pos() + Vector2.RIGHT.rotated(rng.randf() * TAU) * distance

func _spawn_unit(path: String, pos: Vector2, container: String) -> Node:
	return _spawn(load(path) as PackedScene, pos, container, {})

func _spawn_resource(type: int, quantity: int, pos: Vector2) -> Node:
	return _spawn(load(RESOURCE_NODE_SCENE) as PackedScene, pos, "Resources",
		{"resource_type": type, "quantity": quantity})

func _spawn(scene: PackedScene, pos: Vector2, container: String, props: Dictionary) -> Node:
	var world := get_tree().current_scene
	if world == null or scene == null:
		return null
	var parent: Node = world.get_node_or_null(container) if container != "" else null
	if parent == null:
		parent = world
	var node := scene.instantiate()
	for key in props:
		node.set(key, props[key])
	if node is Node2D:
		node.position = (parent as Node2D).to_local(pos) if parent is Node2D else pos
	parent.add_child(node)
	return node

func _toast(text: String, color := Color.WHITE) -> void:
	var toasts := get_tree().get_first_node_in_group("toasts")
	if toasts != null and toasts.has_method("show_toast"):
		toasts.show_toast(text, color)
