extends SceneTree
## 2.3：存读档保持布局与归属（旋转、格子、剩余次数）。


var failed := false


func _initialize() -> void:
	var game := FarmGame.new()
	game.new_game(1000)
	var inv := InventoryGame.new()
	inv.bind(game.state["expedition"])
	inv.grant_basic_kit()
	for def_id in ["old_shortsword", "pack_tools"]:
		inv.move_to_loadout(_id_of(inv, def_id), "chest")
	inv.move_to_loadout(_id_of(inv, "wooden_shield"), "pack")
	var ore := inv.add_instance("iron_ore", "run")
	inv.place_at(int(ore["instance_id"]), "pack", Vector2i(2, 2), true)
	var seed_instance := inv.add_instance("rock_sprout_seed", "run")
	inv.move_to_loadout(int(seed_instance["instance_id"]), "safe")
	var potion := inv.add_instance("small_potion", "run")
	inv.move_to_loadout(int(potion["instance_id"]), "pack")
	var deck_before := DeckBuilder.build(inv)

	var path := "user://d23_save_smoke.json"
	_check(SaveStore.save_state(game.state, path), "保存：含布局的 v6 档写入")
	var loaded := FarmGame.new()
	_check(loaded.load_state(SaveStore.load_state(path)), "读回：加载成功")
	var inv2 := InventoryGame.new()
	inv2.bind(loaded.state["expedition"])
	var deck_after := DeckBuilder.build(inv2)
	_check(deck_before["entries"].size() == deck_after["entries"].size(), "布局：牌组重建一致")
	var ore2 := inv2.find_instance(int(ore["instance_id"]))
	_check(not ore2.is_empty() and bool(ore2.get("rotated", false)) and ore2["cell"] == [2, 2], "布局：旋转与格子坐标保留")
	_check(inv2.owner_of(int(seed_instance["instance_id"])) == "safe", "归属：保险箱内的种子保留")
	_check(inv2.uses_remaining(int(potion["instance_id"])) == 1, "补给：剩余次数保留")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	if failed:
		push_error("D23_SAVE_SMOKE_FAIL")
	else:
		print("D23_SAVE_SMOKE_PASS")
	quit(1 if failed else 0)


func _id_of(inv: InventoryGame, def_id: String) -> int:
	for instance in inv.all_instances():
		if str(instance["def_id"]) == def_id:
			return int(instance["instance_id"])
	return -1


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
