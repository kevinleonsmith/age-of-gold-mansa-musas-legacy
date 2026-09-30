# AI rival settings shared between the mode-select menu and the modes
# (res://ai/AISettings.gd). Static vars survive scene changes and
# GameSession.reset_all(), so ModeSelect sets the difficulty before
# GameSession.start(path) and the mode reads it in _ready().
class_name AISettings
extends RefCounted

const DIFFICULTIES := ["easy", "normal", "hard"]

# Per-difficulty tuning for ai/AIEmpire.gd.
#   income: multiplies every AI income (passive gold, node harvest, manuscripts)
#   wave: raiders gathered before an attack wave marches
#   attack_cooldown: seconds between attack waves
#   max_camps / max_workers / max_libraries / max_raiders: caps
#   research_time: seconds per abstract manuscript tech
#   first_camp_delay: seconds before the first extra camp may be built
const PROFILES := {
	"easy": {"income": 0.7, "wave": 6, "attack_cooldown": 180.0, "max_camps": 2,
		"max_workers": 3, "max_libraries": 1, "max_raiders": 5, "research_time": 130.0, "first_camp_delay": 90.0},
	"normal": {"income": 1.0, "wave": 4, "attack_cooldown": 120.0, "max_camps": 3,
		"max_workers": 4, "max_libraries": 2, "max_raiders": 8, "research_time": 95.0, "first_camp_delay": 45.0},
	"hard": {"income": 1.4, "wave": 3, "attack_cooldown": 75.0, "max_camps": 4,
		"max_workers": 5, "max_libraries": 3, "max_raiders": 12, "research_time": 65.0, "first_camp_delay": 20.0},
}

# Chosen in ui/ModeSelect; read by the modes when their empires are created.
static var difficulty := "normal"
# Scene path last launched from ModeSelect (informational).
static var last_mode := ""

static func profile(level: String) -> Dictionary:
	return PROFILES.get(level, PROFILES["normal"])

static func normalized(level: String) -> String:
	return level if level in DIFFICULTIES else "normal"
