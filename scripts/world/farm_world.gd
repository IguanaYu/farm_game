extends Node3D

const HUD_SCRIPT := preload("res://scripts/ui/farm_hud.gd")
const PLOT_EMPTY := preload("res://assets/models/plot_empty.glb")
## R3 门廊雨棚配色（稿 §4 入口表：绿白条纹）。
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
	# 岩芽菜：独立低模三阶段资产。
	"rock_sprout": {
		"sprout": preload("res://assets/models/plot_rock_sprout_sprout.tscn"),
		"growing": preload("res://assets/models/plot_rock_sprout_growing.tscn"),
		"mature": preload("res://assets/models/plot_rock_sprout_mature.tscn"),
	},
	# 萤果：独立低模三阶段资产。
	"glow_berry": {
		"sprout": preload("res://assets/models/plot_glow_berry_sprout.tscn"),
		"growing": preload("res://assets/models/plot_glow_berry_growing.tscn"),
		"mature": preload("res://assets/models/plot_glow_berry_mature.tscn"),
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


## R2：常驻上下文（GameContext）持有模式/档/线上桥接；farm_world 只做视图与装配。
var context: GameContext = null
## R2：地点路由与地点根——农场 3D 全部挂 FarmLocation 下，切换=该节点可见性（不重建）。
var router: SceneRouter = null
var farm_location: Node3D = null
## R7：拜访地点（运行时按目标家园重建内容；null=未拜访）。
var visit_yard: Node3D = null
var visit_house: Node3D = null
var _party_fingerprint := ""
var _party_clock := 0.0


func _ready() -> void:
	context = GameContext.create()
	context.attach_to(self)
	context.bootstrapped.connect(_on_context_ready)
	context.login_failed.connect(_online_login_failed)
	context.status_changed.connect(_on_online_status)
	context.boot()


## 上下文就绪（离线 boot 完成 / 线上首快照到达）：构建视图。幂等——重复快照不重建。
func _on_context_ready() -> void:
	if hud != null:
		return  # 仅首个快照构建；后续快照由命令路径各自刷新
	game = context.game
	online = context.online
	_build_farm()
	_setup_router()
	_build_hud()
	hud.location_router = Callable(router, "switch_to")
	hud.quote_projection = func(index: int) -> Vector2:
		return get_viewport().get_camera_3d().unproject_position(guest_slots[index].global_position+Vector3(0,1.9,0))
	router.location_changed.connect(_on_location_presented)
	_on_location_presented("farm")
	hud.visit_enter_requested.connect(enter_visit)
	if online != null:
		hud.set_online_mode(true)
		hud.online_request = Callable(online, "request")
		hud.set_online_expedition(online)
	_refresh_all()
	_start_clock()
	AudioKit.play_music(self)
	if online != null:
		## M3：welcome 附带活动局（重连恢复，S05 核心）→ 直接回到局面板。
		if not context.resume_run.is_empty() and str(context.resume_run.get("outcome", "")) == "":
			hud.enter_online_run()
		return
	if context.open_room_on_entry and hud != null:
		# 主菜单"好友联机"直入：读档/建档完成后自动打开房间页（延迟一帧让 HUD 先完成布局）。
		hud.call_deferred("open_room")


func _process(delta: float) -> void:
	_party_clock += delta
	if _party_clock >= 0.5 and hud != null:
		_party_clock = 0.0
		_refresh_camp_party()
	# 成熟标记上下浮动 + 缓慢旋转，让"可收获"一目了然。
	var time := float(Time.get_ticks_msec()) / 1000.0
	# R5 打磨（稿 §9 低频动效）：店内客人轻微起伏、篝火火焰闪烁。
	if not guest_slots.is_empty():
		for slot_index in range(guest_slots.size()):
			var appearance: Node = guest_slots[slot_index].get_node_or_null("GuestAppearance")
			if appearance is Node3D:
				(appearance as Node3D).position.y = 0.04 * sin(time * 1.6 + slot_index * 2.1)
	var flame: MeshInstance3D = get_node_or_null("CaveCamp/Campfire/FireFlame") if has_node("CaveCamp") else null
	if flame != null:
		flame.scale = Vector3.ONE * (1.0 + 0.08 * sin(time * 9.0) + 0.05 * sin(time * 23.0))
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
	farm_location = Node3D.new()
	farm_location.name = "FarmLocation"
	add_child(farm_location)
	var environment_node := WorldEnvironment.new()
	environment_node.name = "FarmEnvironment"
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color("#c6dcd0")
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color("#ecf3ea")
	sky.ambient_light_energy = 0.60
	sky.tonemap_exposure = 1.0
	environment_node.environment = sky
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-58,-25,0)
	sun.light_color = Color("#fffaf0")
	sun.light_energy = 0.70
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_max_distance = 48.0
	add_child(sun)
	var camera := Camera3D.new()
	camera.name = "FarmCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.8
	camera.position = Vector3(6.8,15.8,22.6)
	add_child(camera)
	camera.look_at(Vector3(0,0.4,-2.2))
	camera.make_current()
	SceneArt.landscape(farm_location)
	for column in range(5):
		for row in range(2):
			_add_plot(row*5+column+1, Vector3((column-2)*2.7,0.08,0.5+row*2.7))
	_add_cottage(farm_location,"ShopBuilding",Vector3(-5.4,0,-5.9),"杂货铺",Color("#b9785c"),true,_on_building_input.bind("shop"))
	_add_cottage(farm_location,"NeighborHouse",Vector3(-0.5,0,-7.4),"邻里人家",Color("#849b86"),false,_on_neighbor_entry_input)
	_add_cottage(farm_location,"WarehouseBuilding",Vector3(5.0,0,-5.9),"仓库工坊",Color("#849da0"),false,_on_building_input.bind("warehouse"))
	var breeder := _hotspot(farm_location,"BreederBuilding",Vector3(7.4,0,-2.5),Vector3(1.4,1.8,1.4),"育种台",_on_building_input.bind("breeder"))
	breeder.add_child(BREEDER_MODEL.instantiate())
	var craft := _hotspot(farm_location,"CraftTable",Vector3(5.2,0,-2.5),Vector3(1.7,1.4,1.1),"制作台",_on_building_input.bind("craft"))
	SceneArt.table(craft,Vector3.ZERO,Vector2(1.7,1.0))
	SceneArt.box(craft,"Anvil",Vector3(0.3,1.16,0),Vector3(0.55,0.25,0.35),Color("#859394"))
	var stairs := _hotspot(farm_location,"HillStairs",Vector3(9.0,0,-4.6),Vector3(2.3,1.4,3.0),"上山 · 洞口营地",_on_stairs_to_camp)
	for i in range(5):
		SceneArt.box(stairs,"StoneStep",Vector3(0,0.12+i*0.13,-i*0.48),Vector3(2.0,0.22+i*0.26,0.55),Color("#b7bcaa"))
	SceneArt.lantern(stairs,Vector3(1.2,1.3,-1.5))
	var mailbox := _hotspot(farm_location,"NeighborEntry",Vector3(-8.4,0,3.2),Vector3(1.1,1.7,0.9),"邻里地址簿",_on_neighbor_entry_input)
	SceneArt.box(mailbox,"MailboxPost",Vector3(0,0.65,0),Vector3(0.14,1.3,0.14),SceneArt.WOOD)
	SceneArt.box(mailbox,"Mailbox",Vector3(0,1.35,0),Vector3(0.76,0.50,0.45),Color("#8aa7a3"))
	SceneArt.box(mailbox,"Letter",Vector3(0,1.35,0.24),Vector3(0.52,0.32,0.025),SceneArt.CREAM)
	SceneArt.fence(farm_location,Vector3(-7.3,0,-1.3),Vector3(7.3,0,-1.3))
	SceneArt.fence(farm_location,Vector3(-7.3,0,4.8),Vector3(-1.1,0,4.8))
	SceneArt.fence(farm_location,Vector3(1.1,0,4.8),Vector3(7.3,0,4.8))
	SceneArt.fence(farm_location,Vector3(7.3,0,-1.3),Vector3(7.3,0,4.8))
	SceneArt.crate(farm_location,Vector3(-7.9,0,0.7),true)
	SceneArt.cylinder(farm_location,"WellWall",Vector3(8.6,0.38,2),0.6,0.76,Color("#b6bda6"))
	SceneArt.cylinder(farm_location,"WellWater",Vector3(8.6,0.78,2),0.45,0.02,Color("#749b98"))


func _setup_router() -> void:
	router = SceneRouter.new()
	router.name = "SceneRouter"
	add_child(router)
	router.register("farm", farm_location,
		func(): get_node("FarmCamera").make_current(); _set_location_physics(farm_location, true),
		func(): _set_location_physics(farm_location, false))
	var shop := _build_shop_interior()
	## 隐藏地点的碰撞体不参与射线（物理查询不理会可见性——world_picking 实测坑）：
	## 切入开层 1，切离清层；构建后立即关闭商店侧。
	_set_location_physics(shop, false)
	var enter_shop := func() -> void:
		var cam: Camera3D = shop.get_node_or_null("ShopCamera")
		if cam != null:
			cam.current = true
		_set_location_physics(shop, true)
	var leave_shop := func() -> void:
		var cam: Camera3D = get_node_or_null("FarmCamera")
		if cam != null:
			cam.current = true
		_set_location_physics(shop, false)
	router.register("shop", shop, enter_shop, leave_shop)
	var camp := _build_cave_camp()
	_set_location_physics(camp, false)
	var enter_camp := func() -> void:
		var cam: Camera3D = camp.get_node_or_null("CampCamera")
		if cam != null:
			cam.current = true
		_set_location_physics(camp, true)
	var leave_camp := func() -> void:
		var cam: Camera3D = get_node_or_null("FarmCamera")
		if cam != null:
			cam.current = true
		_set_location_physics(camp, false)
	router.register("cave_camp", camp, enter_camp, leave_camp)
	## R5 地点音乐（稿 §9 声画辨识度）：随地点切换换轨；无对应资产回退农场昼曲。
	router.location_changed.connect(_on_location_music)


## 商店内景（稿 §5，R3 正式版）：暖木地板+三面墙的浅俯视切墙间；后墙柜台、左右货架、
## 委托台角落、前景三客人（点击=今日集市面板）、门=回程。交易规则全部沿用现有面板（39 命令不动）。
func _build_shop_interior() -> Node3D:
	var shop := Node3D.new()
	shop.name = "ShopInterior"
	shop.visible = false
	add_child(shop)
	_place_camera(shop,"ShopCamera",Vector3(0,7.8,13),Vector3(0,1.3,-0.4),9.1)
	SceneArt.room(shop)
	var counter := _hotspot(shop,"ShopCounter",Vector3(0,0,-1.7),Vector3(5.6,1.5,1.0),"今日收购 · 公告",_on_shop_counter_input)
	SceneArt.box(counter,"CounterBody",Vector3(0,0.57,0),Vector3(5.6,1.14,1.0),Color("#ad8b5d"))
	SceneArt.box(counter,"CounterTop",Vector3(0,1.2,0),Vector3(5.9,0.18,1.2),Color("#d5b580"))
	SceneArt.box(counter,"CounterTrim",Vector3(0,0.8,0.52),Vector3(5.65,0.10,0.05),Color("#dcc296"))
	SceneArt.crate(counter,Vector3(1.8,1.3,0),true)
	for i in range(5):
		SceneArt.facet(counter,"DisplayCabbage",Vector3(-1.6+i*0.37,1.41,0),Vector3(0.36,0.29,0.34),Color("#b6ce8b"))
	var seeds := _hotspot(shop,"ShopShelfLeft",Vector3(-4.4,0,-2.7),Vector3(2.5,2.7,1.1),"种子架",_on_shop_shelf_input.bind("seeds"))
	SceneArt.shelf(seeds)
	var fertilizer := _hotspot(shop,"ShopShelfRight",Vector3(4.4,0,-2.7),Vector3(2.5,2.7,1.1),"肥料架",_on_shop_shelf_input.bind("fertilizers"))
	SceneArt.shelf(fertilizer,true)
	var desk := _hotspot(shop,"DelegationDesk",Vector3(4.4,0,1.0),Vector3(2.0,1.4,1.4),"设施与升级",_on_shop_shelf_input.bind("facilities"))
	SceneArt.table(desk,Vector3.ZERO,Vector2(1.8,1.1))
	SceneArt.box(desk,"Ledger",Vector3(0,1.08,0.1),Vector3(0.7,0.08,0.45),Color("#e7ddad"))
	var basket := _hotspot(shop,"CropBasket",Vector3(-4.2,0,2.1),Vector3(1.5,1.1,1.4),"作物篮 · 选数量",_on_basket_input)
	SceneArt.crate(basket,Vector3.ZERO,true)
	var board := _hotspot(shop,"MarketBoard",Vector3(-1.8,1.1,-4.1),Vector3(2.0,1.8,0.3),"今日公式与锁定",_on_shop_counter_input)
	SceneArt.box(board,"BoardFrame",Vector3(0,0.95,0),Vector3(1.9,1.7,0.12),SceneArt.DARK_WOOD)
	SceneArt.box(board,"BoardFace",Vector3(0,0.95,0.08),Vector3(1.65,1.45,0.05),Color("#667c5b"))
	for offset in [-2.8,0.0,2.8]:
		_add_guest_slot(Vector3(offset,0,1.8),shop)
	var door := _hotspot(shop,"ShopDoor",Vector3(-5.15,0,0.0),Vector3(1.3,2.3,0.5),"回农庄",_on_shop_door_input)
	SceneArt.door(door,Vector3.ZERO)
	SceneArt.planter(shop,Vector3(5.4,0,3.2))
	return shop


func _set_location_physics(root: Node, enabled: bool) -> void:
	for child in root.get_children():
		if child is CollisionObject3D:
			if enabled:
				child.collision_layer = 1 if not child.has_meta("orig_layer") else int(child.get_meta("orig_layer"))
			else:
				if not child.has_meta("orig_layer"):
					child.set_meta("orig_layer", child.collision_layer)
				child.collision_layer = 0
		_set_location_physics(child, enabled)


func _on_location_music(location_id: String) -> void:
	var track := "farm_day"
	match location_id:
		"shop":
			track = "shop_cozy"
		"cave_camp":
			track = "camp_fire"
	if track != "farm_day" and AudioKit.stream(track) == null:
		track = "farm_day"
	AudioKit.play_music(self, track)


## 上山石阶：去洞窟营地（稿 §6"避免把上山误当成立即开战"——石阶只换地点，洞口才出发）。
func _on_stairs_to_camp(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		if router != null:
			router.switch_to("cave_camp")


## 营地：山体暗洞口（点击=出发界面）、篝火（组队）、战备台（配装）、帐篷装饰、下山路口。
func _build_cave_camp() -> Node3D:
	var camp := Node3D.new()
	camp.name = "CaveCamp"
	camp.visible = false
	add_child(camp)
	_place_camera(camp,"CampCamera",Vector3(0,9.5,14),Vector3(0,1.1,-1.6),11.5)
	SceneArt.camp(camp)
	var mouth := _hotspot(camp,"CaveMouth",Vector3(0,0,-4.8),Vector3(3.5,3.2,1.6),"洞口 · 出发与继续",_on_cave_mouth_input)
	mouth.set_meta("entry","depart")
	var fire := _hotspot(camp,"Campfire",Vector3(-3.1,0,0.3),Vector3(2.0,1.4,2.0),"篝火 · 组队",_on_campfire_input)
	SceneArt.fire(fire)
	fire.set_meta("entry","team")
	var bench := _hotspot(camp,"WarBench",Vector3(3.2,0,1.5),Vector3(2.4,1.5,1.4),"战备台 · 配装",_on_war_bench_input)
	SceneArt.table(bench,Vector3.ZERO,Vector2(2.3,1.2))
	SceneArt.box(bench,"EquipmentBlade",Vector3(-0.4,1.10,0),Vector3(0.15,0.1,0.85),Color("#bbc4b5"))
	SceneArt.box(bench,"EquipmentHandle",Vector3(-0.4,1.10,0.54),Vector3(0.19,0.13,0.30),SceneArt.DARK_WOOD)
	SceneArt.facet(bench,"Pack",Vector3(0.65,1.35,0.1),Vector3(0.62,0.57,0.42),Color("#9a9f78"))
	bench.set_meta("entry","loadout")
	var downhill := _hotspot(camp,"DownhillPath",Vector3(0,0,5.0),Vector3(2.5,0.9,2.0),"下山 · 回农场",_on_downhill_input)
	downhill.set_meta("entry","downhill")
	var party := Node3D.new()
	party.name = "PartyStand"
	party.position = Vector3(-1.5,0,2.4)
	camp.add_child(party)
	var supplies := _hotspot(camp,"CampSupplies",Vector3(4.8,0,3.5),Vector3(1.7,1.2,1.4),"收获行囊 · 整理仓库",_on_camp_supplies_input)
	SceneArt.crate(supplies,Vector3.ZERO,false)
	SceneArt.facet(supplies,"CarryBag",Vector3(0.3,0.65,0),Vector3(0.70,0.8,0.6),Color("#9a9f78"))
	return camp


func _on_cave_mouth_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		hud.open_expedition_hub()


## 篝火：组队（farm_hud.open_room 自动分流离线房间面板/线上 OnlineRoomPanel）。
func _on_campfire_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		hud.open_room()


## 战备台：配装（M2 配装命令在线离线均可用）。
func _on_war_bench_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		hud.open_loadout()


## 下山路口：回农场。
func _on_downhill_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		if router != null:
			router.go_back()


func _on_shop_counter_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		hud.open_market()


func _on_shop_door_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		if router != null:
			router.go_back()



## —— R3 农场环境（稿 §4/§9）———————————————————————————————————————

## 环境层：林带围合 + 远山轮廓（不参与点击；复用树模型与低细节几何）。
func _on_neighbor_entry_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		if online == null:
			hud.show_status("好友拜访是联机玩法，请从主菜单进入线上农场。")
			return
		hud.open_visit_directory()


## —— R7 拜访（稿 §7）—————————————————————————————————————————————

## 拜访入口：地址簿选中后建院子并切换。owner/farm 来自 visit.snapshot（只读）。
func enter_visit(owner: Dictionary, farm_state: Dictionary) -> void:
	_clear_visit_locations()
	visit_yard = _build_visit_yard(owner, farm_state)
	visit_house = _build_visit_house(owner)
	add_child(visit_yard)
	add_child(visit_house)
	_set_location_physics(visit_yard, false)
	_set_location_physics(visit_house, false)
	_register_visit_location("visit_yard", visit_yard, "VisitYardCamera")
	_register_visit_location("visit_house", visit_house, "VisitHouseCamera")
	hud.set_visiting(true)
	router.switch_to("visit_yard", false)
	hud.show_status("正在拜访 %s 的家园（只读参观）。" % str(owner.get("nick", "邻居")))


func _clear_visit_locations() -> void:
	if visit_yard != null:
		if str(router.current) in ["visit_yard", "visit_house"]:
			router.switch_to("farm", false)
		router.unregister("visit_yard")
		router.unregister("visit_house")
		visit_yard.queue_free()
		visit_house.queue_free()
		visit_yard = null
		visit_house = null


func _register_visit_location(id: String, root: Node3D, camera_name: String) -> void:
	router.register(id, root,
		func(): (root.get_node(camera_name) as Camera3D).make_current(); _set_location_physics(root, true),
		func(): _set_location_physics(root, false))


## 院子（稿 §7）：复用农场视觉模板的只读变体——地块按主人状态渲染（不可交互）、
## 房子（点击进小屋）、屋顶色与房名牌即主人身份、花藤院门（回自己农场）。
func _build_visit_yard(owner: Dictionary, farm_state: Dictionary) -> Node3D:
	var yard := Node3D.new()
	yard.name = "VisitYard"
	yard.visible = false
	yard.set_meta("owner",owner.duplicate(true))
	_place_camera(yard,"VisitYardCamera",Vector3(6.8,15.8,22.6),Vector3(0,0.4,-2.2),14.8)
	SceneArt.landscape(yard,true)
	var plots: Array = farm_state.get("plots",[])
	for index in range(mini(plots.size(),FarmGame.MAX_PLOTS)):
		var plot: Dictionary = plots[index]
		var slot := _hotspot(yard,"VisitPlot_%02d" % (index+1),Vector3((index%5-2)*2.7,0.08,0.5+int(index/5)*2.7),Vector3(2.35,0.65,2.35),"查看地块 %02d" % (index+1),_on_visit_crop_input.bind(plot.duplicate(true)))
		if not bool(plot.get("owned",false)):
			SceneArt.undeveloped(slot)
			continue
		var model: PackedScene = PLOT_EMPTY
		if int(plot.get("seed_id",0)) != 0:
			var kind := str(plot.get("kind","cabbage"))
			var stage := "sprout"
			if _now() >= int(plot.get("ready_at",0)):
				stage = "mature"
			elif _now()-int(plot.get("planted_at",0)) >= int(PlantDefs.get_plant(kind)["grow_seconds"])/3:
				stage = "growing"
			model = STAGE_MODELS.get(kind,{}).get(stage,PLOT_EMPTY)
		var appearance := model.instantiate()
		appearance.name = "VisitCrop"
		slot.add_child(appearance)
	var roof_color := Color(str(owner.get("roof_color","#b9785c")))
	var house := _add_cottage(yard,"VisitHouse",Vector3(0,0,-6.2),str(owner.get("nick","邻居"))+" 的家",roof_color,false,_on_visit_house_input)
	house.set_meta("owner_nick",str(owner.get("nick","邻居")))
	SceneArt.fence(yard,Vector3(-7.3,0,-1.3),Vector3(7.3,0,-1.3))
	SceneArt.fence(yard,Vector3(-7.3,0,4.8),Vector3(-1.1,0,4.8))
	SceneArt.fence(yard,Vector3(1.1,0,4.8),Vector3(7.3,0,4.8))
	var gate := _hotspot(yard,"VisitGate",Vector3(-8.2,0,3.7),Vector3(2.1,2.4,0.8),"花藤院门 · 回自己农场",_on_visit_gate_input)
	for x in [-0.8,0.8]:
		SceneArt.box(gate,"GatePost",Vector3(x,1.1,0),Vector3(0.17,2.2,0.17),SceneArt.WOOD)
	SceneArt.box(gate,"GateLintel",Vector3(0,2.15,0),Vector3(1.9,0.16,0.16),SceneArt.WOOD)
	for i in range(7):
		SceneArt.facet(gate,"Vine",Vector3(-0.88+i*0.28,2.22,0),Vector3(0.40,0.30,0.34),SceneArt.LEAF)
		if i%2:
			SceneArt.facet(gate,"VineFlower",Vector3(-0.88+i*0.28,2.19,0.19),Vector3(0.15,0.13,0.1),Color("#d0a3aa"))
	var leaf := Node3D.new()
	leaf.position = Vector3(-0.75,0,0)
	leaf.rotation_degrees.y = -45
	gate.add_child(leaf)
	SceneArt.box(leaf,"HalfOpenGate",Vector3(0.5,0.65,0),Vector3(1.0,1.1,0.1),SceneArt.WOOD)
	return yard


func _build_visit_house(owner: Dictionary) -> Node3D:
	var house := Node3D.new()
	house.name = "VisitHouseInterior"
	house.visible = false
	house.set_meta("owner",owner.duplicate(true))
	_place_camera(house,"VisitHouseCamera",Vector3(0,7.8,13),Vector3(0,1.2,-0.4),9.1)
	SceneArt.room(house,false)
	var figure := _hotspot(house,"HostFigure",Vector3(-2.5,0,-0.4),Vector3(1.3,2,1),"主人形象 · 查看欢迎内容",_on_visit_board_input)
	figure.add_child(GUEST_MODELS[1].instantiate())
	figure.set_meta("owner_nick",str(owner.get("nick","邻居")))
	var nameplate := Label3D.new()
	nameplate.text = str(owner.get("nick","邻居"))+" · 默认形象\n"+("在线" if bool(owner.get("online",false)) else "离线")
	nameplate.font_size = 32
	nameplate.pixel_size = 0.005
	nameplate.outline_size = 3
	nameplate.modulate = SceneArt.CREAM
	nameplate.outline_modulate = SceneArt.DARK_WOOD
	nameplate.position = Vector3(0,2.35,0)
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	figure.add_child(nameplate)
	SceneArt.table(house,Vector3(0.1,0,-0.6),Vector2(2.3,1.5))
	SceneArt.chair(house,Vector3(-1.4,0,-0.65),-90)
	SceneArt.chair(house,Vector3(1.6,0,-0.65),90)
	SceneArt.cylinder(house,"Teapot",Vector3(0.1,1.12,-0.6),0.19,0.27,Color("#89a79d"),0.13)
	for x in [-0.6,0.7]:
		SceneArt.cylinder(house,"TeaCup",Vector3(x,1.1,-0.2),0.10,0.17,SceneArt.CREAM,0.13)
	var shelf := _hotspot(house,"DisplayShelf",Vector3(4.5,0,-2.8),Vector3(2.5,2.6,1.0),"展示架 · 只读参观",_on_visit_display_input)
	SceneArt.shelf(shelf,false,true)
	SceneArt.lantern(house,Vector3(2.8,1.4,-2.5))
	var board := _hotspot(house,"MessageBoard",Vector3(-2.0,0.7,-4.1),Vector3(2.0,2.0,0.4),"主人欢迎内容",_on_visit_board_input)
	board.set_meta("owner_nick",str(owner.get("nick","邻居")))
	SceneArt.box(board,"BoardFrame",Vector3(0,1.1,0),Vector3(1.9,1.7,0.14),SceneArt.WOOD)
	SceneArt.box(board,"PinnedPaper",Vector3(0,1.1,0.09),Vector3(1.65,1.45,0.04),SceneArt.CREAM)
	var door := _hotspot(house,"HouseDoor",Vector3(-5.15,0,0),Vector3(1.3,2.3,0.5),"出门 · 回院子",_on_visit_back_to_yard_input)
	SceneArt.door(door,Vector3.ZERO)
	var window := _hotspot(house,"HouseWindow",Vector3(2.55,1.25,-3.9),Vector3(2.0,2.1,0.3),"窗外 · 看同一院子",_on_visit_back_to_yard_input)
	window.set_meta("yard_owner",int(owner.get("account_id",0)))
	_build_yard_window(house)
	SceneArt.planter(house,Vector3(5.3,0,2.6))
	return house


func _on_visit_house_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		if router != null:
			router.switch_to("visit_house")


func _on_visit_back_to_yard_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		if router != null:
			router.switch_to("visit_yard", false)


func _on_visit_gate_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		leave_visit()


## 花藤院门回程：清拜访态、恢复操作门控、回自己农场（换朋友需重开地址簿，稿 §7 首版规则）。
func leave_visit() -> void:
	if online != null:
		online.leave_visit()
	hud.set_visiting(false)
	_clear_visit_locations()
	router.switch_to("farm", false)
	hud.show_status("回到了自己的农场。")


func _on_visit_board_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		AudioKit.play(self, "ui_click")
		var owner: Dictionary = visit_yard.get_meta("owner",{}) if visit_yard != null else {}
		var welcome := str(owner.get("welcome_message",""))
		if welcome.is_empty():
			welcome = "主人还没有设置欢迎内容。这里是默认家居展示，可以看看院子和小屋。"
		var presence := "主人在线；屋内是静态展示形象。" if bool(owner.get("online",false)) else "主人当前离线；屋内是静态展示形象。"
		var read_at := int(owner.get("snapshot_read_at",0))
		if read_at > 0:
			presence += "\n家园快照读取于 "+Time.get_datetime_string_from_unix_time(read_at,true)+" UTC。"
		hud.open_readonly("欢迎来坐坐",presence+"\n"+welcome,_visit_owner_nick())


func _visit_owner_nick() -> String:
	for node in [visit_house, visit_yard]:
		if node == null:
			continue
		for name in ["MessageBoard", "VisitHouse"]:
			var target: Node = node.get_node_or_null(name)
			if target != null and target.has_meta("owner_nick"):
				return str(target.get_meta("owner_nick"))
	return "邻居"


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
	## R3（稿 §4）：未购地块不再隐藏——待开垦草桩表达连续扩地位置。
	var stub := SceneArt.undeveloped(body)
	stub.visible = false
	body.input_event.connect(_on_plot_input.bind(plot_id))
	body.mouse_entered.connect(_on_plot_hover.bind(plot_id))
	body.mouse_exited.connect(_on_plot_exit.bind(plot_id))
	_loc().add_child(body)
	plot_holders[plot_id] = model_holder


func _add_guest_slot(location: Vector3, root: Node3D = null) -> void:
	## 客人站位（R3 起位于商店内景前景）：模型按当日出现的客人切换，点击打开今日集市。
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
	(root if root != null else _loc()).add_child(body)
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


func _on_guest_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int, slot_index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		hud.view_now = _now()
		var ids: Array = game.state["market"].get("guest_ids",[])
		if slot_index < ids.size():
			hud.open_guest(int(ids[slot_index]))


func _loc() -> Node3D:
	return farm_location if farm_location != null else self


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
	body.visible = true
	body.input_ray_pickable = true
	holder.visible = owned
	var stub: Node3D = body.get_node_or_null("PlotStub")
	if stub != null:
		stub.visible = not owned
	var ring: MeshInstance3D = body.get_node_or_null("PlotHoverRing")
	if ring != null and not owned:
		ring.visible = false


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
	if context.tick_market():
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


## M2：线上命令提交助手。返回 {done, result}：done=false=未送出/规则失败（提示已给）；
## result=服务器转发的规则返回值（String 型命令是消息串，""=成功）。
func _online_cmd(op: String, args: Dictionary) -> Dictionary:
	var reply: Dictionary = await online.request(op, args)
	if reply.is_empty() or reply.get("t", "") == "req_err":
		if not reply.is_empty():
			AudioKit.play(self, "warn")
			hud.show_status(str(reply.get("msg", "操作失败")))
		return {"done": false}
	return {"done": true, "result": reply.get("result", null)}


## M1 未联网化的入口统一拦截：提示后直接返回，绝不落入本地路径（F09 禁止混合两套存档归属）。
func _online_refused() -> bool:
	if online == null:
		return false
	AudioKit.play(self, "warn")
	hud.show_status("该功能将在联机版后续更新开放。")
	return true


func _on_plot_action(plot_id: int) -> void:
	if plot_id < 1 or plot_id > game.state["plots"].size() or hud.visiting:
		return
	var plot: Dictionary = game.state["plots"][plot_id-1]
	hud.set_object_anchor(get_node("FarmCamera").unproject_position(plot_holders[plot_id].global_position))
	if not bool(plot.get("owned",false)):
		hud.open_expansion()
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
				## R2：商店入口改为切换地点（占位间，柜台仍打开原商店面板；R3 换正式内景）。
				if router != null:
					router.switch_to("shop")
				else:
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
	if online != null:
		var r: Dictionary = await _online_cmd("farm.buy_seeds", {"kind": kind, "quantity": quantity})
		if not r["done"]:
			return
		_finish_buy_seed(kind, quantity, str(r["result"]))
		return
	_finish_buy_seed(kind, quantity, game.buy_seeds(quantity, kind))


func _finish_buy_seed(kind: String, quantity: int, message: String) -> void:
	if message != "":
		AudioKit.play(self, "warn")
		hud.show_status(message)
		return
	AudioKit.play(self, "buy")
	if not _save():
		hud.show_status("存档写入失败，本次购买可能没有保存！")
	_refresh_all()
	var defn := PlantDefs.get_plant(kind)
	hud.show_status("购买了 %d 粒%s种子，花费 %d 金币。" % [quantity, defn["display_name"], quantity * defn["seed_price"]])


func _on_buy_fertilizer_requested(kind: String, quantity: int) -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.buy_fertilizer", {"kind": kind, "quantity": quantity})
		if not r["done"]:
			return
		_finish_buy_fertilizer(kind, quantity, str(r["result"]))
		return
	_finish_buy_fertilizer(kind, quantity, game.buy_fertilizer(kind, quantity))


func _finish_buy_fertilizer(kind: String, quantity: int, message: String) -> void:
	if message != "":
		AudioKit.play(self, "warn")
		hud.show_status(message)
		return
	AudioKit.play(self, "buy")
	if not _save():
		hud.show_status("存档写入失败，本次购买可能没有保存！")
	_refresh_all()
	var defn: Dictionary = PlantDefs.FERTILIZERS[kind]
	var total := MarketDefs.discounted_total(quantity * defn["price"], int(game.state["shop_level"]))
	hud.show_status("购买了 %d 份%s（%d 次使用），花费 %d 金币。" % [quantity, defn["display_name"], quantity * defn["uses_per_pack"], total])


func _on_upgrade_shop_requested() -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.upgrade_shop", {})
		if not r["done"]:
			return
		_finish_upgrade_shop(str(r["result"]))
		return
	_finish_upgrade_shop(game.upgrade_shop())


func _finish_upgrade_shop(message: String) -> void:
	if message != "":
		AudioKit.play(self, "warn")
		hud.show_status(message)
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
	if online != null:
		var r: Dictionary = await _online_cmd("farm.sell_batch", {"batch_id": batch_id})
		if not r["done"]:
			return
		_finish_sell_batch(r["result"])
		return
	_finish_sell_batch(game.sell_batch(batch_id))


func _finish_sell_batch(result: Dictionary) -> void:
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
	if game.state["crop_batches"].is_empty():
		AudioKit.play(self, "warn")
		hud.show_status("仓库里没有可出售的作物。")
		return
	if online != null:
		var r: Dictionary = await _online_cmd("farm.sell_all_batches", {})
		if not r["done"]:
			return
		_finish_sell_all(int(r["result"]))
		return
	_finish_sell_all(game.sell_all_batches())


func _finish_sell_all(earned: int) -> void:
	AudioKit.play(self, "coins")
	_advance_tutorial(3)
	if not _save():
		hud.show_status("存档写入失败，本次出售可能没有保存！")
	_refresh_all()
	hud.show_status("全部出售完成，获得 %d 金币。" % earned)


func _on_recycle_seed_requested(seed_id: int) -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.recycle_seed", {"seed_id": seed_id})
		if not r["done"]:
			return
		_finish_recycle_seed(r["result"])
		return
	_finish_recycle_seed(game.recycle_seed(seed_id))


func _finish_recycle_seed(result: Dictionary) -> void:
	if result["ok"]:
		AudioKit.play(self, "coins")
	hud.show_status("回收 1 粒种子，获得 %d 金币。" % result["coins"] if result["ok"] else result["message"])
	if result["ok"] and not _save():
		hud.show_status("存档写入失败，本次回收可能没有保存！")
	_refresh_all()


func _on_recycle_pending_seed_requested(seed_id: int) -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.recycle_pending_seed", {"seed_id": seed_id})
		if not r["done"]:
			return
		_finish_recycle_pending_seed(r["result"])
		return
	_finish_recycle_pending_seed(game.recycle_pending_seed(seed_id))


func _finish_recycle_pending_seed(result: Dictionary) -> void:
	hud.show_status("回收 1 粒待领取种子，获得 %d 金币。" % result["coins"] if result["ok"] else result["message"])
	if result["ok"] and not _save():
		hud.show_status("存档写入失败，本次回收可能没有保存！")
	_refresh_all()


func _on_sell_pending_crop_requested(batch_id: int) -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.sell_pending_crop", {"batch_id": batch_id})
		if not r["done"]:
			return
		_finish_sell_pending_crop(r["result"])
		return
	_finish_sell_pending_crop(game.sell_pending_crop(batch_id))


func _finish_sell_pending_crop(result: Dictionary) -> void:
	hud.show_status("出售一批待领取作物，获得 %d 金币。" % result["coins"] if result["ok"] else result["message"])
	if result["ok"] and not _save():
		hud.show_status("存档写入失败，本次出售可能没有保存！")
	_refresh_all()


func _on_claim_pending_requested() -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.claim_pending", {})
		if not r["done"]:
			return
		_finish_claim_pending(r["result"])
		return
	_finish_claim_pending(game.claim_pending())


func _finish_claim_pending(moved: Dictionary) -> void:
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
	if online != null:
		var r: Dictionary = await _online_cmd("farm.upgrade_warehouse", {})
		if not r["done"]:
			return
		_finish_upgrade_warehouse(str(r["result"]))
		return
	_finish_upgrade_warehouse(game.upgrade_warehouse())


func _finish_upgrade_warehouse(message: String) -> void:
	if message != "":
		hud.show_status(message)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，仓库升级可能没有保存！")
	_refresh_all()
	hud.show_status("仓库升级完成，两个区的容量都提高了。")


func _on_buy_breeder_requested() -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.buy_breeder", {})
		if not r["done"]:
			return
		_finish_buy_breeder(str(r["result"]))
		return
	_finish_buy_breeder(game.buy_breeder(_now()))


func _finish_buy_breeder(message: String) -> void:
	if message != "":
		hud.show_status(message)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，购买可能没有保存！")
	_refresh_all()
	hud.show_status("育种机买好了！到仓库的种子区选一粒种子设为模板。")


func _on_upgrade_breeder_requested() -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.upgrade_breeder", {})
		if not r["done"]:
			return
		_finish_upgrade_breeder(str(r["result"]))
		return
	_finish_upgrade_breeder(game.upgrade_breeder())


func _finish_upgrade_breeder(message: String) -> void:
	if message != "":
		hud.show_status(message)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，升级可能没有保存！")
	_refresh_all()
	hud.show_status("育种机升级完成。")


func _on_set_template_requested(seed_id: int) -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.set_breeder_template", {"seed_id": seed_id})
		if not r["done"]:
			return
		_finish_set_template(r["result"])
		return
	_finish_set_template(game.set_breeder_template(seed_id, _now()))


func _finish_set_template(result: Dictionary) -> void:
	if not result["ok"]:
		hud.show_status(result["message"])
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，模板设置可能没有保存！")
	_refresh_all()
	hud.show_status("模板已锁定，原种保留在仓库；副本会按周期积存在机内。")


func _on_clear_template_requested() -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.clear_breeder_template", {})
		if not r["done"]:
			return
		_finish_clear_template(str(r["result"]))
		return
	_finish_clear_template(game.clear_breeder_template(_now()))


func _finish_clear_template(message: String) -> void:
	if message != "":
		hud.show_status(message)
	_refresh_all()
	if not _save():
		hud.show_status("存档写入失败，模板解除可能没有保存！")


func _on_collect_breeder_requested() -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.collect_breeder", {})
		if not r["done"]:
			return
		_finish_collect_breeder(r["result"])
		return
	_finish_collect_breeder(game.collect_breeder(_now()))


func _finish_collect_breeder(result: Dictionary) -> void:
	if not result["ok"]:
		hud.show_status(result["message"])
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，采摘可能没有保存！")
	_refresh_all()
	hud.show_status("采摘了 %d 粒模板副本，已放入种子区。" % result["count"])


func _on_buy_plot_requested() -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.buy_plot", {})
		if not r["done"]:
			return
		_finish_buy_plot(str(r["result"]))
		return
	_finish_buy_plot(game.buy_plot())


func _finish_buy_plot(message: String) -> void:
	if message != "":
		hud.show_status(message)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，购地可能没有保存！")
	_refresh_all()
	hud.show_status("新地块已解锁，去种点什么吧！")


func _on_buy_can2_requested() -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.buy_can2", {})
		if not r["done"]:
			return
		_finish_buy_can2(str(r["result"]))
		return
	_finish_buy_can2(game.buy_can2())


func _finish_buy_can2(message: String) -> void:
	if message != "":
		hud.show_status(message)
		_refresh_all()
		return
	if not _save():
		hud.show_status("存档写入失败，水壶升级可能没有保存！")
	_refresh_all()
	hud.show_status("水壶升到 2 级：一次浇三块地，每时段加分翻倍。")


func _on_lock_guest_requested(guest_id: int) -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.lock_guest", {"guest_id": guest_id})
		if not r["done"]:
			return
		_finish_lock_guest(str(r["result"]))
		return
	_finish_lock_guest(game.request_lock_guest(guest_id))


func _finish_lock_guest(message: String) -> void:
	hud.show_status(message if message != "" else "锁定请求已记录，明天零点生效。")
	if message == "" and not _save():
		hud.show_status("存档写入失败，锁定可能没有保存！")
	_refresh_all()


func _on_unlock_guest_requested() -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.lock_guest", {"guest_id": 0})
		if not r["done"]:
			return
		_finish_unlock_guest(str(r["result"]))
		return
	_finish_unlock_guest(game.request_lock_guest(0))


func _finish_unlock_guest(message: String) -> void:
	hud.show_status(message if message != "" else "解锁请求已记录，明天零点生效。")
	if message == "" and not _save():
		hud.show_status("存档写入失败，解锁可能没有保存！")
	_refresh_all()


func _on_lock_formula_requested(kind: String) -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.lock_formula", {"kind": kind})
		if not r["done"]:
			return
		_finish_lock_formula(str(r["result"]))
		return
	_finish_lock_formula(game.request_lock_formula(kind))


func _finish_lock_formula(message: String) -> void:
	hud.show_status(message if message != "" else "公式锁定已记录，明天零点生效（系数仍每日重抽）。")
	if message == "" and not _save():
		hud.show_status("存档写入失败，公式锁定可能没有保存！")
	_refresh_all()


func _on_unlock_formula_requested() -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.unlock_formula", {})
		if not r["done"]:
			return
		_finish_unlock_formula(str(r["result"]))
		return
	_finish_unlock_formula(game.request_unlock_formula())


func _finish_unlock_formula(message: String) -> void:
	hud.show_status(message if message != "" else "公式解锁已记录，明天零点生效。")
	if message == "" and not _save():
		hud.show_status("存档写入失败，公式解锁可能没有保存！")
	_refresh_all()


func _on_sell_batch_to_requested(batch_id: int, count: int, guest_id: int) -> void:
	if online != null:
		var r: Dictionary = await _online_cmd("farm.sell_batch_to", {"batch_id": batch_id, "count": count, "guest_id": guest_id})
		if not r["done"]:
			return
		_finish_sell_batch_to(guest_id, r["result"])
		return
	_finish_sell_batch_to(guest_id, game.sell_batch_to(batch_id, count, guest_id, _now()))


func _finish_sell_batch_to(guest_id: int, result: Dictionary) -> void:
	if not result["ok"]:
		hud.show_status(result["message"])
		_refresh_all()
		return
	_advance_tutorial(3)
	if not _save():
		hud.show_status("存档写入失败，出售可能没有保存！")
	_refresh_all()
	hud.show_status("卖给%s %d 个作物，获得 %d 金币。" % [MarketDefs.GUESTS[guest_id]["display_name"], result["sold_count"], result["coins"]])
	hud._close_modal()
	hud.show_sale_feedback(guest_id,int(result["coins"]))
	if not SettingsStore.get_reduce_motion():
		var slot: int = game.state["market"]["guest_ids"].find(guest_id)
		if slot>=0 and slot<guest_slots.size():
			var figure: Node3D = guest_slots[slot].get_node_or_null("GuestAppearance")
			if figure!=null:
				var nod := figure.create_tween()
				nod.tween_property(figure,"rotation:x",-0.10,0.10)
				nod.tween_property(figure,"rotation:x",0.0,0.18)


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


## R2 薄转发：时间与保存是常驻上下文的服务（切换地点不重建）；保留旧名以零改动调用点。
func _now() -> int:
	return context.now()


func _save() -> bool:
	return context.save_game(game)

func _place_camera(root: Node3D, title: String, at: Vector3, target: Vector3, view_size: float) -> void:
	var cam := Camera3D.new()
	cam.name = title
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_size
	cam.position = at
	root.add_child(cam)
	cam.look_at_from_position(at,target,Vector3.UP)


func _hotspot(root: Node3D, title: String, at: Vector3, dimensions: Vector3, caption: String, action: Callable) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = title
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	body.input_ray_pickable = true
	body.set_meta("caption",caption)
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	hit.shape = shape
	hit.position.y = dimensions.y * 0.5
	body.add_child(hit)
	body.input_event.connect(action)
	body.mouse_entered.connect(func(): _object_hover(body,true))
	body.mouse_exited.connect(func(): _object_hover(body,false))
	root.add_child(body)
	return body


func _object_hover(body: Node3D, enabled: bool) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if enabled else Input.CURSOR_ARROW)
	for mesh in body.find_children("*","MeshInstance3D",true,false):
		if enabled:
			var overlay := SceneArt.material(Color(1.0,0.94,0.74,0.16))
			overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			(mesh as MeshInstance3D).material_overlay = overlay
		else:
			(mesh as MeshInstance3D).material_overlay = null
	if hud != null:
		hud.show_object_hint(str(body.get_meta("caption","")) if enabled else "")


func _add_cottage(root: Node3D, title: String, at: Vector3, caption: String, roof: Color, shop: bool, action: Callable) -> StaticBody3D:
	var body := _hotspot(root,title,at,Vector3(3.7,3.9,3.4),caption,action)
	SceneArt.cottage(body,caption,roof,shop)
	return body


func _on_location_presented(id: String) -> void:
	if hud == null:
		return
	var owner: Dictionary = visit_yard.get_meta("owner",{}) if visit_yard != null else {}
	hud.set_location(id,owner)
	hud.owner_projection = func() -> Vector2:
		return get_viewport().get_camera_3d().unproject_position(visit_house.get_node("HostFigure").global_position+Vector3(0,2.3,0)) if visit_house != null else Vector2.ZERO
	var indoor := id in ["shop","visit_house"]
	var env: Environment = get_node("FarmEnvironment").environment
	env.background_color = Color("#c7bfa2") if indoor else Color("#c6dcd0")
	env.ambient_light_energy = 0.72 if indoor else 0.60
	env.ambient_light_color = Color("#fff5df") if indoor else Color("#ecf3ea")
	get_node("SunLight").light_energy = 0.5 if indoor else 0.70
	if id == "visit_house" and visit_house != null:
		(visit_house.get_node("YardWindowViewport") as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


func _build_yard_window(house: Node3D) -> void:
	# This visual world has no domain objects or writable actions.
	var viewport := SubViewport.new()
	viewport.name = "YardWindowViewport"
	viewport.size = Vector2i(512,384)
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	house.add_child(viewport)
	var visual: Node3D = visit_yard.duplicate(0)
	visual.visible = true
	viewport.add_child(visual)
	(visual.get_node("VisitYardCamera") as Camera3D).make_current()
	_set_location_physics(visual,false)
	var env := WorldEnvironment.new()
	env.environment = get_node("FarmEnvironment").environment.duplicate()
	viewport.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58,-25,0)
	light.light_energy = 0.7
	viewport.add_child(light)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.98,1.88)
	var window := MeshInstance3D.new()
	window.name = "CurrentYardWindow"
	window.mesh = quad
	window.position = Vector3(2.55,2.18,-4.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	window.material_override = mat
	house.add_child(window)


func _on_shop_shelf_input(_camera: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int, tab: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hud.shop_tab = tab
		hud.open_shop()


func _on_camp_supplies_input(_camera: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hud.open_equipment_warehouse()


func _refresh_camp_party() -> void:
	var stand: Node3D = get_node_or_null("CaveCamp/PartyStand")
	if stand == null:
		return
	var members: Array = []
	if online != null and not online.mirror_room.is_empty() and str(online.mirror_room.get("phase","")) != "over":
		members = online.mirror_room.get("members",[]).duplicate(true)
	elif hud.room_panel.host != null:
		members = hud.room_panel.host.room.get("members",{}).values().duplicate(true)
	elif hud.room_panel.client != null:
		members = hud.room_panel.room_view.get("members",{}).values().duplicate(true)
	if members.is_empty():
		members = [{"nick":"我","ready":false,"online":true}]
	var fingerprint := JSON.stringify(members)
	if fingerprint == _party_fingerprint:
		return
	_party_fingerprint = fingerprint
	for child in stand.get_children():
		stand.remove_child(child)
		child.queue_free()
	for i in range(mini(2,members.size())):
		var member: Dictionary = members[i]
		var figure: Node3D = GUEST_MODELS[1+i].instantiate()
		figure.name = "CampMember_%d" % i
		figure.position = Vector3(i*1.9,0,0)
		stand.add_child(figure)
		var label := Label3D.new()
		label.text = str(member.get("nick",member.get("name","队员")))+"\n"+("已准备" if bool(member.get("ready",false)) else "整备中")+(" · 离线" if not bool(member.get("online",true)) else "")
		label.font_size = 40
		label.pixel_size = 0.005
		label.outline_size = 3
		label.modulate = SceneArt.CREAM
		label.outline_modulate = SceneArt.DARK_WOOD
		label.position.y = 2.30
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		figure.add_child(label)


func _on_basket_input(_camera: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hud.open_basket()


func _on_visit_crop_input(_camera: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int, plot: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var content := "尚未开垦" if not bool(plot.get("owned",false)) else "空地"
		if int(plot.get("seed_id",0)) != 0:
			content = PlantDefs.get_plant(str(plot.get("kind","cabbage")))["display_name"]
			content += " · 已成熟" if _now() >= int(plot.get("ready_at",0)) else " · 生长中"
		hud.open_readonly("主人地块",content+"。这是家园快照，可以参观。",_visit_owner_nick())


func _on_visit_display_input(_camera: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		hud.open_readonly("家居展示架","默认家居陈列：书册和陶器。这里仅供参观。",_visit_owner_nick())
