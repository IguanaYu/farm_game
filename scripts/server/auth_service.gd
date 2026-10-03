class_name AuthService
extends RefCounted
## M1 身份服务（计划 §4.2，规划 N01～N03）：一次性邀请码开户、token（只存哈希）、
## 单账户单活动会话（新连接顶替旧 peer）。凭据与邀请码不进日志。
## 注意：GDScript lambda 按值捕获局部变量，跨 lambda 传递结果用 Dictionary/Array 容器。

var store: ServerDB
## N03 单会话映射：account_id ↔ 在线 peer（一个 peer 同一时刻只挂一个账户）。
var _peer_by_account := {}
var _account_by_peer := {}
## M3：账户昵称缓存（房间成员显示用；登录时刷新）。
var _nick_by_account := {}

const CODE_ALPHABET := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"


func generate_invites(count: int, note: String) -> Array:
	var created := _now_string()
	var rows: Array = []
	for i in range(count):
		var code := "FARM-" + _code_group() + "-" + _code_group()
		rows.append([code, note, created])
	var result: Array = store.tx(func() -> bool:
		for row in rows:
			if not store.exec(
				"INSERT INTO invites(code, note, created_at) VALUES(?, ?, ?)",
				[row[0], row[1], row[2]]
			):
				return false
		return true
	)
	if not bool(result[0]):
		return []
	var codes: Array = []
	for row in rows:
		codes.append(row[0])
	return codes


## 邀请激活开户（N01）：核销邀请码 → 建号 → 发 token（明文只此一次出现在网络上）。
## 返回 {ok, code, account_id, nick, token}；code 为 OnlineProtocol.ERR_*。
func activate(invite_code: String, nick: String, initial_state_json: String) -> Dictionary:
	var code := invite_code.strip_edges(true, true).to_upper()
	var trimmed_nick := nick.strip_edges(true, true)
	if trimmed_nick.is_empty() or trimmed_nick.length() > OnlineProtocol.NICK_MAX_CHARS:
		return {"ok": false, "code": OnlineProtocol.ERR_NICK_INVALID}
	if code.is_empty():
		return {"ok": false, "code": OnlineProtocol.ERR_INVITE_INVALID}
	var out := {"account_id": 0, "token": ""}
	var result: Array = store.tx(func() -> bool:
		var invite := store.query_one(
			"SELECT code, used_at FROM invites WHERE code = ?", [code]
		)
		if invite.is_empty():
			return false
		var used: Variant = invite.get("used_at")
		if used != null and str(used) != "":
			return false
		var created := _now_string()
		if not store.exec(
			"INSERT INTO accounts(nick, created_at, farm_state, farm_seq) VALUES(?, ?, ?, 0)",
			[trimmed_nick, created, initial_state_json]
		):
			return false
		var row := store.query_one("SELECT id FROM accounts ORDER BY id DESC LIMIT 1")
		if row.is_empty():
			return false
		out["account_id"] = int(row["id"])
		if not store.exec(
			"UPDATE invites SET used_at = ?, account_id = ? WHERE code = ?",
			[created, out["account_id"], code]
		):
			return false
		out["token"] = _new_token()
		if not store.exec(
			"INSERT INTO tokens(token_hash, account_id, created_at) VALUES(?, ?, ?)",
			[sha256_hex(out["token"]), out["account_id"], created]
		):
			return false
		return true
	)
	if not bool(result[0]):
		# 失败后二次查询区分"邀请码不存在/已用"，避免把数据库故障误报成邀请码问题。
		var invite := store.query_one("SELECT used_at FROM invites WHERE code = ?", [code])
		if invite.is_empty():
			return {"ok": false, "code": OnlineProtocol.ERR_INVITE_INVALID}
		var used: Variant = invite.get("used_at")
		if used != null and str(used) != "":
			return {"ok": false, "code": OnlineProtocol.ERR_INVITE_USED}
		return {"ok": false, "code": OnlineProtocol.ERR_INTERNAL}
	return {"ok": true, "account_id": out["account_id"], "nick": trimmed_nick, "token": out["token"]}


## token 登录（N02 自动登录）。返回 {ok, code, account_id, nick}。
func login(token: String) -> Dictionary:
	if token.strip_edges(true, true).is_empty():
		return {"ok": false, "code": OnlineProtocol.ERR_TOKEN_INVALID}
	var row := store.query_one(
		"SELECT a.id AS id, a.nick AS nick, a.disabled AS disabled " +
		"FROM tokens t JOIN accounts a ON a.id = t.account_id " +
		"WHERE t.token_hash = ? AND t.revoked_at IS NULL",
		[sha256_hex(token)]
	)
	if row.is_empty():
		return {"ok": false, "code": OnlineProtocol.ERR_TOKEN_INVALID}
	if int(row["disabled"]) != 0:
		return {"ok": false, "code": OnlineProtocol.ERR_ACCOUNT_DISABLED}
	return {"ok": true, "account_id": int(row["id"]), "nick": str(row["nick"])}


## 绑定会话（N03）：同账户新 peer 顶替旧 peer（返回被顶替的 peer，0=无）。
## 同一 peer 重复 hello 也走这里，天然换绑。
func bind_session(account_id: int, peer_id: int) -> int:
	var old_peer := int(_peer_by_account.get(account_id, 0))
	if old_peer != 0 and old_peer != peer_id and _account_by_peer.has(old_peer):
		_account_by_peer.erase(old_peer)
		_peer_by_account[account_id] = peer_id
		_account_by_peer[peer_id] = account_id
		return old_peer
	_peer_by_account[account_id] = peer_id
	# peer 换账户登录：清掉旧账户的 peer 映射
	var previous := int(_account_by_peer.get(peer_id, 0))
	if previous != 0 and previous != account_id:
		_peer_by_account.erase(previous)
	_account_by_peer[peer_id] = account_id
	return 0


func account_of_peer(peer_id: int) -> int:
	return int(_account_by_peer.get(peer_id, 0))


## M3 房间服务用：账户当前在线 peer（0=无会话）。
func peer_of_account(account_id: int) -> int:
	return int(_peer_by_account.get(account_id, 0))


func has_session(account_id: int) -> bool:
	return _peer_by_account.has(account_id)


## M3：昵称缓存（登录/激活时写入；未登录账户回退空串）。
func set_nick(account_id: int, nick: String) -> void:
	_nick_by_account[account_id] = nick


func nick_of(account_id: int) -> String:
	return str(_nick_by_account.get(account_id, ""))


func unbind_peer(peer_id: int) -> void:
	var account_id := int(_account_by_peer.get(peer_id, 0))
	if account_id != 0:
		if int(_peer_by_account.get(account_id, 0)) == peer_id:
			_peer_by_account.erase(account_id)
	_account_by_peer.erase(peer_id)


func _code_group() -> String:
	var bytes := Crypto.new().generate_random_bytes(4)
	var group := ""
	for b in bytes:
		group += CODE_ALPHABET[b % CODE_ALPHABET.length()]
	return group


func _new_token() -> String:
	return "t_" + bytes_to_hex(Crypto.new().generate_random_bytes(32))


static func sha256_hex(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return bytes_to_hex(ctx.finish())


static func bytes_to_hex(bytes: PackedByteArray) -> String:
	return OnlineProtocol.bytes_to_hex(bytes)


func _now_string() -> String:
	return Time.get_datetime_string_from_system(true)
