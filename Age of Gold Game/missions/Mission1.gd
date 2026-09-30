# Mission 1: Sand & Sovereignty (res://missions/Mission1.gd)
# Secure the Bambuk gold mines from Songhai raiders. A mine is secured once
# the Mansa has harvested it at least once and no enemy stands within
# SECURE_RADIUS of it (it then stays secured). Raiders guard each mine, and
# fresh waves march on the mines that are still contested.
# Optional: build 2 houses.
extends "res://missions/MissionBase.gd"

const RESOURCE_NODE_SCENE := preload("res://systems/ResourceNode.tscn")

const SECURE_RADIUS := 250.0
const CHECK_INTERVAL := 0.25
const MINE_POSITIONS := [Vector2(700, -80), Vector2(1050, 420), Vector2(380, 620)]
const MINE_QUANTITY := 200
const GUARDS_PER_MINE := 2
const HOUSES_WANTED := 2
const WAVE_SPAWN := Vector2(1700, 250)  # Songhai raiders ride in from the east

@export var waves_enabled := true
@export var wave_interval := 45.0
@export var wave_size := 2
@export var max_waves := 5

var required_gold_mines := 3
var mines: Array = []  # [{"node", "pos", "harvested", "secured"}]
var gold_mines_secured := 0
var waves_sent := 0
var _check_left := 0.0
var _wave_left := 0.0

func _mission_ready() -> void:
	DilemmaManager.auto_triggers_enabled = false
	GameData.gold = 150
	_wave_left = wave_interval
	for i in MINE_POSITIONS.size():
		var mine = RESOURCE_NODE_SCENE.instantiate()
		mine.name = "BambukMine%d" % (i + 1)
		mine.resource_type = 0  # ResourceNode.RESOURCE_TYPE.GOLD
		mine.quantity = MINE_QUANTITY
		mine.position = MINE_POSITIONS[i]
		$GoldMines.add_child(mine)
		var entry := {"node": mine, "pos": mine.global_position, "harvested": false, "secured": false}
		mine.depleted.connect(func() -> void: entry["harvested"] = true)
		mines.append(entry)
		spawn_group(mine.global_position + Vector2(0, -40), GUARDS_PER_MINE, 50.0, mine.global_position)
	set_objectives([
		{"id": "mines", "text": _mines_text()},
		{"id": "houses", "text": "Build houses 0/%d" % HOUSES_WANTED, "optional": true},
	])
	toast("Mansa: Songhai raiders hold the Bambuk mines. Harvest each and drive them off!")
	queue_redraw()

func _mission_process(delta: float) -> void:
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_INTERVAL
		update_mines()
		_update_houses()
	if waves_enabled and waves_sent < max_waves and gold_mines_secured < required_gold_mines:
		_wave_left -= delta
		if _wave_left <= 0.0:
			_wave_left = wave_interval
			send_wave()

# Re-evaluates every mine; public so tests can force a check.
func update_mines() -> void:
	var changed := false
	for entry in mines:
		if entry["secured"]:
			continue
		var mine = entry["node"]
		if is_instance_valid(mine) and int(mine.quantity) < MINE_QUANTITY:
			entry["harvested"] = true
		if entry["harvested"] and is_mine_clear(entry["pos"]):
			entry["secured"] = true
			gold_mines_secured += 1
			changed = true
			toast("Bambuk mine secured (%d/%d)" % [gold_mines_secured, required_gold_mines], COLOR_GOOD)
			AudioManager.play_sfx("coin")
	if changed:
		objective_text("mines", _mines_text())
		queue_redraw()
		if gold_mines_secured >= required_gold_mines:
			complete("mines")
			win_mission()

func is_mine_clear(pos: Vector2) -> bool:
	return count_enemies_near(pos, SECURE_RADIUS) == 0

func is_mine_secured(index: int) -> bool:
	return mines[index]["secured"]

func send_wave() -> void:
	var targets := []
	for entry in mines:
		if not entry["secured"]:
			targets.append(entry["pos"])
	if targets.is_empty():
		return
	waves_sent += 1
	var target: Vector2 = targets[waves_sent % targets.size()]
	var from := WAVE_SPAWN + Vector2(0, randf_range(-200, 200))
	spawn_group(from, wave_size + waves_sent / 2, 40.0, target)
	toast("Songhai raiders ride on the mines! (wave %d)" % waves_sent, COLOR_BAD)
	AudioManager.play_sfx("horn")

func _update_houses() -> void:
	if is_done("houses"):
		return
	var n := count_group("building_house")
	objective_text("houses", "Build houses %d/%d" % [mini(n, HOUSES_WANTED), HOUSES_WANTED])
	if n >= HOUSES_WANTED:
		complete("houses", "The Mansa's people settle around Bambuk.")

func _mines_text() -> String:
	return "Secure the Bambuk gold mines %d/%d" % [gold_mines_secured, required_gold_mines]

func win_mission() -> void:
	toast("The gold of Bambuk flows to Niani once more.", COLOR_GOOD)
	win("Sand & Sovereignty", "The Bambuk goldfields are secured from the Songhai raiders. Mali's wealth now has a foundation.")

# Rings show each mine's secure radius: red while contested, gold once held.
func _draw() -> void:
	for entry in mines:
		var col := Color(1.0, 0.8, 0.2, 0.55) if entry["secured"] else Color(0.9, 0.2, 0.15, 0.35)
		draw_arc(entry["pos"], SECURE_RADIUS, 0.0, TAU, 64, col, 2.0)
