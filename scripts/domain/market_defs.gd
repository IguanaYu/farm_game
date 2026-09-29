class_name MarketDefs
extends RefCounted

## 阶段 4 经济规则配置：每日客人、收购公式、折扣、扩地与升级价格。均为试玩可调初值。

const GUESTS := {
	1: {"display_name": "阿禾（占位形象）", "preferred_kind": "cabbage"},
	2: {"display_name": "小满（占位形象）", "preferred_kind": "cabbage"},
	3: {"display_name": "阿泽（占位形象）", "preferred_kind": "cabbage"},
	4: {"display_name": "阿棉（占位形象）", "preferred_kind": "carrot"},
	5: {"display_name": "小翠（占位形象）", "preferred_kind": "carrot"},
	6: {"display_name": "阿棠（占位形象）", "preferred_kind": "carrot"},
}

const DAILY_GUEST_COUNT := 3
const PREFERENCE_MULTIPLIER := 1.2

## 公式系数池：单属性 / 主辅属性。
const SINGLE_COEFFICIENTS := [0.08, 0.10, 0.16]
const DUAL_MAIN_COEFFICIENTS := [0.06, 0.08, 0.10]
const DUAL_SUB_COEFFICIENTS := [0.02, 0.04, 0.06]

## 北京时间为 UTC+8 固定偏移，无夏令时。
const BEIJING_OFFSET_SECONDS := 8 * 3600

## 扩地价格（逐块购买，仅金币）。
const PLOT_PRICES := {7: 1400, 8: 1600, 9: 15000, 10: 17000}

## 商店与水壶升级价（商店 1→2→3→4；水壶 2 级）。
const SHOP_UPGRADE_COSTS := {2: 1500, 3: 15000, 4: 17000}
const CAN2_COST := 15000

## 商店每升一级，商品购买价优惠 5%；整笔标价合计后打折，最后四舍五入到整数金币。
## 本阶段把折扣应用于种子与肥料（消耗品）；一次性设施升级按标价执行（记录在交付报告）。
const SHOP_DISCOUNT_PER_LEVEL := 0.05

const MAX_SHOP_LEVEL := 4


static func day_index(unix: int) -> int:
	return int(floor(float(unix + BEIJING_OFFSET_SECONDS) / 86400.0))


static func shop_discount(shop_level: int) -> float:
	return clampf((shop_level - 1) * SHOP_DISCOUNT_PER_LEVEL, 0.0, 0.15)


static func discounted_total(raw_total: int, shop_level: int) -> int:
	return int(round(float(raw_total) * (1.0 - shop_discount(shop_level))))


static func formula_multiplier(formula: Dictionary, attributes: Dictionary) -> float:
	if formula.is_empty():
		return 1.0
	var main_value: float = float(attributes.get(formula["attribute"], 0))
	var multiplier := 1.0 + main_value * float(formula["coefficient"])
	if formula.get("type", "") == "dual":
		var sub_value: float = float(attributes.get(formula.get("sub_attribute", ""), 0))
		multiplier += sub_value * float(formula.get("sub_coefficient", 0.0))
	return multiplier
