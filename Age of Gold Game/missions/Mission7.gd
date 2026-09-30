# Mission 7: Pilgrimage Paradox, the 1324 Hajj (res://missions/Mission7.gd)
# Lead the Hajj caravan from Niani via Walata and Cairo to Mecca without
# crashing the economies on the way.
# - The treasury is huge, so inflation (EconomyManager.price_index) soars.
#   Distributing gold (the Economy panel's charity button, or distribute())
#   lowers it. At each city the market is checked: at or above GREEN_LIMIT
#   the Mansa "crashes" that city's gold market (a strike). 3 strikes: defeat.
# - Total charity is capped (the design's "<= 18 tons", scaled). Exceeding it
#   is a defeat. Giving too much too fast attracts bandit raids.
# - Build 4 Friday Mosques within MOSQUE_ROUTE_RADIUS of the route.
# - Mamluk red zones: bandits strike periodically while the caravan is inside.
# Win: the caravan reaches Mecca with the mosques built. Loss: the caravan is
# destroyed, 3 market crashes, or the charity cap is exceeded.
extends "res://missions/MissionBase.gd"

const GREEN_LIMIT := 1.25  # EconomyManager "Stable" band
const DISTRIBUTION_CAP := 3000  # "<= 18 tons of gold", scaled
const MAX_STRIKES := 3
const MOSQUES_NEEDED := 4
const MOSQUE_ROUTE_RADIUS := 300.0
const OVERSPEND_WINDOW := 10.0  # seconds
const OVERSPEND_LIMIT := 600  # gold given within the window that draws bandits
const RAID_COOLDOWN := 20.0
const CITY_REST := 10.0
const START_GOLD := 4500
const RED_ZONES := [[Vector2(2350, -60), 340.0], [Vector2(4150, 40), 340.0]]
const CITY_NAMES := ["Walata", "Cairo", "Mecca"]
const HISTORY_NOTE := "Cairo's gold price fell for over a decade after Mansa Musa's generosity. Twelve years on, it had still not recovered."

@export var red_zone_interval := 12.0
@export var red_zone_raid_size := 2
@export var scripted_dilemmas := true
@export var required_mosques := MOSQUES_NEEDED

var strikes := 0
var total_distributed := 0
var at_mecca := false
var in_red_zone := false
var red_zone_raids := 0
var overspend_raids := 0
var route: Array[Vector2] = []  # caravan spawn point + waypoints
var city_stops := {}  # caravan route_points index -> city name
var caravan = null
var _recent: Array = []  # [[mission_time, amount]]
var _last_raid_time := -1.0e9
var _zone_left := 0.0
var _last_gold := 0
var _last_drop := 0
var _last_drop_frame := -1
var _cap_warned := false
var _debate_done := false
var _check_left := 0.0

func _mission_ready() -> void:
	DilemmaManager.auto_triggers_enabled = false
	AgeManager.current_age = AgeManager.AGES.GOLDEN_HAJJ
	AgeManager.age_changed.emit(AgeManager.current_age)
	TechManager.grant_tech("economic_stabilization")
	GameData.gold = START_GOLD
	GameData.salt = 200
	GameData.manuscripts = 5
	_last_gold = GameData.gold
	_build_route()
	_spawn_caravan()
	_hook_distribution()
	set_objectives([
		{"id": "reach", "text": "Lead the Hajj caravan to Mecca"},
		{"id": "gold", "text": _gold_text()},
		{"id": "mosques", "text": _mosques_text(0)},
		{"id": "zones", "text": "Cross Mamluk red zones with the caravan above half strength", "optional": true},
	])
	toast("1324: The Mansa sets out for Mecca with 60,000 followers and tons of gold.")
	toast("Keep the price meter green at every city: give gold, but not too freely.", COLOR_BAD)
	queue_redraw()

func _mission_process(delta: float) -> void:
	_update_red_zone(delta)
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 0.25
	var mosques := count_mosques_near_route()
	objective_text("mosques", _mosques_text(mosques))
	if mosques >= required_mosques:
		complete("mosques", "A Friday Mosque rises on every stage of the road.")
	if scripted_dilemmas and not _debate_done and EconomyManager.price_index >= 1.75:
		_debate_done = true
		DilemmaManager.trigger("inflation_debate")
	if at_mecca:
		_try_finish()

# --- Setup --------------------------------------------------------------------

func _build_route() -> void:
	var points: Array[Vector2] = []
	for marker in $Route.get_children():
		if String(marker.name) in CITY_NAMES:
			city_stops[points.size()] = String(marker.name)
		points.append((marker as Node2D).global_position)
	route.clear()
	route.append(($HajjCaravan as Node2D).global_position)
	route.append_array(points)

func _spawn_caravan() -> void:
	caravan = $HajjCaravan
	var points: Array[Vector2] = []
	for i in range(1, route.size()):
		points.append(route[i])
	caravan.route_points = points
	caravan.waypoint_reached.connect(_on_waypoint_reached)
	caravan.arrived.connect(_on_caravan_arrived)
	caravan.died.connect(_on_caravan_died)

# The charity button lives in EconomyPanel; EconomyManager has no signal for
# it (yet), so we watch GameData.gold drops that happen within the button's
# `pressed` emission. If EconomyManager ever gains `gold_distributed(amount)`
# we use that instead.
func _hook_distribution() -> void:
	if EconomyManager.has_signal("gold_distributed"):
		EconomyManager.connect("gold_distributed", record_distribution)
		return
	GameData.gold_changed.connect(_on_gold_changed)
	var panel := get_node_or_null("EconomyPanel")
	if panel != null and panel.get("distribute_button") is Button:
		(panel.distribute_button as Button).pressed.connect(_on_distribute_pressed)

func _on_gold_changed(value) -> void:
	if int(value) < _last_gold:
		_last_drop = _last_gold - int(value)
		_last_drop_frame = Engine.get_process_frames()
	_last_gold = int(value)

# Connected after EconomyPanel's own handler, so the gold drop already happened.
func _on_distribute_pressed() -> void:
	if _last_drop > 0 and _last_drop_frame == Engine.get_process_frames():
		record_distribution(_last_drop)
	_last_drop = 0

# Gives `amount` gold through EconomyManager and records it. Returns success.
func distribute(amount: int) -> bool:
	if not EconomyManager.distribute_gold(amount):
		return false
	if not EconomyManager.has_signal("gold_distributed"):
		_last_drop = 0
		record_distribution(amount)
	return true

# --- Charity ------------------------------------------------------------------

func record_distribution(amount: int) -> void:
	if finished or amount <= 0:
		return
	total_distributed += amount
	objective_text("gold", _gold_text())
	if total_distributed > DISTRIBUTION_CAP:
		lose("treasury_squandered", "The Treasury Is Squandered",
			"The Mansa gave away more than the empire could bear. Mali's coffers are empty before Mecca.")
		return
	if not _cap_warned and total_distributed >= DISTRIBUTION_CAP * 0.8:
		_cap_warned = true
		toast("Treasurer: Only %d gold may still be given away!" % (DISTRIBUTION_CAP - total_distributed), COLOR_BAD)
	_recent.append([mission_time, amount])
	var window_total := 0
	for entry in _recent.duplicate():
		if mission_time - float(entry[0]) > OVERSPEND_WINDOW:
			_recent.erase(entry)
		else:
			window_total += int(entry[1])
	if window_total > OVERSPEND_LIMIT and mission_time - _last_raid_time >= RAID_COOLDOWN:
		overspend_raids += 1
		toast("Word of the Mansa's lavish gifts spreads. Bandits close in on the caravan!", COLOR_BAD)
		bandit_raid(3)

func _gold_text() -> String:
	return "Keep markets green: %d/%d gold given, crashes %d/%d" % [total_distributed, DISTRIBUTION_CAP, strikes, MAX_STRIKES]

# --- Cities -------------------------------------------------------------------

func _on_waypoint_reached(index: int) -> void:
	if city_stops.has(index):
		arrive_at_city(city_stops[index], index < caravan.route_points.size() - 1)

# Checks the price meter on arrival. Public for tests.
func arrive_at_city(city_name: String, rest := true) -> void:
	if finished:
		return
	if EconomyManager.price_index >= GREEN_LIMIT:
		strikes += 1
		AudioManager.play_sfx("error")
		toast("Crashed %s's gold market! (%d/%d)" % [city_name, strikes, MAX_STRIKES], COLOR_BAD)
		objective_text("gold", _gold_text())
		if strikes >= MAX_STRIKES:
			lose("markets_crashed", "Markets in Ruin",
				"Gold flooded every market from Walata to Mecca. Prices collapsed and the Mansa's name became a byword for ruin.")
			return
	else:
		AudioManager.play_sfx("coin")
		toast("%s's markets hold steady. The people bless the Mansa's generosity." % city_name, COLOR_GOOD)
	if rest and is_instance_valid(caravan):
		caravan.rest(CITY_REST)

func _on_caravan_arrived() -> void:
	at_mecca = true
	_try_finish()

func _try_finish() -> void:
	if finished or not at_mecca:
		return
	if count_mosques_near_route() < required_mosques:
		if not is_done("reach"):
			complete("reach")
			toast("The caravan waits at Mecca: build the remaining Friday Mosques along the road.", COLOR_BAD)
		return
	complete("reach")
	complete("gold")
	complete("mosques")
	if is_instance_valid(caravan) and caravan.health >= caravan.max_health * 0.5:
		complete("zones")
	toast(HISTORY_NOTE)
	win("Pilgrimage Paradox", "The Hajj caravan reaches Mecca. Mali's wealth is known from Cairo to Venice.\n\n" + HISTORY_NOTE)

func _on_caravan_died() -> void:
	lose("caravan_destroyed", "The Hajj Is Lost", "Bandits destroyed the Hajj caravan before it reached Mecca.")

# --- Mosques ------------------------------------------------------------------

func distance_to_route(point: Vector2) -> float:
	var best := INF
	for i in range(route.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(point, route[i], route[i + 1])
		best = minf(best, point.distance_to(closest))
	return best

func count_mosques_near_route() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("building_mosque"):
		if node.is_queued_for_deletion() or node.get("is_destroyed") == true:
			continue
		if distance_to_route((node as Node2D).global_position) <= MOSQUE_ROUTE_RADIUS:
			n += 1
	return n

func _mosques_text(n: int) -> String:
	return "Build Friday Mosques along the route %d/%d" % [mini(n, required_mosques), required_mosques]

# --- Red zones and bandits ----------------------------------------------------

func red_zone_at(point: Vector2) -> int:
	for i in RED_ZONES.size():
		if point.distance_to(RED_ZONES[i][0]) <= float(RED_ZONES[i][1]):
			return i
	return -1

func _update_red_zone(delta: float) -> void:
	if not is_instance_valid(caravan) or caravan.is_dead:
		return
	var inside := red_zone_at(caravan.global_position) >= 0
	if inside and not in_red_zone:
		toast("The caravan enters Mamluk territory. Bandits watch from the ridges!", COLOR_BAD)
		_zone_left = 0.0
	in_red_zone = inside
	if not inside:
		return
	_zone_left -= delta * time_scale
	if _zone_left <= 0.0:
		_zone_left = red_zone_interval
		red_zone_raids += 1
		bandit_raid(red_zone_raid_size)

# Mamluk bandits strike the caravan from the side.
func bandit_raid(count: int) -> void:
	if not is_instance_valid(caravan):
		return
	_last_raid_time = mission_time
	var from: Vector2 = caravan.global_position + Vector2(0, 260).rotated(randf_range(-0.8, 0.8)) * (1 if randf() < 0.5 else -1)
	spawn_group(from, count, 40.0, caravan.global_position)
	AudioManager.play_sfx("horn")

func _draw() -> void:
	for zone in RED_ZONES:
		draw_circle(zone[0], zone[1], Color(0.85, 0.1, 0.08, 0.16))
		draw_arc(zone[0], zone[1], 0.0, TAU, 72, Color(0.9, 0.15, 0.1, 0.6), 3.0)
	var font := ThemeDB.fallback_font
	for zone in RED_ZONES:
		draw_string(font, zone[0] + Vector2(-80, -zone[1] + 30), "Mamluk territory", HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color(1, 0.8, 0.75, 0.85))
	for i in range(route.size() - 1):
		var seg := route[i + 1] - route[i]
		var n := int(seg.length() / 24.0)
		for j in n:
			if j % 2 == 0:
				draw_line(route[i] + seg * (float(j) / n), route[i] + seg * (float(j + 1) / n), Color(1.0, 0.85, 0.4, 0.45), 3.0)
