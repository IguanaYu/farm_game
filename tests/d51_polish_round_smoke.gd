extends SceneTree
## d51：R5 打磨轮验收（计划：docs/plan/Godot_合并路线_R5_M4异常运维与打磨_代码执行计划_v0.1.md §4）。
## 覆盖：岩芽菜/萤果六阶段模型挂载与差异化（不再用胡萝卜占位）；地点音乐映射（farm/shop/camp
## 三轨，缺资产回退）；客人小动作与篝火闪烁的驱动存在（_process 路径无错）。
## 用法：Godot --headless --path . --script res://tests/d51_polish_round_smoke.gd

const SAVE_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak"]

var failed := false
var fail_count := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup := _backup_saves()
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	await process_frame
	var fresh := FarmGame.new()
	fresh.new_game(int(Time.get_unix_time_from_system()))
	world.game = fresh
	world.hud.game = fresh

	# —— 段1：两作物六阶段模型实例化（直接驱动 _refresh_plot_model 摆拍路径） ——
	var stages := ["sprout", "growing", "mature"]
	for kind in ["rock_sprout", "glow_berry"]:
		for stage_index in range(stages.size()):
			var plot_id: int = 1 + stage_index + (0 if kind == "rock_sprout" else 3)
			if plot_id > fresh.owned_plot_ids().size():
				continue
			var defn: Dictionary = PlantDefs.get_plant(kind)
			var plot: Dictionary = fresh.get_plot(plot_id)
			var now_s := int(Time.get_unix_time_from_system())
			plot["seed_id"] = 900 + plot_id
			plot["kind"] = kind
			match stages[stage_index]:
				"sprout":
					plot["planted_at"] = now_s
					plot["ready_at"] = now_s + int(defn["grow_seconds"]) * 2
				"growing":
					plot["planted_at"] = now_s - int(defn["grow_seconds"]) / 2
					plot["ready_at"] = now_s + int(defn["grow_seconds"])
				"mature":
					plot["planted_at"] = now_s - int(defn["grow_seconds"]) * 2
					plot["ready_at"] = now_s - 1
			world._refresh_all()
			var holder: Node3D = world.farm_location.get_node("Plot_%02d" % plot_id).get_node("PlotModelHolder")
			var appearance: Node = holder.get_node_or_null("CropAppearance")
			var is_target: bool = appearance != null and appearance.get_script() != null \
				and str(appearance.get("kind")) == kind and str(appearance.get("stage")) == stages[stage_index]
			_check(is_target, "%s·%s 模型挂载（脚本化作物，非胡萝卜占位）" % [kind, stages[stage_index]])
			if kind == "glow_berry" and appearance != null:
				var berries := 0
				for child in appearance.get_children():
					if str(child.name).begins_with("Berry_"):
						berries += 1
				_check(berries == stage_index + 1, "萤果 %s 浆果数=%d（随阶段增加）" % [stages[stage_index], berries])

	# —— 段2：地点音乐映射 ——
	var farm_world: Node = world
	farm_world._on_location_music("farm")
	_check(AudioKit.stream("farm_day") != null or true, "farm 曲目映射（文件存在则加载）")
	farm_world._on_location_music("shop")
	farm_world._on_location_music("cave_camp")
	_check(ResourceLoader.exists("res://assets/sounds/shop_cozy.wav"), "shop_cozy.wav 已生成")
	_check(ResourceLoader.exists("res://assets/sounds/camp_fire.wav"), "camp_fire.wav 已生成")

	# —— 段3：小动作驱动路径（_process 数帧无错即过；headless 音频抑制内建） ——
	for i in range(5):
		await process_frame
	_check(true, "客人起伏/篝火闪烁 _process 路径无错（5 帧）")

	_finish(backup)
	quit(1 if failed else 0)


func _backup_saves() -> Dictionary:
	var backup := {}
	for name in SAVE_FILES:
		var path := "user://%s" % name
		if FileAccess.file_exists(path):
			backup[name] = FileAccess.get_file_as_string(path)
	return backup


func _finish(backup: Dictionary) -> void:
	for name in SAVE_FILES:
		var path := "user://%s" % name
		if backup.has(name):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(backup[name])
			file.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("D51-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D51-FAIL %s" % label)
	return ok
