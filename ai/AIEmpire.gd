# One AI rival empire (res://ai/AIEmpire.gd)
# Used by the single-player versions of the design doc's multiplayer modes
# (modes/Showdown, modes/Scholars). Networked multiplayer is out of scope:
# the player's state lives in global autoloads, so the other three "players"
# are AI empires, each with its OWN gold / salt / manuscripts (separate from
# GameData) and its own camps, libraries, workers and raiders.
#
# Split between state/actions and decisions so another controller can drive
# an empire: this node owns the state and exposes the actions
# (train_worker, assign_worker, build_camp, build_library, train_raider,
# assign_guard, launch_attack, start_research). Every `decision_interval`
# seconds it calls `controller.decide(self)`; the default controller is
# ai/AIController.gd. A future human / network player would set `controller`
# to an object that turns their commands into the same action calls (or
# null and call the actions directly).
#
# Simplification: AI empires are hostile to the player only. They never fight
# each other (their raiders all live in "enemies" and hunt "allies"), and
# their controllers avoid nodes another AI has already claimed.
#
# Fast-forward for tests: tick(seconds) runs income, research, decisions and
# worker movement in 0.5 s steps; the `time_scale` export speeds up real time.
class_name AIEmpire
extends Node

signal resources_changed
signal tech_completed(count: int)
signal camp_built(camp)
signal raider_trained(raider)
signal attack_launched(count: int)
signal empire_eliminated

# Presets by empire_id: name, capital, colour and the asset key for its
# banner / node flag (assets/ai/banner_<key>.png, flag_<key>.png).
const EMPIRES := {
	1: {"name": "Songhai", "capital": "Gao", "key": "songhai", "color": Color(0.85, 0.22, 0.2)},
	2: {"name": "Mossi", "capital": "Yatenga", "key": "mossi", "color": Color(0.26, 0.68, 0.32)},
	3: {"name": "Tuareg", "capital": "Kel Adrar", "key": "tuareg", "color": Color(0.3, 0.44, 0.9)},
}

const CAMP_SCENE := preload("res://rival/WarCamp.tscn")
const WORKER_SCENE := preload("res://ai/AIWorker.tscn")
const LIBRARY_SCENE := preload("res://ai/AILibrary.tscn")

# Costs (paid from the empire's own resources).
const WORKER_COST := {"gold": 60}
const CAMP_COST := {"gold": 220, "salt": 25}
const RAIDER_COST := {"gold": 45}
const LIBRARY_COST := {"gold": 160, "salt": 30}
const TECH_MANUSCRIPTS := 3

# Income at difficulty "normal" (multiplied by the profile's "income").
const PASSIVE_GOLD := 2.0 # per second
const WORKER_GOLD := 3.0 # per second per worker at a gold node
const WORKER_SALT := 2.5 # per second per worker at a salt node
const LIBRARY_MANUSCRIPT_TIME := 30.0 # seconds per manuscript per library
const NODE_MANUSCRIPT_TIME := 90.0 # seconds per manuscript per controlled node
# A node is contested (no AI income) while a player unit is this close.
const CONTEST_RADIUS := 150.0
const MAX_RAIDERS_PER_CAMP := 6
const STEP := 0.5

@export_range(1, 3) var empire_id := 1
@export var empire_name := "" # "" = preset name
@export var capital_name := ""
@export var color := Color(0, 0, 0, 0) # alpha 0 = preset colour
@export var home_position := Vector2.ZERO
# "auto" = use AISettings.difficulty (chosen in ui/ModeSelect). Holds the
# resolved level after _ready.
@export_enum("auto", "easy", "normal", "hard") var difficulty := "auto"
# "showdown" or "scholars": shifts the default controller's priorities.
@export var mode := "showdown"
@export var time_scale := 1.0
@export var decision_interval := 2.0
@export var start_gold := 300
@export var start_salt := 60
@export var start_manuscripts := 0
@export var start_workers := 2
# How far from home the default controller looks for nodes (grows over time).
@export var claim_radius := 1100.0
# Where the world nodes go: "" = the current scene's "AIBases" (or this node's parent).
@export var world_parent_path: NodePath

var gold := 0.0
var salt := 0.0
var manuscripts := 0.0
var techs_completed := 0
var research_active := false
var research_elapsed := 0.0
var elapsed := 0.0
var eliminated := false
var nodes_controlled := 0 # kept up to date by ai/NodeControl.gd
var camps: Array = []
var libraries: Array = []
var workers: Array = []
var raiders: Array = [] # raiders this empire trained (may hold freed nodes)
var controller = null # has decide(empire); see ai/AIController.gd
var attack_cooldown_left := 0.0
var profile := {}
var base_node: Node2D # y-sorted container for this empire's world nodes
var rng := RandomNumberGenerator.new()
var _decision_left := 0.0
var _had_camp := false
var _setup_done := false
var _skip_default_setup := false

func _ready() -> void:
	add_to_group("ai_empires")
	var preset: Dictionary = EMPIRES.get(empire_id, EMPIRES[1])
	if empire_name == "":
		empire_name = preset["name"]
	if capital_name == "":
		capital_name = preset["capital"]
	if color.a <= 0.0:
		color = preset["color"]
	rng.seed = 1324 + empire_id * 97
	set_difficulty(difficulty)
	if controller == null:
		controller = load("res://ai/AIController.gd").new()
	_setup.call_deferred()

func get_key() -> String:
	return EMPIRES.get(empire_id, EMPIRES[1])["key"]

func get_display_name() -> String:
	return "%s (%s)" % [empire_name, capital_name]

# Resolves "auto" / "" to AISettings.difficulty and loads the tuning profile.
func set_difficulty(level: String) -> void:
	var settings := load("res://ai/AISettings.gd")
	difficulty = settings.normalized(settings.difficulty if level in ["", "auto"] else level)
	profile = settings.profile(difficulty)
	# The first wave waits a little longer than the later ones.
	attack_cooldown_left = float(profile["attack_cooldown"]) + 60.0

func _setup() -> void:
	if _setup_done or not is_inside_tree():
		return
	_setup_done = true
	_ensure_base()
	if _skip_default_setup:
		return
	gold = start_gold
	salt = start_salt
	manuscripts = start_manuscripts
	build_camp(home_position + Vector2(0, 90), true)
	for i in start_workers:
		train_worker(true)
	resources_changed.emit()

func _ensure_base() -> void:
	if is_instance_valid(base_node):
		return
	var parent: Node = get_node_or_null(world_parent_path) if not world_parent_path.is_empty() else null
	if parent == null:
		var scene := get_tree().current_scene
		parent = scene.get_node_or_null("AIBases") if scene != null else null
	if parent == null:
		parent = get_parent()
	base_node = Node2D.new()
	base_node.name = empire_name + "Base"
	base_node.y_sort_enabled = true
	parent.add_child(base_node)
	var banner := Sprite2D.new()
	banner.name = "Banner"
	banner.texture = load("res://assets/ai/banner_%s.png" % get_key())
	banner.offset = Vector2(0, -36)
	banner.position = home_position
	base_node.add_child(banner)

# --- Clock ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if _setup_done:
		_step(delta * time_scale, false)

# Fast-forwards `seconds` of game time (tests): income, research, decisions
# and worker walking, in STEP-sized slices.
func tick(seconds: float) -> void:
	if not _setup_done:
		_setup()
	var left := seconds
	while left > 0.0:
		var s := minf(left, STEP)
		_step(s, true)
		left -= s

func _step(dt: float, move_workers: bool) -> void:
	if eliminated or dt <= 0.0 or VictoryManager.is_game_over:
		return
	elapsed += dt
	attack_cooldown_left = maxf(attack_cooldown_left - dt, 0.0)
	_prune()
	if move_workers:
		for w in workers:
			w.advance(dt)
	_earn(dt)
	_advance_research(dt)
	_check_eliminated()
	if eliminated:
		return
	_decision_left -= dt
	while _decision_left <= 0.0:
		_decision_left += decision_interval
		if controller != null and controller.has_method("decide"):
			controller.decide(self)

# --- Economy --------------------------------------------------------------------

func income_mult() -> float:
	return float(profile.get("income", 1.0))

func _earn(dt: float) -> void:
	var mult := income_mult()
	gold += PASSIVE_GOLD * mult * dt
	for w in workers:
		if not w.is_harvesting() or is_contested(w.target_node):
			continue
		if int(w.target_node.resource_type) == 1: # ResourceNode.RESOURCE_TYPE.SALT
			salt += WORKER_SALT * mult * dt
		else:
			gold += WORKER_GOLD * mult * dt
	var libs := living(libraries).size()
	manuscripts += (libs / LIBRARY_MANUSCRIPT_TIME + nodes_controlled / NODE_MANUSCRIPT_TIME) * mult * dt
	resources_changed.emit()

# True if a living player-side unit ("allies") stands within CONTEST_RADIUS of node.
func is_contested(node) -> bool:
	if not is_instance_valid(node):
		return true
	for unit in get_tree().get_nodes_in_group("allies"):
		if not (unit is Node2D) or unit.get("is_dead") == true:
			continue
		if unit.global_position.distance_to(node.global_position) <= CONTEST_RADIUS:
			return true
	return false

func can_afford(cost: Dictionary) -> bool:
	for key in cost:
		if float(get(key)) < float(cost[key]):
			return false
	return true

func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for key in cost:
		set(key, float(get(key)) - float(cost[key]))
	resources_changed.emit()
	return true

# --- Actions (called by the controller) ------------------------------------------

func train_worker(free := false) -> Node2D:
	if eliminated or (not free and not spend(WORKER_COST)):
		return null
	_ensure_base()
	var worker := WORKER_SCENE.instantiate() as Node2D
	worker.position = home_position + Vector2(rng.randf_range(-40, 40), rng.randf_range(20, 60))
	base_node.add_child(worker)
	worker.empire = self
	worker.empire_id = empire_id
	worker.time_scale = time_scale
	_tag(worker)
	workers.append(worker)
	return worker

# Untyped: `node` may be freed later.
func assign_worker(worker, node) -> void:
	if not is_instance_valid(worker):
		return
	_release_claim(worker.target_node)
	worker.assign(node)
	if is_instance_valid(node):
		node.set_meta("ai_claimed_by", empire_id)

func _release_claim(node) -> void:
	if not is_instance_valid(node) or int(node.get_meta("ai_claimed_by", 0)) != empire_id:
		return
	for w in workers:
		if w.target_node == node:
			return
	node.remove_meta("ai_claimed_by")

# Builds a War Camp (rival/WarCamp.tscn) near home, or at `pos`. The camp never
# spawns on its own timer: the empire trains raiders into it (train_raider).
func build_camp(pos = null, free := false) -> Node2D:
	if eliminated or (not free and not spend(CAMP_COST)):
		return null
	_ensure_base()
	var camp := CAMP_SCENE.instantiate() as Node2D
	camp.spawn_interval = 1.0e9
	camp.wave_size = 999
	camp.max_raiders = MAX_RAIDERS_PER_CAMP
	camp.position = pos if pos is Vector2 else _free_spot()
	base_node.add_child(camp)
	_tag(camp)
	camps.append(camp)
	_had_camp = true
	camp_built.emit(camp)
	return camp

func build_library(pos = null, free := false) -> Node2D:
	if eliminated or (not free and not spend(LIBRARY_COST)):
		return null
	_ensure_base()
	var lib := LIBRARY_SCENE.instantiate() as Node2D
	lib.position = pos if pos is Vector2 else _free_spot()
	base_node.add_child(lib)
	lib.empire_id = empire_id
	_tag(lib)
	libraries.append(lib)
	return lib

# Trains one raider at `camp` (default: the camp with the fewest raiders).
func train_raider(camp = null) -> Node2D:
	if eliminated:
		return null
	if camp == null:
		for c in living(camps):
			if c.can_spawn() and (camp == null or c.living_raider_count() < camp.living_raider_count()):
				camp = c
	if living_raiders().size() >= int(profile.get("max_raiders", 8)):
		return null
	if camp == null or not is_instance_valid(camp) or not camp.can_spawn() or not can_afford(RAIDER_COST):
		return null
	var raider: Node2D = camp.spawn_raider()
	if raider == null:
		return null
	spend(RAIDER_COST)
	_tag(raider)
	raider.remove_from_group("camp_raiders")
	raider.set_meta("ai_raider", true)
	if raider.has_signal("converted"):
		raider.converted.connect(_untag.bind(raider))
	raiders.append(raider)
	raider_trained.emit(raider)
	return raider

# Stations a raider at a node so it counts toward controlling it.
func assign_guard(raider, node) -> void:
	if not is_instance_valid(raider) or not is_instance_valid(node):
		return
	raider.set_meta("guard_node", node)
	raider.is_marching = false
	raider.patrol_range = 50.0
	raider.home_position = node.global_position + Vector2(rng.randf_range(-40, 40), rng.randf_range(30, 60))
	raider.start_patrol()

func free_raiders() -> Array:
	return living_raiders().filter(func(r): return not r.is_marching and not _is_guard(r))

func guards() -> Array:
	return living_raiders().filter(_is_guard)

func _is_guard(r) -> bool:
	return r.has_meta("guard_node") and is_instance_valid(r.get_meta("guard_node"))

# Sends every free raider marching on the player's base. Returns the count.
func launch_attack() -> int:
	var sent := 0
	for r in free_raiders():
		r.start_march()
		sent += 1
	if sent > 0:
		attack_cooldown_left = float(profile["attack_cooldown"])
		attack_launched.emit(sent)
	return sent

func can_start_research() -> bool:
	return not eliminated and not research_active and manuscripts >= TECH_MANUSCRIPTS

func start_research() -> bool:
	if not can_start_research() or not spend({"manuscripts": TECH_MANUSCRIPTS}):
		return false
	research_active = true
	research_elapsed = 0.0
	return true

func research_time() -> float:
	return float(profile.get("research_time", 95.0))

func research_progress() -> float:
	return clampf(research_elapsed / research_time(), 0.0, 1.0) if research_active else 0.0

func _advance_research(dt: float) -> void:
	if not research_active:
		return
	research_elapsed += dt
	if research_elapsed >= research_time():
		research_active = false
		research_elapsed = 0.0
		techs_completed += 1
		tech_completed.emit(techs_completed)

# --- Queries --------------------------------------------------------------------

# Filters out freed / destroyed / dead nodes. Untyped elements on purpose.
static func living(list: Array) -> Array:
	return list.filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion() \
		and n.get("is_dead") != true and n.get("is_destroyed") != true)

func living_raiders() -> Array:
	return living(raiders).filter(func(r): return r.is_in_group("enemies"))

func living_camps() -> Array:
	return living(camps)

func get_score() -> int:
	return nodes_controlled * 100 + int(gold) / 10 + techs_completed * 150

func _prune() -> void:
	camps = living(camps)
	libraries = living(libraries)
	workers = living(workers)
	raiders = living_raiders()

func _check_eliminated() -> void:
	if eliminated or not _had_camp or not living(camps).is_empty():
		return
	eliminated = true
	research_active = false
	for w in workers:
		_release_claim(w.target_node)
		w.queue_free()
	workers.clear()
	empire_eliminated.emit()

# A spot near home at least 110 px from this empire's other buildings.
func _free_spot() -> Vector2:
	var taken := living(camps) + living(libraries)
	var best := home_position + Vector2(0, 160)
	for attempt in 24:
		var p := home_position + Vector2(rng.randf_range(-280, 280), rng.randf_range(-200, 220))
		var ok := p.distance_to(home_position) > 90.0
		for b in taken:
			if b.global_position.distance_to(p) < 110.0:
				ok = false
				break
		if ok:
			return p
	return best

# Marks a node as this empire's (groups, meta, colour tint via modulate).
func _tag(node: Node) -> void:
	var is_building := node.has_method("get_footprint_rect")
	node.add_to_group("ai_buildings" if is_building else "ai_units")
	node.add_to_group("ai_empire_%d" % empire_id)
	node.set_meta("empire_id", empire_id)
	var robe := node.get_node_or_null("Robe") as CanvasItem
	var sprite := node.get_node_or_null("Sprite2D") as CanvasItem
	if robe != null: # worker: only the pale robe takes the colour
		robe.modulate = color.lerp(Color.WHITE, 0.2)
	elif sprite != null:
		sprite.modulate = color.lerp(Color.WHITE, 0.45 if is_building else 0.3)

# A raider converted by a griot stops counting for this empire.
func _untag(raider) -> void:
	if not is_instance_valid(raider):
		return
	raider.remove_from_group("ai_units")
	raider.remove_from_group("ai_empire_%d" % empire_id)
	raider.remove_meta("empire_id")
	raider.remove_meta("guard_node")
	raiders.erase(raider)

# --- Save / load ----------------------------------------------------------------

static func _positions(list: Array) -> Array:
	var out := []
	for n in living(list):
		out.append({"pos": n.global_position, "health": float(n.health)})
	return out

func get_save_state() -> Dictionary:
	var guard_count := guards().size()
	return {
		"empire_id": empire_id,
		"difficulty": difficulty,
		"gold": gold, "salt": salt, "manuscripts": manuscripts,
		"techs_completed": techs_completed,
		"research_active": research_active,
		"research_elapsed": research_elapsed,
		"elapsed": elapsed,
		"eliminated": eliminated,
		"had_camp": _had_camp,
		"attack_cooldown_left": attack_cooldown_left,
		"camps": _positions(camps),
		"libraries": _positions(libraries),
		"workers": _positions(workers),
		"raiders": _positions(living_raiders()),
		"guards": guard_count,
	}

func load_save_state(d: Dictionary) -> void:
	if not _setup_done:
		_skip_default_setup = true
		_setup()
	set_difficulty(String(d.get("difficulty", difficulty)))
	for list in [camps, libraries, workers, living_raiders()]:
		for n in living(list):
			if n in workers:
				_release_claim(n.target_node)
			n.queue_free()
	camps.clear()
	libraries.clear()
	workers.clear()
	raiders.clear()
	gold = float(d.get("gold", 0.0))
	salt = float(d.get("salt", 0.0))
	manuscripts = float(d.get("manuscripts", 0.0))
	techs_completed = int(d.get("techs_completed", 0))
	research_active = bool(d.get("research_active", false))
	research_elapsed = float(d.get("research_elapsed", 0.0))
	elapsed = float(d.get("elapsed", 0.0))
	eliminated = bool(d.get("eliminated", false))
	attack_cooldown_left = float(d.get("attack_cooldown_left", 0.0))
	for entry in d.get("camps", []):
		var camp := build_camp(entry["pos"], true)
		if camp != null:
			camp.health = float(entry.get("health", camp.max_health))
	_had_camp = bool(d.get("had_camp", _had_camp))
	for entry in d.get("libraries", []):
		var lib := build_library(entry["pos"], true)
		if lib != null:
			lib.health = float(entry.get("health", lib.max_health))
	for entry in d.get("workers", []):
		var w := train_worker(true)
		if w != null:
			w.position = entry["pos"]
	for entry in d.get("raiders", []):
		var r := _restore_raider(entry["pos"])
		if r != null:
			r.health = float(entry.get("health", r.max_health))
	resources_changed.emit()

func _restore_raider(pos: Vector2) -> Node2D:
	if eliminated:
		return null
	var scene := get_tree().current_scene
	var container: Node = scene.get_node_or_null("Enemies") if scene != null else null
	if container == null:
		container = base_node
	var raider := (load("res://entities/EnemyAI.tscn") as PackedScene).instantiate() as Node2D
	container.add_child(raider)
	raider.global_position = pos
	raider.home_position = pos
	_tag(raider)
	raider.set_meta("ai_raider", true)
	raider.converted.connect(_untag.bind(raider))
	raiders.append(raider)
	return raider
