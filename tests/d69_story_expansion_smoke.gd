extends SceneTree

var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("STORY_EXPANSION_FAIL: " + note)

func _session(group: int) -> ForestStoryExpansionCombat:
	return ForestStoryExpansionCombat.create_expansion("anchor_pressure_7", 69001, null, group)

func _uid(session: CombatGame, id: String) -> int:
	for card in session.state.players.p1.hand:
		if str(card.card_id) == id:
			return int(card.uid)
	return -1

func _run() -> void:
	for group in range(2):
		for id in ForestStoryExpansionCombat.GROUPS[group]:
			var session := _session(group)
			var player: Dictionary = session.state.players.p1
			var enemy: Dictionary = session.state.enemies[0]
			player.statuses.clear()
			enemy.hp = 40
			enemy.max_hp = 40
			var definition := session.card_definition(id)
			var uid := _uid(session, id)
			_check(uid > 0, "first hand contains " + id)
			if uid < 0:
				continue
			if id == "forest_rest_bell":
				player.statuses = {"vulnerable": {"stacks": 2}, "weak": {"stacks": 2}, "poison": {"stacks": 3}, "strength": {"stacks": 2}, "dexterity": {"stacks": 3}}
			if id == "forest_glow_bolt":
				enemy.block = 8
				player.statuses.clear()
			var target := "e1" if definition.target == "enemy" else "p1"
			var before := session.to_dict().duplicate(true)
			var preview := session.preview_play("p1", uid, target)
			_check(bool(preview.ok), "legal preview " + id)
			_check(session.to_dict() == before, "preview preserves state and RNG " + id)
			_check(not bool(session.preview_play("p1", uid, "p1" if target == "e1" else "e1").get("ok", false)), "invalid target rejected " + id)
			var result := session.play_card("p1", uid, target)
			_check(bool(result.ok), "plays " + id)
			_check(int(player.energy) == 2, "cost paid " + id)
			_check(not player.hand.any(func(c): return int(c.uid) == uid), "leaves hand " + id)
			var destination: Array = player.exhaust_pile if definition.after == "exhaust" else player.discard_pile
			_check(destination.any(func(c): return int(c.uid) == uid), "correct destination " + id)
			match id:
				"forest_rest_bell":
					_check(player.statuses == {"strength": {"stacks": 2}, "dexterity": {"stacks": 3}}, "cleanse retains positive statuses")
					_check(int(preview.cleanse) == 3, "cleanse preview counts actual removals")
				"forest_glow_bolt":
					_check(int(enemy.hp) == 37 and int(enemy.block) == 6, "5 damage pierces 3 while only 2 block consumed")
					_check(int(preview.damage) == 5 and int(preview.effects[0].to_hp) == 3, "piercing preview matches HP loss")
				"forest_apply_gel": _check(int(player.hp) == 36, "gel heals six")
				"forest_eat_honey": _check(int(player.hp) == 33 and player.hand.size() == 5, "honey heals three and draws one")
				"forest_throw_fire_sac": _check(int(enemy.hp) == 27 and enemy.statuses.is_empty(), "fire pouch direct thirteen, no unsupported burn")
				"forest_throw_frost_sac": _check(int(enemy.hp) == 37 and int(enemy.statuses.weak.stacks) == 2, "frost applies actual weakness")
				"forest_scatter_stings": _check(int(enemy.hp) == 37 and int(enemy.statuses.poison.stacks) == 2, "stinger damage and poison")
				"forest_torch_strike": _check(int(enemy.hp) == 35, "torch initial attack five")
				"forest_throw_net": _check(int(enemy.hp) == 37 and int(enemy.statuses.weak.stacks) == 3, "net damage and weakness")
				"forest_throw_spores":
					_check(int(enemy.hp) == 40 and int(enemy.statuses.poison.stacks) == 3, "spores apply status without direct damage")
					session.end_turn("p1")
					_check(int(enemy.hp) == 37 and int(enemy.statuses.poison.stacks) == 2, "poison tick starts next enemy action")
	# 穿透上限、护甲消耗与攻击修正，均通过真实入口验证。
	for block in [0, 2, 8]:
		var session := _session(1)
		var enemy: Dictionary = session.state.enemies[0]
		session.state.players.p1.statuses.clear()
		enemy.hp = 40
		enemy.block = block
		session.play_card("p1", _uid(session, "forest_glow_bolt"), "e1")
		_check(int(enemy.hp) == 40 - (5 - mini(2, block)), "piercing HP with block %d" % block)
		_check(int(enemy.block) == maxi(0, block - 2), "piercing block consumption %d" % block)
	var capped := _session(0)
	capped.state.players.p1.hp = 39
	capped.play_card("p1", _uid(capped, "forest_apply_gel"), "p1")
	_check(int(capped.state.players.p1.hp) == 40, "healing capped at maximum")
	var cooperative := _session(1)
	var ally: Dictionary = cooperative.state.players.p1.duplicate(true)
	ally.name = "队友"
	ally.statuses = {"poison": {"stacks": 3}, "strength": {"stacks": 2}}
	cooperative.state.players["p2"] = ally
	var caster_statuses: Dictionary = cooperative.state.players.p1.statuses.duplicate(true)
	var cooperative_preview := cooperative.preview_play("p1", _uid(cooperative, "forest_rest_bell"), "p2")
	cooperative.play_card("p1", _uid(cooperative, "forest_rest_bell"), "p2")
	_check(ally.statuses == {"strength": {"stacks": 2}}, "ally cleanse retains ally strength")
	_check(cooperative.state.players.p1.statuses == caster_statuses, "ally cleanse does not cleanse caster")
	_check(int(cooperative_preview.cleanse) == 1 and cooperative_preview.effects[0].target == "p2", "ally cleanse preview target and count")
	var modified := _session(1)
	modified.state.players.p1.statuses = {"strength": {"stacks": 2}, "weak": {"stacks": 1}}
	modified.state.enemies[0].statuses = {"vulnerable": {"stacks": 1}}
	modified.state.enemies[0].hp = 40
	modified.state.enemies[0].block = 8
	var modified_preview := modified.preview_play("p1", _uid(modified, "forest_glow_bolt"), "e1")
	modified.play_card("p1", _uid(modified, "forest_glow_bolt"), "e1")
	_check(int(modified_preview.damage) == 7 and int(modified.state.enemies[0].hp) == 37 and int(modified.state.enemies[0].block) == 4, "piercing respects strength weak vulnerable with final rounding")
	print("STORY_EXPANSION_RULES: %d checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
