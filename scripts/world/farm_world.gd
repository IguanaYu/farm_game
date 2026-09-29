extends Node3D

const HUD_SCRIPT := preload("res://scripts/ui/farm_hud.gd")
const PLOT_EMPTY := preload("res://assets/models/plot_empty.glb")
const SHOP_MODEL := preload("res://assets/models/facility_shop.glb")
const WAREHOUSE_MODEL := preload("res://assets/models/facility_warehouse.glb")
const TREE_MODEL := preload("res://assets/models/deco_tree.glb")
const FENCE_MODEL := preload("res://assets/models/deco_fence.glb")
const FLOWER_MODEL := preload("res://assets/models/deco_flower.glb")
const BREEDER_MODEL := preload("res://assets/models/facility_breeder.glb")

const STAGE_MODELS := {
	"cabbage": {
		"sprout": preload("res://assets/models/plot_cabbage_sprout.glb"),
		"growing": preload("res://assets/models/plot_cabbage_growing.glb"),
		"mature": preload("res://assets/models/plot_cabbage_mature.glb"),
	},
	"carrot": {
		"sprout": preload("res://assets/models/plot_carrot_sprout.glb"),
		"growing": preload("res://assets/models/plot_carrot_growing.glb"),
		"mature": preload("res://assets/models/plot_carrot_mature.glb"),
	},
}

var game: FarmGame
var hud: FarmHud
var plot_holders: Dictionary = {}
var plot_models: Dictionary = {}
var plot_model_keys: Dictionary = {}
var hovered_plot_id: int = 0


func _ready() -> void:
	game = FarmGame.new()
	var saved := SaveStore.load_state()
	var loaded := not saved.is_empty() and game.load_state(saved)
	if not loaded:
		saved = SaveStore.load_backup_state()
		loaded = not saved.is_empty() and game.load_state(saved)
	if not loaded:
		game.new_game(_now())
		_save()
	if game.breeder_settle(_now()):
		_save()
	_build_farm()
	_build_hud()
	_refresh_all()
	var clock := Timer.new()
	clock.name = "GrowthRefreshTimer"
	clock.wait_time = 1.0
	clock.timeout.connect(_on_clock_tick)
	add_child(clock)
	clock.start()


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_debug_mature_all()


func _build_farm() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "FarmEnvironment"
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color("#cde4e3")
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color("#e6f4e4")
	sky.ambient_light_energy = 0.20
	sky.tonemap_exposure = 0.84
	sky.adjustment_enabled = true
	sky.adjustment_saturation = 1.18
	sky.adjustment_contrast = 1.06
	environment_node.environment = sky
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.50
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	camera.name = "FarmCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.2
	camera.position = Vector3(8.8, 11.0, 14.0)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0, 0, 0))
	_add_ground("EarthBase", Vector3(15.2, 0.45, 10.4), Vector3(0, -0.38, 0), Color("#a7794f"))
	_add_ground("GrassTop", Vector3(15.0, 0.18, 10.2), Vector3(0, -0.08, 0), Color("#77a75a"))
	_add_ground("FarmPath", Vector3(9.4, 0.035, 0.45), Vector3(0, 0.035, 0), Color("#c8a772"))
	for column in range(3):
		for row in range(2):
			var plot_id: int = row * 3 + column + 1
			var x: float = (column - 1) * 2.85
			var z: float = (row - 0.5) * 2.85
			_add_plot(plot_id, Vector3(x, 0.08, z))
	_add_building("ShopBuilding", SHOP_MODEL, Vector3(-5.75, 0.08, -0.6), "shop")
	_add_building("WarehouseBuilding", WAREHOUSE_MODEL, Vector3(5.85, 0.08, -2.6), "warehouse")
	_add_building("BreederBuilding", BREEDER_MODEL, Vector3(-5.75, 0.08, 3.1), "breeder")
	for position in [Vector3(-6.35, 0.08, -3.7), Vector3(6.45, 0.08, 3.65)]:
		_add_decoration(TREE_MODEL, position)
	for position in [Vector3(-4.6, 0.08, 3.8), Vector3(-1.3, 0.08, 3.8), Vector3(2.0, 0.08, 3.8), Vector3(4.5, 0.08, -3.7)]:
		_add_decoration(FLOWER_MODEL, position)
	for x in [-4.2, -1.6, 1.0, 3.6]:
		_add_decoration(FENCE_MODEL, Vector3(x, 0.08, -4.75))
		_add_decoration(FENCE_MODEL, Vector3(x, 0.08, 4.75))
	for z in [-2.7, -0.1, 2.5]:
		_add_decoration(FENCE_MODEL, Vector3(-7.1, 0.08, z), 90.0)
		_add_decoration(FENCE_MODEL, Vector3(7.1, 0.08, z), 90.0)


func _add_ground(node_name: String, dimensions: Vector3, location: Vector3, color: Color) -> void:
	var ground := MeshInstance3D.new()
	ground.name = node_name
	var box := BoxMesh.new()
	box.size = dimensions
	ground.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	ground.material_override = material
	ground.position = location
	add_child(ground)


func _add_plot(plot_id: int, location: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Plot_%02d" % plot_id
	body.position = location
	body.collision_layer = 1
	body.collision_mask = 0
	body.input_ray_pickable = true
	var hitbox := CollisionShape3D.new()
	hitbox.name = "PlotHitbox"
	var box := BoxShape3D.new()
	box.size = Vector3(2.35, 0.55, 2.35)
	hitbox.shape = box
	hitbox.position.y = 0.23
	body.add_child(hitbox)
	var model_holder := Node3D.new()
	model_holder.name = "PlotModelHolder"
	body.add_child(model_holder)
	body.input_event.connect(_on_plot_input.bind(plot_id))
	body.mouse_entered.connect(_on_plot_hover.bind(plot_id))
	body.mouse_exited.connect(_on_plot_exit.bind(plot_id))
	add_child(body)
	plot_holders[plot_id] = model_holder


func _add_building(node_name: String, model: PackedScene, location: Vector3, kind: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = location
	body.input_ray_pickable = true
	var hitbox := CollisionShape3D.new()
	hitbox.name = "BuildingHitbox"
	var box := BoxShape3D.new()
	box.size = Vector3(2.25, 2.3, 2.25)
	hitbox.shape = box
	hitbox.position.y = 1.05
	body.add_child(hitbox)
	var appearance := model.instantiate()
	appearance.name = "Appearance"
	body.add_child(appearance)
	body.input_event.connect(_on_building_input.bind(kind))
	add_child(body)


func _add_decoration(model: PackedScene, location: Vector3, rotation_y: float = 0.0) -> void:
	var appearance := model.instantiate()
	appearance.position = location
	appearance.rotation_degrees.y = rotation_y
	add_child(appearance)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "FarmCanvas"
	add_child(canvas)
	hud = HUD_SCRIPT.new()
	hud.name = "FarmHud"
	hud.game = game
	canvas.add_child(hud)
	hud.buy_seed_requested.connect(_on_buy_seed_requested)
	hud.buy_fertilizer_requested.connect(_on_buy_fertilizer_requested)
	hud.upgrade_shop_requested.connect(_on_upgrade_shop_requested)
	hud.plant_seed_requested.connect(_on_plant_seed_requested)
	hud.water_requested.connect(_on_water_requested)
	hud.fertilize_requested.connect(_on_fertilize_requested)
	hud.harvest_all_requested.connect(_on_harvest_all_requested)
	hud.sell_batch_requested.connect(_on_sell_batch_requested)
	hud.sell_all_requested.connect(_on_sell_all_requested)
	hud.recycle_seed_requested.connect(_on_recycle_seed_requested)
	hud.recycle_pending_seed_requested.connect(_on_recycle_pending_seed_requested)
	hud.sell_pending_crop_requested.connect(_on_sell_pending_crop_requested)
	hud.claim_pending_requested.connect(_on_claim_pending_requested)
	hud.upgrade_warehouse_requested.connect(_on_upgrade_warehouse_requested)
	hud.buy_breeder_requested.connect(_on_buy_breeder_requested)
	hud.upgrade_breeder_requested.connect(_on_upgrade_breeder_requested)
	hud.set_template_requested.connect(_on_set_template_requested)
	hud.clear_template_requested.connect(_on_clear_template_requested)
	hud.collect_breeder_requested.connect(_on_collect_breeder_requested)
	hud.debug_mature_requested.connect(_debug_mature_all)


func _refresh_all() -> void:
	hud.view_now = _now()
	for plot_id in range(1, FarmGame.PLOT_COUNT + 1):
		_refresh_plot_model(plot_id)
	hud.refresh(game.state)
	_refresh_hover_hint()


func _refresh_plot_model(plot_id: int) -> void:
	var plot := game.get_plot(plot_id)
	var model_key := "empty"
	var model: PackedScene = PLOT_EMPTY
	if plot["seed_id"] != 0:
		var kind: String = plot.get("kind", "cabbage")
		var defn := PlantDefs.get_plant(kind)
		var elapsed: int = _now() - plot["planted_at"]
		var stage := "sprout"
		if _now() >= plot["ready_at"]:
			stage = "mature"
		elif elapsed >= defn["grow_seconds"] / 3:
			stage = "growing"
		model_key = "%s_%s" % [kind, stage]
		model = STAGE_MODELS[kind][stage]
	if plot_model_keys.get(plot_id, "") == model_key:
		return
	var holder: Node3D = plot_holders[plot_id]
	if plot_models.has(plot_id):
		var previous: Node3D = plot_models[plot_id]
		holder.remove_child(previous)
		previous.queue_free()
	var appearance := model.instantiate()
	appearance.name = "CropAppearance"
	holder.add_child(appearance)
	plot_models[plot_id] = appearance
	plot_model_keys[plot_id] = model_key


func _on_clock_tick() -> void:
	hud.view_now = _now()
	for plot_id in range(1, FarmGame.PLOT_COUNT + 1):
		_refresh_plot_model(plot_id)
	_refresh_hover_hint()
	hud.update_harvest_entry()


func _on_plot_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int, plot_id: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_plot_action(plot_id)


func _on_plot_hover(plot_id: int) -> void:
	hovered_plot_id = plot_id
	_refresh_hover_hint()


func _on_plot_exit(plot_id: int) -> void:
	if hovered_plot_id == plot_id:
		hovered_plot_id = 0
		hud.show_plot_hint(0, {}, _now())


func _refresh_hover_hint() -> void:
	if hovered_plot_id == 0:
		return
	hud.show_plot_hint(hovered_plot_id, game.get_plot(hovered_plot_id), _now())


func _on_plot_action(plot_id: int) -> void:
	var plot := game.get_plot(plot_id)
	if plot["seed_id"] == 0:
		hud.open_seed_picker(plot_id)
		return
	if not game.is_ready(plot_id, _now()):
		hud.open_plot_care(plot_id)
		return
	_do_harvest(plot_id)


func _do_harvest(plot_id: int) -> void:
	var result := game.harvest(plot_id, _now())
	if not result["ok"]:
		hud.show_status(result["message"])
		return
	if not _save():
		hud.show_status("存档写入失败，本次收获结果可能没有保存！")
	_refresh_all()
	var defn := PlantDefs.get_plant(result["batch"]["kind"])
	var message := "第 %d 块地收获了 %d 个%s和 %d 粒新种子。" % [plot_id, result["batch"]["count"], defn["display_name"], result["seeds"]]
	if not result["stored_crops"]:
		message += " 作物区已满，这批作物进入待领取。"
	if not result["stored_seeds"]:
		message += " 种子区已满，新种子进入待领取。"
	hud.show_status(message)
	hud.show_harvest(result)


func _on_building_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int, kind: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		match kind:
			"shop":
				hud.open_shop()
			"warehouse":
				hud.open_warehouse()
			"breeder":
				hud.view_now = _now()
				hud.open_breeder()


func _on_plant_seed_requested(plot_id: int, seed_id: int) -> void:
	var result := game.plant_seed(plot_id, seed_id, _now())
	if result != "":
		hud.show_status(result)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，本次播种可能没有保存！")
	_refresh_all()
	var plot := game.get_plot(plot_id)
	var defn := PlantDefs.get_plant(plot["kind"])
	hud.show_status("第 %d 块地已播种%s（品质 %d 分），约 %d 分钟后成熟。" % [plot_id, defn["display_name"], BreedingDefs.quality_score(plot["parent_traits"]), int(defn["grow_seconds"] / 60)])
	hud.close_modal_after_action()


func _on_water_requested(plot_id: int) -> void:
	var result := game.water(plot_id, _now())
	hud.show_status(result["message"] if not result["ok"] else "第 %d 块地浇水完成，本时段加分已记录。" % plot_id)
	if result["ok"]:
		if not _save():
			hud.show_status("存档写入失败，本次浇水可能没有保存！")
	_refresh_all()


func _on_fertilize_requested(plot_id: int, kind: String) -> void:
	var result := game.apply_fertilizer(plot_id, kind, _now())
	if not result["ok"]:
		hud.show_status(result["message"])
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，本次施肥可能没有保存！")
	_refresh_all()
	hud.show_status("第 %d 块地已施肥，2 小时内的轮次都会获得加分。" % plot_id)


func _on_buy_seed_requested(kind: String, quantity: int) -> void:
	var result := game.buy_seeds(quantity, kind)
	if result != "":
		hud.show_status(result)
		return
	if not _save():
		hud.show_status("存档写入失败，本次购买可能没有保存！")
	_refresh_all()
	var defn := PlantDefs.get_plant(kind)
	hud.show_status("购买了 %d 粒%s种子，花费 %d 金币。" % [quantity, defn["display_name"], quantity * defn["seed_price"]])


func _on_buy_fertilizer_requested(kind: String) -> void:
	var result := game.buy_fertilizer(kind)
	if result != "":
		hud.show_status(result)
		return
	if not _save():
		hud.show_status("存档写入失败，本次购买可能没有保存！")
	_refresh_all()
	var defn: Dictionary = PlantDefs.FERTILIZERS[kind]
	hud.show_status("购买了一份%s（%d 次使用），花费 %d 金币。" % [defn["display_name"], defn["uses_per_pack"], defn["price"]])


func _on_upgrade_shop_requested() -> void:
	var result := game.upgrade_shop()
	if result != "":
		hud.show_status(result)
		return
	if not _save():
		hud.show_status("存档写入失败，商店升级可能没有保存！")
	_refresh_all()
	hud.show_status("商店升到 2 级！种地到 2 级后即可购买第二种种子。")


func _on_harvest_all_requested() -> void:
	var summary := game.harvest_all(_now())
	if not summary["ok"]:
		hud.show_status("现在没有成熟的地块。")
		return
	if not _save():
		hud.show_status("存档写入失败，本次收获结果可能没有保存！")
	_refresh_all()
	hud.show_status("一键收获 %d 块地：作物 ×%d，新种子 ×%d，经验 +%d。" % [summary["results"].size(), summary["total_crops"], summary["total_seeds"], summary["total_exp"]])
	hud.show_harvest_all(summary)


func _on_sell_batch_requested(batch_id: int) -> void:
	var result := game.sell_batch(batch_id)
	if not result["ok"]:
		hud.show_status(result["message"])
		return
	if not _save():
		hud.show_status("存档写入失败，本次出售可能没有保存！")
	_refresh_all()
	hud.show_status("出售一批作物，获得 %d 金币。" % result["coins"])


func _on_sell_all_requested() -> void:
	if game.state["crop_batches"].is_empty():
		hud.show_status("仓库里没有可出售的作物。")
		return
	var earned := game.sell_all_batches()
	if not _save():
		hud.show_status("存档写入失败，本次出售可能没有保存！")
	_refresh_all()
	hud.show_status("全部出售完成，获得 %d 金币。" % earned)


func _on_recycle_seed_requested(seed_id: int) -> void:
	var result := game.recycle_seed(seed_id)
	hud.show_status("回收 1 粒种子，获得 %d 金币。" % result["coins"] if result["ok"] else result["message"])
	if result["ok"] and not _save():
		hud.show_status("存档写入失败，本次回收可能没有保存！")
	_refresh_all()


func _on_recycle_pending_seed_requested(seed_id: int) -> void:
	var result := game.recycle_pending_seed(seed_id)
	hud.show_status("回收 1 粒待领取种子，获得 %d 金币。" % result["coins"] if result["ok"] else result["message"])
	if result["ok"] and not _save():
		hud.show_status("存档写入失败，本次回收可能没有保存！")
	_refresh_all()


func _on_sell_pending_crop_requested(batch_id: int) -> void:
	var result := game.sell_pending_crop(batch_id)
	hud.show_status("出售一批待领取作物，获得 %d 金币。" % result["coins"] if result["ok"] else result["message"])
	if result["ok"] and not _save():
		hud.show_status("存档写入失败，本次出售可能没有保存！")
	_refresh_all()


func _on_claim_pending_requested() -> void:
	var moved := game.claim_pending()
	if moved["crops"] == 0 and moved["seeds"] == 0:
		hud.show_status("仓库空间仍然不足，先出售或回收一些存货。")
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，本次领取可能没有保存！")
	_refresh_all()
	hud.show_status("领取入库：作物 %d 批、种子 %d 粒。" % [moved["crops"], moved["seeds"]])


func _on_upgrade_warehouse_requested() -> void:
	var result := game.upgrade_warehouse()
	if result != "":
		hud.show_status(result)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，仓库升级可能没有保存！")
	_refresh_all()
	hud.show_status("仓库升级完成，两个区的容量都提高了。")


func _on_buy_breeder_requested() -> void:
	var result := game.buy_breeder(_now())
	if result != "":
		hud.show_status(result)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，购买可能没有保存！")
	_refresh_all()
	hud.show_status("育种机买好了！到仓库的种子区选一粒种子设为模板。")


func _on_upgrade_breeder_requested() -> void:
	var result := game.upgrade_breeder()
	if result != "":
		hud.show_status(result)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，升级可能没有保存！")
	_refresh_all()
	hud.show_status("育种机升级完成。")


func _on_set_template_requested(seed_id: int) -> void:
	var result := game.set_breeder_template(seed_id, _now())
	if not result["ok"]:
		hud.show_status(result["message"])
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，模板设置可能没有保存！")
	_refresh_all()
	hud.show_status("模板已锁定，原种保留在仓库；副本会按周期积存在机内。")


func _on_clear_template_requested() -> void:
	var result := game.clear_breeder_template(_now())
	if result != "":
		hud.show_status(result)
	_refresh_all()
	if not _save():
		hud.show_status("存档写入失败，模板解除可能没有保存！")


func _on_collect_breeder_requested() -> void:
	var result := game.collect_breeder(_now())
	if not result["ok"]:
		hud.show_status(result["message"])
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，采摘可能没有保存！")
	_refresh_all()
	hud.show_status("采摘了 %d 粒模板副本，已放入种子区。" % result["count"])


func _debug_mature_all() -> void:
	if not OS.is_debug_build():
		return
	var changed := false
	for plot in game.state["plots"]:
		if plot["seed_id"] != 0 and plot["ready_at"] > _now():
			plot["ready_at"] = _now()
			changed = true
	if changed:
		_save()
	_refresh_all()
	hud.show_status("调试：作物已成熟，可点击收获。" if changed else "没有正在生长的作物。")


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _save() -> bool:
	game.breeder_settle(_now())
	var ok := SaveStore.save_state(game.state)
	if not ok:
		push_error("存档写入失败，请检查磁盘空间与 user:// 目录权限。")
	return ok
