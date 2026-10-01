extends SceneTree
## 2.9：全量回归清单核对——总计划 §12.1 七大块逐行映射到测试文件，
## 并做跨阶段不变量抽检（存档版本、类可加载、关键口径）。


var failed := false

const SUITE := {
	"背包": ["d21_defs_smoke", "d21_inventory_smoke", "d23_inventory_worked", "d23_save_smoke"],
	"战斗": ["d22_rules_smoke", "d22_worked_example", "d22_serialize_smoke", "d23_combat_worked", "d26_combat_coop_smoke"],
	"探索": ["d24_run_smoke", "d24_settle_smoke", "d28_content_smoke"],
	"库存": ["d23_defs_smoke", "d25_crafting_smoke", "d29_arbitrage_smoke"],
	"存档": ["d21_migration_smoke", "d24_recovery_sim", "d27_recovery_matrix"],
	"联机": ["d21_net_probe", "d26_session_smoke", "d27_recovery_matrix"],
	"农场": ["stage1_smoke", "stage2_rules_smoke", "stage3_breeding_smoke", "stage3_warehouse_smoke", "stage4_market_smoke", "stage5_ux_smoke", "stage6_regression_smoke", "d25_plant_smoke", "d25_goals_smoke", "world_picking_smoke"],
}


func _initialize() -> void:
	var all_files := {}
	var dir := DirAccess.open("res://tests")
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.ends_with(".gd"):
				all_files[name.get_basename()] = true
			name = dir.get_next()
	var missing: Array = []
	var total := 0
	for block in SUITE:
		for test_name in SUITE[block]:
			total += 1
			if not all_files.has(test_name):
				missing.append("%s/%s" % [block, test_name])
	_check(missing.is_empty(), "回归清单：七大块 %d 项测试文件齐全（缺失：%s）" % [total, "、".join(missing) if not missing.is_empty() else "无"])

	# 跨阶段不变量抽检。
	var game := FarmGame.new()
	game.new_game(1000)
	_check(int(game.state["version"]) == 7, "不变量：存档版本 7")
	_check(str(ExpeditionBaseline.PROTO_RULES_VERSION).begins_with("d2-baseline-"), "不变量：规则版本锚点")
	var expedition: Dictionary = game.state["expedition"]
	_check(expedition.has("crafting") and expedition["crafting"]["upgrade_levels"]["chest"] == 1, "不变量：v7 crafting 块")
	_check(ItemDefs.validate_definitions().is_empty(), "不变量：物品/牌定义自洽")
	_check(ExpeditionDefs.layer("moss_stone_shallow") != null and ExpeditionDefs.layer("iron_root_deeps") != null, "不变量：两层定义在")
	for cls in [CombatGame, ExpeditionGame, InventoryGame, CraftingGame, DeckBuilder, SessionHost, SessionClient]:
		_check(cls != null, "不变量：核心规则类可加载（%s）" % str(cls.get_class()))
	_finish()


func _finish() -> void:
	if failed:
		push_error("D29_REGRESSION_SMOKE_FAIL")
	else:
		print("D29_REGRESSION_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
