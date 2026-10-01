class_name ExpeditionBaseline
extends RefCounted
## 第二大阶段共用规则基线（2.1 详细设计 §2）。数值是设计初值，试玩后统一在此调整。

const PROTO_RULES_VERSION := "d2-baseline-v0.1"

const MAX_HP := 40
const ENERGY_PER_TURN := 3
const DRAW_PER_TURN := 5
const HAND_LIMIT := 10

const CONTAINERS := ["chest", "pack", "safe"]
const CONTAINER_DISPLAY := {"chest": "胸挂", "pack": "背包", "safe": "保险箱"}
const CONTAINER_SIZE := {
	"chest": Vector2i(3, 4),
	"pack": Vector2i(4, 4),
	"safe": Vector2i(1, 2),
}
## 容器内物品牌从第几回合加入抽牌堆（设计 §2"可用时机"）。
const JOIN_ROUND := {"chest": 1, "pack": 2, "safe": 3}

const FIRST_INSTANCE_ID := 1000

const CATEGORY_DISPLAY := {
	"weapon": "武器",
	"armor": "防具",
	"tool": "工具／饰品",
	"supply": "补给",
	"material": "矿石／材料",
	"rare_seed": "稀有种子",
	"cargo": "贵重货物",
}


static func is_container(container: String) -> bool:
	return container == "warehouse" or JOIN_ROUND.has(container)


static func container_cells(container: String) -> int:
	if not CONTAINER_SIZE.has(container):
		return 0
	var size: Vector2i = CONTAINER_SIZE[container]
	return size.x * size.y


## 物品在 cell（左上角）处、占 size 格；rotated 时宽高互换。
static func cells_of(size: Vector2i, cell: Vector2i, rotated: bool) -> Array:
	var span := Vector2i(size.y, size.x) if rotated else size
	var result: Array = []
	for dx in range(span.x):
		for dy in range(span.y):
			result.append(Vector2i(cell.x + dx, cell.y + dy))
	return result


static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


## occupied：{cell_key: instance_id}。合法 = 全部格子落在容器内且不与已占格重叠。
static func can_place(container: String, size: Vector2i, cell: Vector2i, rotated: bool, occupied: Dictionary, ignore_instance := -1) -> bool:
	if not CONTAINER_SIZE.has(container):
		return false
	var bounds: Vector2i = CONTAINER_SIZE[container]
	for covered in cells_of(size, cell, rotated):
		if covered.x < 0 or covered.y < 0 or covered.x >= bounds.x or covered.y >= bounds.y:
			return false
		var holder = occupied.get(cell_key(covered))
		if holder != null and int(holder) != ignore_instance:
			return false
	return true


## 把容器内全部实例的占格汇总成 {cell_key: instance_id}；非法布局（越界/重叠）返回 ok=false。
static func occupancy_map(instances: Array, container: String) -> Dictionary:
	var result := {}
	for entry in instances:
		var instance: Dictionary = entry
		if str(instance.get("container", "")) != container:
			continue
		var cell: Vector2i = Vector2i(int(instance["cell"][0]), int(instance["cell"][1]))
		for covered in cells_of(_size_of(instance), cell, bool(instance.get("rotated", false))):
			result[cell_key(covered)] = int(instance["instance_id"])
	return result


static func layout_integrity(loadout: Dictionary) -> Array:
	## 返回布局问题清单（空数组=合法）：越界、重叠。
	var problems: Array = []
	for container in CONTAINERS:
		var bounds: Vector2i = CONTAINER_SIZE[container]
		var seen := {}
		for entry in loadout.get(container, []):
			var instance: Dictionary = entry
			var cell: Vector2i = Vector2i(int(instance["cell"][0]), int(instance["cell"][1]))
			for covered in cells_of(_size_of(instance), cell, bool(instance.get("rotated", false))):
				if covered.x < 0 or covered.y < 0 or covered.x >= bounds.x or covered.y >= bounds.y:
					problems.append("%s 内物品 %d 越界" % [CONTAINER_DISPLAY[container], int(instance["instance_id"])])
					continue
				var key := cell_key(covered)
				if seen.has(key):
					problems.append("%s 内格子 %s 重叠" % [CONTAINER_DISPLAY[container], key])
				seen[key] = true
	return problems


static func _size_of(instance: Dictionary) -> Vector2i:
	var def: Dictionary = ItemDefs.get_item(str(instance.get("def_id", "")))
	return def.get("size", Vector2i(1, 1))
