# Mission 2: Salt of the Sahara (res://missions/Mission2.gd)
# Establish the first trans-Saharan salt route.
# Primary: escort 3 salt caravans from Taghaza to Walata; build 2 desert
#   outposts (200 Gold + 100 Salt each, via the build menu).
# Secondary: reach Walata in time (unlocks Camel Lancers).
# Scripted: "Sandstorm!" part-way through; raiders ambush the route and the
#   Tuareg chiefs demand tribute when the lead caravan is halfway.
# Failure: every caravan (convoy and reserves) lost.
extends "res://missions/MissionBase.gd"

const CARAVAN_SCENE := preload("res://entities/Caravan.tscn")
const CAMEL_LANCER_SCENE_PATH := "res://entities/CamelLancer.tscn"

const CARAVANS_NEEDED := 3
const OUTPOSTS_NEEDED := 2
# The design doc gives 15 minutes; scaled to 6 for the prototype.
const WALATA_TIME_LIMIT := 360.0
# The design doc's Sandstorm strikes at 8:00; scaled to 3:00 here.
const SANDSTORM_TIME := 180.0
const SANDSTORM_DURATION := 45.0
const WALATA_REACH_RADIUS := 220.0
const ESCORT_DISTANCE := 450.0
const REPLACEMENT_DELAY := 4.0
const CONVOY_OFFSETS := [Vector2(0, 0), Vector2(-60, 26), Vector2(-120, -26)]
# Ambush points as a share of the route, with raider counts.
const AMBUSHES := [[0.25, 2], [0.5, 3], [0.78, 4]]
const TUAREG_PROGRESS := 0.5

@export var reserve_caravans := 2
@export var scripted_dilemmas := true
@export var ambushes_enabled := true

var delivered := 0
var lost := 0
var caravans: Array = []
var walata_reached := false
var lancers_unlocked := false
var _ambush_done := []
var _tuareg_done := false
var _check_left := 0.0
var _pending_replacements := 0

@onready var taghaza: Node2D = $TradePosts/Taghaza
@onready var walata: Node2D = $TradePosts/Walata
@onready var route: Array[Vector2] = _read_route()
@onready var sandstorm: Node = $Sandstorm

func _mission_ready() -> void:
	DilemmaManager.auto_triggers_enabled = false
	GameData.gold = 450
	GameData.salt = 150
	_ambush_done.resize(AMBUSHES.size())
	_ambush_done.fill(false)
	for i in CONVOY_OFFSETS.size():
		spawn_caravan(CONVOY_OFFSETS[i])
	set_objectives([
		{"id": "caravans", "text": _caravans_text()},
		{"id": "outposts", "text": "Build desert outposts 0/%d" % OUTPOSTS_NEEDED},
		{"id": "walata", "text": _walata_text(), "optional": true},
	])
	schedule(SANDSTORM_TIME - 20.0, func() -> void:
		toast("Guide: The sky turns the colour of rust... a storm is coming.", COLOR_BAD))
	schedule(SANDSTORM_TIME, func() -> void:
		sandstorm.start(SANDSTORM_DURATION))
	toast("Mansa: Lead the salt caravans from Taghaza to Walata. Stay close, they will not travel alone.")
	queue_redraw()

func _mission_process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 0.25
	_update_walata()
	_update_outposts()
	_update_route_events()
	_check_outcome()

# --- Caravans -----------------------------------------------------------------

func _read_route() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for marker in $Route.get_children():
		points.append((marker as Node2D).global_position)
	points.append(walata.global_position)
	return points

# Sends a one-way salt caravan from Taghaza along the route. `offset` shifts
# its start and every waypoint (except Walata) so a convoy doesn't stack.
func spawn_caravan(offset := Vector2.ZERO):
	var caravan = CARAVAN_SCENE.instantiate()
	caravan.one_way = true
	caravan.wait_for_player_distance = ESCORT_DISTANCE
	var points: Array[Vector2] = []
	for i in route.size():
		points.append(route[i] + (offset if i < route.size() - 1 else Vector2.ZERO))
	caravan.route_points = points
	caravan.position = taghaza.global_position + Vector2(60, 30) + offset
	container("Caravans").add_child(caravan)
	caravan.arrived.connect(_on_caravan_arrived.bind(caravan))
	caravan.died.connect(_on_caravan_died.bind(caravan))
	caravans.append(caravan)
	return caravan

func active_caravans() -> Array:
	var result := []
	for c in caravans:
		if is_instance_valid(c) and not c.is_dead and not c.has_arrived:
			result.append(c)
	return result

func lead_progress() -> float:
	var best := 0.0
	for c in active_caravans():
		best = maxf(best, c.get_route_progress())
	return best

# Untyped: the caravan may already be freed.
func _on_caravan_arrived(caravan) -> void:
	if finished:
		return
	delivered += 1
	GameData.salt += 50
	AudioManager.play_sfx("caravan_deliver")
	toast("Salt caravan reaches Walata (%d/%d). Salt is traded weight for weight with gold!" % [mini(delivered, CARAVANS_NEEDED), CARAVANS_NEEDED], COLOR_GOOD)
	objective_text("caravans", _caravans_text())
	if not walata_reached:
		_reach_walata()
	if is_instance_valid(caravan):
		caravan.queue_free()
	_check_outcome()

func _on_caravan_died(_caravan) -> void:
	if finished:
		return
	lost += 1
	if reserve_caravans > 0:
		reserve_caravans -= 1
		toast("A caravan is lost! Another sets out from Taghaza.", COLOR_BAD)
		_pending_replacements += 1
		var generation := GameData.generation
		get_tree().create_timer(REPLACEMENT_DELAY, false).timeout.connect(func() -> void:
			if generation == GameData.generation and is_instance_valid(self) and is_inside_tree():
				_pending_replacements -= 1
				if not finished:
					spawn_caravan())
	else:
		toast("A caravan is lost to the dunes!", COLOR_BAD)
	objective_text("caravans", _caravans_text())
	_check_outcome.call_deferred()

func _caravans_text() -> String:
	return "Escort salt caravans to Walata %d/%d (reserves %d)" % [mini(delivered, CARAVANS_NEEDED), CARAVANS_NEEDED, reserve_caravans]

# --- Objectives ---------------------------------------------------------------

func _update_outposts() -> void:
	var n := count_group("building_outpost")
	objective_text("outposts", "Build desert outposts %d/%d" % [mini(n, OUTPOSTS_NEEDED), OUTPOSTS_NEEDED])
	if n >= OUTPOSTS_NEEDED:
		complete("outposts", "Desert outposts stand watch over the salt road.")

func _update_walata() -> void:
	if walata_reached or is_done("walata"):
		return
	if mission_time > WALATA_TIME_LIMIT:
		objective_text("walata", "Reach Walata within %s (too late)" % format_clock(WALATA_TIME_LIMIT))
		return
	objective_text("walata", _walata_text())
	var player := get_player()
	if player != null and player.global_position.distance_to(walata.global_position) <= WALATA_REACH_RADIUS:
		_reach_walata()

func _walata_text() -> String:
	return "Reach Walata within %s (%s left)" % [format_clock(WALATA_TIME_LIMIT), format_clock(WALATA_TIME_LIMIT - mission_time)]

func _reach_walata() -> void:
	walata_reached = true
	if mission_time > WALATA_TIME_LIMIT:
		return
	complete("walata")
	unlock_camel_lancers()

# Secondary reward: two Camel Lancers join the Mansa.
func unlock_camel_lancers() -> void:
	if lancers_unlocked:
		return
	lancers_unlocked = true
	toast("Walata reached in time! Camel Lancers unlocked: two riders join your escort.", COLOR_GOOD)
	var player := get_player()
	var at := player.global_position if player != null else walata.global_position
	for i in 2:
		var lancer := (load(CAMEL_LANCER_SCENE_PATH) as PackedScene).instantiate() as Node2D
		lancer.position = at + Vector2(-60 + i * 120, 60)
		container("Allies").add_child(lancer)

func _update_route_events() -> void:
	var progress := lead_progress()
	if ambushes_enabled:
		for i in AMBUSHES.size():
			if not _ambush_done[i] and progress >= float(AMBUSHES[i][0]):
				_ambush_done[i] = true
				ambush(int(AMBUSHES[i][1]))
	if scripted_dilemmas and not _tuareg_done and progress >= TUAREG_PROGRESS:
		_tuareg_done = true
		if not DilemmaManager.has_fired("tuareg_negotiation"):
			DilemmaManager.trigger("tuareg_negotiation")

# Raiders strike ahead of the lead caravan, from the dunes beside the road.
func ambush(count: int) -> void:
	var lead = null
	for c in active_caravans():
		if lead == null or c.get_route_progress() > lead.get_route_progress():
			lead = c
	if lead == null:
		return
	var target: Vector2 = lead.route_points[mini(lead.route_index, lead.route_points.size() - 1)]
	var dir: Vector2 = lead.global_position.direction_to(target)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var center: Vector2 = lead.global_position + dir * 220.0 + dir.orthogonal() * 200.0
	spawn_group(center, count, 50.0, lead.global_position + dir * 120.0)
	toast("Tuareg raiders descend from the dunes!", COLOR_BAD)
	AudioManager.play_sfx("horn")

func _check_outcome() -> void:
	if finished:
		return
	if delivered >= CARAVANS_NEEDED:
		complete("caravans")
	if delivered >= CARAVANS_NEEDED and is_done("outposts"):
		toast("The salt road is open: Taghaza's salt now feeds the gold trade.", COLOR_GOOD)
		win("Salt of the Sahara", "Three caravans reached Walata and the outposts guard the road. The trans-Saharan salt route is Mali's.")
		return
	if delivered < CARAVANS_NEEDED and active_caravans().is_empty() and reserve_caravans <= 0 and _pending_replacements == 0:
		lose("caravans_lost", "The Salt Road Is Lost", "Every caravan perished in the desert. Without salt, the gold trade withers.")

# Dashed route line from Taghaza to Walata.
func _draw() -> void:
	if route.is_empty():
		return
	var prev := taghaza.global_position
	for p in route:
		var seg := p - prev
		var n := int(seg.length() / 24.0)
		for i in n:
			if i % 2 == 0:
				draw_line(prev + seg * (float(i) / n), prev + seg * (float(i + 1) / n), Color(0.95, 0.9, 0.75, 0.45), 3.0)
		prev = p
