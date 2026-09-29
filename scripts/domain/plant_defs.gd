class_name PlantDefs
extends RefCounted

## 阶段 2 规则配置。所有数值均为试玩可调初值；修改后需同步更新阶段 2 测试期望与收获算例。

const PLANTS: Dictionary = {
	"cabbage": {
		"display_name": "白菜",
		"grow_seconds": 1200,
		"base_score": 200,
		"crop_count": 5,
		"seed_price": 10,
		"water_segments": 1,
		"encounter_count": 1,
		"harvest_exp": 20,
		"unlock_farming_level": 1,
		"unlock_shop_level": 1,
	},
	# 正式名称未定：carrot 仅是临时美术 ID，不据此确定正式名称。
	"carrot": {
		"display_name": "胡萝卜（暂名）",
		"grow_seconds": 7200,
		"base_score": 1200,
		"crop_count": 5,
		"seed_price": 20,
		"water_segments": 2,
		"encounter_count": 2,
		"harvest_exp": 120,
		"unlock_farming_level": 2,
		"unlock_shop_level": 2,
	},
}

const ENCOUNTER_TIERS := [10, 40, 70]
## 正式遭遇文案：与 +10/+40/+70 档位一一对应，强弱有可感知差异。
const ENCOUNTER_TEXTS := {
	10: "一阵细雨轻抚过叶片",
	40: "暖阳与微风恰好同时到来",
	70: "罕见的完美天气，整块地都在发光",
}
const FLUCTUATION_MAX_PCT := 10

## 升级门槛：1→2、2→3、3→4、4→5、5→6 各需新增经验。种地与植物等级首版用同一张表。
const LEVEL_EXP_STEPS := [120, 720, 2880, 6480, 12960]
## 每升 1 级基准分百分比（种地与植物分开计算，播种时快照）。
const LEVEL_BONUS_PER_LEVEL := 5

## 每完成一个有效浇水时段，每作物加基准分的百分比；键为水壶等级。
## 水壶 2 级购买在阶段 4 接入，这里只预留数据。
const WATER_BONUS_BY_CAN := {1: 10, 2: 20}

const FERTILIZERS: Dictionary = {
	"basic": {
		"display_name": "基础肥料",
		"price": 10,
		"uses_per_pack": 10,
		"duration_seconds": 7200,
		"score_bonus": 20,
	},
	"mutation": {
		"display_name": "变异肥料",
		"price": 100,
		"uses_per_pack": 10,
		"duration_seconds": 7200,
		"score_bonus": 20,
	},
	"preserve": {
		"display_name": "保种肥料",
		"price": 100,
		"uses_per_pack": 10,
		"duration_seconds": 7200,
		"score_bonus": 20,
	},
	"golden": {
		"display_name": "金克拉肥料",
		"price": 150,
		"uses_per_pack": 10,
		"duration_seconds": 7200,
		"score_bonus": 20,
		# 出售倍率加成：数据保留，阶段 4 的统一报价算法使用，本阶段默认出售仍是 1.2 倍。
		"sale_multiplier_bonus": 0.2,
	},
}

## 肥料功能整体解锁的种地等级；金克拉的解锁条件未定，用占位初值，不当作确认规则。
const FERTILIZER_UNLOCK_FARMING_LEVEL := 2
const GOLDEN_FERTILIZER_UNLOCK_LEVEL_PLACEHOLDER := 3

## 商店升级价已移至 MarketDefs（阶段 4 统一经济配置）。

const DEFAULT_SALE_MULTIPLIER := 1.2


static func is_known_plant(kind: String) -> bool:
	return PLANTS.has(kind)


static func plant_kinds() -> Array:
	return PLANTS.keys()


static func get_plant(kind: String) -> Dictionary:
	return PLANTS.get(kind, {})


static func segment_seconds(kind: String) -> int:
	var defn := get_plant(kind)
	if defn.is_empty() or defn["water_segments"] <= 0:
		return 0
	return int(defn["grow_seconds"] / defn["water_segments"])


static func level_from_exp(exp: int) -> int:
	var level := 1
	var remaining := exp
	for step in LEVEL_EXP_STEPS:
		if remaining >= step:
			remaining -= step
			level += 1
		else:
			break
	return level


static func level_progress(exp: int) -> Dictionary:
	var level := level_from_exp(exp)
	var consumed := 0
	for index in range(level - 1):
		consumed += LEVEL_EXP_STEPS[index]
	var next_need := -1
	if level - 1 < LEVEL_EXP_STEPS.size():
		next_need = LEVEL_EXP_STEPS[level - 1]
	return {
		"level": level,
		"exp": exp,
		"consumed": consumed,
		"next_need": next_need,
		"into_level": exp - consumed,
	}
