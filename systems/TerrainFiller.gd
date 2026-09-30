extends TileMapLayer
## Fills a rectangle of this layer with procedurally chosen desert terrain tiles
## from source 0 of assets/tilesets/terrain.tres.

const PLAIN := Vector2i(0, 0)
const RIPPLES := Vector2i(1, 0)
const DUNE := Vector2i(2, 0)
const LATERITE := Vector2i(3, 0)

@export var fill_origin := Vector2i(-15, -12)
@export var fill_size := Vector2i(45, 36)
@export var seed_value := 1324
@export var fill_enabled := true  # `enabled` is a built-in TileMapLayer property


func _ready() -> void:
	z_index = -10
	if fill_enabled:
		fill()


func fill() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.08
	for y in range(fill_size.y):
		for x in range(fill_size.x):
			var cell := fill_origin + Vector2i(x, y)
			set_cell(cell, 0, _pick(rng, noise.get_noise_2d(cell.x, cell.y)))


## Low-frequency noise clumps dunes (high values) and laterite (low values);
## elsewhere it is weighted random sand. Overall ~55/25/12/8.
func _pick(rng: RandomNumberGenerator, n: float) -> Vector2i:
	var r := rng.randf()
	if n > 0.25:
		return DUNE if r < 0.6 else (RIPPLES if r < 0.8 else PLAIN)
	if n < -0.38:
		return LATERITE if r < 0.6 else PLAIN
	if r < 0.64:
		return PLAIN
	if r < 0.93:
		return RIPPLES
	if r < 0.97:
		return DUNE
	return LATERITE
