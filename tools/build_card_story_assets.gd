extends SceneTree
## 仅将已确认原图缩为 640×400 游戏纹理；不重新构图、不覆盖原始生成图。

const SOURCE := "res://assets/art_studies/card_story_v05/"
const TARGET := "res://assets/chapter_one/cards/"

func _initialize() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "manifest.json"))
	var revisions = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "revisions.json"))
	if not manifest is Dictionary or not revisions is Dictionary:
		push_error("Card story manifests are invalid")
		quit(1)
		return
	var replacements := {}
	for revision in revisions.revisions:
		replacements[revision.id] = revision.file
	for card in manifest.cards:
		var filename: String = replacements.get(card.id, card.file)
		var image := Image.load_from_file(SOURCE + filename)
		if image == null or image.is_empty():
			push_error("Missing card source: " + filename)
			quit(1)
			return
		image.resize(640, 400, Image.INTERPOLATE_LANCZOS)
		if image.save_png(TARGET + card.id + ".png") != OK:
			push_error("Failed to save: " + card.id)
			quit(1)
			return
	print("CARD_STORY_BUILD: 6 textures at 640x400")
	quit(0)
