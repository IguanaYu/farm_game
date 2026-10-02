# 联机中继·互联网房间 方案与执行计划 v0.1

日期：2026-10-02
状态：**已实施**——服务端/客户端/测试全部落地，本机全量回归（42 脚本）通过；
待办：腾讯云部署（§8）与两台真机跨网验收（§7.3）。
前提：不上 Steam；服务对象＝朋友内部联机；已有一台公网可达的腾讯云服务器。

## 1. 目标与非目标

**目标**
- 两台不同网络的电脑（各自在 NAT 后）不做任何端口映射，即可联机玩合作洞窟。
- 保留现有局域网 ENet 直连模式，两种方式并存。
- 服务器只做"按房号转发消息"，不理解游戏规则；主机权威模型不变。
- 复用现有可靠性机制：心跳掉线暂停、player_id 重连去重、动作幂等、结算单未决重发、两段式出发事务。

**非目标（本期不做）**
- 专用权威服务器（服务器跑 SessionHost）。
- 账号系统、好友列表、房间列表、跨平台匹配。
- 加密与反作弊加固（内测明文可接受）。
- Steam SDR 通道。

## 2. 总体架构

```
玩家A（主机）                         玩家B（客机）
FarmGame + SessionHost                FarmGame + SessionClient
      │ RelayTransport(主)                  │ RelayTransport(客)
      │  出站 TCP（主动连，无需端口映射）     │  出站 TCP
      ▼                                    ▼
   ┌──────────────────────────────────────────┐
   │  腾讯云中继服务 relay_server.py            │
   │  Python 3 标准库 asyncio，单文件          │
   │  房号 → 两个成员连接，纯转发 JSON          │
   └──────────────────────────────────────────┘
```

- 传输层：**裸 TCP + NDJSON**（一行一条 JSON）。理由：桌面客户端无浏览器兼容需求；
  客户端 Godot 原生 `StreamPeerTCP`、服务端 Python 标准库即可，双端零第三方依赖；
  可用 netcat 手工调试。将来若做 Web 导出，在同一传输抽象下加 WebSocket 实现，不影响游戏层。
- JSON.stringify 输出的控制字符必然转义，消息体内不会出现裸换行，NDJSON 分帧安全。
- 现有 ENet 路径每包本来就是一条完整 JSON（`put_packet(JSON.stringify(...))`），
  与 NDJSON 一比一映射，游戏层消息格式零改动。

## 3. 中继协议（NDJSON over TCP）

**控制消息（连接上的前几条，中继自己消费）**

| 方向 | 消息 | 应答 |
|---|---|---|
| C→S | `{"t":"create_room"}` | `{"t":"room","code":"482913"}` |
| C→S | `{"t":"join_room","code":"482913"}` | `{"t":"joined","code":"482913"}` 或 `{"t":"error","reason":"房间不存在/已满/客机已在线"}` |
| 双向 | `{"t":"_transport_ping"}` | `{"t":"_transport_pong"}`（传输层心跳，不进游戏层） |

**数据消息（进入房间后）**

| 方向 | 消息 | 行为 |
|---|---|---|
| C→S | `{"t":"relay","body":{…游戏层原消息…}}` | 转发给房间内另一成员 |
| S→C | `{"t":"relay","from":1或2,"body":{…}}` | 对端收到，传输层拆包后等同"收到 peer_id=from 的包" |

- 成员编号：创建房间的连接固定 `from=1`（对应 SessionHost 的 peer 1＝主机）；客机 `from=2`。
  客机重连（新 TCP 连接，同一房号）仍拿 2——与现有按 player_id 重连去重逻辑兼容
  （SessionHost 会用新连接覆盖 slot 2 的成员记录）。
- 房号：6 位数字，房间创建即生效；双方都断开 10 分钟后回收；客机槽在线时拒绝第二个 join。

## 4. 服务端设计（relay_server.py，Python 3 标准库单文件）

- asyncio，每连接一个 reader/writer 协程；`rooms: dict[str, Room]`。
- Room：`{code, members: {1: Conn|None, 2: Conn|None}, last_active}`。
- 断线处理：连接断开仅置空槽位、打日志；房间保留 10 分钟供重连；超时回收。
- 限流：每连接令牌桶（默认 50 条/秒，突发 100），超限断开并记日志。
- 心跳：任一方向流量即刷新 last_active；服务端不下推业务数据，无需自身心跳。
  （客户端传输层每 2 秒发 `_transport_ping`，保证 NAT 映射与死连接探测。）
- 日志：create/join/leave/回收/限流事件 + 每分钟一行房间数统计，走 stdout → journald。
- 参数：`--port`（默认 31970）、`--room-ttl-min`、`--rate-per-sec`。
- 运行内存 <50MB，2C2G 轻量服务器可承载数百并发房间；本项目流量为每动作一个 JSON 快照，带宽可忽略。

## 5. 客户端改造（Godot）

### 5.1 传输抽象（新增 3 个文件，scripts/services/）

- `session_transport.gd`（基类，RefCounted）：
  - 主机侧：`open_host_relay(address, port) -> Error`；`get_events() -> Array`（`{kind: message/peer_up/peer_down/link_up/link_down, peer_id, message}`）
  - 客机侧：`open_guest_relay(address, port, code) -> Error`
  - `send(peer_id, dict)`、`broadcast(dict)`（主机）、`poll()`、`close()`
  - 状态：`link_ready()`、`room_code()`（主机创建后供 UI 展示）
- `relay_transport.gd extends session_transport`：`StreamPeerTCP` 实现，NDJSON 分帧
  （累积缓冲按 `\n` 切分），吞掉 `_transport_ping/pong`，每 2 秒心跳，把中继应答映射成事件。
- `enet_transport.gd extends session_transport`：把现 SessionHost/SessionClient 里的
  ENetMultiplayerPeer 逻辑原样搬入（listen/create_client/put_packet/get_packet_peer），
  LAN 行为与现状完全一致。

### 5.2 SessionHost / SessionClient 改动（scripts/services/）

- 成员变量 `peer` 替换为 `transport: session_transport`；
  `listen(farm, port)` 内部建 ENetTransport（LAN），新增 `listen_relay(farm, address, port)`。
- `SessionClient`：`connect_to_host(address, farm, port)` 保持（LAN），
  新增 `connect_relay(code, farm, address, port)`。
- `poll()`：从 `transport.poll()` 取事件分发——`message` 走现有 `_handle(sender, message)`，
  `peer_down` 触发现有掉线标记路径；其余逻辑（裁定、快照、结算单）零改动。
- 中继模式下客机 sender 恒为 2，`sender != 1 → p2` 的判定、成员表、重连覆盖全部按原样工作。

### 5.3 RoomPanel UI（scripts/ui/room_panel.gd）

- 顶部加连接方式选择：「局域网直连」（现 UI 原样）／「互联网房号」。
- 互联网·主机：按钮「创建房间」→ `listen_relay` → 状态行显示 6 位房号＋服务器地址。
- 互联网·客机：房号输入框 → `connect_relay` → 等主机广播房间视图（现有 `_on_room_updated` 复用）。
- 服务器地址：面板一个可编辑输入框＋代码内默认常量（部署后填入公网 IP:31970）。
- 泵点不变：RoomPanel._process 泵主机侧、CoopClientPanel._process 泵客机侧
  （中继模式下主机全程由 RoomPanel 泵，与现状一致——RoomPanel 创建后不销毁）。

### 5.4 主机动作路径

主机自己的动作仍走本地直通 `host_action()`（不过网络），仅结果快照经中继广播——现状逻辑不变。

## 6. 与现有可靠性机制的衔接（全部复用，不改）

| 机制 | 现有实现 | 中继下的表现 |
|---|---|---|
| 掉线检测 | MEMBER_TIMEOUT_MS=2500＋客机 800ms ping | 游戏层 ping 仍经中继转发，超时逻辑照常 |
| 重连 | 按 player_id 去重、欢迎重放快照 | 客机同房号新连接即重连；slot 恒为 2 |
| 动作幂等 | action_log 按 id 去重 | 消息原样转发，不变 |
| 结算单 | 未决登记＋重连补发＋客机幂等回执 | 不变 |
| 主机重启接回 | 局档恢复 attach_resumed_run | 主机重开游戏→重新建房（新房号，需口头告知队友）→客机加入即恢复 |
| 出发事务 | 两段式 depart_begin/depart_saved | 消息转发，不变 |

## 7. 测试计划

1. **d34_relay_smoke.gd**（headless，沿用现有测试框架）：
   - 测试内 `OS.execute` 拉起本地 relay_server.py（127.0.0.1:31999）；
   - 两个 FarmGame 实例分别以 `listen_relay`/`connect_relay` 组网；
   - 跑通：建房→房号→加入→准备→出发→动作→快照镜像（对齐 d26 场景骨架）；
   - 断线恢复：杀客机连接→同房号重连→快照补发、结算单重发（对齐 d27 恢复矩阵子集）。
2. 回归：d26/d27（ENet 路径）不改不改坏；全量 `godot --headless` 测试套件通过。
3. **实机验收清单**（两台不同网络真机）：
   - [ ] 建房→报房号→加入→完整合作局到撤离结算；
   - [ ] 客机断网 30 秒→同房号重连→局继续；
   - [ ] 主机关游戏→重开→新房号告知→恢复局；
   - [ ] 局域网直连模式回归可用；
   - [ ] 房号输错/房间过期给出可读错误。

## 8. 部署与运维（腾讯云 runbook）

1. 安全组放行入站 TCP 31970（来源 0.0.0.0/0）。
2. 上传 `relay_server.py` 到如 `/opt/farm-relay/`。
3. systemd 单元 `farm-relay.service`：`ExecStart=/usr/bin/python3 /opt/farm-relay/relay_server.py --port 31970`，
   `Restart=always`，`DynamicUser=yes`。`systemctl enable --now farm-relay`。
4. 验证：`journalctl -u farm-relay -f` 看启动日志；本机 `echo '{"t":"create_room"}' | nc 服务器IP 31970` 应回房号。
5. 客户端默认服务器地址改为该 IP:31970（RoomPanel 常量＋可编辑）。
6. 巡检：journald 自动轮转；连接数 `ss -tn | grep 31970`；无需数据库。
   注：非 HTTP、非域名、非标端口，不涉及 ICP 备案 [B]。

## 9. 风险与权衡

- **明文传输**：内测可接受；后续可切 TLS（StreamPeerTCP.supports_tls / 自签证书），留传输抽象口子。
- **TCP 队头阻塞**：丢包时快照延迟整体后移；回合制卡牌合作对此无感，实测若差再考虑。
- **快照体积**：整局 JSON 随 log 增长；中继按条转发无上限，如实测超 100KB/条，
  先做 log 滚动截断（保留最近 N 条），增量快照远期再说。
- **房号一次性**：主机重启换房号需口头告知；内测无账号体系，接受。
- **服务器单点**：systemd 自动重启；挂了只影响"新开局"，进行中的局（已建立连接）不中断。
- **限流误伤**：正常双人局远低于 50 条/秒；若快照风暴触发，日志可见再调。

## 10. 工作量与实施顺序

| 步骤 | 内容 | 估时 |
|---|---|---|
| 1 | relay_server.py ＋ 服务器部署 ＋ nc 冒烟 | 0.5~1 天 |
| 2 | session_transport 抽象＋relay/enet 两实现＋SessionHost/Client 接入 | 1~1.5 天 |
| 3 | RoomPanel 双模式 UI | 0.5 天 |
| 4 | d34 headless 测试＋全量回归 | 1 天 |
| 5 | 两台真机跨网验收 | 0.5 天 |

合计约 4 个工作日。步骤 1 完成后即可用 nc 手工验证服务器；步骤 2 完成即可本机 127.0.0.1 全流程联调。

## 11. 实施记录（2026-10-02）

**新增文件**
- `tools/relay_server.py` —— 中继服务（Python 3.6+ 标准库，单文件）。
- `scripts/services/session_transport.gd` —— 传输层基类（事件经 poll() 返回）。
- `scripts/services/relay_transport.gd` —— TCP+NDJSON 中继传输（建房/加入/心跳/断线上报）。
- `scripts/services/enet_transport.gd` —— ENet 局域网传输（原内联逻辑等价搬移）。
- `tests/d34_relay_smoke.gd` —— 中继全链路测试（拉起真实服务器进程）。

**修改文件**
- `scripts/services/session_host.gd` —— peer → transport；新增 listen_relay/relay_room_code/
  relay_error/peer_down 即时掉线路径；裁定与广播逻辑零改动。
- `scripts/services/session_client.gd` —— peer → transport；新增 connect_relay/join_failed。
- `scripts/ui/room_panel.gd` —— 连接方式选择（局域网直连/互联网房号）；服务器地址输入
  并经 user://relay_prefs.cfg 记忆；房号输入与建房展示。

**测试结果（2026-10-02 本机）**
- d34_relay_smoke：20/20 通过（建房房号、加入、出发事务、动作/快照、断线 peer_down、
  同房号重连恢复快照）。
- 全量回归：42 个 headless 脚本全部通过、零脚本错误（含 d26/d27/d29/d31/d32 会话与
  合作 UI 路径；ENet 局域网模式行为不变）。
