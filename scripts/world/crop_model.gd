extends Node3D
## R5 打磨（稿 §9）：岩芽菜/萤果正式占位模型——程序化几何替代胡萝卜占位。
## kind ∈ {rock_sprout, glow_berry}；stage ∈ {sprout, growing, mature} 控制尺度与细节。
## 正式美术素材就位后同名替换（保留本脚本作出处）。

@export var kind := "rock_sprout"
@export var stage := "sprout"


func _ready() -> void:
	var scale_factor := 0.45
	match stage:
		"growing":
			scale_factor = 0.75
		"mature":
			scale_factor = 1.0
	if kind == "glow_berry":
		_build_glow_berry(scale_factor)
	else:
		_build_rock_sprout(scale_factor)


## 岩芽菜：灰岩块簇 + 顶部绿芽（成熟期双芽）。
func _build_rock_sprout(scale_factor: float) -> void:
	var rock := MeshInstance3D.new()
	rock.name = "RockBody"
	var mesh := SphereMesh.new()
	mesh.radial_segments = 7
	mesh.rings = 3
	mesh.radius = 0.34 * scale_factor
	mesh.height = 0.5 * scale_factor
	rock.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#8d8d95")
	material.roughness = 1.0
	rock.material_override = material
	rock.position.y = 0.18 * scale_factor
	rock.rotation_degrees.y = 23.0
	add_child(rock)
	var sprout_count := 2 if stage == "mature" else 1
	for index in range(sprout_count):
		var sprout := MeshInstance3D.new()
		sprout.name = "Sprout_%d" % index
		var stem := CylinderMesh.new()
		stem.top_radius = 0.03 * scale_factor
		stem.bottom_radius = 0.045 * scale_factor
		stem.height = 0.3 * scale_factor
		sprout.mesh = stem
		var stem_material := StandardMaterial3D.new()
		stem_material.albedo_color = Color("#77a75a")
		sprout.material_override = stem_material
		sprout.position = Vector3(-0.08 + index * 0.16, 0.32 * scale_factor, 0.05)
		add_child(sprout)
		var leaf := MeshInstance3D.new()
		leaf.name = "Leaf_%d" % index
		var leaf_mesh := SphereMesh.new()
		leaf_mesh.radial_segments = 6
		leaf_mesh.rings = 2
		leaf_mesh.radius = 0.09 * scale_factor
		leaf_mesh.height = 0.12 * scale_factor
		leaf.mesh = leaf_mesh
		var leaf_material := StandardMaterial3D.new()
		leaf_material.albedo_color = Color("#8fc06a")
		leaf.material_override = leaf_material
		leaf.position = sprout.position + Vector3(0, 0.16 * scale_factor, 0)
		add_child(leaf)


## 萤果：暗绿叶簇 + 发光浆果（成熟期三颗最亮）。
func _build_glow_berry(scale_factor: float) -> void:
	var bush := MeshInstance3D.new()
	bush.name = "BushBody"
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.radius = 0.3 * scale_factor
	mesh.height = 0.44 * scale_factor
	bush.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#3d5a3a")
	material.roughness = 1.0
	bush.material_override = material
	bush.position.y = 0.26 * scale_factor
	add_child(bush)
	var berry_count := 3 if stage == "mature" else (2 if stage == "growing" else 1)
	var glow_energy := 1.4 if stage == "mature" else 0.7
	for index in range(berry_count):
		var berry := MeshInstance3D.new()
		berry.name = "Berry_%d" % index
		var berry_mesh := SphereMesh.new()
		berry_mesh.radial_segments = 6
		berry_mesh.rings = 2
		berry_mesh.radius = 0.075 * scale_factor
		berry_mesh.height = 0.1 * scale_factor
		berry.mesh = berry_mesh
		var berry_material := StandardMaterial3D.new()
		berry_material.albedo_color = Color("#b8f2d8")
		berry_material.emission_enabled = true
		berry_material.emission = Color("#7dffc0")
		berry_material.emission_energy_multiplier = glow_energy
		berry.material_override = berry_material
		var angle := index * TAU / 3.0 + 0.6
		berry.position = Vector3(cos(angle) * 0.2, (0.3 + 0.1 * (index % 2)) * scale_factor, sin(angle) * 0.2) * scale_factor + Vector3(0, 0.1, 0)
		add_child(berry)
