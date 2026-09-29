class_name BreedingDefs
extends RefCounted

## 阶段 3 育种/仓库/育种机规则配置。所有数值均为试玩可调初值，来源为玩法循环草案第 2 节。

const TRAIT_LIMIT := 4

## 六种词条效果。tier 为档位下标（逐档晋升，不可跳档）。
const EFFECTS: Dictionary = {
	"water_guarantee": {
		"display": "水分保底",
		"attribute": "water",
		"kind": "guarantee",
		"tiers": [1, 2, 3],
		"tier_labels": ["+1 点", "+2 点", "+3 点"],
		"quality_scores": [1, 2, 3],
	},
	"fiber_guarantee": {
		"display": "纤维保底",
		"attribute": "fiber",
		"kind": "guarantee",
		"tiers": [1, 2, 3],
		"tier_labels": ["+1 点", "+2 点", "+3 点"],
		"quality_scores": [1, 2, 3],
	},
	"color_guarantee": {
		"display": "色泽保底",
		"attribute": "color",
		"kind": "guarantee",
		"tiers": [1, 2, 3],
		"tier_labels": ["+1 点", "+2 点", "+3 点"],
		"quality_scores": [1, 2, 3],
	},
	"water_tendency": {
		"display": "水分倾向",
		"attribute": "water",
		"kind": "tendency",
		"tiers": [10, 30, 50, 100],
		"tier_labels": ["+10%", "+30%", "+50%", "+100%"],
		"quality_scores": [1, 2, 3, 4],
	},
	"fiber_tendency": {
		"display": "纤维倾向",
		"attribute": "fiber",
		"kind": "tendency",
		"tiers": [10, 30, 50, 100],
		"tier_labels": ["+10%", "+30%", "+50%", "+100%"],
		"quality_scores": [1, 2, 3, 4],
	},
	"color_tendency": {
		"display": "色泽倾向",
		"attribute": "color",
		"kind": "tendency",
		"tiers": [10, 30, 50, 100],
		"tier_labels": ["+10%", "+30%", "+50%", "+100%"],
		"quality_scores": [1, 2, 3, 4],
	},
}

## 亲本词条继承保留率（逐条独立判定）。
const KEEP_RATE := {"preserve": 0.80, "normal": 0.30}

## 保留后的升档率：按词条类型与当前档位下标。
const UPGRADE_RATES := {
	"guarantee": [
		{"preserve": 0.08, "normal": 0.04},
		{"preserve": 0.03, "normal": 0.01},
	],
	"tendency": [
		{"preserve": 0.08, "normal": 0.04},
		{"preserve": 0.08, "normal": 0.04},
		{"preserve": 0.03, "normal": 0.01},
	],
}

## 新词条率：按保留后的词条数（0/1/2/3 条）。变异肥料在对应概率上加 10 个百分点。
const NEW_TRAIT_RATES := [0.70, 0.30, 0.10, 0.01]
const NEW_TRAIT_RATE_BONUS_MUTATION := 0.10

## 属性分配：基础总点数 = 播种时种地等级 + 植物等级（快照）；先满足保底，再按权重随机。
const ATTRIBUTE_BASE_WEIGHT := 100.0

## 仓库：作物区与种子区容量随等级；种子同属性同词条可叠放。
const WAREHOUSE_CAPACITY_BY_LEVEL := [60, 120, 240, 480]
const WAREHOUSE_UPGRADE_COSTS := {2: 1200, 3: 15000, 4: 17000}
const SEED_STACK_MAX := 99

## 种子回收价（阶段 4 并入统一交易）。
const SEED_RECYCLE_PRICE := 5

## 育种机：种地 2 级解锁；60/55/50 分钟一粒；容量 8/12/16。
const BREEDER_UNLOCK_FARMING_LEVEL := 2
const BREEDER_BUY_COST := 15000
const BREEDER_LEVELS := {
	1: {"cycle_seconds": 60 * 60, "capacity": 8, "upgrade_cost": 17000},
	2: {"cycle_seconds": 55 * 60, "capacity": 12, "upgrade_cost": -1},
	3: {"cycle_seconds": 50 * 60, "capacity": 16, "upgrade_cost": -1},
}
# 2→3 级价格待定：upgrade_cost = -1 表示占位（界面显示"价格待定"），不是确认规则。


static func effect_kinds() -> Array:
	return EFFECTS.keys()


static func get_effect(effect: String) -> Dictionary:
	return EFFECTS.get(effect, {})


static func cycle_seconds(level: int) -> int:
	return BREEDER_LEVELS.get(level, BREEDER_LEVELS[1])["cycle_seconds"]


static func capacity(level: int) -> int:
	return BREEDER_LEVELS.get(level, BREEDER_LEVELS[1])["capacity"]


static func trait_text(entry: Dictionary) -> String:
	var defn := get_effect(str(entry.get("effect", "")))
	if defn.is_empty():
		return "未知词条"
	return "%s %s" % [defn["display"], defn["tier_labels"][int(entry.get("tier", 0))]]


static func traits_text(traits: Array) -> String:
	if traits.is_empty():
		return "无词条"
	var parts: Array = []
	for entry in traits:
		parts.append(trait_text(entry))
	return "、".join(parts)


static func quality_score(traits: Array) -> int:
	var best := 0
	for entry in traits:
		var defn := get_effect(str(entry.get("effect", "")))
		if defn.is_empty():
			continue
		var score: int = defn["quality_scores"][int(entry.get("tier", 0))]
		best = maxi(best, score)
	return best


static func seed_signature(seed: Dictionary) -> String:
	var parts: Array = []
	for entry in seed.get("traits", []):
		parts.append("%s:%d" % [entry.get("effect", ""), int(entry.get("tier", 0))])
	parts.sort()
	return "%s|%s" % [seed.get("kind", ""), ",".join(parts)]
