class_name CraftingDefs
extends RefCounted
## 制作与设施升级定义（2.5 设计 §4/§5/§7）。全部为试玩初值。
## 材料口径：item:<def_id>（仓库实例）、crop:<kind>（作物批次，按个数扣）。


const RECIPES := {
	"cabbage_soup": {
		"name": "白菜汤", "output": "cabbage_soup", "coins": 2,
		"materials": [{"kind": "crop", "id": "cabbage", "count": 2}],
		"unlock": {"type": "always"},
		"desc": "占 1 格，恢复 6，一次使用。",
	},
	"bandage": {
		"name": "绷带", "output": "bandage", "coins": 2,
		"materials": [{"kind": "item", "id": "fiber_clump", "count": 1}],
		"unlock": {"type": "goal", "goal": "first_home"},
		"desc": "应急包扎恢复 4。",
	},
	"copper_shortsword": {
		"name": "铜短剑", "output": "copper_shortsword", "coins": 8,
		"materials": [{"kind": "item", "id": "copper_scrap", "count": 3}, {"kind": "item", "id": "fiber_clump", "count": 2}],
		"unlock": {"type": "goal", "goal": "found_copper"},
		"desc": "切击×2＋重击。",
	},
	"reinforced_shield": {
		"name": "加固盾", "output": "reinforced_shield", "coins": 10,
		"materials": [{"kind": "item", "id": "copper_scrap", "count": 4}, {"kind": "item", "id": "fiber_clump", "count": 3}],
		"unlock": {"type": "any", "of": [{"type": "stat", "stat": "craft_copper_shortsword", "value": 1}, {"type": "stat", "stat": "brought_total", "id": "copper_scrap", "value": 6}]},
		"desc": "架盾效果提高到 7、其他牌同类（本版先交付同构成品质版）。",
	},
	"leather_bracer": {
		"name": "皮护腕", "output": "leather_bracer", "coins": 8,
		"materials": [{"kind": "item", "id": "fiber_clump", "count": 3}],
		"unlock": {"type": "goal", "goal": "first_home"},
		"desc": "稳住＋架盾。",
	},
	"rock_elixir": {
		"name": "岩芽药剂", "output": "rock_elixir", "coins": 5,
		"materials": [{"kind": "crop", "id": "rock_sprout", "count": 2}],
		"unlock": {"type": "goal", "goal": "first_rock_harvest"},
		"desc": "恢复 10，售价初值 8。",
	},
	"iron_shortsword": {
		"name": "铁短剑", "output": "iron_shortsword", "coins": 20,
		"materials": [{"kind": "item", "id": "iron_ore", "count": 3}, {"kind": "item", "id": "copper_scrap", "count": 2}],
		"unlock": {"type": "goal", "goal": "deep_material"},
		"desc": "切击(7)×2＋重击(15)。",
	},
	"rescue_kit": {
		"name": "救援包", "output": "rescue_kit", "coins": 8,
		"materials": [{"kind": "crop", "id": "rock_sprout", "count": 1}, {"kind": "item", "id": "fiber_clump", "count": 2}],
		"unlock": {"type": "goal", "goal": "together_home"},
		"desc": "恢复＋救援，共享一次使用（救援 2.6 接入）。",
	},
	"crystal_blade": {
		"name": "辉晶刃", "output": "crystal_blade", "coins": 45,
		"materials": [{"kind": "item", "id": "radiant_cluster", "count": 3}, {"kind": "item", "id": "iron_ore", "count": 2}],
		"unlock": {"type": "stat", "stat": "brought_total", "id": "radiant_cluster", "value": 1},
		"desc": "第三层装备：晶刃斩(8)×2＋裂石一击(17)。",
	},
	"crystal_aegis": {
		"name": "辉晶盾", "output": "crystal_aegis", "coins": 30,
		"materials": [{"kind": "item", "id": "radiant_cluster", "count": 2}, {"kind": "item", "id": "fiber_clump", "count": 2}],
		"unlock": {"type": "stat", "stat": "brought_total", "id": "radiant_cluster", "value": 1},
		"desc": "第三层品质防具（带回辉晶簇解锁）。",
	},
}


## 设施升级（2.5 设计 §5）。storage＝战备仓储（装备/资源区条目格）。
const UPGRADES := {
	"storage_2": {"target": "storage", "to": 2, "coins": 300, "materials": [{"kind": "item", "id": "copper_scrap", "count": 8}], "desc": "装备／资源区各 40→80 条目格"},
	"storage_3": {"target": "storage", "to": 3, "coins": 1500, "materials": [{"kind": "item", "id": "iron_ore", "count": 8}], "desc": "各区 80→160"},
	"pack_expand": {"target": "pack", "to": 2, "coins": 500, "materials": [{"kind": "item", "id": "fiber_clump", "count": 8}, {"kind": "item", "id": "copper_scrap", "count": 4}], "desc": "背包 4×4→4×5"},
	"chest_expand": {"target": "chest", "to": 2, "coins": 800, "materials": [{"kind": "item", "id": "iron_ore", "count": 6}, {"kind": "item", "id": "fiber_clump", "count": 6}], "desc": "胸挂 3×4→4×4"},
	"safe_expand": {"target": "safe", "to": 2, "coins": 1200, "materials": [{"kind": "item", "id": "iron_ore", "count": 8}, {"kind": "item", "id": "glow_crystal", "count": 2}], "desc": "保险箱 1×2→2×2（白名单不变，最多一次）"},
}


## 成长目标（2.5 设计 §7）。判定＝一次性事实；奖励只发一次。
const GOALS := {
	"first_home": {"name": "第一次安全回家", "reward_items": ["small_potion"], "reward_unlock_recipes": ["bandage", "cabbage_soup"], "reward_text": "一瓶药水，解锁绷带与汤"},
	"found_copper": {"name": "发现铜片", "reward_unlock_recipes": ["copper_shortsword"], "reward_text": "解锁铜短剑配方"},
	"ready_gear": {"name": "做好战备", "reward_text": "展示背包升级目标（无实物奖励）"},
	"cave_life": {"name": "洞里的新生命", "reward_unlock_plants": ["rock_sprout"], "reward_text": "解锁岩芽菜与种植指引"},
	"first_rock_harvest": {"name": "第一茬岩芽", "reward_unlock_recipes": ["rock_elixir"], "reward_shop_seed": "rock_sprout", "reward_text": "解锁药剂配方与商店基础种子"},
	"together_home": {"name": "一起回家", "reward_unlock_recipes": ["rescue_kit"], "reward_text": "解锁救援包配方（2.6 实物可用）"},
	"deep_material": {"name": "深层材料", "reward_unlock_recipes": ["iron_shortsword"], "reward_unlock_upgrades": ["chest_expand"], "reward_text": "解锁铁剑与胸挂扩展"},
	"beat_guardian": {"name": "击穿晶脉矿窟", "reward_items": ["star_bloom_seed"], "reward_text": "打穿第三层：星瓣花种子一颗"},
}


static func recipe(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {})


static func upgrade(upgrade_id: String) -> Dictionary:
	return UPGRADES.get(upgrade_id, {})


static func goal(goal_id: String) -> Dictionary:
	return GOALS.get(goal_id, {})
