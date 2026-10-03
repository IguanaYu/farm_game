# 好友联网 M1/M2：线上身份与个人农场 代码执行计划 v0.1

编写日期：2026-10-03。状态：**M1 实施中，M2 待实施**。

依据：[【主要】好友联网试玩版开发规划 v0.1](../【主要】Godot_好友联网试玩版_开发规划_v0.1.md) §3.1/§3.2/§6 M1/M2 行、W02/W03/W04 工作包；M0 技术验证结论（WSS+SQLite+Linux 专服导出全部通过，`Farm_M0_技术验证_2026-10-03.md`）。编号引用 N01～N05、F01～F09、T01～T04/T13。

## 1. 目标与非目标

**M1（身份和最小线上农场）出口**（主规划 §6 原文）：

> 两个独立账户登录，各自播种、照料、收获、重启恢复；改系统时钟不增加收益；对方不能改自己的地块。

覆盖 N01～N05、F01/F02/F08/F09 与 W02 全量、W03/W04 首个纵向流程。

**M2（个人玩法全部联网）出口**：

> 仓库、育种、买卖、制作、升级、配装和教程可正常持续游玩；所有资产入口清单逐项核销。

覆盖 F03～F07，完成 W03/W04。

**非目标（本计划不做）：**

- 洞窟、房间、出发/结算（C/S 编号，M3）。M1/M2 线上模式中洞窟入口置灰并提示"后续开放"。
- 断线自动重连矩阵、服务端重启期间的无损恢复演练（S05～S08，M4）。M1 只保证：已返回成功的操作在服务端重启后仍在（数据库事实）+ 客户端重登录拿回快照。
- 农场互访、实时走动、自动更新器、后台网站（§9 暂缓项）。
- 不改农场数值与规则；规则层只补"服务器可运行"所需的最小注入点。

## 2. 总体架构

```text
Windows 客户端（联机模式）                      腾讯云 111.229.19.23:31971
┌ main_menu "联机农场"入口 ┐                  ┌ server_main（headless，boot --server 分流）┐
│ online_login_panel        │   WSS + 自签证书 │  auth_service   邀请/账户/token/单会话/限速  │
│  ↓ GameFlow.Mode.ONLINE   │ ───────────────→ │  farm_service   FarmGame+CraftingGame+     │
│ farm_world（组合根）       │    JSON 信封     │                 InventoryGame 按账户组合    │
│  ├ online_farm_bridge ────│── req(op,args) →│  server_db      SQLite WAL+FULL，事务提交   │
│  │   └ FarmGame 本地副本  │←─ 快照+事件 ──── │                 + 收据去重                    │
│  └ farm_hud（能力门控）    │                 └ 特性开关 features 随 welcome 下发            │
└ 单机模式完全不变（本地档） ┘
```

关键决策（实施时冻结）：

1. **服务端原样复用规则对象**：每个在线账户一个 `AccountRuntime{FarmGame, CraftingGame, InventoryGame, farm_seq}`，`crafting.bind(farm)`、`inventory.bind(farm.state["expedition"])` 与客户端组合方式一致；规则不进场景树、不感知网络。
2. **全快照 + 收据去重**：每次命令成功响应携带完整农场快照（`farm_game` 存档字典）+ `farm_seq`。S02 的去重子集提前到 M1——F02 完成条件要求"重复点击/重试不重复扣种子或发作物"。快照体积在 d42 实测记录，超阈值再裁剪。
3. **服务器时间为唯一权威（F08）**：客户端命令不携带 `now`；所有 `now` 由服务器注入。客户端 `bridge.now()` = 最近一次 `server_now` + 本地单调流逝，仅用于倒计时/成熟标记展示，改本机时钟不影响收益（T03 生长部分）。
4. **登录时结算**：服务器在账户加载时执行 `refresh_market(now)` 与 `breeder_settle(now)`（与 `farm_world._ready` 同一套语义），结果作为状态变更落库——离线期间累计产出/每日市场由此生效（F03/F05 的服务器侧基础在 M1 铺好，M2 开放入口）。
5. **特性开关**：`welcome.features` 下发命令组（M1 `farm_basic`；M2 增加 `farm_shop` `farm_market` `farm_craft` `farm_inventory`）。客户端据此门控按钮；服务器对未开放命令一律 `feature_disabled`。服务端配置即可灰度，不需要客户端重发版。
6. **M0 假账户命令退役**：`balance`/`tx`/`receipts` 演示命令删除（M0 记录文档与探针保留在仓库供追溯）；`ping` 保留为健康检查。PROTO_VERSION 升 2，旧探针连新服务器得到 `version_mismatch`，属预期。
7. **教程状态**：`tutorial_step` 是农场状态一部分，随快照同步；服务器在对应命令成功后调用与 `farm_world._advance_tutorial` 相同的推进逻辑（M1 覆盖播种/收获步；M2 补制作/配装步），保证双端教程语义一致。

## 3. 通信协议 v2（N04/N05）

一包一条 UTF-8 JSON（沿 M0）。信封字段：`t`（类型）、`req_id`、`op`、`args`、`code`、`msg`、`server_now`、`features`、`snapshot`、`events`、`need`。

### 3.1 客户端 → 服务器

| t | 字段 | 语义 |
| --- | --- | --- |
| `hello` | `token, build, proto, rules` | 登录（N02 自动登录即本机存 token 重放） |
| `activate` | `invite, nick, build, proto, rules` | 邀请激活开户（N01） |
| `req` | `req_id, op, args` | 命令请求；`req_id` 客户端生成、同意图重试不变号 |
| `ping` | — | 健康检查 |

### 3.2 服务器 → 客户端

| t | 字段 | 语义 |
| --- | --- | --- |
| `welcome` | `account_id, nick, server_now, features, snapshot` | 登录/激活成功；快照即 F01 线上视图 |
| `req_ok` | `req_id, op, result, events[], snapshot, server_now` | 命令成功；`result` 为规则返回值（如收获事件），`events` 供 UI 提示 |
| `req_err` | `req_id, op, code, msg` | 命令失败；`duplicate` 不是错误——收据命中回 `req_ok(duplicate=true)` |
| `bye` | `code` | 服务器主动断开前告知（如维护） |
| `kicked` | `reason` | N03 单会话：同账户新连接顶替，旧连接收此包后断开 |
| `error` | `code, msg` | 握手层错误（见下表） |

### 3.3 错误码表

| code | 场景 | 客户端展示要点 |
| --- | --- | --- |
| `bad_json` / `unknown_t` / `oversized` | 畸形包（N05） | 连接异常提示（ oversized 直接断开） |
| `rate_limited` | 窗口内超量（默认 3 秒 30 条） | "操作太快，稍候再试"，不惩罚 |
| `not_authenticated` | hello 前发 req | 不会出现在正常 UI 流程 |
| `invite_invalid` / `invite_used` | 激活失败（N01） | 检查邀请码 / 找开发者 |
| `nick_invalid` | 昵称空或超 16 字符 | 表单校验提示 |
| `version_mismatch` | `need{proto, rules, build}`（N04） | "请下载新版本客户端"，阻止进入 |
| `token_invalid` | token 不存在/已撤销（N02） | 回登录页，支持开发者重发凭据 |
| `account_disabled` | 停用账户 | 联系开发者 |
| `session_replaced` | kicked 原因（N03） | "该账户已在别处登录" |
| `unknown_op` / `feature_disabled` | 命令不在表 / 特性未开 | "功能未开放" |
| `op_failed` | 规则层拒绝（`msg` 带原因，如 `not_enough_coins`） | 透传现有规则提示文案 |
| `state_locked` | 同账户上一命令事务未完成 | 自动重试一次后提示 |
| `internal_error` | 未预期异常 | 错误编号可复制（O06 铺垫） |

### 3.4 连接与请求纪律（N05）

- 单包上限 64KB；超限断开。`hello` 前仅接受 `hello`/`activate`/`ping`。
- 限速：每 peer 滑动窗口 3 秒 30 条；`rate_limited` 不计入踢出。畸形包 3 次断开。
- `req_id` 规则：`<account_id>-<单调序号>`；重连后未确认的 pending 请求**原号重发**，服务器按 `(account_id, req_id)` 收据去重。
- 日志脱敏：token、邀请码全文与私钥路径不得进日志（O06 前置约束）。
- 版本三元组 `proto`（本协议）、`rules`（规则与 defs 变更时 +1）、`build`（导出构建号）；不匹配拒绝在握手，不进局。

## 4. 服务端设计（scripts/server/）

### 4.1 `server_db.gd`（新增）

- SQLite 封装：打开（WAL + synchronous=FULL，沿 M0）、`tx(fn)` 助手（`BEGIN IMMEDIATE` / 失败 `ROLLBACK`）、`query_one` / `query_all`。
- Schema（`schema_version=2`）：

```sql
meta(key TEXT PK, value TEXT)                      -- schema_version / created_at
invites(code TEXT PK, note TEXT, created_at TEXT, used_at TEXT NULL, account_id INTEGER NULL)
accounts(id INTEGER PK AUTOINCREMENT, nick TEXT NOT NULL, created_at TEXT NOT NULL,
         disabled INTEGER NOT NULL DEFAULT 0,
         farm_state TEXT NOT NULL,      -- FarmGame 存档字典 JSON
         farm_seq INTEGER NOT NULL DEFAULT 0)
tokens(token_hash TEXT PK, account_id INTEGER NOT NULL, created_at TEXT, revoked_at TEXT NULL)
receipts(account_id INTEGER, req_id TEXT, op TEXT, outcome TEXT, farm_seq INTEGER, created_at TEXT,
         PRIMARY KEY(account_id, req_id))
```

- token 只存 sha256（凭据泄漏不等于账户接管）；`FarmGame.new_game()` 的初始档在开户事务内生成。

### 4.2 `auth_service.gd`（新增，W02/N01～N05）

- `activate(invite, nick)`：邀请码核销（单事务：置 `used_at`/`account_id` + 建账户 + 发 token），返回明文 token（仅此一次出现在网络上）。
- `hello(token)`：token→账户；N03 单会话——同账户旧 peer 发 `kicked(session_replaced)` 并断开；新会话记录 peer。
- 限速与包纪律在 `server_main` 收包处统一执行（§3.4）。
- 邀请管理（O07 最小切片）：启动参数 `--new-invite N [--invite-note X]` 打印 N 个随机码后退出，不入运行态；码格式 `FARM-XXXX-XXXX`（去除易混淆字符）。

### 4.3 `farm_service.gd`（新增，W03）

- `AccountRuntime`：`farm: FarmGame`、`crafting: CraftingGame`、`inventory: InventoryGame`、`farm_seq`。加载时先 `load_state(库内 JSON)`，再 `refresh_market(now)` + `breeder_settle(now)`，有变化则落库（§2 决策 4）。断开即逐出缓存（写穿模式，逐出无损失）。
- 命令执行统一入口（规划 §4.2 流程的落地）：

```text
认证 → 限速/校验 → 查收据（命中→回 req_ok duplicate=true，原 result）
  → 候选副本 = FarmGame.load_state(深拷贝当前档)（crafting/inventory 重绑候选）
  → 在候选上执行命令（注入服务器 now）→ 规则失败→req_err(op_failed)
  → 事务：UPDATE accounts.farm_state/farm_seq + INSERT receipt → COMMIT
  → 换入候选为正式 → req_ok（result + events + 新快照 + server_now）
```

- 服务器时间：`Time.get_unix_time_from_system()` 取整秒；`--dev --dev-time-shift N` 才允许偏移（d42 用于跨成熟验证；部署配置禁带 `--dev`，生产拒绝该组合启动）。
- 教程推进：命令成功后按 `farm_world._advance_tutorial` 同款映射推进 `tutorial_step`（M1：播种/浇水/收获步；M2 补齐）。

### 4.4 命令表（op → 规则方法；即"资产入口核销"的机器面）

| 分组（特性名） | op | 规则方法 | 里程碑 |
| --- | --- | --- | --- |
| `farm_basic` | `farm.plant` | `plant(plot_id, now, kind)` | M1 |
| | `farm.plant_seed` | `plant_seed(plot_id, seed_id, now)` | M1 |
| | `farm.water` | `water(plot_id, now)` | M1 |
| | `farm.fertilize` | `apply_fertilizer(plot_id, kind, now)` | M1 |
| | `farm.harvest` | `harvest(plot_id, now)` | M1 |
| | `farm.harvest_all` | `harvest_all(now)` | M1 |
| `farm_shop` | `farm.buy_seeds` | `buy_seeds(quantity, kind)` | M2 |
| | `farm.buy_fertilizer` | `buy_fertilizer(kind, quantity)` | M2 |
| | `farm.upgrade_shop` | `upgrade_shop()` | M2 |
| | `farm.buy_can2` | `buy_can2()` | M2 |
| | `farm.buy_plot` | `buy_plot()` | M2 |
| | `farm.upgrade_warehouse` | `upgrade_warehouse()` | M2 |
| `farm_breeding` | `farm.recycle_seed` | `recycle_seed(seed_id)` | M2 |
| | `farm.recycle_pending_seed` | `recycle_pending_seed(seed_id)` | M2 |
| | `farm.claim_pending` | `claim_pending()` | M2 |
| | `farm.buy_breeder` | `buy_breeder(now)` | M2 |
| | `farm.upgrade_breeder` | `upgrade_breeder()` | M2 |
| | `farm.set_breeder_template` | `set_breeder_template(seed_id, now)` | M2 |
| | `farm.clear_breeder_template` | `clear_breeder_template(now)` | M2 |
| | `farm.collect_breeder` | `collect_breeder(now)` | M2 |
| `farm_market` | `farm.sell_batch` | `sell_batch(batch_id)` | M2 |
| | `farm.sell_all_batches` | `sell_all_batches()` | M2 |
| | `farm.sell_pending_crop` | `sell_pending_crop(batch_id)` | M2 |
| | `farm.lock_guest` | `request_lock_guest(guest_id)` | M2 |
| | `farm.unlock_guest` | `request_unlock_formula`（解锁客人位） | M2 |
| | `farm.lock_formula` | `request_lock_formula(kind)` | M2 |
| | `farm.unlock_formula` | `request_unlock_formula()` | M2 |
| | `farm.sell_batch_to` | `sell_batch_to(batch_id, count, guest_id, now)` | M2 |
| `farm_craft` | `craft.craft` | `crafting.craft(recipe_id)` | M2 |
| | `craft.claim_pending` | `crafting.claim_pending()` | M2 |
| | `craft.buy_upgrade` | `crafting.buy_upgrade(upgrade_id)` | M2 |
| | `craft.claim_goal` | `crafting.claim_goal(goal_id)` | M2 |
| | `craft.sell_instance` | `crafting.sell_instance(def_id)` | M2 |
| `farm_inventory` | `inv.move_to_loadout` | `inventory.move_to_loadout(instance_id, container)` | M2 |
| | `inv.move_to_warehouse` | `inventory.move_to_warehouse(instance_id)` | M2 |
| | `inv.place_at` | `inventory.place_at(instance_id, container, cell, rotated)` | M2 |
| | `inv.rotate` | `inventory.rotate_instance(instance_id)` | M2 |
| | `inv.auto_tidy` | `inventory.auto_tidy(container)` | M2 |
| | `inv.discard` | `inventory.discard_instance(instance_id)` | M2 |
| | `inv.claim_reward` | `inventory.claim_reward(def_id, container)` | M2 |
| | `inv.clear_loadout` | `inventory.clear_loadout()` | M2 |
| | `inv.grant_basic_kit` | `inventory.grant_basic_kit()` | M2（教程首装） |

读操作（`quote`、`market_snapshot`、`breeder_status`、`deck_preview` 等）不设命令：由快照在客户端本地计算展示；成交/领取以服务器校验为准（F05 完成条件）。
配装预设（`PresetStore`）是本机便捷设置，不属线上资产，保持本地。
`debug_mature` 等调试入口线上模式不接线，服务器无此命令。

### 4.4 `server_main.gd`（改写）

- 保留：启动参数解析、TLS 监听、`ping`、收包循环、`_shutdown`。
- 新增：装配 `server_db`/`auth_service`/`farm_service`、包纪律与限速、`--new-invite` 子命令、`--dev` 守卫。
- 移除：M0 假账户表与 `balance`/`tx`/`receipts` 命令（§2 决策 6）。

## 5. 客户端设计

### 5.1 `scripts/services/online_protocol.gd`（新增，服务端共用）

版本常量（`PROTO=2`、`RULES=1`）、默认服务器地址 `wss://111.229.19.23:31971`、特性名常量、错误码常量、信封构造助手。纯静态、无依赖，server_main 也引用它保证双端一致。

### 5.2 `scripts/services/online_client.gd`（新增，W02 客户端半）

- WSS 连接：证书钉扎 `TLSOptions.client(内置 res://server/certs/farm_server.crt)`（公钥材料，可入库；私钥永不入库，M0 已有导出排除规则）。
- 状态机：`CONNECTING / ONLINE / RECONNECTING / OFFLINE`；断线后指数退避重连，成功即重放 pending（原 req_id）。
- 请求 API：`request(op, args) -> String(req_id)`，信号 `req_ok/req_err/welcome/kicked/bye/state_changed`。
- 凭据：`user://online/session.json`（`token/account_id/nick`），可删除（N02 可撤销）。

### 5.3 `scripts/services/online_farm_bridge.gd`（新增，W03/W04 之间的桥）

- 持有 `online_client` 与 `FarmGame` 副本；`welcome/req_ok` 的快照经 `farm.load_state()` 灌入后发 `snapshot_applied`（farm_world 刷 UI）。
- `now()`：`server_now` + 本地单调流逝（F08 展示锚点）。
- 离线/重连中：`can_submit()==false`，farm_world 据此禁操作并显示状态（F09）。

### 5.4 登录与入口（W02 UI）

- `scripts/ui/online_login_panel.gd`（新增）：邀请码激活（首次）/ 一键登录（有 token）/ 状态与错误文案（§3.3 表）/ "返回主菜单"。服务器地址取 `SettingsStore [online] server_url`（默认 §5.1 常量，设置页 M1 暂不加界面，改配置文件即可）。
- `main_menu.gd`：新增"联机农场"按钮 → 登录面板 → 成功后 `GameFlow.Mode.ONLINE` 进 `farm_world`。
- `game_flow.gd`：新增 `Mode.ONLINE`（静态意图，沿现有模式）。

### 5.5 `farm_world.gd` 分流（W04 核心改造）

- `_ready`：`Mode.ONLINE` 时不读不写 `SaveStore`，等 bridge 快照灌入（加载页/失败回主菜单）；跳过本地 `refresh_market/breeder_settle/_save`（服务器已做）。
- M1 六命令（§4.4 `farm_basic`）的 `_on_*_requested` 处理器改为：在线 → `bridge.request(...)`，等待快照后按 `result/events` 走与本地路径相同的提示/音效；离线 → 原路径不动（回归零变化）。
- **未迁移处理器统一拦截**：其余全部 `_on_*_requested` 在线分支调 `_online_refused(op)`——提示"该功能将在后续版本开放"，绝不落入本地路径（F09 禁止混合两套存档归属）。M2 逐个替换为真命令。
- `_save()`/`_on_plain_save_requested`/`_on_expedition_save_requested`：在线为 no-op + 状态提示"线上进度由服务器实时保存"。
- `_now()`：在线返回 `bridge.now()`。
- 洞窟入口（建筑点击→hub）：在线置灰 + 提示（M3 开放）。

### 5.6 `farm_hud.gd` 能力门控（F09）

- 新增 `set_online_mode(enabled_features: Array)`：状态角标（连接中/在线/重连中/离线）+ 按 features 禁用对应按钮组（置灰 + tooltip）。M1 只开 `farm_basic` 相关（播种/浇水/施肥/收获/收获全部）；M2 逐组放开。单机模式不调用，界面零变化。

## 6. 农场资产入口核销清单（F01～F09 → 测试映射）

| 规划编号 | 入口（UI/路径） | 处理 | 验证 |
| --- | --- | --- | --- |
| F01 | 联机登录→快照→`load_state`；无本地写 | §5.3 | d42/d43 |
| F02 | 地块点击（播种/选种/浇水/施肥/收获）、收获全部、批量重试 | §4.4 `farm_basic` | d42（含 duplicate 重放） |
| F03 | 育种机面板、待领取区、种子回收 | M2 `farm_breeding` + 登录结算 | d44 |
| F04 | 商店（种子/肥料/水壶/扩地/仓库/商店升级） | M2 `farm_shop` | d44 |
| F05 | 市场（出售/拆批/锁定/批量/待领取出售） | M2 `farm_market` | d44 |
| F06 | 制作台（配方/设施升级/目标领取/实例出售/待领取） | M2 `farm_craft` | d44 |
| F07 | 装备仓库/战备格（移动/旋转/整理/弃置/领取/清空/初始套装） | M2 `farm_inventory` | d44 |
| F08 | 服务器时间（生长/市场刷新/育种结算/展示锚点） | §2 决策 3/4 | d42 `--dev-time-shift`、时钟无关断言 |
| F09 | 在线状态角标、离线禁操作、本地档隔离、未迁移入口拦截 | §5.5/§5.6 | d43 |

M2 出口时此表逐项打勾并补 d44 证据链接；规划 T02/T03/T04 的自动化部分在此闭环。

## 7. 测试计划

| 编号 | 脚本 | 覆盖 |
| --- | --- | --- |
| d42 | `tests/d42_online_auth_farm_smoke.gd` + 编排 `tools/m1_local_verify.py` | 双客户端子进程对独立服务器进程：激活→登录→N03 顶替踢出→N04 版本拒绝→N05 限速/畸形包/未认证→各自播种浇水施肥收获→A 试改 B 地块（命令只作用于自己档，天然隔离，断言 B 快照不变）→强杀服务器重启→状态仍在→收据重放 duplicate=true→`--dev-time-shift` 跨成熟收获成功且本机时钟字段从未上传（断言请求体无 now）→快照体积与提交耗时记录 |
| d43 | `tests/d43_online_client_bridge_smoke.gd` | 桥接层对子进程服务器：welcome 灌入 `FarmGame`、`now()` 锚点、断线 `can_submit()==false`、pending 原号重发、重连快照一致、登录面板状态机（非渲染断言）、farm_world 在线分支（模拟 bridge）六命令路由 + `_online_refused` 拦截 + `_save` no-op |
| d44（M2） | `tests/d44_online_farm_commands_matrix.gd` | §4.4 全命令一正一负断言 + §6 表核销输出 + 教程步进 + 登录结算（离线收益） |
| 回归 | `tests/run_regression.*` | 全量本地回归不动（离线路径零变化）；d42/d43/d44 需编排器，按 `m0_*` 先例排除出常规回归、由 `tools/m1_local_verify.py` 驱动 |

映射规划 T 编号：T01（激活/重启/重复登录部分）、T02（双账户隔离·农场子集）、T03（生长与改时钟·农场子集）、T04（重放去重）、T13（版本/异常包子集）。公网双机人工验收在 M1 收尾部署后做并记录（不冒充自动化）。

## 8. 部署（M1 收尾）

- 沿 M0 通道：`tools/m0_deploy.py` 模式（SSH 密钥 + `/opt/farm-m0/`），产物用现有 `Linux Server` 导出预设重建；部署前先 `sqlite3 .backup` 现库（若存在）到本地。
- 运行参数：`--port 31971 --db /opt/farm-m0/data/farm.db --cert/--key <服务器侧>`；**禁止** `--dev`/`--dev-time-shift`（server_main 检测到公网 bind + `--dev` 组合直接拒绝启动）。
- 守护：M1 先沿用 M0 的 nohup 手动方式（O02/systemd 属 M4），部署记录里写明重启步骤。
- 客户端包：`Windows Desktop` 预设 + 内置 `farm_server.crt`；本计划不发正式试玩包（M5），仅开发者本机导出自测。

## 9. 风险与权衡

| 风险 | 对策 |
| --- | --- |
| 全快照体积随仓库/局档增长 | d42 记录基线（M0 实测 PCK 4.2MB、农场档 KB 级，预期 <100KB）；超阈值再裁 expedition 明细或增量 |
| `farm_hud` 1951 行改动失控 | 门控只加 `set_online_mode` 一个入口，不动布局；离线路径零 diff |
| 教程逻辑与 UI 耦合（对话框/引导） | M1 只同步 `tutorial_step` 数值，引导 UI 沿用现状；出现双端语义漂移在 M2 d44 用状态断言兜住 |
| JSON int/float 归一化（历史坑） | 快照往返走 `FarmGame.load_state` 现有归一化；d42 加往返一致性断言 |
| SQLite 单写锁排队 | 玩法频率低（规划 §2）；d42 测量单命令提交耗时，>100ms 再优化（如收据批量） |
| 顶替踢出误伤（网络抖动重连） | kicked 仅在新连接完成 hello 后发生；重连自身不触发（同 token 重放属新连接顶替旧死连接，预期行为） |
| 邀请码泄漏 | 码一次性、只存明文于开发者手中与库内；日志脱敏；账户可 `disabled` |

## 10. 实施顺序

| 步 | 内容 | 提交点 |
| --- | --- | --- |
| M1-a | 协议常量 + server_db + auth_service + server_main 装配（含 --new-invite） | d42 认证段绿 |
| M1-b | farm_service + `farm_basic` 六命令 + 收据 + 服务器时间 | d42 全绿 |
| M1-c | online_client/bridge/登录面板/主菜单入口/GameFlow + farm_world 分流与拦截 + HUD 门控 | d43 绿 + 全量回归绿 |
| M1-d | 部署腾讯云 + 公网自测 + 记录 | testing/ 新增 M1 记录 |
| M2-a | `farm_shop` + `farm_breeding` 命令组 + UI 放开 | d44 段绿 |
| M2-b | `farm_market` 命令组（含登录结算验证） | d44 段绿 |
| M2-c | `farm_craft` + `farm_inventory` 命令组 + 教程步进补齐 | d44 段绿 |
| M2-d | §6 核销表逐项核销 + 全量回归 + 部署 | M2 收尾记录 |

## 11. 实施记录

### 2026-10-03：M1-a/b/c 代码完成（M1-d 部署待做）

**已交付**（本日提交）：

- 服务端：`server_db.gd`（schema v2 + 事务助手）、`auth_service.gd`（邀请/token 哈希/单会话）、`farm_service.gd`（候选副本→同事务落库→换入，`farm_basic` 六命令，收据去重，登录时市场/育种结算，教程与收获统计服务器侧联动）、`server_main.gd` 改写（装配/限速/包纪律/`--new-invite`/`--features -`/`--dev` 公网守卫）；M0 假账户命令退役。
- 客户端：`online_protocol.gd`（共享常量）、`online_client.gd`（WSS 钉扎/重连/pending 原号重发/session 管理）、`online_farm_bridge.gd`（快照灌入/`now()` 锚点/请求串行）、`online_login_panel.gd` + 主菜单"线上农场"入口 + `GameFlow.Mode.ONLINE`；`farm_world` 六命令分流 + 其余入口 `_online_refused()` 拦截 + `_save/_now/_advance_tutorial/_record_harvest/_on_clock_tick` 线上守卫；HUD 在线角标 + 洞窟/房间/战备入口门控；`SettingsStore [online] server_url`。
- 测试：d42（65 项：激活/登录/版本/未认证/限速/顶替/种植浇水施肥收获/隔离/强杀重启/收据重放/req_id 冲突/跨成熟/特性门控）全绿，均延迟 19ms、快照 3.8KB；d43（26 项：激活→快照→命令→farm_world 线上分支→顶替客户端侧→断线门控→重启自动重连续玩→本地档零写入 F09）全绿；自编排（进程内建邀请码 + 子进程服务端），直接进常规回归，无需独立编排器。全量回归 49/49 过，离线路径零变化。

**与计划的偏差（均已实测定型）**：

1. `req_ok` 不设独立 `events` 字段：规则返回值（`result`）本身携带 UI 所需全部信息（收获事件/提示文案），客户端 `_finish_*` 复用同一渲染路径。
2. M1 的 HUD 门控落地为"角标 + 入口拦截 toast"，未做逐按钮置灰：M1 未迁移命令本就全部拦截，逐按钮禁用随 M2 接线时一并做（§5.6 的 features 驱动禁用推到 M2）。
3. 服务器断开前必须给足送达窗口：`put_packet` 的应答要等后续 `poll()` 冲刷，且任何形式的 `disconnect_peer` 都可能丢弃未读数据——实测延迟断开队列（2 秒）+ 优雅关闭后 `version_mismatch`/`kicked` 稳定送达；踢出（给空闲 peer 推包）另需挪到下一帧在派发外执行（pending kicks）。
4. 客户端重连状态机：等待重试计时期间必须无视旧 peer 的 DISCONNECTED/超时上报（尸体每帧上报会把重连时刻无限推后）；入站包须在所有状态读取（否则握手应答死锁）；握手包每连接周期只发一次。

**M1-d 部署与公网自测已完成（2026-10-03 同日）**：Linux 专服导出 → 部署 `/opt/farm-m1`（接管 31971，M0 进程停止、目录原样保留）→ 服务器端生成 5 个邀请码（1 个被自测消耗）→ 公网探针 `tests/m1_public_probe.gd` 三步全过（证书钉扎拒绝 46ms；真实邀请码激活/播种/浇水/重放去重 48～62ms；`pkill -9` 强杀重启后 token 续玩与状态恢复 ~55ms）。详见 [Farm_M1_部署与公网自测_2026-10-03](../testing/Farm_M1_部署与公网自测_2026-10-03.md)。坑：导出包启动必须带 `--server`（漏掉时 boot 进主菜单，headless 表现为零输出不退出）。真人图形界面双机验收留待试玩。**M1 至此代码+部署+公网自测全部关闭。**
