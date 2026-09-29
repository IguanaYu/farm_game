extends Node3D

const HUD_SCRIPT := preload("res://scripts/ui/farm_hud.gd")
const PLOT_EMPTY := preload("res://assets/models/plot_empty.glb")
const PLOT_SPROUT := preload("res://assets/models/plot_cabbage_sprout.glb")
const PLOT_GROWING := preload("res://assets/models/plot_cabbage_growing.glb")
const PLOT_MATURE := preload("res://assets/models/plot_cabbage_mature.glb")
const SHOP_MODEL := preload("res://assets/models/facility_shop.glb")
const WAREHOUSE_MODEL := preload("res://assets/models/facility_warehouse.glb")
const TREE_MODEL := preload("res://assets/models/deco_tree.glb")
const FENCE_MODEL := preload("res://assets/models/deco_fence.glb")
const FLOWER_MODEL := preload("res://assets/models/deco_flower.glb")

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
	canvas.add_child(hud)
	hud.buy_requested.connect(_on_buy_requested)
	hud.sell_batch_requested.connect(_on_sell_batch_requested)
	hud.sell_all_requested.connect(_on_sell_all_requested)
	hud.debug_mature_requested.connect(_debug_mature_all)


func _refresh_all() -> void:
	for plot_id in range(1, FarmGame.PLOT_COUNT + 1):
		_refresh_plot_model(plot_id)
	hud.refresh(game.state)
	_refresh_hover_hint()


func _refresh_plot_model(plot_id: int) -> void:
	var plot := game.get_plot(plot_id)
	var model_key := "empty"
	var model: PackedScene = PLOT_EMPTY
	if plot["seed_id"] != 0:
		if _now() >= plot["ready_at"]:
			model_key = "mature"
			model = PLOT_MATURE
		elif _now() - plot["planted_at"] >= FarmGame.GROW_SECONDS / 3:
			model_key = "growing"
			model = PLOT_GROWING
		else:
			model_key = "sprout"
			model = PLOT_SPROUT
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
	for plot_id in range(1, FarmGame.PLOT_COUNT + 1):
		_refresh_plot_model(plot_id)
	_refresh_hover_hint()


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
		var result := game.plant(plot_id, _now())
		if result != "":
			hud.show_status(result)
			return
		_save()
		_refresh_all()
		hud.show_status("第 %d 块地已播种，20 分钟后成熟。" % plot_id)
		return
	if not game.is_ready(plot_id, _now()):
		hud.show_status("第 %d 块地还在生长。" % plot_id)
		return
	var result := game.harvest(plot_id, _now())
	if not result["ok"]:
		hud.show_status(result["message"])
		return
	_save()
	_refresh_all()
	hud.show_status("第 %d 块地收获了 5 个白菜和 %d 粒新种子。" % [plot_id, result["seeds"]])
	hud.show_harvest(plot_id, result["seeds"])


func _on_building_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int, kind: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if kind == "shop":
			hud.open_shop()
		else:
			hud.open_warehouse()


func _on_buy_requested(quantity: int) -> void:
	var result := game.buy_seeds(quantity)
	if result != "":
		hud.show_status(result)
		return
	_save()
	_refresh_all()
	hud.show_status("购买了 %d 粒种子，花费 %d 金币。" % [quantity, quantity * FarmGame.SEED_PRICE])


func _on_sell_batch_requested(batch_id: int) -> void:
	var result := game.sell_batch(batch_id)
	if not result["ok"]:
		hud.show_status(result["message"])
		return
	_save()
	_refresh_all()
	hud.show_status("出售一批白菜，获得 %d 金币。" % result["coins"])


func _on_sell_all_requested() -> void:
	if game.state["crop_batches"].is_empty():
		hud.show_status("仓库里没有可出售的作物。")
		return
	var earned := game.sell_all_batches()
	_save()
	_refresh_all()
	hud.show_status("全部出售完成，获得 %d 金币。" % earned)


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
	return SaveStore.save_state(game.state)
