extends RefCounted
## 仅供启动本地测试服务器的集成测试显式安装。
## 场景内部自动创建的客户端信任该测试服务器的证书；不改生产钉扎证书或 TLS 校验。
## 显式传入的证书（包含错误证书负向用例）保持不变。

static func install(tree: SceneTree) -> void:
	tree.node_added.connect(func(node: Node) -> void:
		if node is OnlineClient and node.cert_path == OnlineProtocol.CLIENT_CERT_PATH:
			node.cert_path = ProjectSettings.globalize_path("res://server/secrets/farm_server.crt"))
