class_name CardPresentation
extends RefCounted
## Short visible copy; full rule definitions remain available on demand.

static func effect_text(def: Dictionary) -> String:
	var parts: Array[String] = []
	for effect in def.get("effects", []):
		match str(effect["kind"]):
			"damage": parts.append("%d 伤害" % int(effect["value"]))
			"block": parts.append("%d 格挡" % int(effect["value"]))
			"heal": parts.append("恢复 %d" % int(effect["value"]))
			"draw": parts.append("抽牌 %d" % int(effect["value"]))
			"status": parts.append("%s %d" % [CardDefs.STATUS_DISPLAY.get(str(effect["status"]), ""), int(effect.get("stacks", 1))])
			"rescue": parts.append("救起 · %d 生命" % int(effect["value"]))
	return " · ".join(parts) if not parts.is_empty() else "整理货物"

static func special_rule(def: Dictionary) -> String:
	var parts: Array[String] = []
	if str(def.get("target", "")) == "ally":
		parts.append("自己 / 队友")
	elif str(def.get("target", "")) == "rescue":
		parts.append("倒地队友")
	match str(def.get("after", "")):
		"exhaust": parts.append("本场移除")
		"exhaust_source": parts.append("消耗")
	return " · ".join(parts)

static func full_text(def: Dictionary) -> String:
	var target: String = {"enemy": "敌人", "self": "自己", "ally": "自己或队友", "rescue": "倒地队友"}.get(str(def.get("target", "")), "")
	var after: String = {"discard": "使用后进入弃牌堆", "exhaust": "使用后本场移除", "exhaust_source": "使用后消耗来源物品"}.get(str(def.get("after", "")), "")
	return "%s · %d 能量 · %s\n%s\n%s" % [def.get("name", "卡牌"), int(def.get("cost", 0)), target, def.get("desc", ""), after]
