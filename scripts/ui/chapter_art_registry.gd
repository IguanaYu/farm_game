class_name ChapterArtRegistry
extends RefCounted
## 表现资源查找与统一占位回退（森林第一章，开发计划 §3/§4.1）。
## 玩法存档只记录定义/实例 ID，不保存图片路径；本表把资源 ID 解析为当前可用的表现参数。
## 简洁几何插图以 SVG 独立入库，ready=true 并带纹理路径，不改玩法 ID 与命中区；
## 任何未登记的资源 ID 都回落到统一占位，不允许整块界面空白。


## 统一占位回退：未知资源也给出可画的形状与中性配色。
const FALLBACK := {
	"shape": "gem", "base": Color("#6b7280"), "accent": Color("#aeb6c2"),
}

const ART_ROOT := "res://assets/chapter_one/"


## 区域背景：1280×640 横幅，图片未就绪时仍保留原占位参数。
static func background(area_id: String) -> Dictionary:
	var area := ChapterOneDefs.area(area_id)
	if area.is_empty():
		return _placeholder("bg?", FALLBACK)
	return _with_texture({
		"art_id": str(area["art_id"]),
		"ready": false,
		"name": str(area["name"]),
		"shape": "background",
		"base": area["base"],
		"accent": area["accent"],
	}, "backgrounds/%s.svg" % area_id)


## 搜索对象占位：按模板名的关键词选简化轮廓（计划 §3：轮廓可区分＋名称标签）。
static func prop(template_id: String) -> Dictionary:
	var record := ChapterOneDefs.template(template_id)
	if record.is_empty():
		return _placeholder(template_id, FALLBACK)
	var area := ChapterOneDefs.area(str(record["area"]))
	var palette := {"base": area.get("base", FALLBACK["base"]), "accent": area.get("accent", FALLBACK["accent"])}
	return _with_texture(_placeholder(template_id, palette, str(record["name"])), "props/%s.svg" % template_id)


## 敌人占位：简化身体＋名称；三色史莱姆按元素着色（元素辨识图标在 P2 战斗符号层补）。
static func enemy(enemy_id: String) -> Dictionary:
	var record: Dictionary = ChapterOneDefs.ENEMIES.get(enemy_id, {})
	if record.is_empty():
		return _placeholder(enemy_id, FALLBACK)
	var palette := {"base": Color("#4d5a52"), "accent": Color("#9db8a4")}
	match enemy_id:
		"forest_green_slime":
			palette = {"base": Color("#5f8f5a"), "accent": Color("#a3ccb2")}
		"forest_red_slime":
			palette = {"base": Color("#a55550"), "accent": Color("#e0a09a")}
		"forest_blue_slime":
			palette = {"base": Color("#5a7fa5"), "accent": Color("#a0bfe0")}
	if record.has("area"):
		var area := ChapterOneDefs.area(str(record["area"]))
		palette = {"base": Color(area["base"]).darkened(0.15), "accent": area["accent"]}
	return _with_texture({
		"art_id": enemy_id,
		"ready": false,
		"name": str(record["name"]),
		"shape": _enemy_shape_for(enemy_id),
		"base": palette["base"],
		"accent": palette["accent"],
	}, "enemies/%s.svg" % enemy_id)


## 物品插图独立于 P1 的物品数值定义；五项复用物品不另造玩法 ID。
static func item(def_id: String) -> Dictionary:
	for record in ChapterOneDefs.ITEM_MAPPING.values():
		if str(record["def_id"]) == def_id:
			return _with_texture(_placeholder(def_id, FALLBACK, str(record["name"])), "items/%s.svg" % def_id)
	return _placeholder(def_id, FALLBACK)


## 卡牌插图无框、无文字；费用、效果和品质继续由 UI 绘制。
static func card(card_id: String) -> Dictionary:
	var record: Dictionary = ChapterOneDefs.NEW_CARDS.get(card_id, {})
	if record.is_empty():
		return _placeholder(card_id, FALLBACK)
	return _with_texture(_placeholder(card_id, FALLBACK, str(record["name"])), "cards/%s.svg" % card_id)


## 资源 ID → 当前表现；未知 ID 和缺失图片始终有占位回退。
static func resolve(art_id: String) -> Dictionary:
	if art_id.begins_with("bg.forest_ch1."):
		return background(art_id.trim_prefix("bg.forest_ch1."))
	if art_id.begins_with("prop."):
		return prop(art_id.trim_prefix("prop."))
	if art_id.begins_with("enemy."):
		return enemy(art_id.trim_prefix("enemy."))
	if art_id.begins_with("item."):
		return item(art_id.trim_prefix("item."))
	if art_id.begins_with("card."):
		return card(art_id.trim_prefix("card."))
	return _placeholder(art_id, FALLBACK)


static func _with_texture(spec: Dictionary, relative_path: String) -> Dictionary:
	var path := ART_ROOT + relative_path
	if ResourceLoader.exists(path, "Texture2D"):
		var texture := load(path) as Texture2D
		if texture != null:
			spec["ready"] = true
			spec["texture_path"] = path
	return spec


static func texture(spec: Dictionary) -> Texture2D:
	if not bool(spec.get("ready", false)):
		return null
	return load(str(spec["texture_path"])) as Texture2D


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


## 敌人专用轮廓（计划 §3：简化身体＋武器轮廓；同类共用剪影，颜色与名称区分）。
static func _enemy_shape_for(enemy_id: String) -> String:
	var key := enemy_id.to_lower()
	if key.contains("slime") or key.contains("matriarch"):
		return "slime"
	if key.contains("bat"):
		return "bat"
	if key.contains("wolf"):
		return "wolf"
	if key.contains("spider"):
		return "spider"
	if key.contains("wisp"):
		return "wisp"
	if key.contains("goblin"):
		return "goblin"
	if key.contains("bandit"):
		return "bandit"
	if key.contains("priest") or key.contains("wrapped") or key.contains("walker"):
		return "robe"
	if key.contains("guard") or key.contains("keeper"):
		return "golem"
	return "body"
