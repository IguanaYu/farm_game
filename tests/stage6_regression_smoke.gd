extends SceneTree

## 阶段 6 回归补充测试：聚焦各阶段任务书点名的边界——
## 连续快速重复操作、存档中断恢复（备份回退）、v1→v5 全链迁移、
## 满仓-领取全路径复查、升级发生在收获轮的快照。

const TEST_SAVE := "user://stage6_regression_save.json"

var failed := false


func _initialize() -> void:
	for test in [
		_test_rapid_repeated_actions,
		_test_save_interruption_recovery,
		_test_full_migration_chain,
		_test_upgrade_during_harvest_round,
	]:
		if failed:
			break
		test.call()
	_cleanup()
	if failed:
		print("STAGE6_REGRESSION_FAIL")
		quit(1)
	else:
		print("STAGE6_REGRESSION_PASS")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("STAGE6_REGRESSION_FAIL: " + message)
	failed = true


func _fresh_game(now := 1759000000) -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261030)
	game.new_game(now)
	return game


func _test_rapid_repeated_actions() -> void:
	var game := _fresh_game()
	game.state["coins"] = 500
	# 同一按钮连点：购买
	var coins_before := int(game.state["coins"])
	var seeds_before: int = game.state["seeds"].size()
	for _click in range(3):
		game.buy_seeds(1, "cabbage")
	var spent := coins_before - int(game.state["coins"])
	_check(spent == 30 and game.state["seeds"].size() == seeds_before + 3, "three rapid seed purchases cost exactly three times (30 coins)")
	# 同一按钮连点：收获 + 出售
	game.plant(1, 1759000000)
	game.get_plot(1)["ready_at"] = 1759001200
	var first := game.harvest(1, 1759001200)
	_check(first["ok"] and not game.harvest(1, 1759001201)["ok"], "rapid double harvest yields once")
	var batch_id := int(first["batch"]["id"])
	var coins_after_harvest := int(game.state["coins"])
	var sold := game.sell_batch(batch_id)
	_check(sold["ok"], "first sell works")
	var sold_again := game.sell_batch(batch_id)
	_check(not sold_again["ok"] and int(game.state["coins"]) == coins_after_harvest + sold["coins"], "rapid double sell pays once")
	# 拆批连点
	game.state["crop_batches"].append({
		"id": 900, "plot_id": 2, "kind": "cabbage", "count": 5, "base_score": 200,
		"per_crop_score": 200, "attributes": {"water": 0, "fiber": 0, "color": 0}, "sale_multiplier_bonus": 0.0,
	})
	var guest_id := 1
	for candidate in MarketDefs.GUESTS:
		if MarketDefs.GUESTS[candidate]["preferred_kind"] == "cabbage":
			guest_id = candidate
			break
	var part_one := game.sell_batch_to(900, 5, guest_id, 1759001300)
	_check(part_one["ok"], "selling the whole batch to a guest works")
	_check(not game.sell_batch_to(900, 1, guest_id, 1759001300)["ok"], "repeat split sell finds no batch left")
	# 领取连点
	var moved := game.claim_pending()
	var moved_again := game.claim_pending()
	_check(moved_again["crops"] == 0 and moved_again["seeds"] == 0, "rapid double claim moves nothing extra")


func _test_save_interruption_recovery() -> void:
	var game := _fresh_game()
	game.state["coins"] = 4321
	game.plant(1, 1759000000)
	_check(SaveStore.save_state(game.state, TEST_SAVE), "baseline save works")
	# 备份从第二次保存起存在（首次保存没有可备份的旧档）
	game.state["coins"] = 5321
	_check(SaveStore.save_state(game.state, TEST_SAVE), "second save creates the backup")
	_check(FileAccess.file_exists(TEST_SAVE + ".bak"), "backup file exists after the second save")
	# 模拟写入中断：主档被截断成无效 JSON，备份仍是上一次完整档
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string("{\"version\": 5, \"coins\": \"broken")
	file.close()
	var recovered := SaveStore.load_state(TEST_SAVE)
	_check(not recovered.is_empty(), "broken primary falls back to the backup file")
	var game2 := FarmGame.new()
	_check(game2.load_state(recovered), "backup state loads")
	_check(int(game2.state["coins"]) == 4321, "backup restores the previous complete save (4321), losing only the interrupted one")
	# 备份也坏：拒绝加载而不是给半档
	var backup := FileAccess.open(TEST_SAVE + ".bak", FileAccess.WRITE)
	backup.store_string("not json at all")
	backup.close()
	_check(SaveStore.load_state(TEST_SAVE).is_empty(), "double corruption refuses to load instead of returning a half save")


func _test_full_migration_chain() -> void:
	# v1（阶段 1 存档）一路迁到 v5：物品、金币、地块、生长中轮次全部保留
	var v1 := {
		"version": 1,
		"next_id": 30,
		"coins": 246,
		"created_at": 1790000000,
		"plots": [],
		"seeds": [{"id": 21, "kind": "cabbage", "traits": []}],
		"crop_batches": [{"id": 25, "plot_id": 2, "count": 5, "base_score": 200, "planted_at": 1, "harvested_at": 2}],
	}
	for index in range(6):
		if index == 0:
			v1["plots"].append({"id": 1, "seed_id": 9, "planted_at": 1790000000, "ready_at": 1790001200, "roll_seed": 424242})
		else:
			v1["plots"].append({"id": index + 1, "seed_id": 0, "planted_at": 0, "ready_at": 0, "roll_seed": 0})
	var game := FarmGame.new()
	_check(game.load_state(v1), "v1 save migrates through to v5")
	_check(game.state["version"] == 7, "final version is 7")
	_check(int(game.state["coins"]) == 246, "coins survive the whole chain")
	_check(game.state["seeds"].size() == 1 and int(game.state["seeds"][0]["id"]) == 21, "seeds survive the whole chain")
	_check(game.state["crop_batches"].size() == 1, "batches survive the whole chain")
	_check(game.owned_plot_ids().size() == 6 and game.state["plots"].size() == 10, "six owned plots of ten after migration")
	_check(game.is_ready(1, 1790001200), "growing v1 plot still ripens")
	var result := game.harvest(1, 1790001300)
	_check(result["ok"], "migrated growing plot harvests after the full chain")
	_check(int(game.state["tutorial_step"]) == 99, "migrated players skip the tutorial")


func _test_upgrade_during_harvest_round() -> void:
	# 升级恰好发生在某轮收获：该轮等级加分用播种快照，下一轮用新等级
	var game := _fresh_game()
	game.plant(1, 1759000000)
	game.plant(2, 1759000000)
	# 先收 5 块以外的一轮把经验推到 100（仍 1 级）
	game.state["farming_exp"] = 100
	var early := game.harvest(1, 1759001200)
	_check(early["ok"] and early["batch"]["score_breakdown"]["level_bonus"] == 0, "level-1 snapshot gives no bonus even if the harvest itself levels up")
	_check(int(game.state["farming_exp"]) == 120 and game.farming_level() == 2, "the harvest reaches level 2")
	game.plant(3, 1759001300)
	var next_round := game.harvest(3, 1759002500)
	_check(next_round["ok"] and next_round["batch"]["score_breakdown"]["farming_level_snapshot"] == 2, "the next round snapshots the new level")


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
