extends SceneTree
## 2.1-W4：v5→v6 旧档迁移。旧资产逐字段保留，追加 expedition 块；未知版本拒绝。


var failed := false


func _initialize() -> void:
	# 造一份"有历史"的 v5 档：金币、词条种子、十块地、育种机进度、市场锁定。
	var old_game := FarmGame.new()
	old_game.set_debug_random_seed(20260928)
	old_game.new_game(1000)
	old_game.state["coins"] = 666
	old_game.state["tutorial_step"] = 99
	for plot in old_game.state["plots"]:
		plot["owned"] = true
	var seeds: Array = old_game.state["seeds"]
	if not seeds.is_empty():
		seeds[0]["traits"] = [{"effect": "water_guarantee", "tier": 2}, {"effect": "color_guarantee", "tier": 3}]
	old_game.state["breeder"]["owned"] = true
	old_game.state["breeder"]["level"] = 2
	old_game.state["breeder"]["progress"]["1"] = 1200
	old_game.state["market"]["locked_guest_id"] = 3
	old_game.state["farming_exp"] = 480
	var v5: Dictionary = old_game.state.duplicate(true)
	v5.erase("expedition")
	v5["version"] = 5

	var migrated := FarmGame.new()
	var ok := migrated.load_state(v5)
	_check(ok, "v5 档可加载（自动迁移）")
	if not ok:
		_finish()
		return
	_check(int(migrated.state["version"]) == 7, "迁移：版本升为 7（经 v6 中转）")
	_check(int(migrated.state["coins"]) == 666, "迁移：金币保留")
	_check(int(migrated.state["farming_exp"]) == 480, "迁移：成长经验保留")
	_check(migrated.owned_plot_ids().size() == 10, "迁移：十块地拥有状态保留")
	_check(migrated.state["seeds"].size() == v5["seeds"].size(), "迁移：种子数量保留")
	var first_seed: Dictionary = migrated.state["seeds"][0]
	_check(first_seed["traits"].size() == 2 and int(first_seed["traits"][0]["tier"]) == 2, "迁移：种子词条保留")
	_check(bool(migrated.state["breeder"]["owned"]) and int(migrated.state["breeder"]["progress"]["1"]) == 1200, "迁移：育种机进度保留")
	_check(int(migrated.state["market"]["locked_guest_id"]) == 3, "迁移：市场锁定保留")
	var expedition: Dictionary = migrated.state["expedition"]
	_check(str(expedition["player_id"]).begins_with("p-"), "迁移：生成玩家标识")
	_check(int(expedition["next_instance_id"]) == ExpeditionBaseline.FIRST_INSTANCE_ID, "迁移：实例发号器初值")
	_check(expedition["inventory"]["warehouse"].is_empty(), "迁移：初始库存为空")
	_check(str(expedition["active_run_ref"]) == "" and expedition["applied_settlements"].is_empty(), "迁移：无活动局与已应用结算")

	var new_game := FarmGame.new()
	new_game.new_game(3000)
	_check(new_game.load_state(new_game.state.duplicate(true)), "v6 档直接加载不触发迁移分支")
	var v8: Dictionary = new_game.state.duplicate(true)
	v8["version"] = 8
	_check(not new_game.load_state(v8), "未知版本（8）被拒绝加载")
	var broken: Dictionary = new_game.state.duplicate(true)
	broken["expedition"] = {"player_id": ""}
	_check(not migrated.load_state(broken), "损坏的 expedition 块被拒绝，不静默重建")

	_finish()


func _finish() -> void:
	if failed:
		push_error("D21_MIGRATION_SMOKE_FAIL")
	else:
		print("D21_MIGRATION_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
