class_name OnlineProtocol
extends RefCounted
## M1 联机协议常量（计划：docs/plan/Godot_好友联网_M1_M2_线上身份与个人农场_代码执行计划_v0.1.md §3）。
## 客户端与服务端共用同一份定义，保证信封、版本、错误码、特性名不漂移。
## 纯静态、零依赖；改任何常量都要同时考虑双端与 RULES/PROTO 版本号。

## 传输协议版本（信封结构变更时 +1；不兼容旧版直接握手拒绝）。
## v3（M3）：新增 expedition 特性组、room.*/run.* 命令与 t="push" 主动推送；welcome 扩展 room/run。
const PROTO_VERSION := 3
## 规则/数值版本（PlantDefs/MarketDefs/存档结构等影响线上判定时 +1）。
const RULES_VERSION := 1
## 客户端构建号（发正式试玩包时递增；服务器用它拒绝过旧的包）。
const CLIENT_BUILD := 1
## 服务器要求的最低客户端构建。
const MIN_CLIENT_BUILD := 1

## 特性分组名（welcome.features 下发；服务器侧决定开哪些）。
const FEATURE_FARM_BASIC := "farm_basic"      # M1：播种/选种/浇水/施肥/收获/一键收获
const FEATURE_FARM_SHOP := "farm_shop"        # M2：商店/扩地/仓库/水壶升级
const FEATURE_FARM_BREEDING := "farm_breeding"  # M2：育种机/回收/待领取
const FEATURE_FARM_MARKET := "farm_market"    # M2：市场出售/锁定/批量
const FEATURE_FARM_CRAFT := "farm_craft"      # M2：制作/设施/目标
const FEATURE_FARM_INVENTORY := "farm_inventory"  # M2：装备仓库与战备
const FEATURE_EXPEDITION := "expedition"          # M3：房间/单人洞窟/局内动作/结算

## 默认服务器地址（M0 已部署：腾讯云 + 自签证书直连；设置可覆盖）。
const DEFAULT_SERVER_URL := "wss://111.229.19.23:31971"
## 客户端内置的公钥证书（钉扎信任用；私钥永不入库/入包）。
const CLIENT_CERT_PATH := "res://client/certs/farm_server.crt"

## 本机凭据（N02：可撤销、不进日志）。
const SESSION_PATH := "user://online/session.json"

## 错误码（§3.3 表）。
const ERR_BAD_JSON := "bad_json"
const ERR_UNKNOWN_T := "unknown_t"
const ERR_OVERSIZED := "oversized"
const ERR_RATE_LIMITED := "rate_limited"
const ERR_NOT_AUTHENTICATED := "not_authenticated"
const ERR_INVITE_INVALID := "invite_invalid"
const ERR_INVITE_USED := "invite_used"
const ERR_NICK_INVALID := "nick_invalid"
const ERR_VERSION_MISMATCH := "version_mismatch"
const ERR_TOKEN_INVALID := "token_invalid"
const ERR_ACCOUNT_DISABLED := "account_disabled"
const ERR_SESSION_REPLACED := "session_replaced"
const ERR_UNKNOWN_OP := "unknown_op"
const ERR_FEATURE_DISABLED := "feature_disabled"
const ERR_OP_FAILED := "op_failed"
const ERR_STATE_LOCKED := "state_locked"
const ERR_REQ_ID_CONFLICT := "req_id_conflict"
const ERR_REQ_ID_REQUIRED := "req_id_required"
const ERR_INTERNAL := "internal_error"
const ERR_BUSY := "busy"

## 单包上限（N05：超大包直接断开）。
const MAX_PACKET_BYTES := 65536
## 限速窗口：窗口内超过该条数回 rate_limited（不踢）。
## 阈值依据：客户端桥接按"一命令一往返"串行，正常节奏 ≈ 每命令 35～60ms（实测 d44 均值 36ms），
## 连续点击/批量 UI 的合法突发可达 ~28 条/秒；旧值 30/3s 会误伤该突发（d44 实测丢包）。
const RATE_WINDOW_SECONDS := 3.0
const RATE_WINDOW_MESSAGES := 90
## 畸形包容忍度：3 次断开。
const MAX_MALFORMED := 3
## 昵称约束。
const NICK_MAX_CHARS := 16


## 字节转十六进制（token/req_id 生成用；Godot 4 无内置 hex 编码）。
static func bytes_to_hex(bytes: PackedByteArray) -> String:
	const HEX := "0123456789abcdef"
	var out := ""
	for b in bytes:
		out += HEX[b >> 4] + HEX[b & 0xf]
	return out


static func envelope(t: String, fields: Dictionary = {}) -> Dictionary:
	var payload := {"t": t}
	for key in fields:
		payload[key] = fields[key]
	return payload


static func error_payload(code: String, msg := "", extra: Dictionary = {}) -> Dictionary:
	var payload := envelope("error", {"code": code})
	if msg != "":
		payload["msg"] = msg
	for key in extra:
		payload[key] = extra[key]
	return payload
