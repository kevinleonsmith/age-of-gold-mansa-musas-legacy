extends SceneTree
# Audio: streams load, music loops, sfx rate limit / pool, hooks, mute.

var _fails := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _wait_ms(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await process_frame

func _run() -> void:
	var au = root.get_node("AudioManager")
	var am = root.get_node("AgeManager")
	root.get_node("DilemmaManager").auto_triggers_enabled = false
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	var sm = current_scene.get_node_or_null("SpawnManager")
	if sm:
		sm.free()
	await process_frame

	# --- Streams -----------------------------------------------------------
	for n in au.SFX_NAMES:
		var s = load("res://assets/audio/sfx/%s.wav" % n)
		check(s is AudioStreamWAV and s.get_length() > 0.0 and au.has_sfx(n),
			"sfx '%s' loads as AudioStreamWAV (%.2fs)" % [n, s.get_length() if s else 0.0])
	for n in au.TRACK_NAMES:
		var s = load("res://assets/audio/music/%s.wav" % n)
		check(s is AudioStreamWAV and s.get_length() > 20.0, "track '%s' loads (%.1fs)" % [n, s.get_length() if s else 0.0])
		check(s != null and s.loop_mode == AudioStreamWAV.LOOP_FORWARD, "track '%s' imported with LOOP_FORWARD" % n)
		var ms = au.get_music_stream(n)
		check(ms != null and ms.loop_mode == AudioStreamWAV.LOOP_FORWARD, "AudioManager's '%s' stream loops" % n)
	check(AudioServer.get_bus_index("Music") > 0 and AudioServer.get_bus_index("SFX") > 0, "Music and SFX buses exist")
	check(au.process_mode == Node.PROCESS_MODE_ALWAYS, "AudioManager processes while paused")

	# --- Unknown names -------------------------------------------------------
	var before: String = au.last_sfx
	au.play_sfx("no_such_sound")
	au.play_sfx("no_such_sound", Vector2(10, 10))
	au.play_music("no_such_track")
	check(au.last_sfx == before, "unknown sfx is a silent no-op")
	await _wait_ms(80)

	# --- Rate limit and per-name cap ----------------------------------------
	var played := []
	var on_played := func(n): played.append(n)
	au.sfx_played.connect(on_played)
	au.play_sfx("hit")
	au.play_sfx("hit")
	au.play_sfx("hit")
	check(played.count("hit") == 1, "hit is rate-limited within 60 ms (%d played)" % played.count("hit"))
	await _wait_ms(70)
	au.play_sfx("hit")
	check(played.count("hit") == 2, "hit plays again after 60 ms")
	# horn lasts 2.4 s: eight plays 50 ms apart overlap, so the cap must kick in.
	for i in 8:
		await _wait_ms(50)
		au.play_sfx("horn")
	check(played.count("horn") == au.MAX_PER_NAME, "at most %d concurrent 'horn' (%d of 8 played)" % [au.MAX_PER_NAME, played.count("horn")])
	check(au.count_playing("horn") <= au.MAX_PER_NAME, "count_playing respects the cap (%d)" % au.count_playing("horn"))

	# --- Pool size -------------------------------------------------------------
	for round_i in 3:
		for n in au.SFX_NAMES:
			au.play_sfx(n)
		await _wait_ms(45)
	var players := 0
	for c in au.get_children():
		if c is AudioStreamPlayer2D:
			players += 1
	check(players == au.POOL_SIZE and au.get_pool_size() == au.POOL_SIZE, "sfx pool stays at %d players (%d)" % [au.POOL_SIZE, players])
	check(au.get_busy_voices() <= au.POOL_SIZE, "busy voices never exceed the pool (%d)" % au.get_busy_voices())

	# --- Positional: silent beyond the hearing radius ---------------------------
	await _wait_ms(80)
	played.clear()
	var far: Vector2 = au._listener_position() + Vector2(5000, 0)
	au.play_sfx("error", far)
	check(not played.has("error"), "sfx far from the listener is skipped")
	au.play_sfx("error", au._listener_position() + Vector2(200, 0))
	check(played.has("error"), "sfx near the listener plays")

	# --- Music follows the scene and the age -----------------------------------
	check(au.current_track == "sand_chiefdoms", "gameplay scene plays the Age I track (%s)" % au.current_track)
	am.current_age = am.AGES.MALI_ASCENDANCY
	played.clear()
	am.age_changed.emit(am.current_age)
	check(au.current_track == "mali_ascendancy", "age_changed switches to mali_ascendancy (%s)" % au.current_track)
	check(played.has("age_up"), "age_changed plays age_up")
	await _wait_ms(1700)
	var active := 0
	for c in au.get_children():
		if c is AudioStreamPlayer and c.playing:
			active += 1
	check(active == 1, "only one music player remains after the crossfade (%d)" % active)
	am.current_age = am.AGES.GOLDEN_HAJJ
	am.age_changed.emit(am.current_age)
	check(au.current_track == "golden_hajj", "age_changed switches to golden_hajj")
	au.reset()
	check(au.current_track == "sand_chiefdoms", "reset() returns to the Age I track")
	am.reset()

	# --- Hooks -------------------------------------------------------------------
	await _wait_ms(80)
	played.clear()
	var btn := Button.new()
	btn.text = "test"
	current_scene.add_child(btn)
	btn.pressed.emit()
	check(au.last_sfx == "click" and played.has("click"), "button press plays click")
	btn.queue_free()
	root.get_node("TechManager").tech_researched.emit("test_tech")
	check(played.has("research_done"), "tech_researched plays research_done")
	var gd = root.get_node("GameData")
	gd.ingots += 1
	check(played.has("coin"), "gaining an ingot plays coin")
	var vm = root.get_node("VictoryManager")
	vm.game_won.emit("test", "t", "x")
	check(played.has("victory"), "game_won plays victory")
	vm.game_lost.emit("test", "t", "x")
	check(played.has("defeat"), "game_lost plays defeat")
	root.get_node("DilemmaManager").dilemma_started.emit("test")
	check(played.has("dilemma_open"), "dilemma_started plays dilemma_open")

	# Building placed after the scene settled -> build_place.
	await _wait_ms(80)
	played.clear()
	var menu = current_scene.get_node_or_null("BuildMenu")
	var player = get_first_node_in_group("player")
	if menu and player and menu.has_method("place_building"):
		gd.gold = 100000
		gd.salt = 100000
		var pos: Vector2 = player.global_position + Vector2(0, -150)
		var b = menu.place_building("house", pos)
		await process_frame
		await process_frame
		check(b != null and played.has("build_place"), "placing a building plays build_place")
		if b:
			b.queue_free()
	else:
		print("SKIP: no BuildMenu/player for build_place check")

	# Enemy conversion -> convert.
	await _wait_ms(80)
	played.clear()
	var enemy_scene = load("res://entities/EnemyAI.tscn")
	if enemy_scene and player:
		var e = enemy_scene.instantiate()
		current_scene.add_child(e)
		e.global_position = player.global_position + Vector2(100, 0)
		await process_frame
		await process_frame
		e.converted.emit()
		check(played.has("convert"), "enemy converted signal plays convert")
		e.queue_free()

	# --- Mute ---------------------------------------------------------------------
	var was := AudioServer.is_bus_mute(0)
	au.toggle_mute()
	check(AudioServer.is_bus_mute(0) != was, "toggle_mute flips Master mute")
	var ev := InputEventKey.new()
	ev.keycode = KEY_M
	ev.physical_keycode = KEY_M
	ev.pressed = true
	root.push_input(ev)
	await process_frame
	check(AudioServer.is_bus_mute(0) == was, "M key toggles mute back")
	au.set_muted(false)
	au.set_music_volume(-6.0)
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), -6.0), "set_music_volume sets the Music bus")
	au.set_sfx_volume(-2.0)
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), -2.0), "set_sfx_volume sets the SFX bus")

	# --- Menu scene plays the menu track -------------------------------------------
	var menu_scene := Node.new()
	menu_scene.name = "FakeMenu"
	var old_scene = current_scene
	for p in get_nodes_in_group("player"):
		p.remove_from_group("player")
	root.add_child(menu_scene)
	current_scene = menu_scene
	old_scene.queue_free()
	await process_frame
	await process_frame
	check(au.current_track == "menu", "non-gameplay scene plays menu (%s)" % au.current_track)

	au.sfx_played.disconnect(on_played)
	if _fails == 0:
		print("RESULT: OK (0 failures)")
	else:
		print("RESULT: FAILED (%d failures)" % _fails)
	quit()
