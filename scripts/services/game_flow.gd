class_name GameFlow
extends RefCounted
## 主菜单与农场世界之间的跨场景意图（项目无 autoload，用静态变量传递）。
## 默认 AUTO 保持"直启 main.tscn 即读档"的旧路径：既有测试与联调行为零变化。
## farm_world._ready 消费完意图后必须调 reset()，避免残留影响下一次进入。

enum Mode { AUTO, CONTINUE, NEW_GAME }

static var mode: int = Mode.AUTO
## 主菜单"设置→重新显示新手引导"：进农场读档后把 tutorial_step 归零。
static var reset_tutorial := false


static func reset() -> void:
	mode = Mode.AUTO
	reset_tutorial = false
