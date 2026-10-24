extends SceneTree
## 已生成原图只做等比例缩放，不更改构图；旧 SVG 作为历史资源保留。

func _initialize() -> void:
	var source := "res://assets/art_studies/card_story_v06/"
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(source + "manifest.json"))
	if not manifest is Dictionary:
		quit(1)
		return
	for card in manifest.cards:
		var image := Image.load_from_file(source + card.file)
		if image == null or image.is_empty():
			push_error("Missing expansion illustration: " + str(card.id))
			quit(1)
			return
		image.resize(640, 400, Image.INTERPOLATE_LANCZOS)
		if image.save_png("res://assets/chapter_one/cards/" + card.id + ".png") != OK:
			quit(1)
			return
	print("CARD_STORY_EXPANSION_BUILD: %d textures at 640x400" % manifest.cards.size())
	quit(0)
