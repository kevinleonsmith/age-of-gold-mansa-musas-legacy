extends SceneTree

var failures := 0
var enemy_scene: PackedScene
var main: Node
var griot
var gd: Node

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)

func wait_frames(n: int) -> void:
	for i in n:
		await physics_frame

# A frozen enemy (no AI) at an offset from the griot.
func spawn_enemy(offset: Vector2, frozen := true) -> Node:
	var e = enemy_scene.instantiate()
	main.get_node("Enemies").add_child(e)
	e.global_position = griot.global_position + offset
	e.home_position = e.global_position
	if frozen:
		e.set_physics_process(false)
	return e

# Frames until e is converted (or max_frames + 1).
func frames_to_convert(e, max_frames: int) -> int:
	for i in max_frames:
		await physics_frame
		if e.is_in_group("allies"):
			return i + 1
	return max_frames + 1

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	main = current_scene
	gd = root.get_node("GameData")
	var sm := main.get_node_or_null("SpawnManager")
	if sm:
		sm.queue_free()
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	await process_frame
	enemy_scene = load("res://entities/EnemyAI.tscn")
	var player := get_first_node_in_group("player") as Node2D

	griot = load("res://entities/GriotBard.tscn").instantiate()
	griot.pulse_interval = 1000.0
	main.add_child(griot)
	griot.global_position = player.global_position + Vector2(80, 0) # holds position here
	await wait_frames(5)
	check(griot.convert_radius == 140.0 and griot.convert_time == 4.0 and griot.convert_cooldown == 8.0, "export defaults 140 / 4.0 / 8.0")
	var count0: float = gd.get_modifier("converted_count", 0.0)

	# 1. Enemy in radius converts after ~4 s.
	var e1 := spawn_enemy(Vector2(100, 0))
	var sig := [false]
	e1.converted.connect(func(): sig[0] = true)
	e1.take_damage(20.0)
	var f1 := await frames_to_convert(e1, 400)
	print("enemy at 100 px converted after %d frames (%.2f s)" % [f1, f1 / 60.0])
	check(f1 >= 230 and f1 <= 250, "converts after ~4 s")
	check(e1.is_in_group("allies") and e1.is_in_group("converted") and not e1.is_in_group("enemies"), "converted unit: allies + converted, not enemies")
	check(e1.target_group == "enemies" and e1.target == null, "target_group = enemies, target cleared")
	check(e1.health == e1.max_health, "healed to full")
	var spr = e1.get_node("Sprite2D") as CanvasItem
	check(spr.modulate.is_equal_approx(Color(0.7, 0.85, 1.0)), "sprite tinted")
	check(sig[0], "converted signal emitted")
	check(is_equal_approx(gd.get_modifier("converted_count", 0.0), count0 + 1.0), "converted_count incremented to %s" % gd.get_modifier("converted_count", 0.0))
	check(griot._convert_cooldown_left > 7.5 and griot.conversion_progress == 0.0, "cooldown started")

	# Converted unit attacks another enemy.
	e1.set_physics_process(true)
	var victim := spawn_enemy(Vector2(100, 150))
	var hp0: float = victim.health
	await wait_frames(150)
	check(is_instance_valid(victim) and victim.health < hp0, "converted unit attacks another enemy (hp %s -> %s)" % [hp0, victim.health if is_instance_valid(victim) else -1.0])
	check(is_instance_valid(victim) and victim.is_in_group("enemies"), "victim not converted during cooldown")

	# No bounty for a converted unit; bounty still paid for an enemy.
	var g0: int = gd.gold
	e1.take_damage(10000.0)
	check(e1.is_dead and gd.gold == g0, "no bounty when a converted unit dies (gold %d -> %d)" % [g0, gd.gold])
	g0 = gd.gold
	victim.take_damage(10000.0)
	check(gd.gold == g0 + 5, "bounty still paid for a normal enemy (gold %d -> %d)" % [g0, gd.gold])
	await wait_frames(2)

	# 2. Enemy outside radius never converts.
	griot._convert_cooldown_left = 0.0
	var e2 := spawn_enemy(Vector2(200, 0))
	var f2 := await frames_to_convert(e2, 300)
	check(f2 > 300 and e2.is_in_group("enemies") and griot.conversion_progress == 0.0, "enemy at 200 px not converted after 5 s")
	e2.queue_free()
	await wait_frames(2)

	# 3. conversion_speed_mult 2.0 halves the time.
	griot.convert_cooldown = 2.0 # shortened for the cooldown check below
	gd.set_modifier("conversion_speed_mult", 2.0)
	var e3 := spawn_enemy(Vector2(0, 100))
	var f3 := await frames_to_convert(e3, 400)
	print("with speed 2.0: %d frames (%.2f s)" % [f3, f3 / 60.0])
	check(f3 >= 110 and f3 <= 130, "conversion_speed_mult 2.0 converts in ~2 s")
	gd.set_modifier("conversion_speed_mult", 1.0)

	# 4. Cooldown between conversions (shortened to 2 s).
	e3.set_physics_process(false)
	e3.global_position = griot.global_position + Vector2(-600, 0)
	var e4 := spawn_enemy(Vector2(0, -100))
	var f4 := await frames_to_convert(e4, 600)
	print("next conversion after previous song ended: %d frames" % f4)
	# Cooldown began at e3's conversion: total = 2 s cooldown + 4 s song.
	check(f4 >= 350 and f4 <= 370, "cooldown (2 s) + song (4 s) before next conversion")

	# Cooldown also blocks progress: immediately after, a new enemy gets no progress.
	var e5 := spawn_enemy(Vector2(-100, 0))
	await wait_frames(60)
	check(griot.conversion_progress == 0.0 and e5.is_in_group("enemies"), "no song progress during cooldown")
	e5.queue_free()
	e4.global_position = griot.global_position + Vector2(-600, 50)
	await wait_frames(2)

	# 5. Decay: progress drops 2x as fast when the target leaves radius.
	griot._convert_cooldown_left = 0.0
	var e6 := spawn_enemy(Vector2(100, 0))
	await wait_frames(120) # ~0.5 progress
	var p_mid: float = griot.conversion_progress
	e6.global_position = griot.global_position + Vector2(250, 0)
	await wait_frames(30) # 0.5 s out of range -> -0.25
	var p_after: float = griot.conversion_progress
	print("decay: %.3f -> %.3f" % [p_mid, p_after])
	check(absf((p_mid - p_after) - 0.25) < 0.03, "progress decays at 2x rate out of range")
	await wait_frames(60)
	check(griot.conversion_progress == 0.0 and griot.conversion_target == null, "progress fully decays, target dropped")

	# Target change resets progress.
	e6.global_position = griot.global_position + Vector2(100, 0)
	await wait_frames(60)
	var e7_far := spawn_enemy(Vector2(0, 120))
	e6.queue_free()
	await wait_frames(2)
	check(griot.conversion_target == e7_far and griot.conversion_progress < 0.05, "new target resets progress (%.3f)" % griot.conversion_progress)

	# 6. Griot doesn't flee from its song target unless it's within 40 px.
	check(not griot._is_threatened(), "song target at 120 px not a threat")
	e7_far.global_position = griot.global_position + Vector2(0, 60)
	await wait_frames(1)
	check(not griot._is_threatened(), "song target at 60 px (inside 80 flee radius) not a threat")
	e7_far.global_position = griot.global_position + Vector2(0, 30)
	await wait_frames(1)
	check(griot._is_threatened(), "song target at 30 px is a threat")
	var other := spawn_enemy(Vector2(-70, 0))
	e7_far.global_position = griot.global_position + Vector2(0, 100)
	await wait_frames(1)
	check(griot._is_threatened(), "another enemy at 70 px is still a threat")
	other.queue_free()
	e7_far.queue_free()
	await wait_frames(2)

	# 7. Direct convert_to_ally(). (Free the parked frozen units so nothing blocks the path.)
	e3.queue_free()
	e4.queue_free()
	await wait_frames(2)
	var e8 := spawn_enemy(Vector2(-900, 0), false)
	var c0: float = gd.get_modifier("converted_count", 0.0)
	e8.convert_to_ally()
	check(e8.is_in_group("allies") and e8.is_in_group("converted") and not e8.is_in_group("enemies") and e8.target_group == "enemies", "direct convert_to_ally works")
	e8.convert_to_ally()
	check(is_equal_approx(gd.get_modifier("converted_count", 0.0), c0 + 1.0), "converted_count +1, second call is a no-op")
	# Converted with no target escorts the player.
	await wait_frames(360)
	var dp: float = e8.global_position.distance_to(player.global_position)
	check(dp <= 170.0, "converted unit escorts player (dist %.1f, target %s)" % [dp, e8.target])
	var g1: int = gd.gold
	e8.take_damage(10000.0)
	check(gd.gold == g1, "no bounty for directly converted unit")

	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(failures)
