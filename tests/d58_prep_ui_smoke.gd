extends SceneTree
## 三栏改版·战备面板 UI 冒烟：装备纸娃娃（暗黑 T 形四槽）、容器栈（贴图+格子纵向滚动）、
## 仓库大格子（流式装箱）、装备/卸下拖放协议、预设含装备槽、轮次标签口径；真窗口时留截图。
## 隔离：测试前后备份恢复 user://loadout_presets_v1.json(.bak/.tmp)，同 d39。


const PRESET_PATH := "user://loadout_presets_v1.json"
const KEEP_SUFFIX := ".d58keep"

var failed := false
var checks := 0
var game: FarmGame
var inv: InventoryGame
var panel: LoadoutPanel
var windowed := false


func _initialize() -> void:
	_backup_files()
	windowed = DisplayServer.get_name() != "headless"
	_run.call_deferred()


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


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("D58_PREP_FAIL: " + message)


func _id(def_id: String) -> int:
	for instance in inv.all_instances():
		if str(instance["def_id"]) == def_id:
			return int(instance["instance_id"])
	return -1


func _run() -> void:
	game = FarmGame.new()
	game.set_debug_random_seed(20261006)
	game.new_game(1000)
	inv = InventoryGame.new()
	inv.bind(game.state["expedition"])
	inv.grant_basic_kit()
	inv.equip(_id("old_shortsword"), "main_weapon")
	inv.equip(_id("straw_hat"), "helmet")
	inv.move_to_loadout(_id("wooden_shield"), "chest")
	inv.move_to_loadout(_id("pack_tools"), "chest")
	# iron_shortsword/leather_bracer 留在仓库供真实拖放（可装备件）。
	for def_id in ["copper_shortsword", "iron_ore", "antique_ornament", "bandage", "small_potion", "iron_shortsword", "leather_bracer"]:
		inv.add_instance(def_id, "loot")

	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	await process_frame
	panel = LoadoutPanel.new()
	panel.name = "LoadoutPanel"
	holder.add_child(panel)
	await process_frame
	await process_frame
	panel.open(game)
	await process_frame
	await process_frame

	# —— 布局：纸娃娃四槽 + 容器栈三块 + 仓库大格子 ——
	_check(panel.workspace != null, "工作台组件就位")
	_check(panel.workspace.slot_controls.size() == 4, "装备纸娃娃四槽（主武/副武/头盔/护甲）")
	_check(str(panel.workspace.slot_controls["main_weapon"].instance.get("def_id", "")) == "old_shortsword", "主武器槽显示短刀")
	_check(str(panel.workspace.slot_controls["helmet"].instance.get("def_id", "")) == "straw_hat", "头盔槽显示草帽")
	_check(panel.workspace.slot_controls["off_weapon"].instance.is_empty(), "副武器空槽不画物品")
	_check(panel.workspace.slot_controls["armor"].instance.is_empty(), "护甲空槽不画物品")
	_check(panel.workspace.container_grids.size() == 3, "容器栈三块（胸挂/背包/保险箱）")
	_check(panel.workspace.container_captions["safe"].text.contains("不入牌堆"), "保险箱标注不入牌堆·死亡保留")
	_check(panel.warehouse_grid.entries.size() == 7, "仓库大格子 7 件（自动装箱）")
	_check(panel.stats_label.text.contains("第 1 回合牌（装备槽）6 张"), "统计标签按装备槽口径显示首回合牌数")
	await _shot("01_三栏总览")

	# —— 装备/卸下：协议级（真窗口再补真实拖放） ——
	var owner_id: int = panel.workspace.owner_id
	var copper_payload := {"instance_id": _id("copper_shortsword"), "def_id": "copper_shortsword", "rotated": false, "workspace_owner": owner_id}
	var off_slot: BackpackWorkspace.EquipSlot = panel.workspace.slot_controls["off_weapon"]
	_check(off_slot._can_drop_data(Vector2.ZERO, copper_payload), "武器 payload 可入副武器槽")
	var shield_payload := {"instance_id": _id("wooden_shield"), "def_id": "wooden_shield", "rotated": false, "workspace_owner": owner_id}
	_check(not off_slot._can_drop_data(Vector2.ZERO, shield_payload), "防具 payload 不能进武器槽")
	var stale_payload := copper_payload.duplicate(true)
	stale_payload["workspace_owner"] = owner_id + 999
	_check(not off_slot._can_drop_data(Vector2.ZERO, stale_payload), "跨面板 payload 被归属校验拒绝")
	off_slot._drop_data(Vector2.ZERO, copper_payload)
	await process_frame
	await process_frame
	_check(str(inv.equipped_in("off_weapon").get("def_id", "")) == "copper_shortsword", "装备生效（铜短剑入副武器槽）")
	_check(str(inv.equipped_in("main_weapon").get("def_id", "")) == "old_shortsword", "主武器不受影响")
	await _shot("02_副武器装备后")

	# 卸下：把副武器直接放进胸挂空位（place 语义同时清 slot 字段）
	var fit = inv.find_first_fit("chest", ItemDefs.get_item("copper_shortsword")["size"])
	_check(fit != null, "胸挂仍有空位")
	if fit != null:
		var place_payload := copper_payload.duplicate(true)
		place_payload["rotated"] = bool(fit[2])
		panel.workspace.place_action.call(place_payload, "chest", Vector2i(int(fit[0]), int(fit[1])))
		await process_frame
		await process_frame
		var moved := inv.find_instance(_id("copper_shortsword"))
		_check(inv.equipped_in("off_weapon").is_empty(), "卸下后副武器槽清空")
		_check(str(moved.get("container", "")) == "chest" and not moved.has("slot"), "卸下进容器并清除槽位字段")

	# —— 预设往返（含装备槽） ——
	var saved: Dictionary = panel.save_preset("三栏套装")
	_check(bool(saved.get("ok", false)), "保存预设成功")
	_check((panel.presets_data.get("presets", [{}])[0].get("equipment", []) as Array).size() == 2, "预设含装备槽段（2 件）")
	inv.clear_loadout()
	panel._refresh()
	await process_frame
	_check(inv.equipped_list().is_empty(), "清空配置卸下全部装备")
	var applied: Dictionary = await panel.apply_selected()
	_check(bool(applied.get("ok", false)) and int(applied.get("applied", 0)) == 5, "应用预设复原装备+容器 5 件（装备 2＋容器 3）")
	_check(str(inv.equipped_in("main_weapon").get("def_id", "")) == "old_shortsword", "主武器槽随预设复原")
	await _shot("03_预设应用后")

	# —— 真实拖放（仅真窗口）：仓库大格子 → 头盔槽/护甲槽 ——
	if windowed:
		await _real_drag(_id("iron_shortsword"), panel.workspace.slot_controls["off_weapon"], "04_真实拖入副武器槽")
		_check(str(inv.equipped_in("off_weapon").get("def_id", "")) == "iron_shortsword", "真实拖放装备生效")
		await _real_drag(_id("leather_bracer"), panel.workspace.slot_controls["armor"], "05_真实拖入护甲槽")
		_check(str(inv.equipped_in("armor").get("def_id", "")) == "leather_bracer", "护甲槽真实拖放生效")
		await _shot("06_真实拖放后")

	if failed:
		push_error("D58_PREP_UI_SMOKE_FAIL")
	else:
		print("D58_PREP_UI_SMOKE_PASS  checks=%d" % checks)
	_restore_files()
	quit(1 if failed else 0)


func _payload_of(instance_id: int) -> Dictionary:
	var instance := inv.find_instance(instance_id)
	return {"instance_id": instance_id, "def_id": str(instance.get("def_id", "")), "rotated": false, "workspace_owner": panel.workspace.owner_id}


func _real_drag(instance_id: int, target: Control, shot_name: String) -> void:
	await process_frame
	await process_frame
	var start: Vector2 = _warehouse_item_center(instance_id)
	if start == Vector2.ZERO:
		_check(false, "仓库大格子里找到物品 %d" % instance_id)
		return
	_mouse(start, true)
	var motion := InputEventMouseMotion.new()
	motion.position = start + Vector2(24, 0)
	motion.global_position = motion.position
	motion.relative = Vector2(24, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	await process_frame
	var destination: Vector2 = target.global_position + target.size / 2.0
	motion = InputEventMouseMotion.new()
	motion.position = destination
	motion.global_position = destination
	motion.relative = destination - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.warp_mouse(destination)
	root.push_input(motion, true)
	await process_frame
	await process_frame
	_mouse(destination, false)
	await process_frame
	await process_frame
	await _shot(shot_name)


func _warehouse_item_center(instance_id: int) -> Vector2:
	var entries: Array = panel.warehouse_grid.entries
	for i in range(entries.size()):
		if int(entries[i].get("instance_id", -1)) == instance_id:
			var rect: Rect2 = panel.warehouse_grid.rects[i]
			return panel.warehouse_grid.global_position + rect.position + rect.size / 2.0
	return Vector2.ZERO


func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _shot(name: String) -> void:
	if not windowed:
		return
	await process_frame
	await process_frame
	var dir := "res://screenshots/d58_prep_ui"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	root.get_texture().get_image().save_png(dir + "/" + name + ".png")
