extends SceneTree
# Integration soak: runs main.tscn for ~6 simulated minutes with all systems
# live, resolving dilemmas randomly, sending caravans, building and advancing ages.

var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	rng.seed = 12345
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	var gd := root.get_node("GameData")
	var am := root.get_node("AgeManager")
	var dm := root.get_node("DilemmaManager")
	var em := root.get_node("EconomyManager")
	var tm := root.get_node("TechManager")
	dm.min_gap = 20.0
	dm.mosque_gap = 20.0
	dm.mosque_chance = 1.0
	dm.salt_min_time = 30.0
	dm.duration_scale = 0.2
	var spot := 0
	for sec in 360:
		# one simulated second (process_always timer keeps counting while paused)
		for f in 60:
			await process_frame
			if dm.is_active():
				var a: Dictionary = dm.get_active()
				var opts: Array = []
				for i in a["options"].size():
					if a["options"][i]["available"]:
						opts.append(i)
				if opts.size():
					var pick: int = opts[rng.randi() % opts.size()]
					print("[t=%d] dilemma %s -> option %d" % [sec, a["id"], pick])
					var dlg = current_scene.get_node_or_null("DilemmaDialog") if current_scene else null
					if dlg and dlg.has_method("get_option_button") and dlg.get_option_button(pick):
						dlg.get_option_button(pick).pressed.emit()
					else:
						dm.choose(pick)
		var m := current_scene
		if m == null:
			continue
		var p = m.get_node_or_null("Player")
		if p and "health" in p:
			p.health = p.max_health  # keep the soak going
		if sec % 10 == 5:
			gd.add_resources({"gold": 1500, "salt": 300, "manuscripts": 5})
			var panel = m.get_node_or_null("EconomyPanel")
			if panel and not panel.caravan_button.disabled:
				panel.caravan_button.pressed.emit()
		if sec % 15 == 7 and p:
			var menu = m.get_node_or_null("BuildMenu")
			var types := ["house", "house", "house", "mosque", "mosque", "market", "outpost"]
			for ty in types:
				spot += 1
				var pos := Vector2(1500 + (spot % 6) * 250, 1500 + (spot / 6) * 250)
				p.global_position = pos + Vector2(0, 150)
				if menu and menu.place_building(ty, pos) == null:
					print("[t=%d] place %s refused: %s" % [sec, ty, menu.get_block_reason(ty)])
			if am.can_advance():
				print("[t=%d] advance_age -> %s" % [sec, am.advance_age()])
		if sec % 30 == 20 and tm.has_method("get_all_techs"):
			for t in tm.get_all_techs():
				if tm.can_research(t["id"]):
					tm.start_research(t["id"])
					break
		if sec % 30 == 0:
			print("[t=%d] age=%d gold=%d salt=%d idx=%.2f enemies=%d caravans=%d buildings=%d paused=%s dilemma=%s" % [
				sec, am.current_age, gd.gold, gd.salt, em.price_index,
				get_nodes_in_group("enemies").size(), get_nodes_in_group("caravans").size(),
				get_nodes_in_group("buildings").size(), paused, dm.is_active()])
	print("SOAK DONE")
	quit()
