extends SceneTree
## 三栏改版域层冒烟：装备槽（主/副武器、头盔、护甲）、洗牌轮次（保险箱永不入堆）、
## 预设 fmt2、结算携带口径（装备=未保护携带、保险箱保留）、人形尸体区域顺序（装备最先、地上最后）。


class MemoryExpedition extends ExpeditionGame:
	func save() -> bool:
		return true


var failed := false
var checks := 0
var clock_ms := 1000


func _initialize() -> void:
	_equipment_slots()
	_deck_rules()
	_presets()
	_settlement()
	_corpse_regions()
	_inrun_equip()
	if failed:
		push_error("D57_EQUIPMENT_SMOKE_FAIL")
	else:
		print("D57_EQUIPMENT_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("D57_CORPSE_FAIL: " + message)


func _fresh_farm() -> Array:
	var farm := FarmGame.new()
	farm.new_game(1000)
	var inv := InventoryGame.new()
	inv.bind(farm.state["expedition"])
	return [farm, inv]


func _by_def(inv: InventoryGame, def_id: String) -> Dictionary:
	for instance in inv.all_instances():
		if str(instance["def_id"]) == def_id:
			return instance
	return {}


func _equipment_slots() -> void:
	var pair := _fresh_farm()
	var inv: InventoryGame = pair[1]
	var grant := inv.grant_basic_kit()
	_check(grant["granted"].size() == 4, "基础套装 4 件（含新草帽）")
	_check(inv.basic_kit_missing().is_empty(), "草帽计入基础部件补领口径")

	var sword := _by_def(inv, "old_shortsword")
	var shield := _by_def(inv, "wooden_shield")
	var hat := _by_def(inv, "straw_hat")
	var tools := _by_def(inv, "pack_tools")
	_check(inv.equip(int(sword["instance_id"]), "main_weapon")["ok"], "武器装备进主武器槽")
	_check(inv.owner_of(int(sword["instance_id"])) == "equipped" and str(sword.get("slot")) == "main_weapon", "归属=equipped 且带槽位")
	_check(inv.equip(int(shield["instance_id"]), "main_weapon")["ok"] == false, "防具不能进武器槽")
	_check(inv.equip(int(shield["instance_id"]), "armor")["ok"], "防具装备进护甲槽")
	_check(inv.equip(int(hat["instance_id"]), "helmet")["ok"], "草帽装备进头盔槽")
	_check(inv.equip(int(hat["instance_id"]), "armor")["ok"] == false, "头盔类不能进护甲槽")
	_check(inv.equip(int(tools["instance_id"]), "off_weapon")["ok"] == false, "工具不能进装备槽")
	_check(inv.move_to_loadout(int(hat["instance_id"]), "chest")["ok"], "装备槽物品可再放进容器")
	_check(inv.owner_of(int(hat["instance_id"])) == "chest", "装备→容器归属切换")
	_check(inv.equip(int(hat["instance_id"]), "helmet")["ok"], "容器物品可重新装备")

	var copper := inv.add_instance("copper_shortsword", "test")
	_check(inv.equip(int(copper["instance_id"]), "main_weapon")["ok"], "占用槽位可换装")
	_check(inv.owner_of(int(sword["instance_id"])) == "warehouse", "换装后旧武器自动回仓库")
	_check(str(inv.equipped_in("main_weapon").get("def_id", "")) == "copper_shortsword", "新武器占住主武器槽")
	_check(inv.equipped_list().size() == 3, "装备槽数量=3（主武/护甲/头盔）")
	_check(inv.unequip(int(copper["instance_id"]))["ok"] and inv.owner_of(int(copper["instance_id"])) == "warehouse", "卸下回仓库")
	_check(not _by_def(inv, "copper_shortsword").has("slot"), "卸下后清除槽位字段")
	_check(inv.unequip(int(copper["instance_id"]))["ok"] == false, "非装备状态不能卸下")
	_check(inv.place_at(int(sword["instance_id"]), "equipped", Vector2i(0, 0), false)["ok"] == false, "equipped 不能当容器放置")

	_check(inv.set_run_occupied("run-57")["ok"], "写入占用")
	_check(inv.equip(int(sword["instance_id"]), "main_weapon")["ok"] == false, "占用期拒绝装备")
	_check(inv.unequip(int(shield["instance_id"]))["ok"] == false, "占用期拒绝卸下")
	inv.clear_run_occupied("run-57")

	var unique: Dictionary = {}
	for instance in inv.all_instances():
		unique[int(instance["instance_id"])] = true
	_check(unique.size() == inv.all_instances().size(), "归属唯一：装备槽纳入 all_instances 不重复")


func _deck_rules() -> void:
	var pair := _fresh_farm()
	var inv: InventoryGame = pair[1]
	inv.grant_basic_kit()
	var sword := _by_def(inv, "old_shortsword")
	var shield := _by_def(inv, "wooden_shield")
	var hat := _by_def(inv, "straw_hat")
	var tools := _by_def(inv, "pack_tools")
	inv.equip(int(sword["instance_id"]), "main_weapon")
	inv.equip(int(hat["instance_id"]), "helmet")
	inv.move_to_loadout(int(tools["instance_id"]), "chest")
	inv.move_to_loadout(int(shield["instance_id"]), "pack")
	var ore := inv.add_instance("iron_ore", "test")
	var cluster := inv.add_instance("radiant_cluster", "t2")
	_check(inv.move_to_loadout(int(cluster["instance_id"]), "safe")["ok"], "保险箱仍可放入白名单物品")
	inv.move_to_warehouse(int(cluster["instance_id"]))
	inv.move_to_loadout(int(ore["instance_id"]), "safe")

	var preview := inv.deck_preview()
	_check(int(preview["totals"][1]) == 6, "第 1 回合=装备槽牌（短刀 2＋草帽 4）")
	_check(int(preview["totals"][2]) == 2, "第 2 回合=胸挂牌（工具 2）")
	_check(int(preview["totals"][3]) == 4, "第 3 回合=背包牌（木盾 4）")
	_check(int(preview["counts"][1]["slash"]) == 2, "装备牌按张计数（切击×2）")
	var safe_cards := 0
	for round in [1, 2, 3]:
		for card in preview["rounds"][round]:
			if int(card["instance_id"]) == int(ore["instance_id"]):
				safe_cards += 1
	_check(safe_cards == 0, "保险箱的牌永不入堆")
	var built := DeckBuilder.build(inv)
	_check(built["totals"] == preview["totals"], "DeckBuilder 与预览口径一致")

	var check := inv.loadout_check()
	_check(check["hard_blocks"].is_empty(), "装备+容器配装通过准备检查")
	_check(ExpeditionBaseline.is_container("safe"), "safe 仍是合法容器（JOIN_ROUND 移除不破坏放置校验）")

	var carried := inv.carry_sell_value()
	_check(carried == int(ItemDefs.get_item("iron_ore")["base_value"]), "装备槽计入携带可售价值（保险箱也计）")


func _presets() -> void:
	var pair := _fresh_farm()
	var inv: InventoryGame = pair[1]
	inv.grant_basic_kit()
	var sword := _by_def(inv, "old_shortsword")
	var hat := _by_def(inv, "straw_hat")
	var tools := _by_def(inv, "pack_tools")
	inv.equip(int(sword["instance_id"]), "main_weapon")
	inv.equip(int(hat["instance_id"]), "helmet")
	inv.move_to_loadout(int(tools["instance_id"]), "chest")

	var preset := LoadoutPresets.capture(inv)
	_check(int(preset["fmt"]) == 2, "预设 fmt=2")
	_check(preset["equipment"].size() == 2 and preset["items"].size() == 1, "预设快照含装备槽与容器")
	inv.clear_loadout()
	_check(inv.equipped_list().is_empty() and inv.loadout_list("chest").is_empty(), "清空配置同时卸下装备")
	var applied := LoadoutPresets.apply(inv, preset)
	_check(applied["ok"] and int(applied["applied"]) == 3, "应用复原装备+容器 3 件")
	_check(str(inv.equipped_in("main_weapon").get("def_id", "")) == "old_shortsword", "主武器槽精确复原")
	_check(str(inv.equipped_in("helmet").get("def_id", "")) == "straw_hat", "头盔槽精确复原")

	inv.clear_loadout()
	var legacy := {"fmt": 1, "items": preset["items"]}
	var legacy_result := LoadoutPresets.apply(inv, legacy)
	_check(legacy_result["ok"] and int(legacy_result["applied"]) == 1, "fmt1 旧预设兼容（只复原容器）")
	_check(inv.equipped_list().is_empty(), "fmt1 预设不产生装备")


func _settlement() -> void:
	# 死亡：装备槽=未保护携带（损失）；撤离：装备槽随行带回。
	var pair := _fresh_farm()
	var farm: FarmGame = pair[0]
	var inv: InventoryGame = pair[1]
	inv.grant_basic_kit()
	var sword := _by_def(inv, "old_shortsword")
	var hat := _by_def(inv, "straw_hat")
	var ore := inv.add_instance("iron_ore", "test")
	inv.equip(int(sword["instance_id"]), "main_weapon")
	inv.equip(int(hat["instance_id"]), "helmet")
	inv.move_to_loadout(int(ore["instance_id"]), "safe")
	var game := MemoryExpedition.new()
	game.game = farm
	game.run = ExpeditionGame.compose_run(farm, {}, "d57-death", 1000, false, "test")
	_check(game.run["inventory"]["loadout"].get("equipped", []).size() == 2, "局快照携带装备槽")
	var death := game._settle_run("death", 1)
	_check(bool(death["ok"]), "死亡结算成功")
	var lost_ids := {}
	for entry in death["settlement"]["lost"]:
		lost_ids[int(entry["instance_id"])] = true
	var protected_ids := {}
	for entry in death["settlement"]["protected"]:
		protected_ids[int(entry["instance_id"])] = true
	_check(lost_ids.has(int(sword["instance_id"])) and lost_ids.has(int(hat["instance_id"])), "死亡：装备槽物品按携带损失")
	_check(protected_ids.has(int(ore["instance_id"])), "死亡：保险箱白名单保留")
	_check(inv.find_instance(int(sword["instance_id"])).is_empty() and inv.equipped_list().is_empty(), "农场侧装备已随结算移除")

	pair = _fresh_farm()
	farm = pair[0]
	inv = pair[1]
	inv.grant_basic_kit()
	sword = _by_def(inv, "old_shortsword")
	inv.equip(int(sword["instance_id"]), "off_weapon")
	game = MemoryExpedition.new()
	game.game = farm
	game.run = ExpeditionGame.compose_run(farm, {}, "d57-extract", 1000, false, "test")
	var extract := game._settle_run("extract", 40)
	_check(bool(extract["ok"]), "撤离结算成功")
	var returned_ids := {}
	for entry in extract["settlement"]["returned"]:
		returned_ids[int(entry["instance_id"])] = true
	_check(returned_ids.has(int(sword["instance_id"])), "撤离：装备槽物品随行带回")
	_check(inv.owner_of(int(sword["instance_id"])) == "equipped", "撤离：带回装备保持装备状态（配装延续）")


func _skeleton_game(skeleton := true) -> MemoryExpedition:
	var farm := FarmGame.new()
	farm.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(farm.state["expedition"])
	inventory.grant_basic_kit()
	for item in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(item["instance_id"]), "chest")
	var game := MemoryExpedition.new()
	game.game = farm
	game.run = ExpeditionGame.compose_run(farm, {}, "d57-corpse", 1000, false, "test")
	game.rng.seed = 57
	game.search_clock = func() -> int: return clock_ms
	game.run["current"] = {"row": 3 if skeleton else 1, "col": 1 if skeleton else 0}
	game.run["phase"] = "node"
	game._resolve_node(game.current_node())
	var battle: Dictionary = game.start_battle()
	var combat: CombatGame = battle["combat"]
	for enemy in combat.state["enemies"]:
		enemy["alive"] = false
		enemy["hp"] = 0
	combat._events_check_outcome([])
	game.finish_battle(combat)
	return game


func _resolved(game: ExpeditionGame) -> Dictionary:
	return game.run["resolved"][game.node_id(int(game.run["current"]["row"]), int(game.run["current"]["col"]))]


func _corpse_regions() -> void:
	var game := _skeleton_game(true)
	var regions: Array = _resolved(game)["corpses"][0]["regions"]
	var ids: Array = []
	for region in regions:
		ids.append(str(region["id"]))
	_check(ids == ["main_weapon", "armor", "chest", "pack", "ground"], "人形尸体区域顺序：装备最先、地上最后")
	_check(str(regions[0]["items"][0]["def_id"]) == "copper_shortsword" and regions[0]["size"] == [1, 3], "主武器槽区装敌人武器（1×3）")
	_check(str(regions[1]["items"][0]["def_id"]) == "leather_bracer", "护甲槽区必掉护具（概率接口默认必掉）")
	_check(str(regions[2]["items"][0]["def_id"]) == "bandage", "胸挂装杂物")
	_check(regions[4]["items"].is_empty(), "地上默认为空（特殊情况才出现）")

	var weapon: Dictionary = regions[0]["items"][0]
	_check(game.loot_action("p1", "search_start", {"source": "e1", "region": "main_weapon"})["ok"], "装备槽区可搜索")
	clock_ms += ItemDefs.search_ms(ItemDefs.quality_of(weapon)) + 1
	_check(game.loot_action("p1", "search_step", {})["ok"] and bool(weapon["revealed"]), "装备槽区计时揭晓")
	_check(str(game.run["loot_searches"].get("p1", {}).get("region", "")) == "armor", "装备槽搜完自动接续护甲槽")
	clock_ms += int(game.run["loot_searches"].get("p1", {}).get("duration", 0)) + 1
	game.loot_action("p1", "search_step", {})
	_check(str(game.run["loot_searches"].get("p1", {}).get("region", "")) == "chest", "护甲搜完接续胸挂（顺序=主武→护甲→胸挂→背包→地上）")

	# 地上区无物品：链到它时直接判完，不产生会话。
	var guard := 0
	while not (game.run.get("loot_searches", {}) as Dictionary).is_empty() and guard < 20:
		guard += 1
		clock_ms += int(game.run["loot_searches"]["p1"]["duration"]) + 1
		_check(game.loot_action("p1", "search_step", {})["ok"], "接续搜索")
	_check(guard < 20, "空地上区自动跳过（接续链自然收敛）")
	_check((regions[4]["searched"] as Array).size() == 4, "地上空格已直接判完")

	var beast := _skeleton_game(false)
	var beast_regions: Array = _resolved(beast)["corpses"][0]["regions"]
	_check(beast_regions.size() == 1 and str(beast_regions[0]["id"]) == "body", "野兽尸体保留单一遗骸区")


func _inrun_equip() -> void:
	var game := _skeleton_game(true)
	var inv := game.member_inventory("p1")
	var sword_id := -1
	for instance in inv.loadout_list("chest"):
		if str(instance["def_id"]) == "old_shortsword":
			sword_id = int(instance["instance_id"])
	_check(sword_id > 0, "局内胸挂有武器")
	_check(game.loot_action("p1", "loot_manage", {"operation": "equip", "instance_id": sword_id, "slot": "off_weapon"})["ok"], "局内可装备到副武器槽")
	_check(str(inv.equipped_in("off_weapon").get("def_id", "")) == "old_shortsword", "局内装备槽归属正确")
	_check(game.loot_action("p1", "loot_manage", {"operation": "unequip", "instance_id": sword_id})["ok"], "局内可卸下装备")
	_check(inv.owner_of(sword_id) == "warehouse", "局内卸下回局仓库")
	var shield_id := -1
	for instance in inv.all_instances():
		if str(instance["def_id"]) == "wooden_shield":
			shield_id = int(instance["instance_id"])
	_check(not game.loot_action("p1", "loot_manage", {"operation": "equip", "instance_id": shield_id, "slot": "off_weapon"})["ok"], "局内装备同样受槽位类别校验")
