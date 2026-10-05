extends SceneTree
## 配装预设冒烟（方案 docs/plan/Godot_配装预设UI_方案与执行计划_v0.1.md）。
## 覆盖：领域快照/精确复原/缺失降级/占用拒绝；预设文件往返（int-float 归一化）
## 与主文件损坏回落 .bak；战备面板存/应用/删全链路（无头实例化）。
## 隔离：测试前后备份恢复 user://loadout_presets_v1.json(.bak/.tmp)。


const PRESET_PATH := "user://loadout_presets_v1.json"
const KEEP_SUFFIX := ".d39keep"

var failed := false


func _initialize() -> void:
	_backup_files()
	_run.call_deferred()


func _run() -> void:
	_domain_capture_and_apply()
	_domain_missing_and_occupied()
	_store_roundtrip_and_bak()
	_panel_flow()
	_restore_files()
	_finish()


# —— 领域：快照与精确复原 ———————————————————————————————————————


func _domain_capture_and_apply() -> void:
	var game := _fresh_game()
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()

	# 布局：仓库前三件分别进胸挂（自动位）、背包（自动位后旋转）、背包（再指定位放置）。
	# warehouse_list() 是活引用，先快照 ID 再移动，避免数组缩位串件。
	var kit_ids: Array = inventory.warehouse_list().map(func(entry): return int(entry["instance_id"]))
	_check(kit_ids.size() >= 3, "领域：基础装备至少 3 件可布置")
	inventory.move_to_loadout(kit_ids[0], "chest")
	inventory.move_to_loadout(kit_ids[1], "pack")
	inventory.rotate_instance(kit_ids[1])
	var pack_bounds: Vector2i = ExpeditionBaseline.size_for(game.state["expedition"], "pack")
	inventory.move_to_loadout(kit_ids[2], "pack")
	inventory.place_at(kit_ids[2], "pack", Vector2i(0, maxi(0, pack_bounds.y - 1)), false)
	# 演示物品放胸挂：快照必须排除它。
	inventory.inject_demo_items()
	for instance in inventory.warehouse_list():
		if bool(instance.get("demo", false)):
			inventory.move_to_loadout(int(instance["instance_id"]), "chest")
			break

	var expected := _layout_snapshot(inventory)
	_check(int(expected.size()) == 3, "领域：布置后三容器共 3 件真实物品")

	var captured := LoadoutPresets.capture(inventory)
	_check(int(captured["fmt"]) == 2, "领域：快照格式版本为 2（三栏改版含装备槽）")
	_check(captured.get("equipment") is Array, "领域：快照含 equipment 装备槽段")
	_check((captured["items"] as Array).size() == 3, "领域：快照 3 件（排除演示实例）")
	var snapshot_ok := true
	for entry in captured["items"]:
		var info: Dictionary = expected.get(int(entry["instance_id"]), {})
		if info.is_empty() or str(info["container"]) != str(entry["container"]) \
				or int(info["cell"][0]) != int(entry["cell"][0]) or int(info["cell"][1]) != int(entry["cell"][1]) \
				or bool(info["rotated"]) != bool(entry["rotated"]):
			snapshot_ok = false
	_check(snapshot_ok, "领域：快照逐件记录容器/格位/旋转一致")

	inventory.clear_loadout()
	var result := LoadoutPresets.apply(inventory, captured)
	_check(bool(result["ok"]) and int(result["applied"]) == 3 and int(result["relocated"]) == 0, "领域：清空后应用全部精确就位")
	var restored := _layout_snapshot(inventory)
	_check(_same_layout(expected, restored), "领域：复原后布局与快照前逐件一致")
	_check(_demo_in_warehouse(inventory), "领域：演示物品留在仓库，不入预设不丢")


# —— 领域：缺失降级与占用拒绝 ——————————————————————————————————


func _domain_missing_and_occupied() -> void:
	var game := _fresh_game()
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	var kit_ids: Array = inventory.warehouse_list().map(func(entry): return int(entry["instance_id"]))
	inventory.move_to_loadout(kit_ids[0], "chest")
	inventory.move_to_loadout(kit_ids[1], "pack")
	var captured := LoadoutPresets.capture(inventory)

	# 缺失：清空后移走一件真实实例（模拟编号失效）。
	inventory.clear_loadout()
	var gone := inventory.find_instance(kit_ids[0])
	_check(not gone.is_empty(), "领域：清空后实例回到仓库可定位")
	inventory._inventory()["warehouse"].erase(gone)
	var result := LoadoutPresets.apply(inventory, captured)
	_check(bool(result["ok"]) and int(result["applied"]) == 1 and (result["missing"] as Array).size() == 1, "领域：缺失 1 件时其余照常就位")
	_check(LoadoutPresets.report(result, "缺件套").find("缺失") >= 0, "领域：缺失反馈文案包含“缺失”")

	# 占用：活动局期间整单拒绝。
	inventory.set_run_occupied("d39-run")
	var blocked := LoadoutPresets.apply(inventory, captured)
	_check(not blocked["ok"] and blocked["reason"].find("探险") >= 0, "领域：占用中应用被拒绝")
	inventory.clear_run_occupied("d39-run")


# —— 存取：往返一致与 .bak 回落 —————————————————————————————————


func _store_roundtrip_and_bak() -> void:
	var game := _fresh_game()
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	var warehouse: Array = inventory.warehouse_list()
	inventory.move_to_loadout(int(warehouse[0]["instance_id"]), "chest")
	var captured := LoadoutPresets.capture(inventory)

	var data := PresetStore.empty_presets()
	data["presets"] = [{"name": "第一套", "items": captured["items"]}]
	_check(PresetStore.save_presets(data), "存取：首次保存成功")
	data["presets"] = [{"name": "第二套", "items": captured["items"]}, {"name": "第三套", "items": []}]
	_check(PresetStore.save_presets(data), "存取：第二次保存成功（旧主文件转 .bak）")
	var loaded := PresetStore.load_presets()
	_check((loaded["presets"] as Array).size() == 2 and str(loaded["presets"][0]["name"]) == "第二套", "存取：读回最新版本")

	# JSON 往返后 cell 变 float：apply 的 int() 归一化必须仍能精确复原。
	inventory.clear_loadout()
	var reapplied := LoadoutPresets.apply(inventory, loaded["presets"][0])
	_check(bool(reapplied["ok"]) and int(reapplied["applied"]) == 1, "存取：JSON 往返后的预设仍能精确应用")

	var corrupt := FileAccess.open(PRESET_PATH, FileAccess.WRITE)
	corrupt.store_string("{{{not json")
	corrupt.close()
	var recovered := PresetStore.load_presets()
	_check((recovered["presets"] as Array).size() == 1 and str(recovered["presets"][0]["name"]) == "第一套", "存取：主文件损坏回落 .bak（读到上一版）")


# —— 面板：存/应用/删全链路 ————————————————————————————————————


func _panel_flow() -> void:
	PresetStore.save_presets(PresetStore.empty_presets())
	var game := _fresh_game()
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	var kit_ids: Array = inventory.warehouse_list().map(func(entry): return int(entry["instance_id"]))
	inventory.move_to_loadout(kit_ids[0], "chest")
	inventory.move_to_loadout(kit_ids[1], "chest")

	var panel := LoadoutPanel.new()
	root.add_child(panel)
	panel.open(game)
	_check(panel.preset_names().is_empty(), "面板：打开时无预设")

	var saved: Dictionary = panel.save_preset("标准下洞")
	_check(bool(saved["ok"]) and int(saved["count"]) == 2, "面板：存为预设（2 件）")
	_check(panel.preset_names() == ["标准下洞"], "面板：列表出现预设名")

	inventory.clear_loadout()
	_check((inventory.loadout_list("chest") as Array).is_empty(), "面板：清空后胸挂为空")
	var applied: Dictionary = await panel.apply_selected()
	_check(bool(applied["ok"]) and int(applied["applied"]) == 2, "面板：应用预设 2 件就位")
	_check((inventory.loadout_list("chest") as Array).size() == 2, "面板：胸挂恢复 2 件")
	_check(bool(panel.dirty), "面板：应用后面板标记 dirty（走关闭保存链）")

	var anonymous: Dictionary = panel.save_preset("")
	_check(bool(anonymous["ok"]) and str(anonymous["name"]) == "预设 2", "面板：空名自动编号")

	var deleted: Dictionary = panel.delete_selected()
	_check(bool(deleted["ok"]) and panel.preset_names() == ["标准下洞"], "面板：删除所选“预设 2”后剩“标准下洞”")
	panel.close()
	panel.queue_free()


# —— 辅助 ————————————————————————————————————————————————————————


func _fresh_game() -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261201)
	game.new_game(2000)
	return game


func _layout_snapshot(inventory: InventoryGame) -> Dictionary:
	var snapshot := {}
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in inventory.loadout_list(container):
			if bool(instance.get("demo", false)):
				continue
			snapshot[int(instance["instance_id"])] = {
				"container": str(instance["container"]),
				"cell": [int(instance["cell"][0]), int(instance["cell"][1])],
				"rotated": bool(instance.get("rotated", false)),
			}
	return snapshot


func _same_layout(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for instance_id in a:
		if not b.has(instance_id):
			return false
		var left: Dictionary = a[instance_id]
		var right: Dictionary = b[instance_id]
		if left["container"] != right["container"] or left["rotated"] != right["rotated"] \
				or int(left["cell"][0]) != int(right["cell"][0]) or int(left["cell"][1]) != int(right["cell"][1]):
			return false
	return true


func _demo_in_warehouse(inventory: InventoryGame) -> bool:
	for instance in inventory.warehouse_list():
		if bool(instance.get("demo", false)):
			return true
	return false


func _backup_files() -> void:
	for suffix: String in ["", ".bak"]:
		var path := PRESET_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + KEEP_SUFFIX))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_remove_file(PRESET_PATH + ".tmp")


func _restore_files() -> void:
	for suffix: String in ["", ".bak"]:
		_remove_file(PRESET_PATH + suffix)
		var keep := PRESET_PATH + suffix + KEEP_SUFFIX
		if FileAccess.file_exists(keep):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(keep), ProjectSettings.globalize_path(PRESET_PATH + suffix))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(keep))
	_remove_file(PRESET_PATH + ".tmp")


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if failed:
		push_error("D39_LOADOUT_PRESET_FAIL")
	else:
		print("D39_LOADOUT_PRESET_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
