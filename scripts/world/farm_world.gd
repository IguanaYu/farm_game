extends Node3D

const HUD_SCRIPT := preload("res://scripts/ui/farm_hud.gd")
const PLOT_EMPTY := preload("res://assets/models/plot_empty.glb")
const SHOP_MODEL := preload("res://assets/models/facility_shop.glb")
const WAREHOUSE_MODEL := preload("res://assets/models/facility_warehouse.glb")
const TREE_MODEL := preload("res://assets/models/deco_tree.glb")
const FENCE_MODEL := preload("res://assets/models/deco_fence.glb")
const FLOWER_MODEL := preload("res://assets/models/deco_flower.glb")
const BREEDER_MODEL := preload("res://assets/models/facility_breeder.glb")
const GUEST_MODELS := {
	1: preload("res://assets/models/guest_01.glb"),
	2: preload("res://assets/models/guest_02.glb"),
	3: preload("res://assets/models/guest_03.glb"),
	4: preload("res://assets/models/guest_04.glb"),
	5: preload("res://assets/models/guest_05.glb"),
	6: preload("res://assets/models/guest_06.glb"),
}

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
	# 岩芽菜先用胡萝卜模型占位（2.8 换正式素材）。
	"rock_sprout": {
		"sprout": preload("res://assets/models/plot_carrot_sprout.glb"),
		"growing": preload("res://assets/models/plot_carrot_growing.glb"),
		"mature": preload("res://assets/models/plot_carrot_mature.glb"),
	},
	# 萤果同样先用胡萝卜模型占位（F-05：缺键让地块刷新脚本报错、永远显示空地）。
	"glow_berry": {
		"sprout": preload("res://assets/models/plot_carrot_sprout.glb"),
		"growing": preload("res://assets/models/plot_carrot_growing.glb"),
		"mature": preload("res://assets/models/plot_carrot_mature.glb"),
	},
}

var game: FarmGame
var hud: FarmHud
## M1 线上模式（计划 §5.5）：非空时本世界由服务器权威档驱动，本地 SaveStore 完全停用（F09）。
var online: OnlineFarmBridge = null
var plot_holders: Dictionary = {}
var plot_models: Dictionary = {}
var plot_model_keys: Dictionary = {}
var guest_slots: Array = []
var hovered_plot_id: int = 0


func _ready() -> void:
	game = FarmGame.new()
	if GameFlow.mode == GameFlow.Mode.ONLINE:
		_boot_online()
		return
	var fresh_start := GameFlow.mode == GameFlow.Mode.NEW_GAME
	if fresh_start:
		# 主菜单"开始新游戏"：跳过读档直接开新局（旧档由原子写自动进 .bak）。
		game.new_game(_now())
	else:
		var saved := SaveStore.load_state()
		var loaded := not saved.is_empty() and game.load_state(saved)
		if not loaded:
			saved = SaveStore.load_backup_state()
			loaded = not saved.is_empty() and game.load_state(saved)
		if not loaded:
			fresh_start = true
			game.new_game(_now())
	if _consume_tutorial_replay() and not fresh_start:
		# 只有读档路径需要归零（新档本来就是 0）；新档只落一次盘，保住"开新局前"的 .bak。
		game.state["tutorial_step"] = 0
		_save()
	elif fresh_start:
		_save()
	var open_room := GameFlow.open_room_on_entry
	GameFlow.reset()
	var market_changed := game.refresh_market(_now())
	if game.breeder_settle(_now()) or market_changed:
		_save()
	_build_farm()
	_build_hud()
	_refresh_all()
	_start_clock()
	if open_room and hud != null:
		# 主菜单"好友联机"直入：读档/建档完成后自动打开房间页（延迟一帧让 HUD 先完成布局）。
		hud.call_deferred("open_room")
	AudioKit.play_music(self)


func _process(delta: float) -> void:
	# 成熟标记上下浮动 + 缓慢旋转，让"可收获"一目了然。
	var time := float(Time.get_ticks_msec()) / 1000.0
	for plot_id in plot_holders.keys():
		var holder: Node3D = plot_holders[plot_id]
		if holder == null:
			continue
		var body: StaticBody3D = holder.get_parent()
		var marker: MeshInstance3D = body.get_node_or_null("PlotMatureMarker")
		if marker != null and marker.visible:
			marker.position.y = 1.55 + sin(time * 3.0 + plot_id) * 0.12
			marker.rotation_degrees.y += delta * 90.0


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("debug_mature_all"):
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
	camera.size = 14.6
	camera.position = Vector3(9.4, 12.0, 15.2)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0, 0, 0))
	_add_ground("EarthBase", Vector3(17.6, 0.45, 11.8), Vector3(0, -0.38, 0), Color("#a7794f"))
	_add_ground("GrassTop", Vector3(17.4, 0.18, 11.6), Vector3(0, -0.08, 0), Color("#77a75a"))
	_add_ground("FarmPath", Vector3(11.0, 0.035, 0.45), Vector3(0, 0.035, 0), Color("#c8a772"))
	# 十块地：5 列 × 2 行；未拥有的地块隐藏，购地后出现。
	for column in range(5):
		for row in range(2):
			var plot_id: int = row * 5 + column + 1
			var x: float = (column - 2) * 2.85
			var z: float = (row - 0.5) * 2.85
			_add_plot(plot_id, Vector3(x, 0.08, z))
	_add_building("ShopBuilding", SHOP_MODEL, Vector3(-4.6, 0.08, -4.35), "shop")
	_add_building("BreederBuilding", BREEDER_MODEL, Vector3(0.0, 0.08, -4.35), "breeder")
	_add_building("WarehouseBuilding", WAREHOUSE_MODEL, Vector3(4.6, 0.08, -4.35), "warehouse")
	# 第二大阶段占位入口（2.1 计划 W5）：纯色方盒＋发光顶边，正式素材 2.8 替换。
	# 位置在东南侧草坪，避开地块、建筑、客人站位与栅栏的点击区。
	_add_prop("CaveEntrance", Vector3(6.3, 0.08, 4.1), Vector3(2.0, 2.6, 1.8), Color("#4a4358"), Color("#b79ae8"), "cave")
	_add_prop("LoadoutBench", Vector3(4.6, 0.08, 4.2), Vector3(1.2, 0.9, 0.9), Color("#8a5a33"), Color("#ffd257"), "loadout")
	_add_prop("CraftTable", Vector3(4.6, 0.08, 3.1), Vector3(1.2, 0.9, 0.9), Color("#7d8a8f"), Color("#9fd0d8"), "craft")
	for position in [Vector3(-3.0, 0.08, 4.1), Vector3(0.0, 0.08, 4.1), Vector3(3.0, 0.08, 4.1)]:
		_add_guest_slot(position)
	for position in [Vector3(-6.9, 0.08, 3.6), Vector3(6.9, 0.08, 3.6)]:
		_add_decoration(TREE_MODEL, position)
	for position in [Vector3(-6.6, 0.08, 1.9), Vector3(6.6, 0.08, 1.9), Vector3(-6.6, 0.08, -0.9), Vector3(6.6, 0.08, -0.9)]:
		_add_decoration(FLOWER_MODEL, position)
	for x in [-4.2, -1.6, 1.0, 3.6]:
		_add_decoration(FENCE_MODEL, Vector3(x, 0.08, -4.9))
		_add_decoration(FENCE_MODEL, Vector3(x, 0.08, 4.9))
	for z in [-2.7, -0.1, 2.5]:
		_add_decoration(FENCE_MODEL, Vector3(-7.5, 0.08, z), 90.0)
		_add_decoration(FENCE_MODEL, Vector3(7.5, 0.08, z), 90.0)


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
	var hover_ring := MeshInstance3D.new()
	hover_ring.name = "PlotHoverRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.18
	ring_mesh.outer_radius = 1.38
	hover_ring.mesh = ring_mesh
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color("#ffe28a")
	ring_material.emission_enabled = true
	ring_material.emission = Color("#ffd257")
	ring_material.emission_energy_multiplier = 0.8
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_ring.material_override = ring_material
	hover_ring.position.y = 0.06
	hover_ring.visible = false
	body.add_child(hover_ring)
	var mature_marker := MeshInstance3D.new()
	mature_marker.name = "PlotMatureMarker"
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.3, 0.3, 0.3)
	mature_marker.mesh = marker_mesh
	mature_marker.rotation_degrees.z = 45.0
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color("#ffd257")
	marker_material.emission_enabled = true
	marker_material.emission = Color("#ffc93c")
	marker_material.emission_energy_multiplier = 1.2
	mature_marker.material_override = marker_material
	mature_marker.position.y = 1.55
	mature_marker.visible = false
	body.add_child(mature_marker)
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


## 第二大阶段占位道具（2.1 计划 W5）：纯色方盒＋发光顶边，点击走建筑分发。
func _add_prop(node_name: String, location: Vector3, dimensions: Vector3, fill: Color, edge: Color, kind: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = location
	body.input_ray_pickable = true
	var hitbox := CollisionShape3D.new()
	hitbox.name = "PropHitbox"
	var box := BoxShape3D.new()
	box.size = dimensions
	hitbox.shape = box
	hitbox.position.y = dimensions.y / 2.0
	body.add_child(hitbox)
	var mesh := MeshInstance3D.new()
	mesh.name = "PropMesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = dimensions
	mesh.mesh = box_mesh
	mesh.position = hitbox.position
	var material := StandardMaterial3D.new()
	material.albedo_color = fill
	material.roughness = 0.9
	mesh.material_override = material
	body.add_child(mesh)
	var trim := MeshInstance3D.new()
	trim.name = "PropTrim"
	var trim_mesh := BoxMesh.new()
	trim_mesh.size = Vector3(dimensions.x * 1.02, 0.12, dimensions.z * 1.02)
	trim.mesh = trim_mesh
	trim.position = Vector3(0, dimensions.y + 0.02, 0)
	var trim_material := StandardMaterial3D.new()
	trim_material.albedo_color = edge
	trim_material.emission_enabled = true
	trim_material.emission = edge
	trim_material.emission_energy_multiplier = 0.9
	trim.material_override = trim_material
	body.add_child(trim)
	body.input_event.connect(_on_building_input.bind(kind))
	add_child(body)


func _add_guest_slot(location: Vector3) -> void:
	## 门口的三个客人站位：模型按当日出现的客人切换，点击打开今日集市。
	var slot_index := guest_slots.size()
	var body := StaticBody3D.new()
	body.name = "GuestSlot_%d" % (slot_index + 1)
	body.position = location
	body.input_ray_pickable = true
	var hitbox := CollisionShape3D.new()
	hitbox.name = "GuestHitbox"
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.9, 1.2)
	hitbox.shape = box
	hitbox.position.y = 0.85
	body.add_child(hitbox)
	body.input_event.connect(_on_guest_input.bind(slot_index))
	add_child(body)
	guest_slots.append(body)


func _refresh_guest_models() -> void:
	var guest_ids: Array = game.state["market"].get("guest_ids", [])
	for slot_index in range(guest_slots.size()):
		var body: StaticBody3D = guest_slots[slot_index]
		var holder: Node = body.get_node_or_null("GuestAppearance")
		if holder != null:
			body.remove_child(holder)
			holder.queue_free()
		if slot_index < guest_ids.size() and GUEST_MODELS.has(int(guest_ids[slot_index])):
			var appearance: Node = GUEST_MODELS[int(guest_ids[slot_index])].instantiate()
			appearance.name = "GuestAppearance"
			body.add_child(appearance)


func _on_guest_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int, _slot_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		hud.view_now = _now()
		hud.open_market()


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
	hud.buy_plot_requested.connect(_on_buy_plot_requested)
	hud.buy_can2_requested.connect(_on_buy_can2_requested)
	hud.lock_guest_requested.connect(_on_lock_guest_requested)
	hud.unlock_guest_requested.connect(_on_unlock_guest_requested)
	hud.lock_formula_requested.connect(_on_lock_formula_requested)
	hud.unlock_formula_requested.connect(_on_unlock_formula_requested)
	hud.sell_batch_to_requested.connect(_on_sell_batch_to_requested)
	hud.debug_mature_requested.connect(_debug_mature_all)
	hud.expedition_save_requested.connect(_on_expedition_save_requested)
	hud.save_requested.connect(_on_plain_save_requested)


func _refresh_all() -> void:
	hud.view_now = _now()
	for plot_id in range(1, FarmGame.MAX_PLOTS + 1):
		_refresh_plot_visibility(plot_id)
		_refresh_plot_model(plot_id)
	_refresh_guest_models()
	hud.refresh(game.state)
	_refresh_hover_hint()


func _refresh_plot_visibility(plot_id: int) -> void:
	var holder: Node3D = plot_holders.get(plot_id)
	if holder == null:
		return
	var body: StaticBody3D = holder.get_parent()
	var owned: bool = plot_id in game.owned_plot_ids()
	body.visible = owned
	body.input_ray_pickable = owned


func _refresh_plot_model(plot_id: int) -> void:
	var plot := game.get_plot(plot_id)
	if plot.is_empty():
		return
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
		## F-05 兜底：未知植物/阶段缺模型时回退空地并告警，不再让场景刷新抛错。
		var stages: Dictionary = STAGE_MODELS.get(kind, {})
		if stages.has(stage):
			model = stages[stage]
		else:
			push_warning("plot model missing: %s（回退空地模型）" % model_key)
			model_key = "empty_%s" % kind
			model = PLOT_EMPTY
	_set_mature_marker(plot_id, model_key.ends_with("_mature"))
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
	if online != null:
		## 线上模式：市场跨日/结算在服务器登录与命令路径完成，本端只做展示刷新（F08/F09）。
		for plot_id in range(1, FarmGame.MAX_PLOTS + 1):
			_refresh_plot_model(plot_id)
		_refresh_hover_hint()
		hud.update_harvest_entry()
		hud.tick_update(_now())
		return
	if game.refresh_market(_now()):
		_save()
		_refresh_guest_models()
	for plot_id in range(1, FarmGame.MAX_PLOTS + 1):
		_refresh_plot_model(plot_id)
	_refresh_hover_hint()
	hud.update_harvest_entry()
	hud.tick_update(_now())


func _on_plot_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int, plot_id: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_plot_action(plot_id)


func _on_plot_hover(plot_id: int) -> void:
	hovered_plot_id = plot_id
	_set_hover_ring_visible(plot_id, true)
	_refresh_hover_hint()


func _on_plot_exit(plot_id: int) -> void:
	_set_hover_ring_visible(plot_id, false)
	if hovered_plot_id == plot_id:
		hovered_plot_id = 0
		hud.show_plot_hint(0, {}, _now())


func _set_hover_ring_visible(plot_id: int, visible_on: bool) -> void:
	var holder: Node3D = plot_holders.get(plot_id)
	if holder == null:
		return
	var body: StaticBody3D = holder.get_parent()
	var ring: MeshInstance3D = body.get_node_or_null("PlotHoverRing")
	if ring != null:
		ring.visible = visible_on


func _set_mature_marker(plot_id: int, visible_on: bool) -> void:
	var holder: Node3D = plot_holders.get(plot_id)
	if holder == null:
		return
	var body: StaticBody3D = holder.get_parent()
	var marker: MeshInstance3D = body.get_node_or_null("PlotMatureMarker")
	if marker != null:
		marker.visible = visible_on


func _refresh_hover_hint() -> void:
	if hovered_plot_id == 0:
		return
	hud.show_plot_hint(hovered_plot_id, game.get_plot(hovered_plot_id), _now())


# —— M1 线上模式（计划 §5.5） ——————————————————————————————————————


func _boot_online() -> void:
	## 不读不写本地档（F09）；等服务器快照灌入后再构建场景与 HUD。
	online = OnlineFarmBridge.new()
	online.name = "OnlineFarmBridge"
	add_child(online)
	game = online.game
	online.snapshot_applied.connect(_online_bootstrap)
	online.login_failed.connect(_online_login_failed)
	online.status_changed.connect(_on_online_status)
	var token := GameFlow.online_token
	GameFlow.reset()
	if token == "":
		token = str(OnlineClient.load_session().get("token", ""))
	online.begin(SettingsStore.get_online_server_url(), token)


func _online_bootstrap() -> void:
	if hud != null:
		return  # 仅首个快照构建；后续快照由命令路径各自刷新
	_build_farm()
	_build_hud()
	hud.set_online_mode(true)
	_refresh_all()
	_start_clock()
	AudioKit.play_music(self)


func _online_login_failed(code: String, _need: Dictionary) -> void:
	## 登录失败：给出原因并回到主菜单（不落任何本地档）。
	var layer := CanvasLayer.new()
	layer.name = "OnlineFailLayer"
	add_child(layer)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 12)
	layer.add_child(box)
	var label := Label.new()
	label.text = "线上登录失败（%s）。\n本机存档未受任何影响，返回主菜单重试或玩单机模式。" % code
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var back := Button.new()
	back.text = "返回主菜单"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	box.add_child(back)


func _on_online_status(text: String, is_online: bool) -> void:
	if hud != null:
		hud.set_online_status(text, is_online)


func _start_clock() -> void:
	var clock := Timer.new()
	clock.name = "GrowthRefreshTimer"
	clock.wait_time = 1.0
	clock.timeout.connect(_on_clock_tick)
	add_child(clock)
	clock.start()


## M1 未联网化的入口统一拦截：提示后直接返回，绝不落入本地路径（F09 禁止混合两套存档归属）。
func _online_refused() -> bool:
	if online == null:
		return false
	AudioKit.play(self, "warn")
	hud.show_status("该功能将在联机版后续更新开放。")
	return true


func _on_plot_action(plot_id: int) -> void:
	var plot := game.get_plot(plot_id)
	if plot.is_empty():
		return
	if plot["seed_id"] == 0:
		hud.open_seed_picker(plot_id)
		return
	if not game.is_ready(plot_id, _now()):
		hud.open_plot_care(plot_id)
		return
	_do_harvest(plot_id)


func _do_harvest(plot_id: int) -> void:
	if online != null:
		var reply: Dictionary = await online.request("farm.harvest", {"plot_id": plot_id})
		if reply.is_empty() or reply.get("t", "") == "req_err":
			if not reply.is_empty():
				AudioKit.play(self, "warn")
				hud.show_status(str(reply.get("msg", "收获失败")))
			return
		_finish_harvest(plot_id, reply["result"])
		return
	_finish_harvest(plot_id, game.harvest(plot_id, _now()))


func _finish_harvest(plot_id: int, result: Dictionary) -> void:
	if not result["ok"]:
		AudioKit.play(self, "warn")
		hud.show_status(result["message"])
		return
	AudioKit.play(self, "harvest")
	_record_harvest(str(result["batch"]["kind"]), int(result["batch"]["count"]))
	_advance_tutorial(2)
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
		AudioKit.play(self, "ui_click")
		if online != null and kind == "cave":
			hud.show_status("洞窟探险将在联机版后续更新开放。")
			return
		match kind:
			"shop":
				hud.open_shop()
			"warehouse":
				hud.open_warehouse()
			"breeder":
				hud.view_now = _now()
				hud.open_breeder()
			"cave":
				hud.open_expedition_hub()
			"loadout":
				hud.open_loadout()
			"craft":
				hud.open_crafting()
			"equip_wh":
				hud.open_equipment_warehouse()


func _on_plant_seed_requested(plot_id: int, seed_id: int) -> void:
	if online != null:
		var reply: Dictionary = await online.request("farm.plant_seed", {"plot_id": plot_id, "seed_id": seed_id})
		if reply.is_empty() or reply.get("t", "") == "req_err":
			if not reply.is_empty():
				AudioKit.play(self, "warn")
				hud.show_status(str(reply.get("msg", "播种失败")))
			return
		_finish_plant_seed(reply["result"], plot_id)
		return
	var message := game.plant_seed(plot_id, seed_id, _now())
	_finish_plant_seed({"ok": message == "", "message": message}, plot_id)


func _finish_plant_seed(result: Dictionary, plot_id: int) -> void:
	if not result["ok"]:
		AudioKit.play(self, "warn")
		hud.show_status(result["message"])
		_refresh_all()
		return
	AudioKit.play(self, "plant")
	## F-08：成功动作先推进引导再统一保存/刷新——推进本身也会落盘（见 _advance_tutorial），
	## 保证播种后磁盘与横幅立即到下一步，退出重开不回退。线上由服务器推进（本地钩子直通）。
	if int(game.state.get("tutorial_step", 99)) == 0:
		_advance_tutorial(0)
	elif int(game.state.get("tutorial_step", 99)) == 4:
		_advance_tutorial(4)
	if not _save():
		hud.show_status("存档写入失败，本次播种可能没有保存！")
	_refresh_all()
	var plot := game.get_plot(plot_id)
	var defn := PlantDefs.get_plant(plot["kind"])
	hud.show_status("第 %d 块地已播种%s（品质 %d 分），约 %d 分钟后成熟。" % [plot_id, defn["display_name"], BreedingDefs.quality_score(plot["parent_traits"]), int(defn["grow_seconds"] / 60)])
	hud.close_modal_after_action()


func _on_water_requested(plot_id: int) -> void:
	if online != null:
		var reply: Dictionary = await online.request("farm.water", {"plot_id": plot_id})
		if reply.is_empty() or reply.get("t", "") == "req_err":
			if not reply.is_empty():
				AudioKit.play(self, "warn")
				hud.show_status(str(reply.get("msg", "浇水失败")))
			return
		_finish_water(plot_id, reply["result"])
		return
	_finish_water(plot_id, game.water(plot_id, _now()))


func _finish_water(plot_id: int, result: Dictionary) -> void:
	if result["ok"]:
		AudioKit.play(self, "water")
	hud.show_status(result["message"] if not result["ok"] else "第 %d 块地浇水完成，本时段加分已记录。" % plot_id)
	if result["ok"]:
		_advance_tutorial(1)
		if not _save():
			hud.show_status("存档写入失败，本次浇水可能没有保存！")
	_refresh_all()


func _on_fertilize_requested(plot_id: int, kind: String) -> void:
	if online != null:
		var reply: Dictionary = await online.request("farm.fertilize", {"plot_id": plot_id, "kind": kind})
		if reply.is_empty() or reply.get("t", "") == "req_err":
			if not reply.is_empty():
				AudioKit.play(self, "warn")
				hud.show_status(str(reply.get("msg", "施肥失败")))
			return
		_finish_fertilize(plot_id, reply["result"])
		return
	_finish_fertilize(plot_id, game.apply_fertilizer(plot_id, kind, _now()))


func _finish_fertilize(plot_id: int, result: Dictionary) -> void:
	if not result["ok"]:
		AudioKit.play(self, "warn")
		hud.show_status(result["message"])
		_refresh_all()
		return
	AudioKit.play(self, "water")
	if not _save():
		hud.show_status("存档写入失败，本次施肥可能没有保存！")
	_refresh_all()
	hud.show_status("第 %d 块地已施肥，2 小时内的轮次都会获得加分。" % plot_id)


func _on_buy_seed_requested(kind: String, quantity: int) -> void:
	if _online_refused():
		return
	var result := game.buy_seeds(quantity, kind)
	if result != "":
		AudioKit.play(self, "warn")
		hud.show_status(result)
		return
	AudioKit.play(self, "buy")
	if not _save():
		hud.show_status("存档写入失败，本次购买可能没有保存！")
	_refresh_all()
	var defn := PlantDefs.get_plant(kind)
	hud.show_status("购买了 %d 粒%s种子，花费 %d 金币。" % [quantity, defn["display_name"], quantity * defn["seed_price"]])


func _on_buy_fertilizer_requested(kind: String, quantity: int) -> void:
	if _online_refused():
		return
	var result := game.buy_fertilizer(kind, quantity)
	if result != "":
		AudioKit.play(self, "warn")
		hud.show_status(result)
		return
	AudioKit.play(self, "buy")
	if not _save():
		hud.show_status("存档写入失败，本次购买可能没有保存！")
	_refresh_all()
	var defn: Dictionary = PlantDefs.FERTILIZERS[kind]
	var total := MarketDefs.discounted_total(quantity * defn["price"], int(game.state["shop_level"]))
	hud.show_status("购买了 %d 份%s（%d 次使用），花费 %d 金币。" % [quantity, defn["display_name"], quantity * defn["uses_per_pack"], total])


func _on_upgrade_shop_requested() -> void:
	if _online_refused():
		return
	var result := game.upgrade_shop()
	if result != "":
		AudioKit.play(self, "warn")
		hud.show_status(result)
		return
	AudioKit.play(self, "buy")
	if not _save():
		hud.show_status("存档写入失败，商店升级可能没有保存！")
	_refresh_all()
	hud.show_status("商店升到 2 级！种地到 2 级后即可购买第二种种子。")


func _on_harvest_all_requested() -> void:
	if online != null:
		var reply: Dictionary = await online.request("farm.harvest_all", {})
		if reply.is_empty() or reply.get("t", "") == "req_err":
			if not reply.is_empty():
				AudioKit.play(self, "warn")
				hud.show_status(str(reply.get("msg", "收获失败")))
			return
		_finish_harvest_all(reply["result"])
		return
	_finish_harvest_all(game.harvest_all(_now()))


func _finish_harvest_all(summary: Dictionary) -> void:
	if not summary["ok"]:
		AudioKit.play(self, "warn")
		hud.show_status("现在没有成熟的地块。")
		return
	AudioKit.play(self, "harvest")
	for entry in summary["results"]:
		_record_harvest(str(entry["batch"]["kind"]), int(entry["batch"]["count"]))
	_advance_tutorial(2)
	if not _save():
		hud.show_status("存档写入失败，本次收获结果可能没有保存！")
	_refresh_all()
	hud.show_status("一键收获 %d 块地：作物 ×%d，新种子 ×%d，经验 +%d。" % [summary["results"].size(), summary["total_crops"], summary["total_seeds"], summary["total_exp"]])
	hud.show_harvest_all(summary)


func _on_sell_batch_requested(batch_id: int) -> void:
	if _online_refused():
		return
	var result := game.sell_batch(batch_id)
	if not result["ok"]:
		AudioKit.play(self, "warn")
		hud.show_status(result["message"])
		return
	AudioKit.play(self, "coins")
	_advance_tutorial(3)
	if not _save():
		hud.show_status("存档写入失败，本次出售可能没有保存！")
	_refresh_all()
	hud.show_status("出售一批作物，获得 %d 金币。" % result["coins"])


func _on_sell_all_requested() -> void:
	if _online_refused():
		return
	if game.state["crop_batches"].is_empty():
		AudioKit.play(self, "warn")
		hud.show_status("仓库里没有可出售的作物。")
		return
	AudioKit.play(self, "coins")
	var earned := game.sell_all_batches()
	_advance_tutorial(3)
	if not _save():
		hud.show_status("存档写入失败，本次出售可能没有保存！")
	_refresh_all()
	hud.show_status("全部出售完成，获得 %d 金币。" % earned)


func _on_recycle_seed_requested(seed_id: int) -> void:
	if _online_refused():
		return
	var result := game.recycle_seed(seed_id)
	if result["ok"]:
		AudioKit.play(self, "coins")
	hud.show_status("回收 1 粒种子，获得 %d 金币。" % result["coins"] if result["ok"] else result["message"])
	if result["ok"] and not _save():
		hud.show_status("存档写入失败，本次回收可能没有保存！")
	_refresh_all()


func _on_recycle_pending_seed_requested(seed_id: int) -> void:
	if _online_refused():
		return
	var result := game.recycle_pending_seed(seed_id)
	hud.show_status("回收 1 粒待领取种子，获得 %d 金币。" % result["coins"] if result["ok"] else result["message"])
	if result["ok"] and not _save():
		hud.show_status("存档写入失败，本次回收可能没有保存！")
	_refresh_all()


func _on_sell_pending_crop_requested(batch_id: int) -> void:
	if _online_refused():
		return
	var result := game.sell_pending_crop(batch_id)
	hud.show_status("出售一批待领取作物，获得 %d 金币。" % result["coins"] if result["ok"] else result["message"])
	if result["ok"] and not _save():
		hud.show_status("存档写入失败，本次出售可能没有保存！")
	_refresh_all()


func _on_claim_pending_requested() -> void:
	if _online_refused():
		return
	var moved := game.claim_pending()
	if moved["crops"] == 0 and moved["seeds"] == 0:
		AudioKit.play(self, "warn")
		hud.show_status("仓库空间仍然不足，先出售或回收一些存货。")
		_refresh_all()
		return
	AudioKit.play(self, "open")
	if not _save():
		hud.show_status("存档写入失败，本次领取可能没有保存！")
	_refresh_all()
	hud.show_status("领取入库：作物 %d 批、种子 %d 粒。" % [moved["crops"], moved["seeds"]])


func _on_upgrade_warehouse_requested() -> void:
	if _online_refused():
		return
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
	if _online_refused():
		return
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
	if _online_refused():
		return
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
	if _online_refused():
		return
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
	if _online_refused():
		return
	var result := game.clear_breeder_template(_now())
	if result != "":
		hud.show_status(result)
	_refresh_all()
	if not _save():
		hud.show_status("存档写入失败，模板解除可能没有保存！")


func _on_collect_breeder_requested() -> void:
	if _online_refused():
		return
	var result := game.collect_breeder(_now())
	if not result["ok"]:
		hud.show_status(result["message"])
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，采摘可能没有保存！")
	_refresh_all()
	hud.show_status("采摘了 %d 粒模板副本，已放入种子区。" % result["count"])


func _on_buy_plot_requested() -> void:
	if _online_refused():
		return
	var result := game.buy_plot()
	if result != "":
		hud.show_status(result)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，购地可能没有保存！")
	_refresh_all()
	hud.show_status("新地块已解锁，去种点什么吧！")


func _on_buy_can2_requested() -> void:
	if _online_refused():
		return
	var result := game.buy_can2()
	if result != "":
		hud.show_status(result)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，水壶升级可能没有保存！")
	_refresh_all()
	hud.show_status("水壶升到 2 级：一次浇三块地，每时段加分翻倍。")


func _on_lock_guest_requested(guest_id: int) -> void:
	if _online_refused():
		return
	var result := game.request_lock_guest(guest_id)
	hud.show_status(result if result != "" else "锁定请求已记录，明天零点生效。")
	if result == "" and not _save():
		hud.show_status("存档写入失败，锁定可能没有保存！")
	_refresh_all()


func _on_unlock_guest_requested() -> void:
	if _online_refused():
		return
	var result := game.request_lock_guest(0)
	hud.show_status(result if result != "" else "解锁请求已记录，明天零点生效。")
	if result == "" and not _save():
		hud.show_status("存档写入失败，解锁可能没有保存！")
	_refresh_all()


func _on_lock_formula_requested(kind: String) -> void:
	if _online_refused():
		return
	var result := game.request_lock_formula(kind)
	hud.show_status(result if result != "" else "公式锁定已记录，明天零点生效（系数仍每日重抽）。")
	if result == "" and not _save():
		hud.show_status("存档写入失败，公式锁定可能没有保存！")
	_refresh_all()


func _on_unlock_formula_requested() -> void:
	if _online_refused():
		return
	var result := game.request_unlock_formula()
	hud.show_status(result if result != "" else "公式解锁已记录，明天零点生效。")
	if result == "" and not _save():
		hud.show_status("存档写入失败，公式解锁可能没有保存！")
	_refresh_all()


func _on_sell_batch_to_requested(batch_id: int, count: int, guest_id: int) -> void:
	if _online_refused():
		return
	var result := game.sell_batch_to(batch_id, count, guest_id, _now())
	if not result["ok"]:
		hud.show_status(result["message"])
		_refresh_all()
		return
	_advance_tutorial(3)
	if not _save():
		hud.show_status("存档写入失败，出售可能没有保存！")
	_refresh_all()
	hud.show_status("卖给%s %d 个作物，获得 %d 金币。" % [MarketDefs.GUESTS[guest_id]["display_name"], result["sold_count"], result["coins"]])


func _on_plain_save_requested() -> void:
	## HUD 本地改动的立即保存（跳过引导等）：不剔除演示物品，仅整档写入＋刷新。
	if online != null:
		hud.show_status("线上进度由服务器实时保存，无需手动存档。")
		return
	if not _save():
		hud.show_status("存档写入失败，本次操作可能没有保存！")
	_refresh_all()


func _on_expedition_save_requested(dirty: bool) -> void:
	## 战备面板关闭：先剔除演示物品再保存（2.1 计划 W6：演示内容不进存档）。
	if online != null:
		_refresh_all()
		return
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.strip_demo_instances()
	if dirty and not _save():
		hud.show_status("存档写入失败，战备调整可能没有保存！")
	_refresh_all()


func _debug_mature_all() -> void:
	if not OS.is_debug_build() or online != null:
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


func _advance_tutorial(completed_step: int) -> void:
	## 首轮引导：动作成功且正处在对应步骤时推进；最后一步完成或跳过后不再打扰。
	## F-08：推进即落盘并刷新横幅——不依赖玩家再做一次无关操作才可见/持久。
	## 线上模式：教程步由服务器在命令事务内推进并随快照回传，本地禁止改动（防双推进）。
	if online != null:
		return
	if int(game.state.get("tutorial_step", 99)) != completed_step:
		return
	game.state["tutorial_step"] = 99 if completed_step >= 4 else completed_step + 1
	if not _save():
		hud.show_status("存档写入失败，引导进度可能没有保存！")
	if is_instance_valid(hud):
		hud.refresh(game.state)


## 2.5：收获事件进成长统计（第一茬岩芽菜等目标判定）。
## 线上模式：服务器在命令事务内记账，本地不再重复统计。
func _record_harvest(kind: String, count: int) -> void:
	if online != null:
		return
	var crafting := CraftingGame.new()
	crafting.bind(game)
	crafting.record_event("harvested", {"kind": kind, "count": count})


func _now() -> int:
	if online != null:
		## F08：线上时间锚定服务器（本机单调流逝补足），改本机时钟不影响生长/收益。
		return online.now()
	return int(Time.get_unix_time_from_system())


## 主菜单"重新显示新手引导"：合并 GameFlow（本次会话）与 settings.cfg（跨启动）两个来源，
## cfg 标志消费即清除，避免下次进农场再次重播。
func _consume_tutorial_replay() -> bool:
	var replay := GameFlow.reset_tutorial or SettingsStore.get_tutorial_replay()
	if SettingsStore.get_tutorial_replay():
		SettingsStore.set_tutorial_replay(false)
	return replay


func _save() -> bool:
	if online != null:
		## 线上档只存在服务器（F01/F09）：每命令成功即事务落库，本地无保存动作。
		return true
	game.breeder_settle(_now())
	var ok := SaveStore.save_state(game.state)
	if not ok:
		push_error("存档写入失败，请检查磁盘空间与 user:// 目录权限。")
	return ok
