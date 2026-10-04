# 合并路线 R7：好友拜访系统 代码执行计划 v0.1

编写日期：2026-10-04。状态：**已定稿，开始实施**。

依据：[合并路线图](Godot_合并路线图_联网与多场景_v0.1.md) R7 行；[多场景设计稿 v0.4](../design/Farm_多场景与空间交互_设计稿_v0.4.md) §7（拜访）。

## 1. 目标与非目标

**出口**（路线图 R7）：

> 访客不触发主人收获/消费/买卖；读失败有原因；自家与好友资产隔离。

**范围基线（稿 §7 功能边界）**：第一步只做**开放参观**——邻里地址簿（四态）、好友院子（复用农场模板只读）、好友小屋（切墙内景：主人形象/茶桌/留言板/门窗）。帮浇水、礼物、邀请下洞留后续。

**非目标：**
- 好友关系表/权限管理（首版=试玩池内所有账户互为"邻里"，主人家园默认开放；设计稿 §7"建议首期采用主人主动开放、好友身份访问"——首版以服务器配置默认开放落地，账户级开关留后续）。
- 留言自由输入/聊天/通知（固定欢迎语模板）。
- 单机模式拜访（线上专属功能）。

## 2. 协议扩展（v4）

新增特性组 `visit`：

| op | args | 语义 | 错误 |
| --- | --- | --- | --- |
| `visit.list` | `{}` | 邻里地址簿：所有其他账户条目（account_id/nick/在线/开放状态/上次拜访标记由客户端本地记） | — |
| `visit.snapshot` | `{account_id}` | 目标账户只读家园视图（farm_state 全量快照 + owner 概要） | `visit_closed`（未开放）/`account_missing` |

推送：无（只读）。PROTO_VERSION 3→4。

## 3. 服务端（scripts/server/visit_service.gd 或并入 room_service 旁挂）

- `visit.list`：查 accounts 表全量（排除自己；试玩规模 ≤10 直接全量，分页留真实需求）+ auth.has_session 在线态 + `visits_open` 配置（server_main `--visits-open/--visits-closed` 开关，默认开放）。
- `visit.snapshot`：加载目标账户 farm_state（读库不改库——**绝不经过 farm_service 的写穿 runtime**，纯 SELECT + JSON 解析）；返回 `{"owner": {account_id, nick}, "farm": state}`。
- 只读保证：无写路径、无收据副作用（读命令不 INSERT receipt——与 farm 读操作口径一致）。

## 4. 客户端

1. **bridge**：`visit_list()/visit_snapshot(account_id)` + 拜访模式状态（`visiting: Dictionary`——空=未拜访）。
2. **地址簿 OnlineVisitPanel**（信箱/小桥/邻里房屋点击打开，替换 R3 占位提示）：条目列表（昵称/在线/开放态）、点击开放条目 → `visit.snapshot` → 进院。
3. **院子 VisitYard**：地点 "visit_yard"——复用农场 3D 构建函数的只读变体（`_build_visit_yard(farm_state)`：地块按 owner 状态渲染、无点击操作、房名牌=主人昵称）；房子点击 → 小屋；花藤院门点击 → 回农场（router.go_back 到 farm）。
4. **小屋 VisitHouse**：地点 "visit_house"——切墙小内景（暖木+主人形象占位模型+茶桌+留言板+门+窗）；留言板显示"主人 X 的留言：欢迎来坐坐（固定模板）"；门/窗点击 → 回院子。
5. **资产隔离**：拜访模式 hud 全门控——`farm_hud.set_visiting(true)` 复用 `_online_blocked` 式拦截（提示"拜访中不能操作主人的农场"）；返回自己农场后恢复。地块/建筑 input 处理器在拜访地点不接线（只建非交互展示）。
6. **拜访回归自家**：router 栈：farm → visit_yard → visit_house；院门 go_back 两级或直接回 farm（`switch_to("farm", false)` 清栈——稿 §7"换朋友需回农场重开地址簿"）。

## 5. 测试（d52）

`tests/d52_visit_smoke.gd`（子进程服务器 + 双账户）：
1. 协议：visit.list 条目含对方账户/在线态；visit.snapshot 返回对方 farm（金币/地块数与 d46 造的数据一致）；自己不在列表；`--visits-closed` 服务器 → list 全关 + snapshot 拒 visit_closed。
2. 隔离红线：拜访期间对目标 farm_state 的任何 farm.*/run.* 命令仍只作用于自己（A 拜访 B 后 farm.harvest 只影响 A——快照断言）；visit.snapshot 不产生收据（重放无 duplicate）。
3. 客户端：地址簿面板渲染（headless）；进入 visit_yard 地点（结构与只读：地块节点存在且 input_ray_pickable=false）；进小屋（留言板文案含主人昵称）；院门回农场后 hud 门控解除。
4. 回归：全量 58 项零变化。

## 6. 实施顺序

| 步 | 内容 | 提交点 |
| --- | --- | --- |
| R7-a | 协议 v4 + visit.list/snapshot + 配置开关 | d52 段1/2 |
| R7-b | 地址簿面板 + 院子/小屋地点 + hud 门控 + 入口接线 | d52 段3 + 回归绿 |

## 7. 风险

| 风险 | 对策 |
| --- | --- |
| 拜访地点残留可操作入口 | 院子/小屋构建走独立函数，不接线任何 `_on_*_input`；d52 断言 pickable=false |
| visit.list 泄露信息（试玩外场景） | 首版封闭试玩池口径（§1 已声明）；分页/关系表留真实需求 |
| PROTO 4 拒旧客户端 | 与 M3 同口径（version_mismatch 属预期升级路径） |

## 8. 维护

完成后更新本文件状态与[合并路线图](Godot_合并路线图_联网与多场景_v0.1.md) §0；偏差记录在本文件末尾。
