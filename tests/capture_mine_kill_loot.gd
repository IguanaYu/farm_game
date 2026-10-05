extends SceneTree
## 补拍：真实出牌击杀敌人（首次命中/首次击杀/胜利画面）+ 搜刮领取入背包。
## 需带窗口运行。


const OUT := "res://screenshots/mine_live_20261005"


func _initialize() -> void:
	_capture.call_deferred()


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)


func _capture() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var hud: FarmHud = world.get_node("FarmCanvas/FarmHud")
	# 上一次 capture 被强杀可能留下未完成局：先恢复并放弃，清掉占用
	var leftover := InventoryGame.new()
	leftover.bind(world.game.state["expedition"])
	if leftover.is_run_occupied():
		var resumed := ExpeditionGame.resume(world.game)
		if resumed["ok"]:
			resumed["game"].abandon()
	var inventory := InventoryGame.new()
	inventory.bind(world.game.state["expedition"])
	inventory.grant_basic_kit()
	# 三栏改版：武器与草帽先上装备槽（保证第 1 回合有牌），其余基础件入胸挂。
	for instance in inventory.warehouse_list().duplicate():
		if str(instance["def_id"]) == "old_shortsword":
			inventory.equip(int(instance["instance_id"]), "main_weapon")
		elif str(instance["def_id"]) == "straw_hat":
			inventory.equip(int(instance["instance_id"]), "helmet")
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	var depart := ExpeditionGame.depart(world.game, int(Time.get_unix_time_from_system()))
	if not depart["ok"]:
		push_error("KILL_LOT_DEPART_FAIL: " + str(depart["reason"]))
		quit(1)
		return
	var expedition: ExpeditionGame = depart["game"]
	hud.active_expedition = expedition
	hud.map_panel.open(expedition)

	# 静默打穿前两层，直达第三层
	for expected in ["iron_root_deeps", "crystal_vein_deeps"]:
		var changed := _clear_layer(expedition)
		if changed != expected:
			push_error("KILL_LOT_LAYER_FAIL: " + changed)
			quit(1)
			return

	# 第三层首场战斗：真实出牌打到底
	expedition.move_to(1, 0)
	hud.map_panel._refresh()
	hud.map_panel._on_start_battle()
	await _auto_battle(hud)

	# 搜刮台：候选选中 → 取走入背包
	await _shot("%s/15_loot_candidates.png" % OUT)
	var loot := hud.map_panel.loot_panel
	var token := ""
	for entry in loot.entries:
		if str(entry["kind"]) == "claim_reward" and bool(entry["available"]):
			token = str(entry["token"])
			break
	if token == "":
		push_error("KILL_LOT_NO_REWARD_CANDIDATE")
		quit(1)
		return
	loot.select_item(token)
	await _shot("%s/16_loot_item_selected.png" % OUT)
	loot._take(loot._entry(token), "pack")
	await _shot("%s/17_loot_item_in_pack.png" % OUT)
	print("CAPTURE_KILL_LOOT_OK -> ", OUT)
	world.queue_free()
	quit(0)


## 真实出牌循环：点卡→点目标（都是屏幕按钮的真实回调）；关键瞬间截图。
## 玩家血量过低时静默回满，保证能打到胜利（敌我伤害数字全部来自真实结算）。
func _auto_battle(hud: FarmHud) -> void:
	var bs := hud.battle_screen
	var first_strike := false
	var first_kill := false
	var guard := 0
	while str(bs.combat.state.get("outcome", "")) == "" and guard < 60:
		guard += 1
		var played := true
		while played and guard < 60:
			guard += 1
			played = false
			var hand: Array = (bs.combat.state["players"]["p1"]["hand"] as Array).duplicate()
			for card in hand:
				var uid := int(card["uid"])
				if not bs._playable_card(uid):
					continue
				var energy_before := int(bs.combat.state["players"]["p1"]["energy"])
				bs._on_card_clicked(uid)
				var def: Dictionary = CardDefs.get_card(str(card["card_id"]))
				var target := "p1" if str(def.get("target", "")) == "self" else _weakest_enemy_key(bs)
				if target == "":
					bs._cancel_selection()
					continue
				var alive_before := _alive_enemies(bs)
				bs._on_target_clicked(target)
				var still_in_hand := false
				for c in bs.combat.state["players"]["p1"]["hand"]:
					if int(c["uid"]) == uid:
						still_in_hand = true
						break
				if still_in_hand or int(bs.combat.state["players"]["p1"]["energy"]) == energy_before and int(def.get("cost", 1)) > 0:
					continue
				played = true
				if not first_strike and target != "p1":
					first_strike = true
					await _shot("%s/12_battle_first_strike.png" % OUT)
				if not first_kill and _alive_enemies(bs) < alive_before:
					first_kill = true
					await _shot("%s/13_battle_first_kill.png" % OUT)
				break
		if str(bs.combat.state.get("outcome", "")) != "":
			break
		if int(bs.combat.state["players"]["p1"]["hp"]) < 15:
			bs.combat.state["players"]["p1"]["hp"] = int(bs.combat.state["players"]["p1"]["max_hp"])
		bs._on_end_turn()
	await _shot("%s/14_battle_victory.png" % OUT)
	hud.battle_screen._on_close()
	await process_frame


func _alive_enemies(bs) -> int:
	var count := 0
	for enemy in bs.combat.state["enemies"]:
		if bool(enemy["alive"]):
			count += 1
	return count


func _weakest_enemy_key(bs) -> String:
	var best := ""
	var best_hp := 1 << 30
	for enemy in bs.combat.state["enemies"]:
		if bool(enemy["alive"]) and int(enemy["hp"]) < best_hp:
			best_hp = int(enemy["hp"])
			best = str(enemy["id"])
	return best


func _clear_layer(expedition: ExpeditionGame) -> String:
	for row in range(1, 9):
		var moved := expedition.move_to(row, 0)
		if not moved["ok"]:
			return "move r%dc0: %s" % [row, str(moved["reason"])]
		if str(expedition.current_node()["type"]) in ["battle", "elite", "gate"]:
			var started := expedition.start_battle()
			var combat: CombatGame = started["combat"]
			for enemy in combat.state["enemies"]:
				enemy["hp"] = 0
				enemy["alive"] = false
			combat._events_check_outcome([])
			expedition.finish_battle(combat)
		var left := expedition.leave_node()
		if not left["ok"]:
			return "leave r%dc0: %s" % [row, str(left["reason"])]
		if str(left.get("layer_changed", "")) != "":
			return str(left["layer_changed"])
	return "layer ended without gate change"
