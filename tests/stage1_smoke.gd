extends SceneTree

const TEST_SAVE := "user://stage1_smoke_save.json"


func _initialize() -> void:
	var game := FarmGame.new()
	game.set_debug_random_seed(20260928)
	game.new_game(1000)
	_check(game.state["seeds"].size() == 6, "new game must start with six seeds")
	for plot_id in range(1, 7):
		_check(game.plant(plot_id, 1000) == "", "plant should succeed")
	_check(game.state["seeds"].is_empty(), "planting six plots must consume six seeds")
	_check(not game.is_ready(1, 2199), "crop cannot ripen early")
	_check(game.is_ready(1, 2200), "crop must ripen at deadline")
	_check(SaveStore.save_state(game.state, TEST_SAVE), "saving planted game must succeed")
	var loaded := FarmGame.new()
	_check(loaded.load_state(SaveStore.load_state(TEST_SAVE)), "saved game must load")
	_check(loaded.is_ready(1, 2200), "loaded crop must ripen offline")
	for plot_id in range(1, 7):
		var harvest := loaded.harvest(plot_id, 2201)
		_check(harvest["ok"], "ripe crop must be harvestable")
		_check(harvest["seeds"] >= 2 and harvest["seeds"] <= 3, "each plot grants two or three seeds")
	_check(not loaded.harvest(1, 2201)["ok"], "harvest cannot be duplicated")
	_check(loaded.state["crop_batches"].size() == 6, "six plots must produce separate batches")
	_check(loaded.state["seeds"].size() >= 12, "harvested seeds must cover next planting")
	_check(loaded.batch_sale_price(loaded.state["crop_batches"][0]) == 12, "default sale price must be 12 coins per batch")
	_check(loaded.sell_all_batches() == 72, "six batches must sell for 72 coins")
	_check(loaded.buy_seeds(6) == "", "earned coins must buy seeds")
	_check(loaded.state["coins"] == 12, "buying six seeds must cost 60 coins")
	_check(SaveStore.save_state(loaded.state, TEST_SAVE), "second save must succeed")
	var restored := FarmGame.new()
	_check(restored.load_state(SaveStore.load_state(TEST_SAVE)), "second save must restore")
	_check(restored.state["coins"] == 12, "coins must persist")
	_check(restored.state["crop_batches"].is_empty(), "sold crops must stay sold")
	_cleanup()
	print("STAGE1_SMOKE_PASS")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("STAGE1_SMOKE_FAIL: " + message)
	_cleanup()
	quit(1)


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
