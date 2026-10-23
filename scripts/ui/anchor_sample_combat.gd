class_name AnchorSampleCombat
extends RefCounted
## 可重开的费用锚点样例。普通 CombatGame 快照即可恢复，不需要子类规则。

const TIERS := ["initial", "standard", "quality"]
const TIER_NAMES := {"initial": "初始 · 5攻 / 5挡", "standard": "标准 · 8攻 / 8挡", "quality": "高质量 · 13攻 / 12挡"}
const ATTACKS := {"initial": "slash", "standard": "slash7", "quality": "slash8"}
const GUARDS := {"initial": "shield_up", "standard": "guard_standard", "quality": "guard_quality"}
const SOURCE_IDS := {
	"slash": "old_shortsword", "slash7": "iron_shortsword", "slash8": "crystal_blade",
	"shield_up": "wooden_shield", "guard_standard": "reinforced_shield", "guard_quality": "crystal_aegis",
	"guarded_strike": "old_shortsword", "expose": "iron_shortsword", "venom_stab": "pack_tools",
	"battle_focus": "pack_tools", "nimble_stance": "pack_tools", "suppress": "pack_tools",
}
const SAMPLE_SOURCES := {
	"guarded_strike": "样例 · 攻守训练", "expose": "样例 · 破绽训练", "venom_stab": "样例 · 毒刺训练",
	"battle_focus": "样例 · 力量训练", "nimble_stance": "样例 · 敏捷训练", "suppress": "样例 · 压制训练",
}

static func create_sample(pressure: int, tier: String = "standard") -> CombatGame:
	if pressure not in [7, 10, 15]:
		pressure = 7
	if tier not in TIERS:
		tier = "standard"
	var attack: String = ATTACKS[tier]
	var guard: String = GUARDS[tier]
	# 前五张固定为三防两攻，能直接比较挡住 7／10／15 点的能量投入。
	# 第二手包含混合与四种状态来源，第三手提供虚弱；所有档位只替换纯攻击与格挡。
	var card_ids := [guard, guard, guard, attack, attack,
		"guarded_strike", "expose", "venom_stab", "battle_focus", "nimble_stance",
		guard, guard, attack, attack, "suppress"]
	var deck: Array = []
	for index in range(card_ids.size()):
		var card_id: String = card_ids[index]
		deck.append({"card_id": card_id, "join_round": 1, "source_instance_id": 0,
			"source_def_id": SOURCE_IDS[card_id], "source_quality": 1 + TIERS.find(tier), "source_seq": index})
	var session := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": deck}],
		"anchor_pressure_%d" % pressure, 20261022, null, deck)
	if session.state.is_empty():
		return session
	session.state["anchor_sample"] = {"pressure": pressure, "tier": tier}
	for card in session.state["players"]["p1"]["pending_join"]["1"]:
		var card_id := str(card["card_id"])
		if SAMPLE_SOURCES.has(card_id):
			card["preview_source_name"] = SAMPLE_SOURCES[card_id]
	session.start()
	session.state["log"].append("费用锚点样例：%s；敌人每次攻击 %d；固定 15 张牌，40 生命／3 能量／每回合抽 5。" % [TIER_NAMES[tier], pressure])
	return session
