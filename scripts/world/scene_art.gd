class_name SceneArt
extends RefCounted
## Shared low-poly scenery. Dimensions are in metres; every object has a ground-centred origin.
## Art has no game state, collision or save lifecycle. The world binds the visible objects to actions.

const GRASS := Color("#9bb879")
const WOOD := Color("#a88758")
const DARK_WOOD := Color("#69563e")
const CREAM := Color("#eddfb8")
const PATH := Color("#d4c49b")
const LEAF := Color("#72985b")

static func material(color: Color, glow := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	if glow > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	return mat


static func box(root: Node3D, title: String, at: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return shape(root, title, at, mesh, color)


static func shape(root: Node3D, title: String, at: Vector3, mesh: Mesh, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.position = at
	node.material_override = material(color)
	root.add_child(node,true)
	return node


static func cylinder(root: Node3D, title: String, at: Vector3, radius: float, height: float, color: Color, top := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.height = height
	return shape(root, title, at, mesh, color)


static func facet(root: Node3D, title: String, at: Vector3, dimensions: Vector3, color: Color, phase := 0.0) -> MeshInstance3D:
	var points: Array[Vector3] = []
	points.append(Vector3(0, dimensions.y * 0.5, 0))
	for y in [0.20, -0.15]:
		for i in range(7):
			var angle := TAU * i / 7.0 + phase
			points.append(Vector3(cos(angle) * dimensions.x * 0.5, dimensions.y * y,
				sin(angle) * dimensions.z * 0.5))
	points.append(Vector3(0, -dimensions.y * 0.5, 0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(7):
		var j := (i + 1) % 7
		_triangle(st, points[0], points[1 + j], points[1 + i])
		_triangle(st, points[1 + i], points[1 + j], points[8 + j])
		_triangle(st, points[1 + i], points[8 + j], points[8 + i])
		_triangle(st, points[15], points[8 + i], points[8 + j])
	return shape(root, title, at, st.commit(), color)


static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	# Godot front faces use clockwise winding; keep the outward geometric normal.
	for v in [a, c, b]:
		st.set_normal(normal)
		st.add_vertex(v)


static func ribbon(root: Node3D, title: String, points: Array[Vector3], width: float, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in range(points.size()):
		var tangent := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		var side := Vector3(-tangent.z, 0, tangent.x).normalized() * width * 0.5
		left.append(points[i] + side)
		right.append(points[i] - side)
	for i in range(points.size() - 1):
		_triangle(st, left[i], left[i + 1], right[i])
		_triangle(st, right[i], left[i + 1], right[i + 1])
	return shape(root, title, Vector3.ZERO, st.commit(), color)


static func path(root: Node3D, title: String, points: Array[Vector3], width := 1.3) -> void:
	ribbon(root, title, points, width, PATH)
	for p in [points[0], points[-1]]:
		cylinder(root, title + "End", p, width * 0.5, 0.03, PATH, width * 0.5)


static func tree(root: Node3D, at: Vector3, height := 3.6, tint := LEAF) -> Node3D:
	var node := Node3D.new()
	node.name = "WoodlandTree"
	node.position = at
	root.add_child(node,true)
	cylinder(node, "Trunk", Vector3(0, height * 0.30, 0), 0.13, height * 0.6, WOOD, 0.1)
	facet(node, "Crown", Vector3(0, height * 0.73, 0), Vector3(height * 0.56, height * 0.62, height * 0.52), tint, at.x * 0.2)
	return node


static func landscape(root: Node3D, visit := false) -> void:
	box(root, "ContinuousGround", Vector3(0, -0.14, 0), Vector3(90, 0.25, 90), GRASS)
	# Far silhouettes and a visible woodland sit behind the buildings, inside the camera composition.
	for i in range(8):
		var x := -23.0 + i * 6.5
		facet(root, "FarHill", Vector3(x, 0.6, -17.5 - (i % 2) * 2.0),
			Vector3(12, 4 + i % 3, 7), Color("#b0c9ac"), i * 0.3)
	for i in range(9):
		var x := -16.0 + i * 4.0
		facet(root, "MeadowSlope", Vector3(x, -0.7, -10.4 - (i % 2)),
			Vector3(7.0, 4.8, 6.0), Color("#8da970"), i * 0.7)
		if i != 4:
			tree(root, Vector3(x, 0.18, -9.3 - (i % 2)), 3.1 + (i % 3) * 0.5,
				Color("#75915e") if i % 2 else Color("#91aa68"))
	for p in [Vector3(-11,0,0), Vector3(11,0,-1), Vector3(11.8,0,6.5), Vector3(-10,0,7.5), Vector3(-13,0,-5), Vector3(14,0,-6)]:
		tree(root, p, 3.6 if p.z < 3 else 4.0)
	var water: Array[Vector3] = [Vector3(-14,0.035,-17), Vector3(-12,0.035,-8), Vector3(-10.7,0.035,-3),
		Vector3(-12,0.035,1), Vector3(-10,0.035,5), Vector3(-9.5,0.035,14), Vector3(-11,0.035,24)]
	ribbon(root, "StreamBank", water, 3.5, Color("#d2d3ac"))
	for i in range(water.size()):
		water[i].y = 0.06
	ribbon(root, "MeadowStream", water, 2.8, Color("#86b9b5"))
	for p in [Vector3(-11.4,0.065,-3), Vector3(-11.1,0.065,2), Vector3(-10.4,0.065,10)]:
		box(root, "WaterRipple", p, Vector3(0.8,0.01,0.035), Color("#c9dcd0"))
	bridge(root, Vector3(-10,0.1,5.2))
	path(root, "FrontWalk", [Vector3(0,0.07,18), Vector3(0,0.07,7), Vector3(-3,0.07,5.2), Vector3(-10,0.07,5.2)], 1.4)
	path(root, "BuildingWalk", [Vector3(-7,0.07,-4), Vector3(0,0.07,-3.8), Vector3(7,0.07,-4), Vector3(10,0.07,-5)], 1.4)
	path(root, "MiddleWalk", [Vector3(0,0.07,5.8), Vector3(0,0.07,0), Vector3(0,0.07,-4)], 0.85)
	for i in range(12):
		var p := Vector3(-8.5 + (i % 6) * 3.2, 0.06, -6.8 if i < 6 else 7.1)
		flowers(root, p)
	for p in [Vector3(-8.8,0.2,3), Vector3(8.2,0.2,5.5), Vector3(7.4,0.2,-7)]:
		facet(root, "MeadowStone", p, Vector3(0.75,0.55,0.6), Color("#9da18b"))
	if visit:
		path(root, "HouseWalk", [Vector3(0,0.08,-4), Vector3(0,0.08,-6)], 1.0)


static func bridge(root: Node3D, at: Vector3) -> void:
	var node := Node3D.new()
	node.name = "NeighborBridge"
	node.position = at
	root.add_child(node,true)
	for i in range(10):
		box(node, "BridgePlank", Vector3(-1.8 + i * 0.4, 0.15, 0), Vector3(0.38,0.15,1.6), Color("#cec8a9"))
	for z in [-0.85,0.85]:
		box(node, "BridgeRail", Vector3(0,0.58,z), Vector3(4,0.10,0.12), Color("#bac2a4"))
		for x in [-1.8,1.8]:
			box(node, "BridgePost", Vector3(x,0.38,z), Vector3(0.13,0.8,0.13), Color("#bac2a4"))


static func flowers(root: Node3D, at: Vector3) -> void:
	for i in range(3):
		var p := at + Vector3(i * 0.16,0,0.06 * (i % 2))
		cylinder(root, "FlowerStem", p + Vector3(0,0.17,0), 0.018,0.34,LEAF)
		facet(root, "Flower", p + Vector3(0,0.35,0), Vector3(0.13,0.11,0.13), Color("#efe4ad"))


static func fence(root: Node3D, start: Vector3, end: Vector3) -> void:
	var length := start.distance_to(end)
	var node := Node3D.new()
	node.name = "GardenFence"
	node.position = (start + end) * 0.5
	root.add_child(node,true)
	node.rotation.y = atan2(-(end.z-start.z), end.x-start.x)
	for y in [0.38,0.78]:
		box(node, "FenceRail", Vector3(0,y,0), Vector3(length,0.10,0.09), Color("#baa579"))
	for i in range(int(length/1.9)+1):
		var x := -length/2 + float(i) * length/maxi(1,int(length/1.9))
		box(node, "FencePost", Vector3(x,0.48,0), Vector3(0.12,0.96,0.12), Color("#c5af83"))
		var cap := PrismMesh.new()
		cap.size = Vector3(0.15,0.16,0.15)
		shape(node,"FenceCap",Vector3(x,1.01,0),cap,Color("#c5af83"))


static func cottage(root: Node3D, title: String, roof_color: Color, shop := false) -> void:
	box(root,"Plinth",Vector3(0,0.10,0),Vector3(3.3,0.2,2.8),Color("#c6bc99"))
	box(root,"Plaster",Vector3(0,1.3,0),Vector3(3.1,2.5,2.5),CREAM)
	var roof := PrismMesh.new()
	roof.size = Vector3(3.7,1.6,3.1)
	shape(root,"GabledRoof",Vector3(0,3.12,0),roof,roof_color)
	box(root,"Eaves",Vector3(0,2.49,0),Vector3(3.7,0.16,3.1),roof_color.darkened(0.12))
	box(root,"Chimney",Vector3(0.95,3.4,-0.6),Vector3(0.29,1.45,0.33),Color("#b6a282"))
	box(root,"ChimneyCap",Vector3(0.95,4.14,-0.6),Vector3(0.38,0.12,0.42),Color("#a08b70"))
	door(root,Vector3(0.32,0,1.28))
	window(root,Vector3(-0.89,1.62,1.27),Vector2(0.74,0.88))
	box(root,"Doorstep",Vector3(0.3,0.14,1.63),Vector3(1.4,0.28,0.63),Color("#b5b495"))
	box(root,"DoorstepLower",Vector3(0.3,0.06,1.99),Vector3(1.7,0.12,0.46),Color("#c6c39e"))
	var sign := Label3D.new()
	sign.name = "HouseNameplate"
	sign.text = title
	sign.font_size = 64
	sign.pixel_size = 0.006
	sign.modulate = Color("#fff3cc")
	sign.outline_size = 4
	sign.position = Vector3(0,2.62,1.64)
	root.add_child(sign)
	if shop:
		for i in range(6):
			var awning := box(root,"AwningStripe",Vector3(-1.4+i*0.56,2.12,1.84),Vector3(0.56,0.11,1.23),Color("#758c61") if i%2==0 else CREAM)
			awning.rotation_degrees.x = 13
			box(root,"AwningValance",Vector3(-1.4+i*0.56,1.97,2.43),Vector3(0.56,0.28,0.08),Color("#758c61") if i%2==0 else CREAM)
		crate(root,Vector3(-1.85,0.05,1.5),true)
	else:
		crate(root,Vector3(1.88,0.05,1.3))
	planter(root,Vector3(1.6,0.05,2.0))


static func door(root: Node3D, at: Vector3) -> void:
	box(root,"DoorFrame",at+Vector3(0,1.0,0),Vector3(1.0,2.0,0.13),DARK_WOOD)
	box(root,"DoorLeaf",at+Vector3(0,0.96,0.08),Vector3(0.78,1.82,0.08),Color("#8e7350"))
	for x in [-0.24,0,0.24]:
		box(root,"DoorJoin",at+Vector3(x,0.96,0.13),Vector3(0.015,1.8,0.015),Color("#786144"))
	facet(root,"DoorHandle",at+Vector3(0.25,0.9,0.18),Vector3(0.10,0.1,0.08),Color("#ead99c"))


static func window(root: Node3D, at: Vector3, dimensions := Vector2(1.5,1.5)) -> void:
	box(root,"WindowFrame",at,Vector3(dimensions.x+0.16,dimensions.y+0.16,0.12),DARK_WOOD)
	box(root,"GardenThroughWindow",at+Vector3(0,0,0.07),Vector3(dimensions.x,dimensions.y,0.06),Color("#a2beaa"))
	box(root,"WindowMullion",at+Vector3(0,0,0.12),Vector3(0.065,dimensions.y,0.06),CREAM)
	box(root,"WindowCrossbar",at+Vector3(0,0,0.12),Vector3(dimensions.x,0.065,0.06),CREAM)
	box(root,"WindowSill",at+Vector3(0,-dimensions.y/2,0.2),Vector3(dimensions.x+0.25,0.10,0.3),WOOD)


static func crate(root: Node3D, at: Vector3, filled := false) -> void:
	box(root,"CrateCore",at+Vector3(0,0.3,0),Vector3(0.8,0.6,0.65),WOOD)
	for y in [0.12,0.3,0.48]:
		box(root,"CrateSlat",at+Vector3(0,y,0.34),Vector3(0.78,0.035,0.025),DARK_WOOD)
	for x in [-0.35,0.35]:
		box(root,"CrateCorner",at+Vector3(x,0.3,0.36),Vector3(0.07,0.60,0.04),Color("#c2a575"))
	if filled:
		for i in range(4):
			facet(root,"Produce",at+Vector3(-0.26+i*0.17,0.62,0),Vector3(0.27,0.24,0.30),Color("#b6ce82"))


static func planter(root: Node3D, at: Vector3) -> void:
	cylinder(root,"FlowerPot",at+Vector3(0,0.23,0),0.24,0.46,Color("#b7805b"),0.31)
	flowers(root,at+Vector3(-0.12,0.44,0))


static func table(root: Node3D, at: Vector3, dimensions := Vector2(2.0,1.1)) -> void:
	box(root,"Tabletop",at+Vector3(0,0.95,0),Vector3(dimensions.x,0.16,dimensions.y),WOOD)
	for x in [-0.4,0.4]:
		for z in [-0.35,0.35]:
			box(root,"TableLeg",at+Vector3(x*dimensions.x,0.46,z*dimensions.y),Vector3(0.13,0.92,0.13),DARK_WOOD)


static func room(root: Node3D, shop := true) -> void:
	box(root,"RoomFoundation",Vector3(0,-0.2,0),Vector3(12,0.4,9),Color("#aa8961"))
	for i in range(24):
		box(root,"Floorboard",Vector3(-5.76+i*0.50,0.016,0),Vector3(0.49,0.05,8.85),
			Color("#c2a478") if i%3 else Color("#b99a6f"))
	for i in range(24):
		for z in [-3.0,0.1,3.2]:
			box(root,"PlankJoint",Vector3(-5.76+i*0.50,0.046,z+(i%3)*0.35),Vector3(0.46,0.008,0.015),Color("#ac8c65"))
	box(root,"BackPlaster",Vector3(0,1.9,-4.4),Vector3(12,3.8,0.2),CREAM)
	box(root,"LeftPlaster",Vector3(-6,1.6,0),Vector3(0.18,3.2,8.8),CREAM)
	box(root,"RightCutWall",Vector3(6,0.6,0),Vector3(0.18,1.2,8.8),CREAM)
	box(root,"BackBeam",Vector3(0,3.8,-4.2),Vector3(12,0.18,0.18),WOOD)
	box(root,"Skirting",Vector3(0,0.28,-4.23),Vector3(12,0.3,0.12),WOOD)
	window(root,Vector3(2.55,2.18,-4.17),Vector2(2,1.9))
	for x in [-5.8,0,5.8]:
		box(root,"WallTimber",Vector3(x,1.9,-4.15),Vector3(0.18,3.8,0.18),WOOD)
	if shop:
		var title := Label3D.new()
		title.text = "田 边 杂 货 铺"
		title.font_size = 64
		title.pixel_size = 0.006
		title.position = Vector3(-0.1,3.18,-4.05)
		title.modulate = DARK_WOOD
		title.outline_size = 0
		root.add_child(title)


static func shelf(root: Node3D, fertilizer := false, household := false) -> void:
	box(root,"ShelfBack",Vector3(0,1.15,-0.30),Vector3(2.4,2.3,0.13),DARK_WOOD)
	for y in [0.22,0.95,1.68,2.4]:
		box(root,"ShelfBoard",Vector3(0,y,0.04),Vector3(2.5,0.09,0.72),WOOD)
	for x in [-1.18,1.18]:
		box(root,"ShelfPost",Vector3(x,1.25,0),Vector3(0.12,2.5,0.60),WOOD)
	for level in range(3):
		for i in range(4):
			var p := Vector3(-0.85+i*0.56,0.5+level*0.73,0.13)
			if household:
				if i % 2:
					cylinder(root,"HouseVase",p,0.15,0.38,Color("#8daaa6"),0.10)
				else:
					box(root,"HouseBook",p,Vector3(0.24,0.45,0.22),Color("#b57f64") if level%2 else Color("#99ae7b"))
			elif fertilizer:
				cylinder(root,"FertilizerJar",p,0.17,0.45,Color("#a6b4a0") if i%2 else Color("#ccb477"),0.15)
				cylinder(root,"JarLid",p+Vector3(0,0.25,0),0.18,0.06,DARK_WOOD)
			else:
				box(root,"SeedPacket",p,Vector3(0.34,0.48,0.12),Color("#f1e8c7"))
				facet(root,"PacketLeaf",p+Vector3(0,0,0.08),Vector3(0.16,0.23,0.035),LEAF)


static func camp(root: Node3D) -> void:
	box(root,"CampGround",Vector3(0,-0.15,0),Vector3(70,0.3,70),Color("#a1af82"))
	path(root,"DownhillTrail",[Vector3(0,0.04,20),Vector3(0,0.04,4),Vector3(0,0.04,0),Vector3(0,0.04,-4)],1.5)
	for i in range(13):
		var x := -10.5+i*1.75
		if absf(x) < 2.3:
			continue
		var height := 4.1 + sin(i*2.0)*0.9
		facet(root,"CliffRock",Vector3(x,height*0.42,-5.2),Vector3(3.5,height,3.7),
			Color("#929b91") if i%2 else Color("#a4aa96"),i*0.4)
		if i%3 == 0:
			tree(root,Vector3(x,height*0.6,-6),2.8)
	# A black chamber recedes behind an irregular stone arch; no glowing rectangular door.
	box(root,"CaveDepth",Vector3(0,1.55,-7.1),Vector3(3.7,3.0,0.2),Color("#233940"))
	box(root,"CaveFloor",Vector3(0,0.06,-5.4),Vector3(3.9,0.10,4.5),Color("#65766e"))
	for side in [-1,1]:
		for i in range(3):
			facet(root,"CaveJamb",Vector3(side*(2.0-i*0.10),0.6+i*1.0,-4.8),
				Vector3(1.6,1.6,2.3),Color("#828d84"),i*0.6)
	for i in range(4):
		facet(root,"ArchCrown",Vector3(-1.6+i*1.08,3.45+sin(i*1.05)*0.35,-5),
			Vector3(1.8,1.5,2.6),Color("#98a08e"),i*0.2)
	for p in [Vector3(-9,0,2),Vector3(8,0,3),Vector3(-7,0,-2),Vector3(8,0,-4)]:
		tree(root,p,3.8)
	for i in range(6):
		facet(root,"PathStone",Vector3(-0.6+(i%2)*1.1,0.1,3.8+i*0.6),Vector3(1,0.18,0.55),Color("#bdbea3"),i*0.4)
	# Tent fabric, a dark opening, ropes, packs and a low lantern.
	var tent := Node3D.new()
	tent.name = "CampTent"
	tent.position = Vector3(4.2,0,-2.0)
	root.add_child(tent)
	var tent_mesh := PrismMesh.new()
	tent_mesh.size = Vector3(2.5,2.1,2.8)
	shape(tent,"Canvas",Vector3(0,1.05,0),tent_mesh,Color("#c6b079"))
	var entry := PrismMesh.new()
	entry.size = Vector3(1.4,1.55,0.025)
	shape(tent,"TentOpening",Vector3(0,0.78,1.43),entry,Color("#544f40"))
	box(tent,"Groundsheet",Vector3(0,0.04,0),Vector3(2.9,0.06,3.1),Color("#7d8562"))
	crate(tent,Vector3(-1.9,0,0.6))
	lantern(tent,Vector3(1.1,0.35,1.7))
	flowers(root,Vector3(-4.5,0.03,3))


static func lantern(root: Node3D, at: Vector3) -> void:
	box(root,"LanternGlass",at,Vector3(0.23,0.33,0.23),Color("#e7c477"))
	for y in [-0.2,0.2]:
		box(root,"LanternFrame",at+Vector3(0,y,0),Vector3(0.29,0.07,0.29),DARK_WOOD)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffcf8c")
	light.light_energy = 0.35
	light.omni_range = 2.4
	light.position = at
	root.add_child(light)


static func fire(root: Node3D) -> void:
	for i in range(10):
		var angle := TAU*i/10
		facet(root,"HearthStone",Vector3(cos(angle)*0.76,0.17,sin(angle)*0.76),Vector3(0.39,0.33,0.34),Color("#a3a598"),i)
	for i in range(3):
		var log := cylinder(root,"Firewood",Vector3(0,0.23,0),0.1,1.2,DARK_WOOD)
		log.rotation_degrees = Vector3(90,i*60,0)
	var flame := cylinder(root,"FireFlame",Vector3(0,0.63,0),0.32,0.85,Color("#e9ac54"),0.025)
	flame.material_override = material(Color("#f4bd61"),0.35)
	cylinder(root,"FlameHeart",Vector3(0.06,0.46,0.10),0.2,0.5,Color("#ffe1a0"),0.02)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffc276")
	light.light_energy = 0.7
	light.omni_range = 4.5
	light.position = Vector3(0,0.8,0)
	root.add_child(light)


static func chair(root: Node3D, at: Vector3, turn := 0.0) -> void:
	var node := Node3D.new()
	node.position = at
	node.rotation_degrees.y = turn
	root.add_child(node,true)
	box(node,"ChairSeat",Vector3(0,0.55,0),Vector3(0.65,0.1,0.65),WOOD)
	box(node,"ChairBack",Vector3(0,1.02,-0.29),Vector3(0.65,0.9,0.09),WOOD)
	for x in [-0.25,0.25]:
		for z in [-0.25,0.25]:
			box(node,"ChairLeg",Vector3(x,0.27,z),Vector3(0.09,0.54,0.09),DARK_WOOD)


static func undeveloped(root: Node3D) -> Node3D:
	var node := Node3D.new()
	node.name = "PlotStub"
	root.add_child(node,true)
	box(node,"PlotBoundary",Vector3(0,0.02,0),Vector3(2.22,0.06,2.22),Color("#819c65"))
	for x in [-1.05,1.05]:
		for z in [-1.05,1.05]:
			cylinder(node,"BoundaryStake",Vector3(x,0.19,z),0.06,0.38,WOOD)
	for i in range(5):
		facet(node,"UncutGrass",Vector3(-0.75+i*0.38,0.18,-0.3+(i%2)*0.7),Vector3(0.48,0.35,0.38),Color("#91ad6c"))
	return node
