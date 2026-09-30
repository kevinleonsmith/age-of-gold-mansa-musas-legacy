# New game / mission flow (res://autoload/GameSession.gd)
# Resets every stateful autoload, then loads a scene. Delayed effects from the
# previous game check GameData.generation and are skipped.
extends Node

signal session_reset

# Autoloads with a reset() method, in reset order (GameData first: it clears
# the modifiers the others rebuild).
const RESETTABLE := ["GameData", "AgeManager", "TechManager", "EconomyManager",
	"DilemmaManager", "VictoryManager", "AudioManager"]

func reset_all() -> void:
	for autoload_name in RESETTABLE:
		var node := get_node_or_null("/root/" + autoload_name)
		if node != null and node.has_method("reset"):
			node.reset()
	session_reset.emit()

# Fresh state + load `scene_path` (a mission or the skirmish map).
func start(scene_path: String) -> void:
	get_tree().paused = false
	reset_all()
	get_tree().change_scene_to_file(scene_path)
