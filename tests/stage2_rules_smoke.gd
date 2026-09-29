extends SceneTree

## 阶段 2 规则测试：计分构成、时间边界、解锁链、肥料生命周期、一键收获一致性、
## 离线与重复读档稳定性、旧档迁移。全部使用受控时间与固定随机种子，不改系统时钟。

const TEST_SAVE := "user://stage2_rules_save.json"

var failed := false


func _initialize() -> void:
	for test in [
		_test_new_game_defaults,
		_test_v1_migration,
		_test_preroll_determinism,
		_test_score_breakdown_exact,
		_test_watering_boundaries,
		_test_fertilizer_lifecycle,
		_test_harvest_all_equivalence,
		_test_offline_and_reload_stability,
		_test_experience_and_snapshots,
		_test_unlock_chain,
		_test_mid_round_save_roundtrip,
	]:
		if failed:
			break
		test.call()
	_cleanup()
	if failed:
		print("STAGE2_RULES_FAIL")
		quit(1)
	else:
		print("STAGE2_RULES_PASS")
		quit(0)


func _fresh_game() -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20260930)
	game.new_game(1000)
	return game


func _grant_carrot_seed(game: FarmGame, seed_id: int) -> void:
	game.state["seeds"].append({"id": seed_id, "kind": "carrot", "traits": []})


func _test_new_game_defaults() -> void:
	var game := _fresh_game()
	_check(game.state["version"] == 4, "new game writes save version 4")
	_check(game.owned_plot_ids().size() == 6 and game.state["plots"].size() == 10, "new game owns six of ten plot slots")
	_check(game.state["seeds"].size() == 6 and game.seed_counts()["cabbage"] == 6, "new game grants six cabbage seeds")
	_check(game.state["shop_level"] == 1 and game.state["can_level"] == 1, "shop and can start at level 1")
	_check(game.state["fertilizers"].size() == 4, "all four fertilizers start owned at zero uses")
	_check(game.farming_level() == 1, "farming starts at level 1")
	var plot := game.get_plot(1)
	_check(plot["seed_id"] == 0 and plot["fertilizer"].is_empty() and plot["watered_segments"].is_empty(), "plots start clean")


func _test_v1_migration() -> void:
	var legacy_seed_rng := RandomNumberGenerator.new()
	legacy_seed_rng.seed = 777
	var legacy_seed_count: int = legacy_seed_rng.randi_range(2, 3)
	var v1 := {
		"version": 1,
		"next_id": 20,
		"coins": 500,
		"created_at": 900,
		"plots": [],
		"seeds": [{"id": 6, "kind": "cabbage", "traits": []}],
		"crop_batches": [{"id": 7, "plot_id": 2, "count": 5, "base_score": 200, "planted_at": 800, "harvested_at": 900}],
	}
	for index in range(6):
		if index == 0:
			v1["plots"].append({"id": 1, "seed_id": 5, "planted_at": 1000, "ready_at": 2200, "roll_seed": 777})
		else:
			v1["plots"].append({"id": index + 1, "seed_id": 0, "planted_at": 0, "ready_at": 0, "roll_seed": 0})
	var game := FarmGame.new()
	_check(game.load_state(v1), "version 1 save must migrate and load")
	_check(game.state["version"] == 4, "migrated save reports version 4")
	_check(game.state["coins"] == 500, "migration keeps coins")
	_check(game.state["seeds"].size() == 1 and game.state["seeds"][0]["id"] == 6, "migration keeps seeds")
	_check(game.state["crop_batches"].size() == 1, "migration keeps crop batches")
	_check(game.batch_sale_price(game.state["crop_batches"][0]) == 12, "legacy batch still prices at 12 coins")
	var plot := game.get_plot(1)
	_check(plot["kind"] == "cabbage" and plot["snapshot"]["farming_level"] == 1, "growing v1 plot becomes level-1 cabbage round")
	_check(plot["preroll"]["seed_count"] == legacy_seed_count, "migrated preroll seed count matches v1 first draw from roll_seed")
	_check(game.is_ready(1, 2200), "mature v1 crop stays ready")
	_check(game.state["shop_level"] == 1 and game.state["farming_exp"] == 0, "migration fills new progression fields with defaults")


func _test_preroll_determinism() -> void:
	var game := _fresh_game()
	game.plant(1, 2000)
	var preroll: Dictionary = game.get_plot(1)["preroll"].duplicate(true)
	_check(SaveStore.save_state(game.state, TEST_SAVE), "saving growing round must succeed")
	for _attempt in range(3):
		var reloaded := FarmGame.new()
		_check(reloaded.load_state(SaveStore.load_state(TEST_SAVE)), "repeated loads must succeed")
		_check(reloaded.get_plot(1)["preroll"] == preroll, "repeated loads must not reroll the round")
	var harvest := game.harvest(1, 3201)
	_check(harvest["ok"] and harvest["seeds"] == preroll["seed_count"], "harvest must grant the prerolled seed count")


func _test_score_breakdown_exact() -> void:
	var game := _fresh_game()
	_grant_carrot_seed(game, 900)
	game.state["fertilizers"]["golden"] = 1
	_check(game.plant(1, 100000, "carrot") == "", "carrot must plant from granted seed")
	var plot := game.get_plot(1)
	plot["snapshot"] = {"farming_level": 2, "plant_level": 3}
	plot["preroll"]["fluctuation_pct"] = 7
	plot["preroll"]["encounters"] = [{"tier": 40, "offset": 10}, {"tier": 10, "offset": 20}]
	_check(game.water(1, 100100)["ok"], "first carrot segment water must succeed")
	_check(game.water(1, 103700)["ok"], "second carrot segment water must succeed")
	_check(game.apply_fertilizer(1, "golden", 100050)["ok"], "golden fertilizer must apply during growth")
	_check(game.state["fertilizers"]["golden"] == 0, "applying fertilizer consumes one use")
	var result := game.harvest(1, 107200)
	_check(result["ok"], "carrot must harvest at deadline")
	var breakdown: Dictionary = result["batch"]["score_breakdown"]
	_check(breakdown["base"] == 1200, "carrot base score is 1200")
	_check(breakdown["level_bonus"] == 180, "level bonus 15% of 1200 is 180")
	_check(breakdown["fluctuation_bonus"] == 84, "fluctuation 7% of 1200 is 84")
	_check(breakdown["water_bonus"] == 240, "two watered segments at 10% each give 240")
	_check(breakdown["fertilizer_kind"] == "golden" and breakdown["fertilizer_bonus"] == 240, "golden fertilizer gives 20% bonus")
	_check(breakdown["encounter_bonus"] == 50, "encounter tiers 40+10 sum to 50")
	_check(breakdown["per_crop_score"] == 1994, "per-crop score sums to 1994")
	_check(result["batch"]["count"] == 5 and result["batch"]["per_crop_score"] == 1994, "batch stores per-crop score")
	_check(game.batch_sale_price(result["batch"]) == 139, "default price with golden +0.2 floors 9970*1.4/100 to 139 (stage-4 rule)")
	_check(result["batch"]["sale_multiplier_bonus"] == 0.2, "golden batch keeps the +0.2 sale multiplier flag")
	_check(result["exp_gain"] == 120 and int(game.state["plant_exp"]["carrot"]) == 120, "carrot grants 120 exp to farming and carrot")


func _test_watering_boundaries() -> void:
	var game := _fresh_game()
	_grant_carrot_seed(game, 901)
	game.plant(1, 5000, "carrot")
	game.plant(2, 5000)
	var result: Dictionary
	result = game.water(3, 5000)
	_check(not result["ok"], "watering an empty plot fails")
	result = game.water(1, 5100)
	_check(result["ok"] and result["segment"] == 0, "carrot minute ~1 water lands in segment 1")
	result = game.water(1, 5300)
	_check(not result["ok"], "same segment twice is rejected")
	_check(game.get_plot(1)["watered_segments"] == [{"segment": 0, "can_level": 1}], "rejected water does not record")
	result = game.water(1, 8599)
	_check(not result["ok"], "just before the boundary still counts as segment 1")
	result = game.water(1, 8600)
	_check(result["ok"] and result["segment"] == 1, "exactly minute 60 starts segment 2")
	result = game.water(1, 12199)
	_check(not result["ok"], "second water in segment 2 is rejected")
	result = game.water(1, 12200)
	_check(not result["ok"], "watering at maturity is invalid")
	_check(game.get_plot(1)["watered_segments"] == [{"segment": 0, "can_level": 1}, {"segment": 1, "can_level": 1}], "carrot records both segments")
	result = game.water(2, 5100)
	_check(result["ok"] and result["segment"] == 0, "cabbage single segment water works")
	result = game.water(2, 5600)
	_check(not result["ok"], "cabbage has only one valid segment")
	var status := game.watering_status(1, 5300)
	_check(status["current"] == 0 and status["segments"].size() == 2, "watering status reports two carrot segments")


func _test_fertilizer_lifecycle() -> void:
	var game := _fresh_game()
	game.state["fertilizers"]["basic"] = 1
	var t0 := 1000
	_check(game.apply_fertilizer(1, "basic", t0)["ok"], "fertilizer applies to an empty plot")
	_check(game.state["fertilizers"]["basic"] == 0, "applying consumes one use")
	var blocked: Dictionary = game.apply_fertilizer(1, "basic", t0 + 10)
	_check(not blocked["ok"] and game.state["fertilizers"]["basic"] == 0, "replacing an unexpired fertilizer is rejected without consuming uses")
	_check(game.plant(1, t0 + 60) == "", "planting on pre-fertilized soil works")
	var first := game.harvest(1, t0 + 1260)
	_check(first["ok"] and first["batch"]["score_breakdown"]["fertilizer_kind"] == "basic", "pre-plant fertilizer covers the round")
	var offsets := [1300, 2540, 3780]
	for index in range(offsets.size()):
		game.plant(1, t0 + offsets[index])
		var round_result := game.harvest(1, t0 + offsets[index] + 1200)
		_check(round_result["ok"] and round_result["batch"]["score_breakdown"]["fertilizer_kind"] == "basic", "fertilizer covers consecutive 20-minute rounds %d" % (index + 1))
	game.plant(1, t0 + 7300)
	var expired := game.harvest(1, t0 + 8500)
	_check(expired["ok"] and expired["batch"]["score_breakdown"]["fertilizer_kind"] == "", "expired fertilizer no longer covers later rounds")
	game.state["fertilizers"]["basic"] = 1
	_check(game.apply_fertilizer(4, "basic", t0 + 7400)["ok"], "a fresh fertilizer applies after the old one expired")
	game.plant(4, t0 + 7500)
	var renewed := game.harvest(4, t0 + 8700)
	_check(renewed["ok"] and renewed["batch"]["score_breakdown"]["fertilizer_kind"] == "basic", "fresh fertilizer covers the next planted round")
	game.plant(2, t0 + 100)
	game.state["fertilizers"]["basic"] = 1
	_check(game.apply_fertilizer(2, "basic", t0 + 200)["ok"], "mid-growth fertilizer applies")
	var mid := game.harvest(2, t0 + 1300)
	_check(mid["ok"] and mid["batch"]["score_breakdown"]["fertilizer_bonus"] == 40, "mid-growth fertilizer gives the full round bonus")
	game.state["fertilizers"]["basic"] = 1
	game.apply_fertilizer(3, "basic", t0)
	game.plant(3, t0 + 7200)
	var boundary := game.harvest(3, t0 + 8400)
	_check(boundary["ok"] and boundary["batch"]["score_breakdown"]["fertilizer_kind"] == "", "fertilizer expiring exactly at planting no longer covers the round")


func _test_harvest_all_equivalence() -> void:
	var setup := _fresh_game()
	for plot_id in range(1, 4):
		setup.plant(plot_id, 4000)
	setup.water(1, 4100)
	setup.water(3, 4100)
	var state_copy: Dictionary = setup.state.duplicate(true)
	var single := FarmGame.new()
	single.state = state_copy
	for plot_id in range(1, 4):
		_check(single.harvest(plot_id, 5200)["ok"], "single harvest %d works" % plot_id)
	var bulk := setup
	var summary := bulk.harvest_all(5200)
	_check(summary["ok"] and summary["results"].size() == 3, "harvest-all collects every mature plot")
	_check(bulk.state["coins"] == single.state["coins"], "coins match between harvest modes")
	_check(bulk.state["seeds"].size() == single.state["seeds"].size(), "seed counts match between harvest modes")
	_check(bulk.state["crop_batches"].size() == 3 and single.state["crop_batches"].size() == 3, "batch counts match between harvest modes")
	_check(int(bulk.state["farming_exp"]) == int(single.state["farming_exp"]), "experience matches between harvest modes")
	var bulk_score := 0
	var single_score := 0
	for batch in bulk.state["crop_batches"]:
		bulk_score += batch["per_crop_score"]
	for batch in single.state["crop_batches"]:
		single_score += batch["per_crop_score"]
	_check(bulk_score == single_score, "total scores match between harvest modes")
	var again := bulk.harvest_all(5201)
	_check(not again["ok"], "harvest-all cannot be repeated for extra output")


func _test_offline_and_reload_stability() -> void:
	var game := _fresh_game()
	_grant_carrot_seed(game, 902)
	game.plant(1, 60000, "carrot")
	game.water(1, 60100)
	_check(not game.is_ready(1, 67000), "carrot is not ready before two hours")
	_check(SaveStore.save_state(game.state, TEST_SAVE), "saving offline round works")
	var offline := FarmGame.new()
	_check(offline.load_state(SaveStore.load_state(TEST_SAVE)), "offline reload works")
	_check(offline.is_ready(1, 67200), "carrot matures while the game was closed")
	var reference: Dictionary = offline.get_plot(1)["preroll"].duplicate(true)
	for _attempt in range(3):
		var again := FarmGame.new()
		again.load_state(SaveStore.load_state(TEST_SAVE))
		_check(again.get_plot(1)["preroll"] == reference, "offline reload never rerolls encounters")
	var result := offline.harvest(1, 67200)
	_check(result["ok"] and result["batch"]["score_breakdown"]["water_segments_done"] == 1, "offline harvest keeps the watered segment")


func _test_experience_and_snapshots() -> void:
	var game := _fresh_game()
	for plot_id in range(1, 6):
		game.plant(plot_id, 1000)
	game.plant(6, 1010)
	for plot_id in range(1, 6):
		game.harvest(plot_id, 2200)
	_check(int(game.state["farming_exp"]) == 100 and game.farming_level() == 1, "five harvests give 100 exp, still level 1")
	var late := game.harvest(6, 2210)
	_check(late["ok"] and late["batch"]["score_breakdown"]["farming_level_snapshot"] == 1, "snapshot taken at planting survives later level-ups")
	_check(late["batch"]["score_breakdown"]["level_bonus"] == 0, "level-1 snapshot gives no level bonus")
	_check(int(game.state["farming_exp"]) == 120 and game.farming_level() == 2, "120 exp reaches farming level 2")
	game.plant(1, 2300)
	var next_round := game.harvest(1, 3500)
	_check(next_round["ok"] and next_round["batch"]["score_breakdown"]["level_bonus"] == 20, "next round snapshots farming and plant level 2, gaining 5%% each (20 points)")
	_check(game.plant_level("cabbage") == 2, "cabbage plant level reaches 2 at 120 exp")


func _test_unlock_chain() -> void:
	var game := _fresh_game()
	var message: String = game.buy_seeds(1, "carrot")
	_check(message != "" and message.contains("种地等级 2") and message.contains("商店等级 2"), "locked carrot purchase names both missing conditions")
	game.state["coins"] = 2000
	_check(game.upgrade_shop() == "" and game.state["shop_level"] == 2 and game.state["coins"] == 500, "shop upgrade costs 1500 coins")
	_check(game.upgrade_shop() != "", "shop cannot upgrade past 2 in this stage")
	message = game.buy_seeds(1, "carrot")
	_check(message != "" and message.contains("种地等级"), "carrot still locked below farming level 2")
	game.state["farming_exp"] = 120
	_check(game.buy_seeds(1, "carrot") == "" and game.state["coins"] == 481, "carrot seeds cost 19 coins at shop level 2 (5%% discount on 20)")
	_check(game.seed_counts()["carrot"] == 1, "carrot seed is owned after purchase")
	_check(game.plant(1, 7000, "carrot") == "", "carrot plants into an empty plot")
	_check(game.buy_fertilizer("basic") == "" and game.state["coins"] == 471, "basic fertilizer costs 10 after rounding the 5%% discount")
	_check(game.state["fertilizers"]["basic"] == 10, "one fertilizer pack holds ten uses")
	var golden_message: String = game.buy_fertilizer("golden")
	_check(golden_message != "" and golden_message.contains("种地等级 3"), "golden fertilizer stays locked behind the placeholder level")
	game.state["farming_exp"] = 840
	_check(game.buy_fertilizer("golden") == "" and game.state["coins"] == 471 - 143, "golden fertilizer costs 143 after the 5%% discount on 150")


func _test_mid_round_save_roundtrip() -> void:
	var game := _fresh_game()
	game.state["fertilizers"]["basic"] = 2
	game.plant(1, 8000)
	game.water(1, 8100)
	game.apply_fertilizer(1, "basic", 8130)
	_check(SaveStore.save_state(game.state, TEST_SAVE), "mid-round save works")
	var reloaded := FarmGame.new()
	_check(reloaded.load_state(SaveStore.load_state(TEST_SAVE)), "mid-round load works")
	var plot := reloaded.get_plot(1)
	_check(plot["watered_segments"] == [{"segment": 0, "can_level": 1}], "watered segments persist")
	_check(plot["fertilizer"]["kind"] == "basic" and int(plot["fertilizer"]["expires_at"]) == 8130 + 7200, "active fertilizer persists")
	_check(reloaded.state["fertilizers"]["basic"] == 1, "remaining fertilizer uses persist")
	_check(not plot["events"].is_empty(), "round events persist")
	var result := reloaded.harvest(1, 9200)
	_check(result["ok"], "harvest after roundtrip works")
	var breakdown: Dictionary = result["batch"]["score_breakdown"]
	_check(breakdown["water_bonus"] == 20 and breakdown["fertilizer_bonus"] == 40, "roundtrip keeps water and fertilizer effects")
	_check(int(200 + 200 * breakdown["fluctuation_pct"] / 100.0 + 20 + 40 + breakdown["encounter_bonus"]) == breakdown["per_crop_score"], "breakdown components still sum to the per-crop score")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("STAGE2_RULES_FAIL: " + message)
	failed = true


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
