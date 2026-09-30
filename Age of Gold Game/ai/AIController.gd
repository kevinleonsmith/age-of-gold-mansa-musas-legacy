# Default decision-maker for an AIEmpire (res://ai/AIController.gd)
# AIEmpire calls decide(empire) about every 2 s. The controller only reads the
# empire's state and calls its public actions, so a human / network
# controller can replace it with the same interface.
#
# Priorities each decision:
#   1. workers up to the difficulty cap; idle workers claim the best free node
#   2. libraries (early in Scholars, one later in Showdown)
#   3. war camps up to the cap (after first_camp_delay)
#   4. raiders from the camps; one guard stands at each claimed node
#   5. attack wave when enough free raiders and the cooldown is over
#   6. research whenever manuscripts allow
extends RefCounted

const SALT_TYPE := 1 # ResourceNode.RESOURCE_TYPE.SALT
const MANUSCRIPT_TYPE := 2 # ResourceNode.RESOURCE_TYPE.MANUSCRIPTS
const SALT_WANTED := 80.0
const PLAYER_SIDE := 0
const NEUTRAL_SIDE := -1
const CLAIM_GROWTH := 3.0 # px of claim radius per second of game time
const MAX_CLAIM_RADIUS := 2600.0
const SHOWDOWN_LIBRARY_DELAY := 120.0

func decide(e) -> void:
	if e.eliminated:
		return
	var p: Dictionary = e.profile
	_manage_workers(e, int(p["max_workers"]))
	_manage_libraries(e, int(p["max_libraries"]))
	if e.living_camps().size() < int(p["max_camps"]) and e.elapsed >= float(p["first_camp_delay"]):
		e.build_camp()
	_manage_raiders(e)
	if e.free_raiders().size() >= int(p["wave"]) and e.attack_cooldown_left <= 0.0:
		e.launch_attack()
	if e.can_start_research():
		e.start_research()

func _manage_workers(e, cap: int) -> void:
	if e.workers.size() < cap:
		e.train_worker()
	for w in e.workers:
		if not w.has_target() or not is_node_available(e, w.target_node):
			var node = pick_node(e, w)
			if node != null or not w.has_target():
				e.assign_worker(w, node)

func _manage_libraries(e, cap: int) -> void:
	var have: int = e.living(e.libraries).size()
	if e.mode == "scholars":
		# Scholars: libraries come first, but keep one camp's worth of defence.
		if have < cap:
			e.build_library()
	elif have < mini(cap, 1) and e.elapsed >= SHOWDOWN_LIBRARY_DELAY:
		e.build_library()

func _manage_raiders(e) -> void:
	var camps: Array = e.living_camps()
	if camps.is_empty():
		return
	# Scholars empires save gold for libraries before arming.
	var reserve := 0.0
	if e.mode == "scholars" and e.living(e.libraries).size() < int(e.profile["max_libraries"]):
		reserve = float(e.LIBRARY_COST["gold"])
	if e.gold - reserve >= float(e.RAIDER_COST["gold"]):
		e.train_raider()
	# One guard per node that this empire's workers claim.
	for node in claimed_nodes(e):
		if _has_guard(e, node):
			continue
		var best = null
		var best_d := INF
		for r in e.free_raiders():
			var d: float = r.global_position.distance_to(node.global_position)
			if d < best_d:
				best_d = d
				best = r
		if best == null:
			break
		e.assign_guard(best, node)

func claimed_nodes(e) -> Array:
	var out := []
	for w in e.workers:
		if w.has_target() and not out.has(w.target_node):
			out.append(w.target_node)
	return out

func _has_guard(e, node) -> bool:
	for r in e.guards():
		if r.has_meta("guard_node") and r.get_meta("guard_node") == node:
			return true
	return false

# Gold / salt nodes on the map (NodeControl's "control_nodes" group, else the
# scene's Resources container).
func candidate_nodes(e) -> Array:
	var tree: SceneTree = e.get_tree()
	var nodes := tree.get_nodes_in_group("control_nodes")
	if nodes.is_empty() and tree.current_scene != null:
		var res := tree.current_scene.get_node_or_null("Resources")
		if res != null:
			nodes = res.get_children()
	return nodes.filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion() \
		and n.get("resource_type") != null and int(n.resource_type) != MANUSCRIPT_TYPE)

# False if another AI claims or owns the node (AIs don't fight each other).
func is_node_available(e, node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	var claimed := int(node.get_meta("ai_claimed_by", e.empire_id))
	if claimed != e.empire_id:
		return false
	var owner := int(node.get_meta("control_owner", NEUTRAL_SIDE))
	return owner == NEUTRAL_SIDE or owner == PLAYER_SIDE or owner == e.empire_id

func claim_radius(e) -> float:
	return minf(e.claim_radius + e.elapsed * CLAIM_GROWTH, MAX_CLAIM_RADIUS)

# Best node for `worker`: near home, not crowded by our own workers, and a
# little reluctant to contest nodes the player holds.
func pick_node(e, worker):
	var radius := claim_radius(e)
	var best = null
	var best_score := INF
	for node in candidate_nodes(e):
		if not is_node_available(e, node):
			continue
		var d: float = node.global_position.distance_to(e.home_position)
		if d > radius:
			continue
		var crowd := 0
		for w in e.workers:
			if w != worker and w.target_node == node:
				crowd += 1
		var score := d + crowd * 500.0
		if int(node.get_meta("control_owner", NEUTRAL_SIDE)) == PLAYER_SIDE:
			score += 350.0
		# Short of salt (camps and libraries need it): favour salt nodes.
		if int(node.resource_type) == SALT_TYPE and e.salt < SALT_WANTED:
			score -= 400.0
		if score < best_score:
			best_score = score
			best = node
	return best
