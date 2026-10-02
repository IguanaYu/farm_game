extends SceneTree
## 修复轮批次 C（F-05/F-08）：场景接入——四种植物全生长阶段模型映射无异常、
## 播种引导推进即落盘即刷新、跳过引导立即保存。
## 运行前后备份/恢复真实存档文件（与 capture_ui_audit 的隔离约定一致）。


var failed := false
const SAVE_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup := _backup_saves()
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var hud: FarmHud = world.hud

	# 换内存新档演练（测试收尾恢复存档文件，不保留测试进度）。
	var fresh := FarmGame.new()
	fresh.new_game(int(Time.get_unix_time_from_system()))
	world.game = fresh
	hud.game = fresh
	world._refresh_all()
	var plot_id := int(fresh.owned_plot_ids()[0])
	var now := int(Time.get_unix_time_from_system())

	# —— F-08：播种推进引导——内存、横幅、磁盘三处同步（先于地块摆拍，用干净地块）——
	var seed_id := int((fresh.state["seeds"][0] as Dictionary)["id"])
	fresh.state["tutorial_step"] = 0
	hud.refresh(fresh.state)
	world._on_plant_seed_requested(plot_id, seed_id)
	_check(int(fresh.state.get("tutorial_step", -1)) == 1, "F-08：播种后引导推进到第 2 步（内存）")
	_check(int(hud.current_state.get("tutorial_step", -1)) == 1, "F-08：HUD 状态随推进刷新（横幅数据源）")
	_check(hud.tutorial_panel.visible, "F-08：引导横幅仍显示")
	var on_disk: Dictionary = SaveStore.load_state()
	_check(int(on_disk.get("tutorial_step", -1)) == 1, "F-08：磁盘存档同步为第 2 步（此前停留在 0）")

	# —— F-08：跳过引导立即保存 ——
	if not _click_skip(hud):
		_check(false, "F-08：跳过按钮存在")
	else:
		await process_frame
		_check(int(fresh.state.get("tutorial_step", -1)) == 99, "F-08：跳过后引导关闭（内存）")
		_check(not hud.tutorial_panel.visible, "F-08：横幅隐藏")
		var disk_after: Dictionary = SaveStore.load_state()
		_check(int(disk_after.get("tutorial_step", -1)) == 99, "F-08：跳过立即落盘（此前只改内存）")

	# —— F-05：四种植物 × 三阶段模型映射（直接摆拍地块状态，覆盖载入存档刷新路径）——
	var kinds := ["cabbage", "carrot", "rock_sprout", "glow_berry"]
	var stages := ["sprout", "growing", "mature"]
	var plot_count: int = fresh.owned_plot_ids().size()
	var plot_index := 0
	for kind in kinds:
		var defn: Dictionary = PlantDefs.get_plant(str(kind))
		for stage in stages:
			## 地块循环复用（新档地块数少于 12 组合）：每次摆拍后刷新即验证当次映射。
			var target_plot := plot_id + (plot_index % plot_count)
			var plot: Dictionary = fresh.get_plot(target_plot)
			plot["seed_id"] = 9000 + plot_index
			plot["kind"] = str(kind)
			plot["planted_at"] = now - int(defn["grow_seconds"]) / 2
			plot["ready_at"] = now + int(defn["grow_seconds"])
			if str(stage) == "mature":
				plot["ready_at"] = now - 1
			elif str(stage) == "sprout":
				plot["planted_at"] = now - 1
			world._refresh_plot_model(target_plot)
			var key := str(world.plot_model_keys.get(target_plot, ""))
			_check(key == "%s_%s" % [kind, stage], "F-05：%s %s → 模型 %s" % [kind, stage, key])
			plot_index += 1
	_check(true, "F-05：12 次地块模型刷新无脚本异常")

	world.queue_free()
	await process_frame
	_restore_saves(backup)
	_finish()


func _click_skip(hud: FarmHud) -> bool:
	# 文案精简后仍按同一入口检查落盘，不把按钮显示文字当作接口。
	var button := hud.find_child("SkipTutorialButton", true, false) as Button
	if button != null and not button.disabled:
		button.pressed.emit()
		return true
	return false


func _backup_saves() -> Dictionary:
	var backup := {}
	for save_name in SAVE_FILES:
		var path: String = "user://" + str(save_name)
		if FileAccess.file_exists(path):
			backup[str(save_name)] = FileAccess.get_file_as_bytes(path)
	return backup


func _restore_saves(backup: Dictionary) -> void:
	var dir := DirAccess.open("user://")
	for save_name in SAVE_FILES:
		var path: String = "user://" + str(save_name)
		if backup.has(str(save_name)):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(backup[str(save_name)])
			file.close()
		elif FileAccess.file_exists(path) and dir != null:
			dir.remove(str(save_name))


func _finish() -> void:
	if failed:
		push_error("D33_SCENE_INTEGRATION_FAIL")
	else:
		print("D33_SCENE_INTEGRATION_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
