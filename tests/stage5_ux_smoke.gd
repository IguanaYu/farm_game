extends SceneTree

## 阶段 5 体验测试：首轮引导状态机、遭遇正式文案、存档 v4→v5 迁移。
## 界面反馈（悬停高亮、成熟标记、筛选、倒计时）属于视觉层，由人工试玩与截图验收。

const TEST_SAVE := "user://stage5_ux_save.json"

var failed := false


func _initialize() -> void:
	for test in [
		_test_tutorial_flow,
		_test_encounter_texts,
		_test_v4_to_v5_migration,
	]:
		if failed:
			break
		test.call()
	_cleanup()
	if failed:
		print("STAGE5_UX_FAIL")
		quit(1)
	else:
		print("STAGE5_UX_PASS")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("STAGE5_UX_FAIL: " + message)
	failed = true


func _test_tutorial_flow() -> void:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261020)
	game.new_game(1759000000)
	_check(int(game.state["tutorial_step"]) == 0, "a new game starts the tutorial at step 0")
	# 引导只是状态字段：规则层照常工作，跳过不影响任何玩法
	game.state["tutorial_step"] = 99
	_check(game.plant(1, 1759000000) == "", "gameplay works regardless of tutorial state")
	_check(int(game.state["tutorial_step"]) == 99, "no tutorial side effects from gameplay")
	_check(SaveStore.save_state(game.state, TEST_SAVE), "tutorial field saves")
	var reloaded := FarmGame.new()
	_check(reloaded.load_state(SaveStore.load_state(TEST_SAVE)), "tutorial field loads")
	_check(int(reloaded.state["tutorial_step"]) == 99, "skipped tutorial stays skipped")


func _test_encounter_texts() -> void:
	for tier in PlantDefs.ENCOUNTER_TIERS:
		_check(PlantDefs.ENCOUNTER_TEXTS.has(tier), "every encounter tier %+d has formal text" % tier)
	var game := FarmGame.new()
	game.set_debug_random_seed(20261021)
	game.new_game(1759000000)
	game.plant(1, 1759000000)
	var result := game.harvest(1, 1759001200)
	_check(result["ok"], "harvest works for the story check")
	var encounter_lines: Array = result["events"].filter(func(event): return event["type"] == "encounter")
	_check(not encounter_lines.is_empty(), "the round story includes encounters")
	for event in encounter_lines:
		_check(event["text"].contains("正向遭遇") and event["text"].contains("分）"), "encounter text keeps the scoring explanation: %s" % event["text"])
		var matched_tier := false
		for tier in PlantDefs.ENCOUNTER_TIERS:
			if event["text"].contains(PlantDefs.ENCOUNTER_TEXTS[tier]):
				matched_tier = true
		_check(matched_tier, "encounter text uses a formal tier description")


func _test_v4_to_v5_migration() -> void:
	var v4 := {
		"version": 4,
		"next_id": 10,
		"coins": 123,
		"farming_exp": 0,
		"plant_exp": {},
		"shop_level": 1,
		"can_level": 1,
		"warehouse_level": 1,
		"fertilizers": {"basic": 0, "mutation": 0, "preserve": 0, "golden": 0},
		"breeder": {"owned": false, "level": 1, "template_seed_id": 0, "pending": 0, "progress": {}, "last_settled": 0},
		"pending": {"crops": [], "seeds": []},
		"market": {"day_index": 20000, "guest_ids": [1, 2, 3], "formulas": {"cabbage": {"kind": "cabbage", "type": "single", "attribute": "water", "coefficient": 0.1}, "carrot": {"kind": "carrot", "type": "dual", "attribute": "fiber", "sub_attribute": "color", "coefficient": 0.08, "sub_coefficient": 0.04}}, "locked_guest_id": 0, "lock_guest_pending": 0, "locked_formula": {}, "lock_formula_pending": {}},
		"ledger": [],
		"plots": [],
		"seeds": [],
		"crop_batches": [],
		"created_at": 1,
	}
	for index in range(10):
		v4["plots"].append({
			"id": index + 1, "owned": index < 6, "seed_id": 0, "planted_at": 0, "ready_at": 0, "roll_seed": 0,
			"kind": "", "snapshot": {}, "watered_segments": [], "fertilizer": {}, "preroll": {}, "events": [], "parent_traits": [],
		})
	var game := FarmGame.new()
	_check(game.load_state(v4), "version 4 save migrates to version 5")
	_check(game.state["version"] == 5, "migrated save reports version 5")
	_check(int(game.state["tutorial_step"]) == 99, "existing players skip the tutorial")
	_check(game.state["market"]["guest_ids"] == [1, 2, 3], "market state survives the migration")
	_check(game.state["coins"] == 123, "coins survive the migration")


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
