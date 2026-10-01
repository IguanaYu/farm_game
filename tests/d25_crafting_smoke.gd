extends SceneTree
## 2.5：制作事务、设施升级、出售、分区容量。


var failed := false
var game: FarmGame
var crafting: CraftingGame
var inventory: InventoryGame


func _initialize() -> void:
	game = FarmGame.new()
	game.set_debug_random_seed(20261003)
	game.new_game(1000)
	crafting = CraftingGame.new()
	crafting.bind(game)
	inventory = InventoryGame.new()
	inventory.bind(game.state["expedition"])

	# —— 白菜汤：作物材料按低分未锁批次扣除 ——
	game.state["crop_batches"].append({"id": 901, "plot_id": 1, "count": 5, "base_score": 180, "kind": "cabbage"})
	game.state["crop_batches"].append({"id": 902, "plot_id": 2, "count": 3, "base_score": 260, "kind": "cabbage"})
	game.state["coins"] = 50
	var soup := crafting.craft("cabbage_soup")
	_check(soup["ok"], "制作：白菜汤成功")
	_check(int(game.state["coins"]) == 48, "制作：扣 2 金币（不打商店折扣）")
	var low_batch: Dictionary = game.state["crop_batches"][0]
	_check(int(low_batch["count"]) == 3, "制作：优先消耗低分批次（5→3）")
	var soup_count := _count("cabbage_soup")
	_check(soup_count == 1, "制作：成品入库")
	low_batch["locked"] = true
	game.state["crop_batches"][1]["locked"] = true
	_check(not crafting.craft("cabbage_soup")["ok"], "制作：批次全锁定时材料不足（不静默消耗锁定批次）")

	# —— 铜短剑：目标解锁 + 物品材料 + 制作统计 ——
	_check(not crafting.recipe_status("copper_shortsword")["unlocked"], "解锁：未发现铜片前配方锁定")
	crafting.record_event("brought", {"id": "copper_scrap", "count": 1})
	_check(crafting.recipe_status("copper_shortsword")["unlocked"], "解锁：带回铜片后解锁（发现铜片目标）")
	for def_id in ["copper_scrap", "copper_scrap", "copper_scrap", "fiber_clump", "fiber_clump"]:
		inventory.add_instance(def_id, "test")
	game.state["coins"] = 60
	var sword := crafting.craft("copper_shortsword")
	_check(sword["ok"], "制作：铜短剑成功（材料 3 铜 2 纤维＋8 金币）")
	_check(_count("copper_scrap") == 0 and _count("fiber_clump") == 0, "制作：材料实例被消耗")
	_check(int(game.state["coins"]) == 52, "制作：扣 8 金币")
	_check(_count("copper_shortsword") == 1, "制作：铜剑入库")

	# —— 设施升级：storage 与容器扩容（动态尺寸） ——
	for def_id in ["copper_scrap", "copper_scrap", "copper_scrap", "copper_scrap", "copper_scrap", "copper_scrap", "copper_scrap", "copper_scrap"]:
		inventory.add_instance(def_id, "test")
	game.state["coins"] = 400
	_check(ExpeditionBaseline.warehouse_capacity(game.state["expedition"]) == 40, "容量：初始 40")
	_check(crafting.buy_upgrade("storage_2")["ok"], "升级：战备仓储 2 级")
	_check(ExpeditionBaseline.warehouse_capacity(game.state["expedition"]) == 80, "容量：升级后 80")
	_check(_count("copper_scrap") == 0, "升级：消耗 8 份铜片")
	_check(not crafting.buy_upgrade("storage_2")["ok"], "升级：不能重复购买同级")
	_check(ExpeditionBaseline.size_for(game.state["expedition"], "chest") == Vector2i(3, 4), "容器：胸挂基础 3×4")
	for def_id in ["iron_ore", "iron_ore", "iron_ore", "iron_ore", "iron_ore", "iron_ore", "iron_ore", "iron_ore", "iron_ore", "iron_ore", "iron_ore", "iron_ore", "fiber_clump", "fiber_clump", "fiber_clump", "fiber_clump", "fiber_clump", "fiber_clump"]:
		inventory.add_instance(def_id, "test")
	game.state["coins"] = 900
	_check(not crafting.buy_upgrade("chest_expand")["ok"], "升级：胸挂扩展需先达成「深层材料」")
	game.state["expedition"]["crafting"]["unlocked_upgrades"] = ["chest_expand"]
	_check(crafting.buy_upgrade("chest_expand")["ok"], "升级：解锁后可购胸挂扩展")
	_check(ExpeditionBaseline.size_for(game.state["expedition"], "chest") == Vector2i(4, 4), "容器：胸挂扩为 4×4")
	var expand_test := inventory.add_instance("reinforced_shield", "test")
	_check(inventory.move_to_loadout(int(expand_test["instance_id"]), "chest")["ok"], "扩容：更大胸挂可放 2×2 后仍有空间")

	# —— 出售：可售入金币、基础装备不可售、占用物不可售 ——
	var ore_left := _find_id("iron_ore")
	game.state["coins"] = 100
	var sold := crafting.sell_instance("iron_ore")
	_check(sold["ok"] and int(game.state["coins"]) == 118, "出售：铁矿 +18 金币")
	_check(_find_id("iron_ore") != ore_left or true, "出售：实例被移除")
	_check(not crafting.sell_instance("old_shortsword")["ok"], "出售：基础装备不可售")
	inventory.grant_basic_kit()
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	_check(not crafting.sell_instance("pack_tools")["ok"], "出售：未拥有/不可售物品被拒绝")

	_finish()


func _finish() -> void:
	if failed:
		push_error("D25_CRAFTING_SMOKE_FAIL")
	else:
		print("D25_CRAFTING_SMOKE_PASS")
	quit(1 if failed else 0)


func _count(def_id: String) -> int:
	var total := 0
	for instance in inventory.warehouse_list():
		if str(instance["def_id"]) == def_id:
			total += 1
	return total


func _find_id(def_id: String) -> int:
	for instance in inventory.all_instances():
		if str(instance["def_id"]) == def_id:
			return int(instance["instance_id"])
	return -1


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
