extends SceneTree

## 阶段 3 仓库测试：分区容量、种子叠放、仓库满时的待领取结果、领取不可重复、
## 回收与升级、存档 v2→v3 迁移。

const TEST_SAVE := "user://stage3_warehouse_save.json"

var failed := false


func _initialize() -> void:
	for test in [
		_test_capacity_and_stacking,
		_test_harvest_overflow_to_pending,
		_test_claim_once_and_recycle,
		_test_warehouse_upgrade,
		_test_v2_to_v3_migration,
	]:
		if failed:
			break
		test.call()
	_cleanup()
	if failed:
		print("STAGE3_WAREHOUSE_FAIL")
		quit(1)
	else:
		print("STAGE3_WAREHOUSE_PASS")
		quit(0)


func _fresh_game() -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261002)
	game.new_game(1000)
	return game


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("STAGE3_WAREHOUSE_FAIL: " + message)
	failed = true


func _test_capacity_and_stacking() -> void:
	var game := _fresh_game()
	_check(game.warehouse_capacity() == 60, "warehouse level 1 gives 60 slots per zone")
	_check(game.seed_slots_used() == 1, "six identical no-entry seeds stack into one slot")
	game.state["seeds"][0]["traits"] = [{"effect": "water_guarantee", "tier": 0}]
	_check(game.seed_slots_used() == 2, "a different entry signature opens a new slot")
	for index in range(98):
		game.state["seeds"].append({"id": 900000 + index, "kind": "cabbage", "traits": []})
	_check(game.seed_slots_used() == 3, "104 identical seeds occupy two slots (99 per slot) plus the entry slot")
	_check(game.crop_slots_used() == 0, "crop zone starts empty")


func _test_harvest_overflow_to_pending() -> void:
	var game := _fresh_game()
	# 填满作物区（60 批）
	for index in range(59):
		game.state["crop_batches"].append({
			"id": 800000 + index, "plot_id": 1, "kind": "cabbage", "count": 5,
			"base_score": 200, "per_crop_score": 200, "planted_at": 1, "harvested_at": 2,
		})
	game.plant(1, 5000)
	var in_stock := game.harvest(1, 6200)
	_check(in_stock["ok"] and in_stock["stored_crops"] and in_stock["stored_seeds"], "harvest stores into a warehouse with space")
	_check(game.crop_slots_used() == 60, "crop zone is exactly full now")
	game.plant(2, 6300)
	var overflow := game.harvest(2, 7500)
	_check(overflow["ok"] and not overflow["stored_crops"], "crop overflow goes to pending results")
	_check(game.state["pending"]["crops"].size() == 1, "pending holds exactly the overflowing batch")
	_check(game.state["crop_batches"].size() == 60, "crop zone stays at capacity")
	# 重复收获不产生新东西
	_check(not game.harvest(2, 7501)["ok"], "harvest cannot be repeated")


func _test_claim_once_and_recycle() -> void:
	var game := _fresh_game()
	for index in range(60):
		game.state["crop_batches"].append({
			"id": 810000 + index, "plot_id": 1, "kind": "cabbage", "count": 5,
			"base_score": 200, "per_crop_score": 200, "planted_at": 1, "harvested_at": 2,
		})
	game.plant(3, 9000)
	game.harvest(3, 10200)
	_check(game.state["pending"]["crops"].size() == 1 and game.state["pending"]["seeds"].size() == 0, "one crop batch pending; seeds had space")
	var nothing := game.claim_pending()
	_check(nothing["crops"] == 0, "claiming without free space moves nothing")
	var pending_batch: Dictionary = game.state["pending"]["crops"][0]
	var expected_price := game.batch_sale_price(pending_batch)
	var sell := game.sell_pending_crop(int(pending_batch["id"]))
	_check(sell["ok"] and sell["coins"] == expected_price, "pending batch sells at its default price")
	var moved := game.claim_pending()
	_check(moved["crops"] == 0, "nothing left to claim after selling the pending batch")
	# 种子区精确填满 60 格，且让无词条亲本的后代无论如何都要开新格：
	# 无词条组与全部单词条组合都叠到 99（占 1+42 格），再用双词条组合补到 60 格。
	var no_trait_count := 0
	for seed in game.state["seeds"]:
		if seed.get("traits", []).is_empty():
			no_trait_count += 1
	for index in range(no_trait_count, BreedingDefs.SEED_STACK_MAX):
		game.state["seeds"].append({"id": 830000 + index, "kind": "cabbage", "traits": []})
	var effects: Array = BreedingDefs.EFFECTS.keys()
	var made := 0
	for kind in ["cabbage", "carrot"]:
		for first in range(effects.size()):
			for tier in range(BreedingDefs.EFFECTS[effects[first]]["tiers"].size()):
				for copy in range(BreedingDefs.SEED_STACK_MAX):
					game.state["seeds"].append({"id": 840000 + made, "kind": kind, "traits": [{"effect": effects[first], "tier": tier}]})
					made += 1
	for kind in ["cabbage", "carrot"]:
		for first in range(effects.size()):
			for second in range(first + 1, effects.size()):
				if game.seed_slots_used() >= game.warehouse_capacity():
					break
				game.state["seeds"].append({"id": 860000 + made, "kind": kind, "traits": [{"effect": effects[first], "tier": 0}, {"effect": effects[second], "tier": 0}]})
				made += 1
	_check(game.seed_slots_used() == game.warehouse_capacity(), "seed zone filled to exactly %d slots" % game.warehouse_capacity())
	game.plant(4, 11000)
	var seed_overflow := game.harvest(4, 12200)
	_check(seed_overflow["ok"] and not seed_overflow["stored_seeds"], "any new seed overflows the exactly-full seed zone into pending")
	var pending_seed_id := int(game.state["pending"]["seeds"][0]["id"])
	var recycle := game.recycle_pending_seed(pending_seed_id)
	_check(recycle["ok"] and recycle["coins"] == 5, "recycling a pending seed yields 5 coins")
	var claimed := game.claim_pending()
	_check(claimed["seeds"] >= 1, "freed space lets pending seeds move in")
	var pending_after: int = game.state["pending"]["seeds"].size()
	var again := game.claim_pending()
	_check(again["seeds"] == 0 or game.state["pending"]["seeds"].size() == pending_after, "second claim adds nothing new")


func _test_warehouse_upgrade() -> void:
	var game := _fresh_game()
	game.state["coins"] = 1000
	_check(game.upgrade_warehouse() != "", "warehouse upgrade fails below 1200 coins")
	game.state["coins"] = 1200
	_check(game.upgrade_warehouse() == "" and int(game.state["warehouse_level"]) == 2, "warehouse upgrade to level 2 costs 1200")
	_check(game.warehouse_capacity() == 120, "level 2 warehouse gives 120 slots")
	game.state["coins"] = 15000
	_check(game.upgrade_warehouse() == "" and int(game.state["warehouse_level"]) == 3, "warehouse upgrade to level 3 costs 15000")
	game.state["coins"] = 17000
	_check(game.upgrade_warehouse() == "" and int(game.state["warehouse_level"]) == 4, "warehouse upgrade to level 4 costs 17000")
	_check(game.upgrade_warehouse() != "", "warehouse cannot upgrade past level 4")
	_check(game.warehouse_capacity() == 480, "level 4 warehouse gives 480 slots")


func _test_v2_to_v3_migration() -> void:
	var v2 := {
		"version": 2,
		"next_id": 40,
		"coins": 300,
		"farming_exp": 120,
		"plant_exp": {"cabbage": 120},
		"shop_level": 1,
		"can_level": 1,
		"fertilizers": {"basic": 3, "mutation": 0, "preserve": 0, "golden": 0},
		"plots": [],
		"seeds": [{"id": 20, "kind": "cabbage", "traits": []}],
		"crop_batches": [{
			"id": 30, "plot_id": 2, "kind": "cabbage", "count": 5, "base_score": 200,
			"per_crop_score": 245, "planted_at": 1, "harvested_at": 2,
		}],
		"created_at": 1,
	}
	for index in range(6):
		if index == 0:
			v2["plots"].append({
				"id": 1, "seed_id": 19, "planted_at": 1000, "ready_at": 2200, "roll_seed": 55,
				"kind": "cabbage", "snapshot": {"farming_level": 2, "plant_level": 1},
				"watered_segments": [0], "fertilizer": {}, "preroll": {"seed_count": 2, "fluctuation_pct": 5, "encounters": [{"tier": 40, "offset": 100}]},
				"events": [{"t": 1000, "type": "plant", "text": "播种了白菜。"}],
			})
		else:
			v2["plots"].append({
				"id": index + 1, "seed_id": 0, "planted_at": 0, "ready_at": 0, "roll_seed": 0,
				"kind": "", "snapshot": {}, "watered_segments": [], "fertilizer": {}, "preroll": {}, "events": [],
			})
	var game := FarmGame.new()
	_check(game.load_state(v2), "version 2 save must migrate to version 3")
	_check(game.state["version"] == 5, "migrated save reports version 5")
	_check(game.state["warehouse_level"] == 1 and game.state["breeder"]["owned"] == false, "migration fills warehouse and breeder defaults")
	_check(game.state["pending"]["crops"].is_empty() and game.state["pending"]["seeds"].is_empty(), "migration starts with empty pending")
	_check(game.get_plot(1)["parent_traits"] == [], "growing plot gets an empty parent entry list")
	_check(game.batch_sale_price(game.state["crop_batches"][0]) == int(floor(5.0 * 245 * 1.2 / 100.0)), "old batch keeps its per-crop score pricing")
	_check(game.state["crop_batches"][0]["attributes"] == {"water": 0, "fiber": 0, "color": 0}, "old batch gets zero placeholder attributes")
	_check(game.plant_seed(2, 20, 2500) == "", "old no-entry seed still plants after migration")
	var harvest := game.harvest(1, 2300)
	_check(harvest["ok"], "migrated growing plot still harvests")
	_check(game.recycle_seed(int(game.state["seeds"][0]["id"]))["ok"], "recycling works on migrated seeds")


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
