class_name ChapterArtRegistry
extends RefCounted
## 表现资源查找与统一占位回退（森林第一章 P0，开发计划 §3/§4.1）。
## 玩法存档只记录定义/实例 ID，不保存图片路径；本表把资源 ID 解析为当前可用的表现参数。
## P8 换正式图片时只扩本表（ready=true 并带纹理路径），不改玩法 ID 与命中区；
## 任何未登记的资源 ID 都回落到统一占位，不允许整块界面空白。


## 统一占位回退：未知资源也给出可画的形状与中性配色。
const FALLBACK := {
	"shape": "gem", "base": Color("#6b7280"), "accent": Color("#aeb6c2"),
}


## 区域背景：占位为"基色底＋强调色远景轮廓"，由预览面板/探索场景绘制。
static func background(area_id: String) -> Dictionary:
	var area := ChapterOneDefs.area(area_id)
	if area.is_empty():
		return _placeholder("bg?", FALLBACK)
	return {
		"art_id": str(area["art_id"]),
		"ready": false,
		"name": str(area["name"]),
		"shape": "background",
		"base": area["base"],
		"accent": area["accent"],
	}


## 搜索对象占位：按模板名的关键词选简化轮廓（计划 §3：轮廓可区分＋名称标签）。
static func prop(template_id: String) -> Dictionary:
	var record := ChapterOneDefs.template(template_id)
	if record.is_empty():
		return _placeholder(template_id, FALLBACK)
	var area := ChapterOneDefs.area(str(record["area"]))
	var palette := {"base": area.get("base", FALLBACK["base"]), "accent": area.get("accent", FALLBACK["accent"])}
	return _placeholder(template_id, palette, str(record["name"]))


## 敌人占位：简化身体＋名称；元素史莱姆等辨识信息由战斗符号层补（不单靠颜色）。
static func enemy(enemy_id: String) -> Dictionary:
	var record: Dictionary = ChapterOneDefs.ENEMIES.get(enemy_id, {})
	if record.is_empty():
		return _placeholder(enemy_id, FALLBACK)
	var palette := {"base": Color("#4d5a52"), "accent": Color("#9db8a4")}
	if record.has("area"):
		var area := ChapterOneDefs.area(str(record["area"]))
		palette = {"base": area.get("base", FALLBACK["base"]).darkened(0.15), "accent": area.get("accent", FALLBACK["accent"])}
	return _placeholder(enemy_id, palette, str(record["name"]))


## 资源 ID → 当前表现。已登记 ID 一律 ready=false（首批图片未做）；
## 未登记 ID 也返回占位参数并附 hint，供测试断言"缺图有回退"。
static func resolve(art_id: String) -> Dictionary:
	if art_id.begins_with("bg.forest_ch1."):
		return background(art_id.trim_prefix("bg.forest_ch1."))
	if art_id.begins_with("prop."):
		return prop(art_id.trim_prefix("prop."))
	if art_id.begins_with("enemy."):
		return enemy(art_id.trim_prefix("enemy."))
	return _placeholder(art_id, FALLBACK)


static func _placeholder(resource_key: String, palette: Dictionary, display_name := "") -> Dictionary:
	return {
		"art_id": resource_key,
		"ready": false,
		"name": display_name,
		"shape": _shape_for(resource_key),
		"base": palette.get("base", FALLBACK["base"]),
		"accent": palette.get("accent", FALLBACK["accent"]),
	}


## 简化轮廓分类：只看资源键关键词，保证同一模板每次解析结果一致（可测试、可复现）。
static func _shape_for(resource_key: String) -> String:
	var key := resource_key.to_lower()
	for pair in [
		["sarcophagus", "sarcophagus"], ["coffin", "sarcophagus"],
		["nest", "nest"], ["hive", "nest"],
		["pool", "pool"], ["cistern", "pool"],
		["herb", "plant"], ["gel", "pool"], ["glowcap", "plant"], ["spore", "plant"],
		["log", "wood"], ["stump", "wood"], ["raft", "wood"], ["tree", "wood"],
		["remains", "remains"],
		["camp", "camp"], ["kiln", "camp"], ["rack", "camp"],
		["wisp", "wisp"],
	]:
		if key.contains(str(pair[0])):
			return str(pair[1])
	return "box"
