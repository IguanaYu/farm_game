class_name ExpeditionBaseline
extends RefCounted
## 第二大阶段共用规则基线（2.1 详细设计 §2）。数值是设计初值，试玩后统一在此调整。

const PROTO_RULES_VERSION := "d2-baseline-v0.2"

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


## 容器扩容（2.5 设计 §5）：等级→尺寸。基础等级沿用 CONTAINER_SIZE。
const CONTAINER_UPGRADE_SIZE := {
	"chest": {1: Vector2i(3, 4), 2: Vector2i(4, 4)},
	"pack": {1: Vector2i(4, 4), 2: Vector2i(4, 5)},
	"safe": {1: Vector2i(1, 2), 2: Vector2i(2, 2)},
}

## 战备仓储等级→装备区／资源区条目格（2.5 设计 §2）。
const WAREHOUSE_CAPACITY_BY_STORAGE := {1: 40, 2: 80, 3: 160}


## 按存档的升级等级取容器实际尺寸；expedition 块缺省时用基础值。
static func size_for(expedition_block: Dictionary, container: String) -> Vector2i:
	if not CONTAINER_SIZE.has(container):
		return Vector2i.ZERO
	var crafting: Dictionary = expedition_block.get("crafting", {})
	# 局内库存保留出发时的扩容等级；旧局缺此字段仍采用原来的基础尺寸。
	var levels: Dictionary = crafting.get("upgrade_levels", expedition_block.get("inventory", {}).get("container_levels", {}))
	var level := int(levels.get(container, 1))
	if level <= 1:
		return CONTAINER_SIZE[container]
	var table: Dictionary = CONTAINER_UPGRADE_SIZE.get(container, {})
	return table.get(level, CONTAINER_SIZE[container])


static func warehouse_capacity(expedition_block: Dictionary) -> int:
	var crafting: Dictionary = expedition_block.get("crafting", {})
	return int(WAREHOUSE_CAPACITY_BY_STORAGE.get(int(crafting.get("upgrade_levels", {}).get("storage", 1)), 40))


## 物品归属的仓库分区：装备区（武器/防具/工具）与资源区（补给/材料/货物）。
static func warehouse_zone(def_id: String) -> String:
	var def := ItemDefs.get_item(def_id)
	var category := str(def.get("category", "material"))
	return "equipment" if category in ["weapon", "armor", "tool"] else "resource"


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
	return can_place_in(bounds, size, cell, rotated, occupied, ignore_instance)


## 动态尺寸版：升级后的容器用实际 bounds 判定。
static func can_place_in(bounds: Vector2i, size: Vector2i, cell: Vector2i, rotated: bool, occupied: Dictionary, ignore_instance := -1) -> bool:
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


static func layout_integrity(loadout: Dictionary, expedition_block := {}) -> Array:
	## 返回布局问题清单（空数组=合法）：越界、重叠。
	var problems: Array = []
	for container in CONTAINERS:
		var bounds: Vector2i = size_for(expedition_block, container)
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


## 容器内最大连续空闲矩形（宽×高）。用于满包提示"还差 2×2 连续空间"，而非只报总格数。
static func largest_free_rect(container: String, instances: Array, expedition_block := {}) -> Vector2i:
	var bounds: Vector2i = size_for(expedition_block, container)
	var occupied := {}
	for instance in instances:
		if str(instance.get("container", "")) != container:
			continue
		for covered in cells_of(_size_of(instance), Vector2i(int(instance["cell"][0]), int(instance["cell"][1])), bool(instance.get("rotated", false))):
			occupied[cell_key(covered)] = true
	var best := Vector2i(0, 0)
	for y in range(bounds.y):
		for x in range(bounds.x):
			if occupied.has(cell_key(Vector2i(x, y))):
				continue
			var max_w := 0
			for dx in range(bounds.x - x):
				if occupied.has(cell_key(Vector2i(x + dx, y))):
					break
				max_w += 1
			var height_limit := bounds.y - y
			for width in range(1, max_w + 1):
				var h := 0
				while h < height_limit:
					var blocked := false
					for dx in range(width):
						if occupied.has(cell_key(Vector2i(x + dx, y + h))):
							blocked = true
							break
					if blocked:
						break
					h += 1
				if width * h > best.x * best.y:
					best = Vector2i(width, h)
	return best


static func _size_of(instance: Dictionary) -> Vector2i:
	var def: Dictionary = ItemDefs.get_item(str(instance.get("def_id", "")))
	return def.get("size", Vector2i(1, 1))
