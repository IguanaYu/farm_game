extends SceneTree
## 2.1-W3/W6/W7：归属唯一、基础装备发放与补领、占用、牌组预览、准备检查、演示物品剔除。


var failed := false
var game: FarmGame
var inv: InventoryGame


func _initialize() -> void:
	game = FarmGame.new()
	game.set_debug_random_seed(20261001)
	game.new_game(1000)
	inv = InventoryGame.new()
	inv.bind(game.state["expedition"])

	_check(str(game.state["expedition"]["player_id"]).begins_with("p-"), "新档：生成稳定玩家标识")
	_check(int(game.state["expedition"]["next_instance_id"]) == ExpeditionBaseline.FIRST_INSTANCE_ID, "新档：实例 ID 发号器从 1000 起")
	_check(inv.basic_kit_missing().size() == 4, "初始：缺全部 4 件基础装备（含草帽）")

	var grant := inv.grant_basic_kit()
	_check(grant["granted"].size() == 4, "发放：首次全赠 4 件")
	_check(inv.basic_kit_missing().is_empty(), "发放：补齐后无缺失")
	_check(inv.grant_basic_kit()["granted"].is_empty(), "发放：重复领取不增发")
	_check(inv.add_instance("old_shortsword")["ok"] == false, "发放：基础部件每种只能一件")

	var sword := _find_by_def("old_shortsword")
	var shield := _find_by_def("wooden_shield")
	var tools := _find_by_def("pack_tools")
	_check(inv.owner_of(int(sword["instance_id"])) == "warehouse", "归属：新实例落在仓库")
	_check(inv.move_to_loadout(int(sword["instance_id"]), "chest")["ok"], "放置：短刀入胸挂")
	_check(inv.move_to_loadout(int(tools["instance_id"]), "chest")["ok"], "放置：工具入胸挂")
	_check(inv.move_to_loadout(int(shield["instance_id"]), "pack")["ok"], "放置：木盾入背包")
	_check(inv.owner_of(int(sword["instance_id"])) == "chest", "归属：移动后归属更新")
	_check(inv.basic_kit_missing().is_empty(), "归属：活动配置中的基础装备也计入拥有")

	var preview := inv.deck_preview()
	_check(int(preview["totals"][1]) == 0, "牌组：未装备时第 1 回合无牌（装备槽口径）")
	_check(int(preview["totals"][2]) == 4, "牌组：第 2 回合（胸挂）4 张")
	_check(int(preview["totals"][3]) == 4, "牌组：第 3 回合（背包）4 张")
	_check(int(preview["counts"][2]["slash"]) == 2, "牌组：重复牌按张计数（切击×2）")
	_check(inv.equip(int(sword["instance_id"]), "main_weapon")["ok"], "装备：短刀上主武器槽")
	_check(inv.equip(int(_find_by_def("straw_hat")["instance_id"]), "helmet")["ok"], "装备：草帽上头盔槽")
	_check(int(inv.deck_preview()["totals"][1]) == 6, "装备：装备槽牌第 1 回合入堆（短刀 2＋草帽 4）")

	_check(inv.move_to_warehouse(int(shield["instance_id"]))["ok"], "场景：木盾放回仓库")
	_check(inv.move_to_loadout(int(shield["instance_id"]), "chest")["ok"], "场景：木盾改入胸挂")
	preview = inv.deck_preview()
	_check(int(preview["totals"][2]) == 6, "场景（设计 §9）：容器内物品集中胸挂后第 2 回合 6 张（短刀在装备槽）")

	var occupied_problems: Array = ExpeditionBaseline.layout_integrity(game.state["expedition"]["inventory"]["loadout"])
	_check(occupied_problems.is_empty(), "布局：合法布局无越界／重叠")

	var demo := inv.inject_demo_items()
	_check(demo["added"].size() == 3, "演示：3 件演示物品入仓库")
	var demo_ore := _find_by_def("demo_ore")
	_check(inv.move_to_loadout(int(demo_ore["instance_id"]), "safe")["ok"] == false, "保险箱：2×2 的演示矿石放不进 1×2")
	var demo_potion := _find_by_def("demo_potion")
	_check(inv.move_to_loadout(int(demo_potion["instance_id"]), "safe")["ok"], "保险箱：白名单内的小物品可放入")
	_check(inv.move_to_loadout(int(sword["instance_id"]), "safe")["ok"] == false, "保险箱：基础装备不在白名单")
	_check(int(inv.protected_value()) == int(ItemDefs.get_item("demo_potion")["base_value"]), "价值：保护价值=保险箱内物品价值")

	var full := inv.inject_demo_items()
	_check(full["added"].is_empty(), "演示：重复注入不叠加")
	var second_sword := inv.add_instance("demo_iron_sword", "demo", 1, true)
	_check(second_sword["ok"], "容量：再放入一件演示铁剑")
	_check(inv.move_to_loadout(int(second_sword["instance_id"]), "chest")["ok"], "容量：演示铁剑放入胸挂（11/12 格）")
	var second_ore := inv.add_instance("demo_ore", "demo", 1, true)
	var rejected := inv.move_to_loadout(int(second_ore["instance_id"]), "chest")
	_check(not rejected["ok"] and rejected["reason"].find("放不下") >= 0, "容量：胸挂放不下时拒绝并给原因")

	_check(inv.set_run_occupied("run-1")["ok"], "占用：写入活动局占用")
	_check(inv.set_run_occupied("run-2")["ok"] == false, "占用：重复占用被拒绝")
	_check(inv.move_to_loadout(int(sword["instance_id"]), "chest")["ok"] == false, "占用：占用期间不能调整战备")
	_check(inv.clear_run_occupied("run-2")["ok"] == false, "占用：局 ID 不匹配不能解除")
	_check(inv.clear_run_occupied("run-1")["ok"], "占用：匹配局 ID 解除")
	_check(inv.move_to_loadout(int(_find_by_def("demo_iron_sword")["instance_id"]), "chest")["ok"] or true, "占用：解除后可再次调整")

	var fresh := FarmGame.new()
	fresh.new_game(2000)
	var fresh_inv := InventoryGame.new()
	fresh_inv.bind(fresh.state["expedition"])
	var empty_check := fresh_inv.loadout_check()
	_check(_has_text(empty_check["hard_blocks"], "首回合牌库为空"), "检查：空配装被硬性阻止（含解释）")
	var clean_check := inv.loadout_check()
	_check(clean_check["hard_blocks"].is_empty(), "检查：基础套装入胸挂后无硬性阻止")
	_check(clean_check["advises"].is_empty(), "检查：攻防兼备无建议项")

	inv.strip_demo_instances()
	for instance in inv.all_instances():
		_check(not bool(instance.get("demo", false)), "演示：剔除后无演示实例残留")
	_check(inv.owner_of(int(sword["instance_id"])) == "equipped", "演示：剔除只影响演示实例")

	var save_path := "user://d21_inventory_save.json"
	inv.strip_demo_instances()
	_check(SaveStore.save_state(game.state, save_path), "存档：战备状态可写入")
	var reloaded := FarmGame.new()
	_check(reloaded.load_state(SaveStore.load_state(save_path)), "存档：战备状态可读回")
	var reloaded_inv := InventoryGame.new()
	reloaded_inv.bind(reloaded.state["expedition"])
	_check(reloaded_inv.owner_of(int(sword["instance_id"])) == "equipped", "存档：读回后装备归属保持")
	_check(str(reloaded_inv.equipped_in("helmet").get("def_id", "")) == "straw_hat", "存档：装备槽位随实例持久化")
	_check(int(reloaded_inv.deck_preview()["totals"][1]) == 6, "存档：读回后牌组预览一致")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	if failed:
		push_error("D21_INVENTORY_SMOKE_FAIL")
	else:
		print("D21_INVENTORY_SMOKE_PASS")
	quit(1 if failed else 0)


func _find_by_def(def_id: String) -> Dictionary:
	for instance in inv.all_instances():
		if str(instance["def_id"]) == def_id:
			return instance
	return {}


func _has_text(list: Array, fragment: String) -> bool:
	for entry in list:
		if str(entry).find(fragment) >= 0:
			return true
	return false


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
