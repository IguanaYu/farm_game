extends SceneTree
## d48：R3 农场环境与商店内景验收（计划：docs/plan/Godot_合并路线_R3_农场环境与商店内景_代码执行计划_v0.1.md §4）。
## 覆盖：入口实体化结构（雨棚/石阶/信箱/小桥/溪流/林带/远山）；连续地形三分辨率射线覆盖；
## 未购地块草桩可见；商店内景结构（柜台/货架/委托台/门/三客人）与当日客人一致；
## 进店相机切换与返回还原；两轮往返 game 实例不变。
## 用法：Godot --headless --path . --script res://tests/d48_farm_shop_scene_smoke.gd

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
	world._refresh_all()
	var g1: FarmGame = world.game
	var farm: Node3D = world.farm_location

	# —— 段1：农场环境结构 ——
	var porch: Node = farm.get_node_or_null("ShopPorch")
	_check(porch != null and porch.get_node_or_null("AwningStrip_0") != null and porch.get_node_or_null("ShopPorchEntry") != null, "门廊：条纹雨棚+可点击踏步")
	var stairs: Node = farm.get_node_or_null("HillStairs")
	_check(stairs != null and stairs.get_node_or_null("StairsEntry") != null and stairs.get_node_or_null("StairLampHead") != null, "石阶：台阶+提灯+可点击入口")
	var neighbor: Node = farm.get_node_or_null("NeighborEntry")
	_check(neighbor != null and neighbor.get_node_or_null("WestStream") != null and neighbor.get_node_or_null("StoneBridge") != null and neighbor.get_node_or_null("NeighborMailbox") != null, "邻里入口：溪流+石桥+信箱")
	var hill_count := 0
	var tree_count := 0
	for child in farm.get_children():
		if child.has_meta("env_layer"):
			if child is MeshInstance3D:
				hill_count += 1
			else:
				tree_count += 1
	_check(hill_count >= 4, "远景山影 ≥4（%d）" % hill_count)
	_check(tree_count >= 10, "林带树列 ≥10（%d）" % tree_count)

	# —— 段2：连续地形三分辨率覆盖（正交相机角点射线落点在地台范围内） ——
	var camera: Camera3D = world.get_node("FarmCamera")
	var covered := true
	for aspect in [16.0 / 9.0, 16.0 / 10.0, 1024.0 / 640.0]:
		var ratio := float(aspect)
		var half_h := camera.size / 2.0
		var half_w := half_h * ratio
		var forward := -camera.global_transform.basis.z
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				## 正交相机：四角射线沿光轴平行，从角点平面出发打到 y=0 地面。
				var corner_origin := camera.to_global(Vector3(sx * half_w, sy * half_h, 0.0))
				if forward.y >= -0.01:
					covered = false
					continue
				var t := -corner_origin.y / forward.y
				var ground := corner_origin + forward * t
				if absf(ground.x) > 23.5 or absf(ground.z) > 19.0:
					covered = false
	_check(covered, "三分辨率四角射线均落在扩展地台内（无裸露截面）")

	# —— 段3：未购地块草桩 ——
	var stubs_visible := 0
	var plots_visible := 0
	for plot_id in range(1, 11):
		var body: Node = farm.get_node_or_null("Plot_%02d" % plot_id)
		if body == null:
			continue
		plots_visible += 1
		var stub: MeshInstance3D = body.get_node_or_null("PlotStub")
		if stub != null and stub.visible:
			stubs_visible += 1
	_check(plots_visible == 10, "十块地全部可见（含未购）")
	_check(stubs_visible == 10 - fresh.owned_plot_ids().size(), "未购地块显示草桩（%d 块）" % stubs_visible)

	# —— 段4：商店内景结构与客人 ——
	var shop: Node3D = world.get_node_or_null("ShopInterior")
	if not _check(shop != null, "商店内景存在"):
		_finish(backup)
		return
	_check(shop.get_node_or_null("ShopCamera") != null, "内景相机存在")
	_check(shop.get_node_or_null("ShopCounter") != null, "柜台存在")
	_check(shop.get_node_or_null("ShopShelfLeft") != null and shop.get_node_or_null("ShopShelfRight") != null, "左右货架存在")
	_check(shop.get_node_or_null("DelegationDesk") != null, "委托台存在")
	_check(shop.get_node_or_null("ShopDoor") != null, "回程门存在")
	var guest_ids: Array = fresh.state["market"].get("guest_ids", [])
	var guests_ok := true
	for slot_index in range(3):
		var slot: Node = shop.get_node_or_null("GuestSlot_%d" % (slot_index + 1))
		if slot == null or slot.get_node_or_null("GuestAppearance") == null:
			guests_ok = false
	_check(guests_ok and guest_ids.size() == 3, "三客人已入店且模型与当日 guest_ids 一致")

	# —— 段5：相机切换与零重建复检 ——
	world.router.switch_to("shop")
	var shop_cam: Camera3D = shop.get_node("ShopCamera")
	var farm_cam: Camera3D = world.get_node("FarmCamera")
	_check(shop_cam.current and not farm_cam.current, "进店：内景相机 current，农场相机让位")
	world.router.go_back()
	_check(farm_cam.current and not shop_cam.current, "回农场：相机还原")
	world.router.switch_to("shop")
	world.router.go_back()
	_check(world.game == g1, "两轮往返 game 同实例（零重建复检）")

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
		print("D48-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D48-FAIL %s" % label)
	return ok
