class_name ItemDefs
extends RefCounted
## 物品定义表。2.1 只包含基础套装与演示物品；2.3 扩到 12~16 种。
## cards 序列长度必须等于占格数（占 N 格给 N 张牌实例，可重复）。

const ITEMS := {
	# —— 免费基础套装（2.1 设计 §7）：死亡后可补领缺失部件，不可出售／分享／制作。
	"old_shortsword": {
		"name": "旧短刀", "category": "weapon", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 0, "sellable": false, "basic_kit": true, "demo": false,
		"safe_allowed": false, "cards": ["slash", "slash"],
		"desc": "基础装备：占 2 格，提供 2 张切击。不能出售或分享。",
	},
	"wooden_shield": {
		"name": "木盾", "category": "armor", "size": Vector2i(2, 2), "quality": 1,
		"base_value": 0, "sellable": false, "basic_kit": true, "demo": false,
		"safe_allowed": false, "cards": ["shield_up", "shield_up", "cover", "brace"],
		"desc": "基础装备：占 4 格，提供 架盾×2／掩护／稳住。不能出售或分享。",
	},
	"pack_tools": {
		"name": "行囊工具", "category": "tool", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 0, "sellable": false, "basic_kit": true, "demo": false,
		"safe_allowed": false, "cards": ["deep_breath", "observe"],
		"desc": "基础装备：占 2 格，提供 调整呼吸／观察。不能出售或分享。",
	},
	# —— 演示物品（2.1 设计 §5）：只在战备预览中使用，不写入正式库存。
	"demo_iron_sword": {
		"name": "铁剑（演示）", "category": "weapon", "size": Vector2i(1, 3), "quality": 2,
		"base_value": 30, "sellable": true, "basic_kit": false, "demo": true,
		"safe_allowed": false, "cards": ["slash", "heavy_strike", "slash"],
		"desc": "演示用：看看正式武器会提供什么样的牌。",
	},
	"demo_ore": {
		"name": "铁矿石（演示）", "category": "material", "size": Vector2i(2, 2), "quality": 1,
		"base_value": 24, "sellable": true, "basic_kit": false, "demo": true,
		"safe_allowed": true, "cards": ["heavy_cargo", "heavy_cargo", "heavy_cargo", "heavy_cargo"],
		"desc": "演示用：值钱但拖累战斗——4 张笨重货物会塞满手牌。",
	},
	"demo_potion": {
		"name": "小药水（演示）", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 8, "sellable": true, "basic_kit": false, "demo": true,
		"safe_allowed": true, "cards": ["drink_potion"], "uses": 2,
		"desc": "演示用：消耗品，同一瓶的牌共享剩余次数。",
	},
	# —— 正式物品池（2.3 设计 §4）：12~16 种预算内新增 12 种。
	"copper_shortsword": {
		"name": "铜短剑", "category": "weapon", "size": Vector2i(1, 3), "quality": 1,
		"base_value": 40, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["slash", "slash", "heavy_strike"],
		"desc": "普通攻击装备：占 3 格，切击×2＋重击。",
	},
	"reinforced_shield": {
		"name": "加固盾", "category": "armor", "size": Vector2i(2, 2), "quality": 2,
		"base_value": 50, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["shield_up", "shield_up", "cover", "brace"],
		"desc": "品质版防御：牌构成与木盾相同（后续品质提升改数值，不改占格规则）。",
	},
	"leather_bracer": {
		"name": "皮护腕", "category": "armor", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 25, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["brace", "shield_up"],
		"desc": "小体积防御补充：占 2 格，稳住＋架盾。",
	},
	"scout_whistle": {
		"name": "侦察哨", "category": "tool", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 30, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["observe", "deep_breath"],
		"desc": "抽牌工具：观察＋调整呼吸。",
	},
	"small_potion": {
		"name": "小药水", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 6, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["drink_potion"], "uses": 1,
		"desc": "一次恢复补给：使用一次后实体消耗、关联牌清除。",
	},
	"bandage": {
		"name": "绷带", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 5, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["first_aid"], "uses": 1,
		"desc": "一次恢复补给：给自己或队友包扎。",
	},
	"copper_scrap": {
		"name": "铜片", "category": "material", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 8, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo"],
		"desc": "基础制作材料，可放保险箱；携带时是一张笨重货物。",
	},
	"fiber_clump": {
		"name": "纤维团", "category": "material", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 6, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["heavy_cargo"],
		"desc": "护具制作材料；不能放保险箱。",
	},
	"iron_ore": {
		"name": "铁矿", "category": "material", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 18, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo", "heavy_cargo"],
		"desc": "深层装备材料，可放保险箱；占 2 格＝2 张笨重货物。",
	},
	"rock_sprout_seed": {
		"name": "岩芽菜种子", "category": "rare_seed", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 2, "sellable": false, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo"],
		"desc": "新植物的种子（暂名）：保险箱可保护；回家按种子回收规则处理（2.5 接入）。",
	},
	"antique_ornament": {
		"name": "古旧摆件", "category": "cargo", "size": Vector2i(2, 2), "quality": 1,
		"base_value": 90, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["heavy_cargo", "heavy_cargo", "heavy_cargo", "heavy_cargo"],
		"desc": "高价值出售货物：值 90 金币，但 4 张笨重货物会拖累战斗；不可保护。",
	},
	"glow_crystal": {
		"name": "微光晶石", "category": "material", "size": Vector2i(1, 2), "quality": 2,
		"base_value": 60, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["brace", "observe"],
		"desc": "小型高价值资源：值钱也能打（稳住＋观察）；不可保护。",
	},
}


static func get_item(def_id: String) -> Dictionary:
	return ITEMS.get(def_id, {})


static func is_known_item(def_id: String) -> bool:
	return ITEMS.has(def_id)


static func is_basic(def_id: String) -> bool:
	return bool(ITEMS.get(def_id, {}).get("basic_kit", false))


static func basic_kit_ids() -> Array:
	var result: Array = []
	for def_id in ITEMS:
		if bool(ITEMS[def_id]["basic_kit"]):
			result.append(def_id)
	return result


## 校验定义表自身一致性：占格数=牌数、demo 与正式物品互斥、引用的牌都存在。
static func validate_definitions() -> Array:
	var problems: Array = []
	for def_id in ITEMS:
		var def: Dictionary = ITEMS[def_id]
		var cells: int = def["size"].x * def["size"].y
		if def["cards"].size() != cells:
			problems.append("%s 占 %d 格但提供 %d 张牌" % [def_id, cells, def["cards"].size()])
		for card_id in def["cards"]:
			if not CardDefs.CARDS.has(card_id):
				problems.append("%s 引用了未定义的牌 %s" % [def_id, card_id])
	return problems
