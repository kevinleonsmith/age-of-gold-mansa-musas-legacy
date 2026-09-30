extends SceneTree

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var world := main.get_node("World") as TileMapLayer
	check(world != null, "World is a TileMapLayer")
	check(world.z_index == -10, "World z_index == -10")
	var cells := world.get_used_cells()
	check(cells.size() == 45 * 36, "World has 45*36 cells (got %d)" % cells.size())
	var counts := {}
	for c in cells:
		var a := world.get_cell_atlas_coords(c)
		counts[a] = counts.get(a, 0) + 1
	print("atlas coord counts: ", counts)
	check(counts.size() == 4, "all 4 atlas tiles used")
	var expected := {
		"res://entities/Player.tscn": "res://assets/sprites/player.png",
		"res://entities/EnemyAI.tscn": "res://assets/sprites/enemy.png",
		"res://entities/CamelLancer.tscn": "res://assets/sprites/camel_lancer.png",
		"res://entities/GriotBard.tscn": "res://assets/sprites/griot_bard.png",
	}
	for scene_path in expected:
		var inst: Node = load(scene_path).instantiate()
		var spr := inst.get_node("Sprite2D") as Sprite2D
		var tex_path := spr.texture.resource_path if spr and spr.texture else ""
		check(tex_path == expected[scene_path], "%s texture = %s" % [scene_path, tex_path])
		check(spr.modulate == Color.WHITE, "%s has no modulate tint" % scene_path)
		inst.free()
	var m1: Node = load("res://missions/Mission1.tscn").instantiate()
	check(m1.get_node("TileMapLayer").get_script() == load("res://systems/TerrainFiller.gd"), "Mission1 TileMapLayer has TerrainFiller")
	m1.free()
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
