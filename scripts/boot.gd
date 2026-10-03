extends Node
## 启动分流：官方导出二进制禁用了路径覆盖（--script/位置场景不可用），
## 专用服务端与客户端共用一个导出包，由启动参数决定入口。
## 客户端：正常启动即主菜单；服务端：./farm_server.x86_64 --headless -- --server --port ...

const SERVER_SCENE := "res://scenes/server_main.tscn"
const CLIENT_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	var server_mode := "--server" in OS.get_cmdline_user_args()
	var path := SERVER_SCENE if server_mode else CLIENT_SCENE
	# _ready 期间场景树正在装卸节点，同步切场景会报 remove_child 错误
	get_tree().change_scene_to_file.call_deferred(path)
