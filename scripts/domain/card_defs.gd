class_name CardDefs
extends RefCounted
## 卡牌定义表（2.2 详细设计 §5 的 12 个效果模板）。效果在 2.2 的战斗引擎里解析，这里只存定义。

## target：enemy=一名存活敌人；self=自己；ally=存活友方（单人含自己）。
## after：discard=弃牌；exhaust=本场移除；exhaust_source=消耗来源物品并移除其关联牌。
const CARDS := {
	"slash": {
		"name": "切击", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 6}],
		"desc": "对一名敌人造成 6 点伤害。",
	},
	"heavy_strike": {
		"name": "重击", "cost": 2, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 13}],
		"desc": "对一名敌人造成 13 点伤害。",
	},
	"shield_up": {
		"name": "架盾", "cost": 1, "target": "self", "after": "discard",
		"effects": [{"kind": "block", "value": 6}],
		"desc": "自己获得 6 点格挡，直到自己下个回合开始。",
	},
	"cover": {
		"name": "掩护", "cost": 1, "target": "ally", "after": "discard",
		"effects": [{"kind": "block", "value": 6}],
		"desc": "给予自己或一名存活队友 6 点格挡。",
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
		"desc": "造成 4 点伤害，并添加 1 回合易伤（受到普通攻击伤害 ×1.5）。",
	},
	"venom_stab": {
		"name": "毒刺", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 3}, {"kind": "status", "status": "poison", "stacks": 3}],
		"desc": "造成 3 点伤害，并添加 3 层中毒（行动前受到层数点伤害并减 1 层，绕过格挡）。",
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
		"effects": [{"kind": "damage", "value": 7}],
		"desc": "对一名敌人造成 7 点伤害。",
	},
	"heavy_strike15": {
		"name": "沉重一击", "cost": 2, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 15}],
		"desc": "对一名敌人造成 15 点伤害。",
	},
	"slash8": {
		"name": "晶刃斩", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 8}],
		"desc": "对一名敌人造成 8 点伤害。",
	},
	"heavy_strike17": {
		"name": "裂石一击", "cost": 2, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 17}],
		"desc": "对一名敌人造成 17 点伤害。",
	},
	"rescue_signal": {
		"name": "救援信号", "cost": 1, "target": "rescue", "after": "exhaust_source",
		"effects": [{"kind": "rescue", "value": 8}],
		"desc": "救起倒地队友并恢复到 8 生命（每人每场一次；倒地规则见 2.6），消耗来源救援包一次。",
	},
	# —— 第一章苔冠森林（P1）：16 张新牌。新效果：灼烧/寒冷（status）、cleanse（净化）、pierce（部分穿透）。——
	"forest_shoot": {
		"name": "射击", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 6}],
		"desc": "对一名敌人造成 6 点伤害（弓箭射击）。",
	},
	"forest_thrust": {
		"name": "突刺", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 6}],
		"desc": "对一名敌人造成 6 点伤害（长矛突刺）。",
	},
	"forest_power_shot": {
		"name": "强射", "cost": 2, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 13}],
		"desc": "对一名敌人造成 13 点伤害（弩的爆发一击）。",
	},
	"forest_bell_strike": {
		"name": "敲击", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 4}],
		"desc": "对一名敌人造成 4 点伤害（祭铃敲击）。",
	},
	"forest_rest_bell": {
		"name": "安息铃", "cost": 1, "target": "ally", "after": "discard",
		"effects": [{"kind": "cleanse", "status": "poison", "stacks": 2, "clear": ["burn"]}],
		"desc": "移除自己或一名队友的 2 层中毒，并清除灼烧。",
	},
	"forest_guard_bell": {
		"name": "守护铃", "cost": 1, "target": "ally", "after": "discard",
		"effects": [{"kind": "block", "value": 5}],
		"desc": "给予自己或一名存活队友 5 点格挡（铃音护佑）。",
	},
	"forest_glow_bolt": {
		"name": "微光弹", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 5, "pierce": 3}],
		"desc": "造成 5 点伤害；结算此击时忽略至多 3 点格挡，被忽略的格挡不会被删除。",
	},
	"forest_apply_gel": {
		"name": "凝胶敷药", "cost": 0, "target": "ally", "after": "exhaust_source",
		"effects": [{"kind": "heal", "value": 6}],
		"desc": "恢复自己或一名存活队友 6 点生命，消耗来源绿凝胶一次。",
	},
	"forest_throw_fire_sac": {
		"name": "投掷火囊", "cost": 1, "target": "enemy", "after": "exhaust_source",
		"effects": [{"kind": "damage", "value": 4}, {"kind": "status", "status": "burn", "stacks": 2}],
		"desc": "造成 4 点伤害并附加灼烧 2（其下次行动开始受到 2 点无视格挡的伤害），消耗来源赤凝胶囊一次。",
	},
	"forest_throw_frost_sac": {
		"name": "投掷冰囊", "cost": 1, "target": "enemy", "after": "exhaust_source",
		"effects": [{"kind": "damage", "value": 3}, {"kind": "status", "status": "chill", "stacks": 1}],
		"desc": "造成 3 点伤害并附加寒冷（其下次行动的第一段攻击 -2，行动结束清除），消耗来源蓝凝胶囊一次。",
	},
	"forest_eat_honey": {
		"name": "食蜜", "cost": 0, "target": "self", "after": "exhaust_source",
		"effects": [{"kind": "heal", "value": 3}, {"kind": "draw", "value": 1}],
		"desc": "恢复自己 3 点生命并抽 1 张牌，消耗来源蜂蜜块一次。",
	},
	"forest_scatter_stings": {
		"name": "撒蜂针", "cost": 1, "target": "enemy", "after": "exhaust_source",
		"effects": [{"kind": "damage", "value": 3}, {"kind": "status", "status": "poison", "stacks": 2}],
		"desc": "造成 3 点伤害并附加 2 层中毒，消耗来源蜂针囊一次。",
	},
	"forest_torch_strike": {
		"name": "火把挥击", "cost": 1, "target": "enemy", "after": "discard",
		"effects": [{"kind": "damage", "value": 4}, {"kind": "status", "status": "burn", "stacks": 1}],
		"desc": "造成 4 点伤害并附加灼烧 1（其下次行动开始受到 1 点无视格挡的伤害）；不消耗火把。",
	},
	"forest_smoke_screen": {
		"name": "烟幕", "cost": 1, "target": "ally", "after": "discard",
		"effects": [{"kind": "block", "value": 4}],
		"desc": "给予自己或一名存活队友 4 点格挡（扬起烟幕遮蔽身形）。",
	},
	"forest_throw_net": {
		"name": "投网", "cost": 1, "target": "enemy", "after": "exhaust_source",
		"effects": [{"kind": "damage", "value": 2}, {"kind": "status", "status": "weak", "stacks": 1}],
		"desc": "造成 2 点伤害并附加 1 回合虚弱，消耗来源绳网一次（连同其笨重货物牌一并移除）。",
	},
	"forest_throw_spores": {
		"name": "抛孢", "cost": 1, "target": "enemy", "after": "exhaust_source",
		"effects": [{"kind": "status", "status": "poison", "stacks": 4}],
		"desc": "对一名敌人附加 4 层中毒，消耗来源腐菌囊一次。",
	},
}

const STATUS_DISPLAY := {
	"vulnerable": "易伤",
	"weak": "虚弱",
	"poison": "中毒",
	"burn": "灼烧",
	"chill": "寒冷",
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
