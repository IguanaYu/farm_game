extends SceneTree

const TEST_SAVE := "user://stage1_smoke_save.json"

var failed := false


func _initialize() -> void:
	var game := FarmGame.new()
	game.set_debug_random_seed(20260928)
	game.new_game(1000)
	_check(game.state["seeds"].size() == 6, "new game must start with six seeds")
	_check(game.state["version"] == 4, "new game must use save version 4")
	for plot_id in range(1, 7):
		_check(game.plant(plot_id, 1000) == "", "plant should succeed")
	_check(game.state["seeds"].is_empty(), "planting six plots must consume six seeds")
	_check(not game.is_ready(1, 2199), "crop cannot ripen early")
	_check(game.is_ready(1, 2200), "crop must ripen at deadline")
	# 阶段 2 起，波动与遭遇在播种时预抽；收获前记录预抽值，收获后按它复算价格。
	var expected_scores := {}
	for plot_id in range(1, 7):
		var preroll: Dictionary = game.get_plot(plot_id)["preroll"]
		var per_crop := 200 + int(200 * preroll["fluctuation_pct"] / 100.0)
		for entry in preroll["encounters"]:
			per_crop += entry["tier"]
		expected_scores[plot_id] = per_crop
	_check(SaveStore.save_state(game.state, TEST_SAVE), "saving planted game must succeed")
	var loaded := FarmGame.new()
	_check(loaded.load_state(SaveStore.load_state(TEST_SAVE)), "saved game must load")
	_check(loaded.is_ready(1, 2200), "loaded crop must ripen offline")
	for plot_id in range(1, 7):
		var harvest := loaded.harvest(plot_id, 2201)
		_check(harvest["ok"], "ripe crop must be harvestable")
		_check(harvest["seeds"] >= 2 and harvest["seeds"] <= 3, "each plot grants two or three seeds")
		_check(harvest["batch"]["per_crop_score"] == expected_scores[plot_id], "batch score must match prerolled fluctuation and encounters")
	_check(not loaded.harvest(1, 2201)["ok"], "harvest cannot be duplicated")
	_check(loaded.state["crop_batches"].size() == 6, "six plots must produce separate batches")
	_check(loaded.state["seeds"].size() >= 12, "harvested seeds must cover next planting")
	var total_score := 0
	for batch in loaded.state["crop_batches"]:
		total_score += batch["count"] * batch["per_crop_score"]
		_check(loaded.batch_sale_price(batch) == int(floor(float(batch["count"] * batch["per_crop_score"]) * 1.2 / 100.0)), "default sale price totals then floors")
	var expected_earned := int(floor(float(total_score) * 1.2 / 100.0))
	_check(expected_earned >= 72, "six stage-1 batches must earn at least the stage-1 baseline of 72 coins")
	_check(loaded.sell_all_batches() == expected_earned, "selling all batches must match the derived total")
	_check(loaded.state["coins"] == expected_earned, "coins must equal earnings")
	_check(loaded.buy_seeds(6) == "", "earned coins must buy seeds")
	_check(loaded.state["coins"] == expected_earned - 60, "buying six seeds must cost 60 coins")
	_check(int(loaded.state["farming_exp"]) == 120, "six harvests must grant 120 farming exp")
	_check(loaded.farming_level() == 2, "120 exp must reach farming level 2")
	_check(SaveStore.save_state(loaded.state, TEST_SAVE), "second save must succeed")
	var restored := FarmGame.new()
	_check(restored.load_state(SaveStore.load_state(TEST_SAVE)), "second save must restore")
	_check(restored.state["coins"] == expected_earned - 60, "coins must persist")
	_check(restored.state["crop_batches"].is_empty(), "sold crops must stay sold")
	_check(restored.farming_level() == 2, "farming level must persist")
	_cleanup()
	if failed:
		print("STAGE1_SMOKE_FAIL")
		quit(1)
	else:
		print("STAGE1_SMOKE_PASS")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("STAGE1_SMOKE_FAIL: " + message)
	failed = true


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
