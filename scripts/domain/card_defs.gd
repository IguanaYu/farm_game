class_name CardDefs
extends RefCounted
## 卡牌定义表。统一参照：1 费 8 攻击／8 格挡；初始档 5，高质量档 13 攻击／12 格挡。

## target：enemy=一名存活敌人；self=自己；ally=存活友方（单人含自己）。
## 单项 effects 可用 target 覆盖整牌目标；未指定时沿用所选目标。旧卡 ID 的数字不是现行数值。
## after：discard=弃牌；exhaust=本场移除；exhaust_source=消耗来源物品并移除其关联牌。
const CARDS := {
	"slash": {
		"name": "切击", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 5}],
		"desc": "对一名敌人造成 5 点攻击伤害（初始档）。",
	},
	"heavy_strike": {
		"name": "重击", "cost": 2, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 13}],
		"desc": "对一名敌人造成 13 点伤害。",
	},
	"shield_up": {
		"name": "架盾", "cost": 1, "target": "self", "after": "discard",
		"effects": [{"kind": "block", "value": 5}],
		"desc": "自己获得 5 点格挡（初始档），直到自己下次行动开始。",
	},
	"cover": {
		"name": "掩护", "cost": 1, "target": "ally", "after": "discard",
		"effects": [{"kind": "block", "value": 5}],
		"desc": "给予自己或一名存活队友 5 点格挡（初始档）。",
	},
	"brace": {
		"name": "稳住", "cost": 0, "target": "self", "after": "discard",
		"effects": [{"kind": "block", "value": 3}],
		"desc": "自己获得 3 点格挡。",
	},
	"deep_breath": {
		"name": "调整呼吸", "cost": 0, "target": "self", "after": "exhaust",
		"effects": [{"kind": "draw", "value": 1}],
		"desc": "抽 1 张牌，本场移除这张牌。",
	},
	"observe": {
		"name": "观察", "cost": 1, "target": "self", "after": "discard",
		"effects": [{"kind": "draw", "value": 2}],
		"desc": "抽 2 张牌。",
	},
	"expose": {
		"name": "破绽", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 4}, {"kind": "status", "status": "vulnerable", "stacks": 1}],
		"desc": "先造成 4 点攻击伤害，再添加 1 层易伤（受到攻击伤害 ×1.5，持有者行动结束减 1 层）。",
	},
	"venom_stab": {
		"name": "毒刺", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 3}, {"kind": "status", "status": "poison", "stacks": 3}],
		"desc": "先造成 3 点攻击伤害，再添加 3 层中毒（行动开始先受层数点伤害再减 1 层，绕过格挡）。",
	},
	"drink_potion": {
		"name": "饮药", "cost": 0, "target": "self", "after": "exhaust_source",
		"effects": [{"kind": "heal", "value": 8}],
		"desc": "恢复 8 点生命（不超过上限），消耗来源药水一次。",
	},
	"heavy_cargo": {
		"name": "笨重货物", "cost": 1, "target": "self", "after": "exhaust",
		"effects": [],
		"desc": "没有直接收益；花 1 点能量整理掉这张牌，本场移除。下一场会重新生成。",
	},
	"first_aid": {
		"name": "应急包扎", "cost": 1, "target": "ally", "after": "exhaust_source",
		"effects": [{"kind": "heal", "value": 4}],
		"desc": "恢复自己或一名存活队友 4 点生命，消耗来源绷带一次。",
	},
	"drink_soup": {
		"name": "喝汤", "cost": 0, "target": "self", "after": "exhaust_source",
		"effects": [{"kind": "heal", "value": 6}],
		"desc": "恢复 6 点生命，消耗来源白菜汤一次。",
	},
	"drink_elixir": {
		"name": "饮下药剂", "cost": 0, "target": "self", "after": "exhaust_source",
		"effects": [{"kind": "heal", "value": 10}],
		"desc": "恢复 10 点生命，消耗来源岩芽药剂一次。",
	},
	"slash7": {
		"name": "利刃斩", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 8}],
		"desc": "对一名敌人造成 8 点攻击伤害（标准档）。",
	},
	"heavy_strike15": {
		"name": "沉重一击", "cost": 2, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 16}],
		"desc": "对一名敌人造成 16 点攻击伤害（2 费标准档）。",
	},
	"slash8": {
		"name": "晶刃斩", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 13}],
		"desc": "对一名敌人造成 13 点攻击伤害（高质量档）。",
	},
	"heavy_strike17": {
		"name": "裂石一击", "cost": 2, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 24}],
		"desc": "对一名敌人造成 24 点攻击伤害（2 费高质量初值）。",
	},
	"guard_standard": {
		"name": "稳固架盾", "cost": 1, "target": "self", "after": "discard",
		"effects": [{"kind": "block", "value": 8}],
		"desc": "自己获得 8 点格挡（标准档）。",
	},
	"guard_quality": {
		"name": "晶盾守护", "cost": 1, "target": "self", "after": "discard",
		"effects": [{"kind": "block", "value": 12}],
		"desc": "自己获得 12 点格挡（高质量档）。",
	},
	"cover_standard": {
		"name": "稳固掩护", "cost": 1, "target": "ally", "after": "discard",
		"effects": [{"kind": "block", "value": 8}],
		"desc": "给予自己或一名存活队友 8 点格挡，使用出牌者的敏捷加成。",
	},
	"cover_quality": {
		"name": "晶盾掩护", "cost": 1, "target": "ally", "after": "discard",
		"effects": [{"kind": "block", "value": 12}],
		"desc": "给予自己或一名存活队友 12 点格挡，使用出牌者的敏捷加成。",
	},
	"guarded_strike": {
		"name": "攻守兼备", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 3, "target": "selected"}, {"kind": "block", "value": 3, "target": "self"}],
		"desc": "对选定敌人造成 3 点攻击伤害，自己获得 3 点格挡（初始混合档）。",
	},
	"battle_focus": {
		"name": "凝聚力量", "cost": 1, "target": "self", "after": "exhaust",
		"effects": [{"kind": "status", "status": "strength", "stacks": 2, "target": "self"}],
		"desc": "自己获得 2 层力量（每段攻击伤害 +2，本场持续），本场移除此牌。样例初值。",
	},
	"nimble_stance": {
		"name": "灵巧架势", "cost": 1, "target": "self", "after": "exhaust",
		"effects": [{"kind": "status", "status": "dexterity", "stacks": 2, "target": "self"}],
		"desc": "自己获得 2 层敏捷（每次普通格挡 +2，本场持续），本场移除此牌。样例初值。",
	},
	"suppress": {
		"name": "压制", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "status", "status": "weak", "stacks": 2}],
		"desc": "对选定敌人施加 2 层虚弱（攻击伤害 ×0.75，持有者行动结束减 1 层）。样例来源。",
	},
	"rescue_signal": {
		"name": "救援信号", "cost": 1, "target": "rescue", "after": "exhaust_source",
		"effects": [{"kind": "rescue", "value": 8}],
		"desc": "救起倒地队友并恢复到 8 生命（每人每场一次；倒地规则见 2.6），消耗来源救援包一次。",
	},
}

const STATUS_DISPLAY := {
	"vulnerable": "易伤",
	"weak": "虚弱",
	"poison": "中毒",
	"strength": "力量",
	"dexterity": "敏捷",
}


static func get_card(card_id: String) -> Dictionary:
	return CARDS.get(card_id, {})


static func is_attack_card(card_id: String) -> bool:
	for effect in get_card(card_id).get("effects", []):
		if str(effect.get("kind", "")) == "damage":
			return true
	return false


static func is_defense_card(card_id: String) -> bool:
	for effect in get_card(card_id).get("effects", []):
		if str(effect.get("kind", "")) == "block":
			return true
	return false
