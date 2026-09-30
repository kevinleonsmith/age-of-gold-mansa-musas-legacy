# Sandstorm (res://systems/Sandstorm.gd)
# Reusable scripted weather: start(duration) / stop(). While active a sandy
# full-screen overlay (animated noise + blowing grit, ~80% visibility drop,
# clearer near the screen centre where the camera follows the Mansa) covers
# the world, and GameData "sandstorm_slow_mult" is set to slow_mult so
# non-"camel" units crawl. The previous modifier value is restored after.
# Find it via the "sandstorm" group.
extends CanvasLayer

signal started
signal stopped

const SLOW_KEY := "sandstorm_slow_mult"
const FADE_TIME := 1.2
const SAND_SHADER := """
shader_type canvas_item;
uniform float intensity = 0.8;
uniform vec2 aspect = vec2(1.78, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}
void fragment() {
	vec2 p = UV * aspect;
	float n = fbm(p * vec2(4.0, 7.0) + vec2(-TIME * 1.4, TIME * 0.15));
	float streak = fbm(p * vec2(1.5, 22.0) + vec2(-TIME * 3.0, 0.0));
	float d = distance(p, aspect * 0.5);
	float clear_zone = smoothstep(0.1, 0.45, d);
	float a = intensity * (0.72 + 0.28 * clear_zone) * (0.85 + 0.3 * n);
	vec3 dark = vec3(0.62, 0.45, 0.26);
	vec3 light = vec3(0.93, 0.8, 0.56);
	COLOR = vec4(mix(dark, light, clamp(n * 0.7 + streak * 0.5, 0.0, 1.0)), clamp(a, 0.0, 0.93));
}
"""

@export var slow_mult := 0.4
@export var visibility_drop := 0.8

var active := false
var _saved_slow := 1.0
var _generation := -1
var _token := 0
var _overlay: ColorRect
var _grit: CPUParticles2D
var _tween: Tween

func _ready() -> void:
	add_to_group("sandstorm")
	_build()
	visible = false

func _build() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SAND_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("intensity", visibility_drop)
	_overlay.material = mat
	add_child(_overlay)
	_grit = CPUParticles2D.new()
	_grit.name = "Grit"
	_grit.emitting = false
	_grit.amount = 220
	_grit.lifetime = 1.6
	_grit.position = Vector2(1250, 324)
	_grit.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_grit.emission_rect_extents = Vector2(40, 360)
	_grit.direction = Vector2(-1.0, 0.12)
	_grit.spread = 6.0
	_grit.gravity = Vector2.ZERO
	_grit.initial_velocity_min = 700.0
	_grit.initial_velocity_max = 1100.0
	_grit.scale_amount_min = 1.5
	_grit.scale_amount_max = 4.0
	_grit.color = Color(0.98, 0.88, 0.62, 0.75)
	add_child(_grit)

# Starts (or extends) the storm. duration <= 0 lasts until stop().
func start(duration := 30.0) -> void:
	if not active:
		active = true
		_generation = GameData.generation
		_saved_slow = GameData.get_modifier(SLOW_KEY)
		GameData.set_modifier(SLOW_KEY, slow_mult)
		visible = true
		_overlay.modulate.a = 0.0
		_grit.emitting = true
		_fade_to(1.0)
		_toast("Sandstorm! Only camels keep their pace.", Color(1.0, 0.8, 0.45))
		AudioManager.play_sfx("horn")
		started.emit()
	_token += 1
	if duration > 0.0:
		var token := _token
		var generation := GameData.generation
		get_tree().create_timer(duration, false).timeout.connect(func() -> void:
			if token == _token and generation == GameData.generation and is_instance_valid(self):
				stop())

func stop() -> void:
	if not active:
		return
	active = false
	_token += 1
	_restore()
	_grit.emitting = false
	_fade_to(0.0)
	_toast("The sandstorm passes.", Color(1.0, 0.92, 0.7))
	stopped.emit()

func is_active() -> bool:
	return active

func _restore() -> void:
	if _generation == GameData.generation:
		GameData.set_modifier(SLOW_KEY, _saved_slow)

func _fade_to(alpha: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		return
	_tween = create_tween()
	_tween.tween_property(_overlay, "modulate:a", alpha, FADE_TIME)
	if alpha <= 0.0:
		_tween.tween_callback(func() -> void: visible = false)

func _exit_tree() -> void:
	if active:
		active = false
		_restore()

func _toast(text: String, color: Color) -> void:
	var toasts := get_tree().get_first_node_in_group("toasts")
	if toasts != null and toasts.has_method("show_toast"):
		toasts.show_toast(text, color)
