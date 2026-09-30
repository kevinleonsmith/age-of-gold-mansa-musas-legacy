# Campaign mission list and saved progress (res://missions/MissionRegistry.gd)
# A static data class (not an autoload). Progress is stored with ConfigFile at
# save_path: mission1 is always unlocked, and winning a mission unlocks the next.
# Missions whose scene doesn't exist yet are listed but not playable.
class_name MissionRegistry
extends RefCounted

const DEFAULT_SAVE_PATH := "user://campaign.cfg"
const SECTION := "completed"

const MISSIONS := [
	{
		"id": "mission1",
		"chapter": "Chapter 1: Sand Chiefdoms",
		"title": "Sand & Sovereignty",
		"scene": "res://missions/Mission1.tscn",
		"description": "Secure the Bambuk gold mines. Drive off the raiders and bring the mines' gold to your treasury.",
		"historical_note": "The goldfields of Bambuk and Bure, between the Senegal and Niger rivers, supplied much of the gold that crossed the Sahara. Mali's rulers controlled the trade without mining the fields themselves.",
	},
	{
		"id": "mission2",
		"chapter": "Chapter 1: Sand Chiefdoms",
		"title": "Salt of the Sahara",
		"scene": "res://missions/Mission2.tscn",
		"description": "Establish the first trans-Saharan salt route. Escort salt caravans from Taghaza to Walata and build desert outposts.",
		"historical_note": "Salt slabs cut at Taghaza were carried south by camel caravan. In the markets of Mali, salt could trade for its weight in gold.",
	},
	{
		"id": "mission3",
		"chapter": "Chapter 1: Sand Chiefdoms",
		"title": "Outposts of the Sands",
		"scene": "res://missions/Mission3.tscn",
		"description": "Build three desert trade outposts before the Tuareg confederations rise against Mali's caravan tolls.",
		"historical_note": "The Tuareg (Kel Tamasheq) controlled the desert wells and routes between the Sahel and North Africa. Mali depended on their cooperation for the caravan trade.",
	},
	{
		"id": "mission4",
		"chapter": "Chapter 2: Mali Ascendancy",
		"title": "Walls of Timbuktu",
		"scene": "res://missions/Mission4.tscn",
		"description": "Breach the northern gates of Timbuktu, capture the Sankore library, and win over its scholars with your griots.",
		"historical_note": "Timbuktu came under Mali's rule in the early 14th century. Its Sankore mosque became the heart of a scholarly community whose manuscripts survive to this day.",
	},
	{
		"id": "mission5",
		"chapter": "Chapter 2: Mali Ascendancy",
		"title": "Taghaza Under Siege",
		"scene": "res://missions/Mission5.tscn",
		"description": "Hold the Taghaza salt mines against raiders. If the mines fall, famine will stalk the rest of the campaign.",
		"historical_note": "Taghaza was a salt-mining town deep in the Sahara, where even the houses were built of salt blocks. Its salt fed the markets of the whole Sahel.",
	},
	{
		"id": "mission6",
		"chapter": "Chapter 2: Mali Ascendancy",
		"title": "Niger's Fury",
		"scene": "res://missions/Mission6.tscn",
		"description": "Build a fleet of war canoes and destroy the Songhai river fleet on the Niger, striking during calm currents.",
		"historical_note": "The Niger was Mali's highway. The Bozo and Sorko boatmen carried grain, gold and armies along the river between Djenné, Timbuktu and Gao.",
	},
	{
		"id": "mission7",
		"chapter": "Chapter 3: Golden Hajj",
		"title": "Pilgrimage Paradox (1324 Hajj)",
		"scene": "res://missions/Mission7.tscn",
		"description": "Lead Mansa Musa's pilgrimage to Mecca. Spend generously to win prestige, but beware: too much gold will crash the price of gold in Cairo.",
		"historical_note": "In 1324 Mansa Musa travelled to Mecca with a vast retinue. Chroniclers such as al-Umari reported that he gave away so much gold in Cairo that its value there stayed depressed for years.",
	},
	{
		"id": "mission8",
		"chapter": "Chapter 3: Golden Hajj",
		"title": "Lords of Gao",
		"scene": "res://missions/Mission8.tscn",
		"description": "Returning from Mecca, bring the Songhai capital of Gao under Mali's rule and escort the architect as-Sahili home to build a great mosque.",
		"historical_note": "Around 1325 Mali's general Sagmandia secured Gao. Mansa Musa returned from the Hajj with the Andalusian poet-architect Abu Ishaq es-Sahili, credited with the Djinguereber mosque in Timbuktu.",
	},
	{
		"id": "mission9",
		"chapter": "Chapter 3: Golden Hajj",
		"title": "Crescent and Cross",
		"scene": "res://missions/Mission9.tscn",
		"description": "Establish Mali's economic hegemony: control the great wonders, hold a fortune in gold ingots, and outlast the alliances formed against you.",
		"historical_note": "The 1375 Catalan Atlas shows Mansa Musa enthroned, holding a gold nugget. Europe's mapmakers knew Mali as the source of the world's gold.",
	},
	{
		"id": "scholars_revolt",
		"chapter": "Bonus",
		"title": "Scholars' Revolt",
		"scene": "res://missions/ScholarsRevolt.tscn",
		"description": "Rogue libraries spawn rebel armies from their manuscripts. Destroy them before the revolt spreads.",
		"historical_note": "Timbuktu's private libraries held tens of thousands of manuscripts on law, astronomy and medicine, many preserved by families for centuries.",
		"bonus": true,
		"unlocked_by": "mission4",
	},
]

# Tests point this at a temporary file so the player's real save isn't touched.
static var save_path := DEFAULT_SAVE_PATH

static func set_save_path(path: String) -> void:
	save_path = path

static func get_missions() -> Array:
	return MISSIONS.duplicate(true)

static func get_mission(id: String) -> Dictionary:
	for mission in MISSIONS:
		if mission["id"] == id:
			return mission.duplicate(true)
	return {}

static func _index_of(id: String) -> int:
	for i in MISSIONS.size():
		if MISSIONS[i]["id"] == id:
			return i
	return -1

# True if the mission's scene exists ("Coming soon" otherwise).
static func is_available(id: String) -> bool:
	var mission := get_mission(id)
	return not mission.is_empty() and ResourceLoader.exists(mission["scene"])

static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(save_path) # a missing file just leaves it empty
	return config

static func is_completed(id: String) -> bool:
	return bool(_load().get_value(SECTION, id, false))

# The first mission is always unlocked; each later one once the previous is won.
static func is_unlocked(id: String) -> bool:
	var index := _index_of(id)
	if index < 0:
		return false
	var mission: Dictionary = MISSIONS[index]
	if mission.get("bonus", false):
		return is_completed(mission.get("unlocked_by", ""))
	if index == 0:
		return true
	# The previous story mission (bonus missions don't gate the story).
	for i in range(index - 1, -1, -1):
		if not MISSIONS[i].get("bonus", false):
			return is_completed(MISSIONS[i]["id"])
	return true

static func mark_completed(id: String) -> void:
	if _index_of(id) < 0:
		return
	var config := _load()
	config.set_value(SECTION, id, true)
	var err := config.save(save_path)
	if err != OK:
		push_warning("MissionRegistry: could not save %s (error %d)" % [save_path, err])

# The mission after `id`, or {} if it is the last one.
static func get_next(id: String) -> Dictionary:
	var index := _index_of(id)
	if index < 0:
		return {}
	for i in range(index + 1, MISSIONS.size()):
		if not MISSIONS[i].get("bonus", false):
			return MISSIONS[i].duplicate(true)
	return {}

# The mission whose scene is `path` (e.g. current_scene.scene_file_path), or {}.
static func find_by_scene(path: String) -> Dictionary:
	for mission in MISSIONS:
		if mission["scene"] == path:
			return mission.duplicate(true)
	return {}

# Persistent campaign flags (e.g. "salt_famine" after losing Mission 5).
const FLAGS_SECTION := "flags"

static func set_flag(key: String, value: Variant) -> void:
	var config := _load()
	config.set_value(FLAGS_SECTION, key, value)
	config.save(save_path)

static func get_flag(key: String, default: Variant = null) -> Variant:
	return _load().get_value(FLAGS_SECTION, key, default)

# Forgets all progress (used by tests).
static func clear_progress() -> void:
	var config := ConfigFile.new()
	config.save(save_path)
