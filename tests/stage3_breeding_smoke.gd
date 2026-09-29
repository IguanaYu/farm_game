extends SceneTree

## 阶段 3 育种规则测试：词条生成的不变量与边界、概率表复算、属性分配、
## 逐粒播种、育种机计时/模板/容量。固定随机种子与受控时间。

const TEST_SAVE := "user://stage3_breeding_save.json"

var failed := false


func _initialize() -> void:
	for test in [
		_test_child_trait_invariants,
		_test_probability_table,
		_test_attribute_allocation,
		_test_plant_by_seed_id,
		_test_harvest_children_determinism,
		_test_breeder_lifecycle,
	]:
		if failed:
			break
		test.call()
	_cleanup()
	if failed:
		print("STAGE3_BREEDING_FAIL")
		quit(1)
	else:
		print("STAGE3_BREEDING_PASS")
		quit(0)


func _fresh_game() -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261001)
	game.new_game(1000)
	return game


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("STAGE3_BREEDING_FAIL: " + message)
	failed = true


func _traits_valid(traits: Array) -> bool:
	if traits.size() > BreedingDefs.TRAIT_LIMIT:
		return false
	var seen: Dictionary = {}
	for entry in traits:
		var effect: String = entry["effect"]
		if seen.has(effect) or not BreedingDefs.EFFECTS.has(effect):
			return false
		seen[effect] = true
		if int(entry["tier"]) < 0 or int(entry["tier"]) >= BreedingDefs.EFFECTS[effect]["tiers"].size():
			return false
	return true


func _test_child_trait_invariants() -> void:
	var game := _fresh_game()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var parents: Array = [
		[],
		[{"effect": "water_guarantee", "tier": 0}],
		[
			{"effect": "water_guarantee", "tier": 1},
			{"effect": "fiber_tendency", "tier": 0},
			{"effect": "color_guarantee", "tier": 2},
		],
		[
			{"effect": "water_guarantee", "tier": 2},
			{"effect": "fiber_guarantee", "tier": 2},
			{"effect": "color_guarantee", "tier": 2},
			{"effect": "water_tendency", "tier": 3},
		],
	]
	for sample in range(4000):
		var parent: Array = parents[sample % parents.size()]
		var preserve: bool = sample % 2 == 0
		var mutation: bool = sample % 3 == 0
		var child := game._generate_child_traits(parent, preserve, mutation, rng)
		_check(_traits_valid(child), "child traits must stay within limit, unique effects and legal tiers")
		var parent_tiers: Dictionary = {}
		for entry in parent:
			parent_tiers[entry["effect"]] = int(entry["tier"])
		for entry in child:
			if parent_tiers.has(entry["effect"]):
				var parent_tier := int(parent_tiers[entry["effect"]])
				var child_tier := int(entry["tier"])
				# 继承的词条只能同档或 +1 档；亲本有但未继承的效果可被当作全新词条从 0 档重新抽到。
				_check(child_tier == 0 or (child_tier >= parent_tier and child_tier <= parent_tier + 1), "inherited traits stay at the same tier or upgrade by one; lost-then-redrawn traits restart at tier 0")
			else:
				_check(int(entry["tier"]) == 0, "brand new traits must start at the lowest tier")
	# 四条满配亲本：任何情况下后代不超过 4 条
	var full_parent: Array = parents[3]
	for sample in range(2000):
		var child := game._generate_child_traits(full_parent, sample % 2 == 0, true, rng)
		_check(child.size() <= 4, "full parent must never exceed four traits even with mutation fertilizer")
	# 固定种子完全可复现
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 777
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 777
	for sample in range(200):
		var a := game._generate_child_traits(parents[2], true, true, rng_a)
		var b := game._generate_child_traits(parents[2], true, true, rng_b)
		_check(a == b, "same seed must reproduce the same draw sequence")


func _test_probability_table() -> void:
	var game := _fresh_game()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var samples := 40000
	# 继承保留率（亲本 1 条）。注意：未继承时新词条有 70%×1/6 的机会重新抽到同一效果（0 档），
	# 因此"子代含有该词条"的概率 = keep + (1-keep)×0.7/6。
	var kept_normal := 0
	var kept_preserve := 0
	var parent_one: Array = [{"effect": "water_guarantee", "tier": 0}]
	for sample in range(samples):
		var normal_child := game._generate_child_traits(parent_one, false, false, rng)
		if normal_child.size() > 0 and normal_child[0]["effect"] == "water_guarantee":
			kept_normal += 1
		var preserve_child := game._generate_child_traits(parent_one, true, false, rng)
		if preserve_child.size() > 0 and preserve_child[0]["effect"] == "water_guarantee":
			kept_preserve += 1
	var expected_normal := 0.30 + (1.0 - 0.30) * 0.70 / 6.0
	var expected_preserve := 0.80 + (1.0 - 0.80) * 0.70 / 6.0
	_check(abs(float(kept_normal) / samples - expected_normal) < 0.02, "normal contain-rate must be ~%.3f (got %.3f)" % [expected_normal, float(kept_normal) / samples])
	_check(abs(float(kept_preserve) / samples - expected_preserve) < 0.02, "preserve contain-rate must be ~%.3f (got %.3f)" % [expected_preserve, float(kept_preserve) / samples])
	# 升档率：guarantee 0→1（保种 8% / 普通 4%）。每粒后代出现升档的概率 = 继承率 × 升档率。
	var upgraded_normal := 0
	var upgraded_preserve := 0
	var normal_children := 0
	var preserve_children := 0
	for sample in range(samples * 2):
		var normal_child := game._generate_child_traits(parent_one, false, false, rng)
		normal_children += 1
		if normal_child.size() > 0 and normal_child[0]["effect"] == "water_guarantee" and int(normal_child[0]["tier"]) == 1:
			upgraded_normal += 1
		var preserve_child := game._generate_child_traits(parent_one, true, false, rng)
		preserve_children += 1
		if preserve_child.size() > 0 and preserve_child[0]["effect"] == "water_guarantee" and int(preserve_child[0]["tier"]) == 1:
			upgraded_preserve += 1
	_check(abs(float(upgraded_normal) / normal_children - 0.30 * 0.04) < 0.005, "normal per-child upgrade probability must be ~0.012")
	_check(abs(float(upgraded_preserve) / preserve_children - 0.80 * 0.08) < 0.01, "preserve per-child upgrade probability must be ~0.064")
	# 新词条率：空亲本 70% / 变异 80%
	var got_new_normal := 0
	var got_new_mutation := 0
	for sample in range(samples):
		if not game._generate_child_traits([], false, false, rng).is_empty():
			got_new_normal += 1
		if not game._generate_child_traits([], false, true, rng).is_empty():
			got_new_mutation += 1
	_check(abs(float(got_new_normal) / samples - 0.70) < 0.02, "new entry rate at 0 kept must be ~70%%")
	_check(abs(float(got_new_mutation) / samples - 0.80) < 0.02, "mutation new entry rate at 0 kept must be ~80%%")
	# 新词条只会出现在未拥有的效果上（构造性检查：4 条满配亲本也不会重复或超限）
	var four_parent: Array = []
	for effect in ["fiber_guarantee", "color_guarantee", "water_tendency", "fiber_tendency"]:
		four_parent.append({"effect": effect, "tier": 0})
	for sample in range(3000):
		var child := game._generate_child_traits(four_parent, false, false, rng)
		_check(_traits_valid(child), "four-effect parent children stay valid")
		_check(child.size() <= 4, "four-trait parent never exceeds the cap")
	# 品质分 = 最高单条
	_check(BreedingDefs.quality_score([]) == 0, "quality of no-entry seed is 0")
	_check(BreedingDefs.quality_score([{"effect": "water_guarantee", "tier": 2}, {"effect": "water_tendency", "tier": 3}]) == 4, "quality takes the single best entry")
	_check(BreedingDefs.quality_score([{"effect": "color_guarantee", "tier": 1}, {"effect": "fiber_guarantee", "tier": 1}]) == 2, "quality does not sum")
	# 签名：同词条不同顺序视为相同种子
	_check(BreedingDefs.seed_signature({"kind": "cabbage", "traits": [{"effect": "a", "tier": 0}, {"effect": "b", "tier": 1}]}) == BreedingDefs.seed_signature({"kind": "cabbage", "traits": [{"effect": "b", "tier": 1}, {"effect": "a", "tier": 0}]}), "entry order does not affect stacking signature")


func _test_attribute_allocation() -> void:
	var game := _fresh_game()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	# 倾向 +100%：剩余点约 50% 落在水分（权重 200:100:100）
	var plot := {"snapshot": {"farming_level": 3, "plant_level": 2}, "parent_traits": [{"effect": "water_tendency", "tier": 3}]}
	var water_points := 0
	var total_points := 0
	for sample in range(2000):
		var attributes := game._allocate_attributes(plot, rng)
		water_points += int(attributes["water"])
		total_points += int(attributes["water"]) + int(attributes["fiber"]) + int(attributes["color"])
	_check(total_points == 2000 * 5, "all remaining points must be allocated (total = farming + plant level)")
	_check(abs(float(water_points) / total_points - 0.5) < 0.03, "water tendency +100%% draws ~50%% of points (got %.3f)" % (float(water_points) / total_points))
	# 保底先满足且可超出总点数
	var plot2 := {"snapshot": {"farming_level": 1, "plant_level": 1}, "parent_traits": [{"effect": "water_guarantee", "tier": 2}, {"effect": "fiber_guarantee", "tier": 0}]}
	var attributes2 := game._allocate_attributes(plot2, rng)
	_check(int(attributes2["water"]) >= 3 and int(attributes2["fiber"]) >= 1, "guarantees are satisfied even beyond the total point budget")
	_check(int(attributes2["water"]) + int(attributes2["fiber"]) + int(attributes2["color"]) == 4, "no random allocation remains when guarantees consume the budget")
	# 收获写入批次属性，且读档稳定
	game.plant(1, 5000)
	var plot_state := game.get_plot(1)
	plot_state["parent_traits"] = [{"effect": "color_tendency", "tier": 1}]
	var result := game.harvest(1, 6200)
	_check(result["ok"] and not result["batch"]["attributes"].is_empty(), "harvest stores batch attributes")
	var attributes: Dictionary = result["batch"]["attributes"]
	_check(int(attributes["water"]) + int(attributes["fiber"]) + int(attributes["color"]) == 2, "level-1 snapshot gives exactly two attribute points")


func _test_plant_by_seed_id() -> void:
	var game := _fresh_game()
	var target_id := int(game.state["seeds"][2]["id"])
	game.state["seeds"][2]["traits"] = [{"effect": "color_guarantee", "tier": 1}]
	_check(game.plant_seed(3, target_id, 2000) == "", "planting a specific seed must succeed")
	_check(game.get_plot(3)["parent_traits"] == [{"effect": "color_guarantee", "tier": 1}], "plot records the exact parent traits")
	var consumed := true
	for seed in game.state["seeds"]:
		if int(seed["id"]) == target_id:
			consumed = false
	_check(consumed, "planted seed must be removed from the warehouse")
	_check(game.plant_seed(3, target_id, 2100) != "", "planting the same seed twice must fail")
	_check(game.plant_seed(4, 999999, 2100) != "", "planting an unknown seed id must fail")


func _test_harvest_children_determinism() -> void:
	var game := _fresh_game()
	game.state["seeds"][0]["traits"] = [{"effect": "water_guarantee", "tier": 1}, {"effect": "fiber_tendency", "tier": 0}]
	game.plant_seed(1, int(game.state["seeds"][0]["id"]), 3000)
	game.plant(2, 3000)
	var first := game.harvest(1, 4200)
	_check(first["ok"] and first["seeds"] >= 2 and first["seeds"] <= 3, "harvest yields two or three seeds")
	var ids := {}
	for seed in game.state["seeds"]:
		ids[seed["id"]] = true
	_check(ids.size() == game.state["seeds"].size(), "each new seed has a unique id")
	_check(SaveStore.save_state(game.state, TEST_SAVE), "saving after harvest works")
	var snapshot_traits: Array = game.state["seeds"].map(func(seed): return seed["traits"])
	for _attempt in range(3):
		var reloaded := FarmGame.new()
		_check(reloaded.load_state(SaveStore.load_state(TEST_SAVE)), "reload must succeed")
		var reloaded_traits: Array = reloaded.state["seeds"].map(func(seed): return seed["traits"])
		_check(reloaded_traits == snapshot_traits, "seed traits must never reroll across reloads")


func _test_breeder_lifecycle() -> void:
	var game := _fresh_game()
	var t := 100000
	_check(game.buy_breeder(t) != "", "breeder purchase must fail below farming level 2")
	game.state["farming_exp"] = 120
	game.state["coins"] = 20000
	_check(game.buy_breeder(t) == "", "breeder purchase succeeds at farming level 2 with coins")
	_check(game.state["coins"] == 5000, "breeder costs 15000")
	var seed_a: Dictionary = game.state["seeds"][0]
	var seed_b: Dictionary = game.state["seeds"][1]
	seed_a["traits"] = [{"effect": "water_guarantee", "tier": 1}]
	seed_b["traits"] = [{"effect": "color_tendency", "tier": 2}]
	_check(game.set_breeder_template(int(seed_a["id"]), t)["ok"], "setting template A works")
	game.breeder_settle(t + 1800)  # 半个周期
	var status_a := game.breeder_status(t + 1800)
	_check(int(status_a["progress_seconds"]) == 1800, "half cycle recorded as 1800 seconds")
	_check(game.set_breeder_template(int(seed_b["id"]), t + 1800)["ok"], "switching to template B works")
	game.breeder_settle(t + 1800 + 600)
	_check(game.set_breeder_template(int(seed_a["id"]), t + 1800 + 600)["ok"], "switching back to A works")
	var status_a2 := game.breeder_status(t + 2400)
	_check(int(status_a2["progress_seconds"]) == 1800, "template A progress survives switching away and back")
	_check(int(game.state["breeder"]["pending"]) == 0, "no copies produced before a full cycle")
	# 离线跨多个周期：只产到机内容量上限（8）
	game.breeder_settle(t + 2400 + 60 * 60 * 20)
	var status_full := game.breeder_status(t + 2400 + 60 * 60 * 20)
	_check(int(status_full["pending"]) == 8, "offline production caps at machine capacity (got %d)" % status_full["pending"])
	_check(not status_full["running"], "machine pauses when full")
	# 满仓领取：腾不出空间则失败，机内不减；腾出后成功
	var result := game.collect_breeder(t + 2400 + 60 * 60 * 20)
	_check(result["ok"] and int(result["count"]) == 8, "collecting eight copies works when space allows")
	var still_there := false
	for seed in game.state["seeds"]:
		if int(seed["id"]) == int(seed_a["id"]):
			still_there = true
	_check(still_there, "template original stays in the warehouse")
	var template_copies: Array = []
	for seed in game.state["seeds"]:
		if seed["traits"] == seed_a["traits"] and int(seed["id"]) != int(seed_a["id"]):
			template_copies.append(seed)
	_check(template_copies.size() == 8, "eight identical copies were collected")
	# 育种机模板种子不能被回收
	_check(not game.recycle_seed(int(seed_a["id"]))["ok"], "template seed cannot be recycled")
	_check(game.clear_breeder_template(t + 2400 + 60 * 60 * 21) == "", "clearing template works")
	_check(game.recycle_seed(int(seed_a["id"]))["ok"], "recycling works after clearing the template")
	# 升级 1→2 级 17000 金币；2→3 价格待定
	game.state["coins"] = 17000
	_check(game.upgrade_breeder() == "" and int(game.state["breeder"]["level"]) == 2, "breeder upgrade to level 2 costs 17000")
	_check(game.upgrade_breeder() != "", "breeder upgrade to level 3 is placeholder-locked")
	_check(BreedingDefs.cycle_seconds(2) == 55 * 60 and BreedingDefs.capacity(2) == 12, "level 2 breeder: 55 minutes, capacity 12")


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
