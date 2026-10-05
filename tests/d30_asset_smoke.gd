extends SceneTree
## 修复轮批次 A（F-01/F-02）：实例 ID 全程唯一 + 节点奖励一次性消费 + 恢复后继续唯一。
## 覆盖反馈 §5 F-01/F-02 的复测标准：连续领取 3 件 ID 唯一、恢复后仍唯一、
## 满包/白名单失败不消费候选、重复应用结算不增减库存、合作局双成员编号不冲突。


var failed := false


func _initialize() -> void:
	solo_flow()
	coop_flow()
	_finish()


# —— 单人：连续领取→恢复→撤离→逐件入库 ——————————————————————————————


func solo_flow() -> void:
	var game := _fresh_game()
	var counter_start := int(game.state["expedition"].get("next_instance_id", 1000))
	var depart := ExpeditionGame.depart(game, 3000)
	if not _check(depart["ok"], "出发：事务成功"):
		return
	var expedition: ExpeditionGame = depart["game"]
	var seen := {}
	var rows: Array = expedition.run["map"]["rows"]
	var types := ["battle", "gather", "chest", "rest_exit"]
	for row_index in range(1, types.size() + 1):
		rows[row_index] = [{"type": types[row_index - 1], "risk": "normal", "hint": "专项摆拍", "col": 0}]

	# 第 1 排战斗：搜索后转移实例，同一物品不能重复拿取
	expedition.move_to(1, 0)
	var battle := expedition.start_battle()
	if not _check(battle["ok"], "战斗：发起成功"):
		return
	var combat: CombatGame = battle["combat"]
	for enemy in combat.state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	combat._events_check_outcome([])
	expedition.finish_battle(combat)
	var key1 := expedition.node_id(1, 0)
	var resolved1: Dictionary = expedition.run["resolved"][key1]
	var clock := [1000]
	expedition.search_clock = func() -> int: return clock[0]
	expedition.loot_action("p1", "search_start", {"source": "e1", "region": "body"})
	while not expedition.run.get("loot_searches", {}).get("p1", {}).is_empty():
		clock[0] += int(expedition.run["loot_searches"]["p1"]["duration"]) + 1
		expedition.loot_action("p1", "search_step", {})
	var body: Dictionary = resolved1["corpses"][0]["regions"][0]
	var pick_a := int(body["items"][0]["instance_id"])
	var c1: Dictionary = expedition.loot_action("p1", "claim_corpse", {"instance_id": pick_a, "container": "pack"})
	if not _check(c1["ok"], "战斗奖励：领取候选 A"):
		return
	seen[int(c1["instance_id"])] = true
	_check(not expedition.loot_action("p1", "claim_corpse", {"instance_id": pick_a})["ok"], "战斗奖励：同一实例不能领两次")
	# 满包/白名单等价路径：非白名单物品放保险箱被拒，候选保留可重领
	var safe_try: Dictionary = expedition.loot_action("p1", "claim_corpse", {"instance_id": pick_a, "container": "safe"})
	_check(not safe_try["ok"], "失败路径：非法容器被拒")
	expedition.search_clock = Callable()
	expedition.leave_node()

	# 第 2 排采集：每条各一次
	expedition.move_to(2, 0)
	var key2 := expedition.node_id(2, 0)
	var resolved2: Dictionary = expedition.run["resolved"][key2]
	var gathered: Array = resolved2["rewards"].duplicate()
	if gathered.size() >= 2:
		var g1: Dictionary = expedition.claim_node_reward("p1", key2, str(gathered[0]), "pack")
		if _check(g1["ok"], "采集：领取第 1 条"):
			seen[int(g1["instance_id"])] = true
		_check(not expedition.claim_node_reward("p1", key2, str(gathered[0]), "pack")["ok"], "采集：同一条不能领两次")
		var g2: Dictionary = expedition.claim_node_reward("p1", key2, str(gathered[1]), "pack")
		if _check(g2["ok"], "采集：领取第 2 条"):
			seen[int(g2["instance_id"])] = true
	_check(seen.size() == 3, "F-01：连续领取 3 件 ID 全部唯一（%s）" % str(seen.keys()))
	expedition.leave_node()

	# 恢复：重开进程语义 = resume 重读局档；继续领取仍唯一
	var resume := ExpeditionGame.resume(game)
	if not _check(resume["ok"], "恢复：局档可达"):
		return
	var expedition2: ExpeditionGame = resume["game"]
	expedition2.move_to(3, 0)
	var key3 := expedition2.node_id(3, 0)
	var resolved3: Dictionary = expedition2.run["resolved"][key3]
	var chest_items: Array = resolved3["rewards"].duplicate()
	if not chest_items.is_empty():
		var c3: Dictionary = expedition2.claim_node_reward("p1", key3, str(chest_items[0]), "pack")
		if _check(c3["ok"], "宝箱：恢复后领取第 1 条"):
			_check(not seen.has(int(c3["instance_id"])), "F-01：恢复后分配的编号不与恢复前冲突")
			seen[int(c3["instance_id"])] = true
	expedition2.leave_node()

	# 撤离：逐件入库对账
	expedition2.move_to(4, 0)
	var extract := expedition2.extract()
	if not _check(extract["ok"], "撤离：结算成功"):
		return
	var settlement: Dictionary = extract["settlement"]
	var gained: Array = settlement["gained"]
	var gained_ids := {}
	for entry in gained:
		gained_ids[int(entry["instance_id"])] = true
	_check(gained_ids.size() == gained.size(), "撤离：结算清单 ID 无重复")
	_check(gained_ids.size() == seen.size(), "撤离：每件领取物都进入结算（%d/%d）" % [gained_ids.size(), seen.size()])
	var warehouse_ids := {}
	for instance in game.state["expedition"]["inventory"]["warehouse"]:
		warehouse_ids[int(instance["instance_id"])] = true
	var all_in := true
	for id in gained_ids:
		if not warehouse_ids.has(id):
			all_in = false
	_check(all_in, "撤离：获得物逐件入库")
	var farm_counter := int(game.state["expedition"].get("next_instance_id", 1000))
	_check(farm_counter > counter_start and farm_counter >= int(settlement["next_instance_id"]), "撤离：农场计数越过结算计数")
	var again := ExpeditionGame.apply_settlement(game, settlement)
	_check(again.get("duplicate", false), "幂等：重复应用只回执")
	_check(game.state["expedition"]["inventory"]["warehouse"].size() == warehouse_ids.size(), "幂等：仓库件数不变")


# —— 合作：双成员从同一节点领取，编号不冲突、消费按成员计 ————————————————————


func coop_flow() -> void:
	var host_game := _fresh_game()
	var guest_game := _fresh_game()
	var guest_inv := InventoryGame.new()
	guest_inv.bind(guest_game.state["expedition"])
	guest_inv.grant_basic_kit()
	for instance in guest_inv.warehouse_list().duplicate():
		guest_inv.move_to_loadout(int(instance["instance_id"]), "chest")
	var guest_profile := {
		"name": "客机阿禾",
		"player_id": "p-guest-test",
		"loadout": guest_game.state["expedition"]["inventory"]["loadout"],
		"carried": _carried(guest_game),
		"next_instance_id": int(guest_game.state["expedition"].get("next_instance_id", 1000)),
		"hp": 40,
	}
	var depart := ExpeditionGame.depart_coop(host_game, guest_profile, 4000)
	if not _check(depart["ok"], "合作：出发事务成功"):
		return
	var expedition: ExpeditionGame = depart["game"]
	var rows: Array = expedition.run["map"]["rows"]
	rows[1] = [{"type": "gather", "risk": "normal", "hint": "合作专项", "col": 0}]
	expedition.move_to(1, 0)
	var key := expedition.node_id(1, 0)
	var resolved: Dictionary = expedition.run["resolved"][key]
	var def_a := str(resolved["rewards"][0])
	var host_claim: Dictionary = expedition.claim_node_reward("p1", key, def_a, "pack")
	var guest_claim: Dictionary = expedition.claim_node_reward("p2", key, def_a, "pack")
	if _check(host_claim["ok"] and guest_claim["ok"], "合作：双成员各自领到同一候选"):
		_check(int(host_claim["instance_id"]) != int(guest_claim["instance_id"]), "合作：双成员实例 ID 不冲突（F-01）")
	_check(not expedition.claim_node_reward("p1", key, def_a, "pack")["ok"], "合作：主机同候选不能领两次（F-02）")
	_check(not expedition.claim_node_reward("p2", key, def_a, "pack")["ok"], "合作：客机同候选不能领两次（F-02）")


func _carried(game: FarmGame) -> Array:
	var ids: Array = []
	var loadout: Dictionary = game.state["expedition"]["inventory"]["loadout"]
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in loadout.get(container, []):
			ids.append(int(instance["instance_id"]))
	return ids


func _fresh_game() -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261030)
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	# 三栏改版：武器与草帽先上装备槽（保证第 1 回合有牌），其余基础件入胸挂。
	for instance in inventory.warehouse_list().duplicate():
		if str(instance["def_id"]) == "old_shortsword":
			inventory.equip(int(instance["instance_id"]), "main_weapon")
		elif str(instance["def_id"]) == "straw_hat":
			inventory.equip(int(instance["instance_id"]), "helmet")
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	return game


func _finish() -> void:
	if failed:
		push_error("D30_ASSET_SMOKE_FAIL")
	else:
		print("D30_ASSET_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> bool:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
	return ok
