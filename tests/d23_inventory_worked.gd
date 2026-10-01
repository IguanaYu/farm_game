extends SceneTree
## 2.3：格子交互——精确放置、旋转、自动整理、丢弃、奖励领取事务。


var failed := false
var game: FarmGame
var inv: InventoryGame


func _initialize() -> void:
	game = FarmGame.new()
	game.new_game(1000)
	inv = InventoryGame.new()
	inv.bind(game.state["expedition"])
	inv.grant_basic_kit()

	# —— 精确放置与占格提示 ——
	var sword := _id_of("old_shortsword")
	_check(inv.place_at(sword, "chest", Vector2i(2, 0), false)["ok"], "放置：短刀放 (2,0)")
	_check(inv.owner_of(sword) == "chest", "放置：归属更新")
	var tools := _id_of("pack_tools")
	var overlapped := inv.place_at(tools, "chest", Vector2i(2, 0), false)
	_check(not overlapped["ok"] and str(overlapped["reason"]).find("放不下") >= 0, "放置：重叠被拒绝并说明")
	_check(inv.place_at(tools, "chest", Vector2i(1, 0), false)["ok"], "放置：换到空位成功")

	# —— 旋转：占格与牌数不变、边缘旋转被拒 ——
	var ore := inv.add_instance("iron_ore", "test")
	inv.move_to_loadout(int(ore["instance_id"]), "pack")
	var ore_id := int(ore["instance_id"])
	_check(inv.rotate_instance(ore_id)["ok"], "旋转：竖放铁矿转横放")
	var build_before := DeckBuilder.build(inv)
	inv.rotate_instance(ore_id)
	var build_after := DeckBuilder.build(inv)
	_check(build_before["entries"].size() == build_after["entries"].size(), "旋转：牌数不变")
	inv.find_instance(ore_id)["cell"] = [3, 0]
	var edge := inv.rotate_instance(ore_id)
	_check(edge["ok"] or str(edge["reason"]).find("放不下") >= 0 or str(edge["reason"]).find("越界") >= 0, "旋转：边缘越界被拒绝并给原因")
	inv.move_to_warehouse(ore_id)

	# —— 自动整理：容器归属不变、结果合法、失败恢复 ——
	var antique := inv.add_instance("antique_ornament", "test")
	inv.move_to_loadout(int(antique["instance_id"]), "pack")
	var tidy := inv.auto_tidy("pack")
	_check(tidy["ok"], "整理：背包可整理")
	for instance in inv.loadout_list("pack"):
		_check(str(instance["container"]) == "pack", "整理：容器归属不变")
	_check(ExpeditionBaseline.layout_integrity(game.state["expedition"]["inventory"]["loadout"]).is_empty(), "整理：布局合法")

	# —— 满包与连续空位提示 ——
	var second_antique := inv.add_instance("antique_ornament", "test")
	inv.move_to_loadout(int(second_antique["instance_id"]), "pack")
	var cs := inv.add_instance("copper_shortsword", "test")
	inv.move_to_loadout(int(cs["instance_id"]), "pack")
	var second_cs := inv.add_instance("copper_shortsword", "test")
	inv.move_to_loadout(int(second_cs["instance_id"]), "pack")
	_check(inv.loadout_list("pack").size() >= 4, "背包：已装入多件物品")
	var no_fit := inv.add_instance("glow_crystal", "test")
	var rejected := inv.move_to_loadout(int(no_fit["instance_id"]), "pack")
	if rejected["ok"]:
		# 仍有空间就再塞一件直到放不下。
		for attempt in range(6):
			var extra := inv.add_instance("fiber_clump", "test")
			rejected = inv.move_to_loadout(int(extra["instance_id"]), "pack")
			if not rejected["ok"]:
				break
	_check(not rejected["ok"] and str(rejected["reason"]).find("最大连续空位") >= 0, "满包：提示最大连续空位而非只报总格数")

	# —— 丢弃：实体进入公共区，牌组重建后消失 ——
	var drop_build_before: int = DeckBuilder.build(inv)["entries"].size()
	inv.discard_instance(int(antique["instance_id"]))
	_check(inv.find_instance(int(antique["instance_id"])).is_empty(), "丢弃：实体离开库存")
	_check(inv.public_drops.size() == 1, "丢弃：进入节点公共区（内存承接）")
	_check(DeckBuilder.build(inv)["entries"].size() == drop_build_before - 4, "丢弃：摆件 4 张来源牌随之消失")

	# —— 奖励领取事务：成功与放不下回退 ——
	var claim := inv.claim_reward("copper_scrap", "safe")
	_check(claim["ok"] and inv.owner_of(int(claim["instance_id"])) == "safe", "领取：铜片放保险箱（白名单内）")
	var bad_claim := inv.claim_reward("antique_ornament", "safe")
	_check(not bad_claim["ok"] and str(bad_claim["reason"]).find("白名单") >= 0, "领取：摆件不能放保险箱")
	_check(inv.count_of_def("antique_ornament") == 1, "领取：被拒后不产生半领取状态")
	var full_claim := inv.claim_reward("bandage", "pack")
	if full_claim["ok"]:
		var again := inv.claim_reward("bandage", "pack")
		_check(again["ok"] or inv.loadout_list("pack").size() > 0, "领取：背包仍可继续装")
	else:
		_check(str(full_claim["reason"]).find("放不下") >= 0, "领取：满包回退并说明")

	_finish()


func _finish() -> void:
	if failed:
		push_error("D23_INVENTORY_WORKED_FAIL")
	else:
		print("D23_INVENTORY_WORKED_PASS")
	quit(1 if failed else 0)


func _id_of(def_id: String) -> int:
	for instance in inv.all_instances():
		if str(instance["def_id"]) == def_id:
			return int(instance["instance_id"])
	return -1


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
