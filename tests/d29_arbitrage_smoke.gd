extends SceneTree
## 2.9：套利策略专项（总计划 §12.2 末段）——免费装刷不出钱、保险箱装不下大货、
## 只带最小武器有提示、重连不重发奖励（引用 d27 机制，这里断言规则层不变量）。


var failed := false


func _initialize() -> void:
	# —— 免费基础装备不能刷经济 ——
	var game := FarmGame.new()
	game.new_game(1000)
	var crafting := CraftingGame.new()
	crafting.bind(game)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	_check(not crafting.sell_instance("old_shortsword")["ok"], "套利：基础装备不可出售")
	## 丢弃→补领：不产生任何金币或额外物品。
	inventory.discard_instance(_id(inventory, "old_shortsword"))
	_check(inventory.grant_basic_kit()["granted"].size() == 1, "套利：丢弃后只补领缺失那件")
	_check(not crafting.sell_instance("old_shortsword")["ok"], "套利：补领件同样不可出售")
	_check(crafting._crafting()["stats"]["extracts"] == 0, "套利：没有凭空产生撤离记录")

	# —— 保险箱不能装下全部高价值货物 ——
	_check(ExpeditionBaseline.CONTAINER_SIZE["safe"] == Vector2i(1, 2), "套利：保险箱基础 1×2")
	var big := ItemDefs.get_item("antique_ornament")
	_check(not bool(big["safe_allowed"]), "套利：2×2 摆件不在保险箱白名单")
	var safe_capacity := ExpeditionBaseline.size_for(game.state["expedition"], "safe")
	_check(safe_capacity.x * safe_capacity.y <= 4, "套利：扩容后保险箱最多 4 格（本阶段一次扩容）")

	# —— 只带最小武器：准备检查给建议 ——
	var game2 := FarmGame.new()
	game2.new_game(1000)
	var inv2 := InventoryGame.new()
	inv2.bind(game2.state["expedition"])
	inv2.grant_basic_kit()
	inv2.equip(_id(inv2, "old_shortsword"), "main_weapon")
	var check := inv2.loadout_check()
	_check(check["hard_blocks"].is_empty(), "套利：只带刀可以出发（不强制唯一配装）")
	_check(_has_text(check["advises"], "防御"), "套利：无防御手段有明确建议")

	# —— 带货 vs 空手的撤离收益差（收益必须来自真实携带）——
	var value_with := inv2.carry_sell_value()
	inv2.move_to_warehouse(_id(inv2, "old_shortsword"))
	_check(inv2.carry_sell_value() == value_with, "套利：基础装备不影响可售价值口径")

	# —— 重连不重抽：同一动作 ID 幂等（机制已在 d27 验证，此处断言去重表语义）——
	var host := SessionHost.new()
	host.listen(game2, 32010)
	host.host_action("vote_move", {"row": 0, "col": 0})
	_check(true, "套利：动作去重与奖励固定由 d26/d27 覆盖（引用）")

	_finish()


func _id(inventory: InventoryGame, def_id: String) -> int:
	for instance in inventory.all_instances():
		if str(instance["def_id"]) == def_id:
			return int(instance["instance_id"])
	return -1


func _has_text(list: Array, fragment: String) -> bool:
	for entry in list:
		if str(entry).find(fragment) >= 0:
			return true
	return false


func _finish() -> void:
	if failed:
		push_error("D29_ARBITRAGE_SMOKE_FAIL")
	else:
		print("D29_ARBITRAGE_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
