# 复核关闭轮（F-03／F-06／F-10）代码执行计划 v0.1

编写日期：2026-10-04。基线：`f9c3393`（D-01 修复后 HEAD，回归 60/60）。

依据：[【重要】d996462 反馈复核](../testing/Farm_反馈复核_d996462_2026-10-02.md) 判定 F-03／F-06／F-10 三项部分完成，并给出关闭标准。经 2026-10-04 复查，三项至今未关闭：

| 项 | 现状证据 |
| --- | --- |
| F-03（P1） | `scripts/ui/room_panel.gd:402-414`：顺序仍是 保存→`confirm_depart()`（写占用＋发回执一体）→保存；第二次保存失败仅显示警告返回，成功回执已发出、主机照常开局。`confirm_depart()` 内占用写入与 `_send(depart_saved)` 绑定在 `scripts/services/session_client.gd:134-147`。d31 场景二 `fail_save=true` 使第一次保存即失败，覆盖不到该路径 |
| F-06（P1） | `tests/run_regression.ps1:12` 与 `tests/run_regression.sh` 白名单仍按错误行数放行（stage6=3、d41=1、d53=1），不检查错误内容；无收集器负向测试。另：f9c3393 只同步了 .sh 的 d53 白名单，.ps1 缺条目——两份收集器已漂移，Windows 版会把 d53 的引擎级 ERROR 误判 FAIL |
| F-10（P2） | `README.md` 第 5 段仍写“F-01～F-06 全部 P1 缺陷清零”；[修复计划](../Godot_第二大阶段_测试反馈修复计划_v0.1.md) §“P1 状态”仍写“全部关闭”；[总计划](../Godot_第二大阶段_农场与合作洞窟_整体开发计划_v0.1.md) 开头仍写“第二大阶段尚未开发”“（尚未实施）”、§16 仍写“已编写完成，尚未实施”，而 2.1～2.9 早已交付 |

## 1. F-03：占用落盘成功才发回执

### 1.1 session_client.gd 拆分

把 `confirm_depart()` 一个调用拆成三步，回执移到落盘之后：

- `prepare_depart() -> Dictionary`：只写内存态（`set_run_occupied(run_id)`＋`active_run_ref`），**不发任何消息**。若已被其他局占用（`occupied_by_run` 非空且不等于本次 `pending_run_id`）返回失败。
- `commit_depart()`：占用已落盘后发送 `depart_saved` 回执（主机收到才开局）。
- `abort_depart(reason)`：准备后落盘失败等场景——回滚内存占用（`clear_run_occupied(run_id)`，仅当局 ID 匹配）、清 `active_run_ref`（仅当匹配）、清 `pending_run_id`，发送 `depart_declined`（主机收到后作废本次出发、可再次发起）。
- `confirm_depart()` 保留为兼容层（prepare＋commit 连做）：`d26_session_smoke`、`d27_recovery_matrix`、`d34_relay_smoke` 直接调用它，不改动这些测试。
- `decline_depart()` 原样保留（第一次保存失败路径继续用）。

### 1.2 room_panel.gd `_on_depart_begin` 顺序重排

```text
保存①（整档）→ 失败：decline_depart，返回
prepare_depart()     → 失败：decline_depart，返回
保存②（占用态）→ 失败：abort_depart（回滚＋拒绝），返回
commit_depart()      → 成功：“已确认出发，等待主机开局……”
```

同时改写 `room_panel.gd:400-401` 的过时注释（现注释声称“任一步失败都不回执”，与旧实现矛盾；新实现使其成真）。

### 1.3 d31 新增场景三：第一次成功、第二次失败

`ProbeRoomPanel` 增加 `fail_save_on_nth`（仅第 N 次调用失败；0=永不）。场景三（端口 31983）断言：

1. 客机 `fail_save_on_nth=2`，主机出发 → 主机 `expedition == null`（不开局）；
2. 客机内存回滚：`occupied_by_run == ""` 且 `active_run_ref == ""`；
3. 主机状态含拒绝原因（与场景二同款断言）；
4. `fail_save_on_nth=0` 后同房间再次出发 → 开局成功、写入新局 ID、`save_calls >= 4`。

## 2. F-06：白名单按内容匹配＋收集器负向测试

### 2.1 两份收集器统一为内容匹配（.ps1 与 .sh 同步改）

判定规则：

1. 输出中任何 `SCRIPT ERROR` 行 → 一律 FAIL（白名单永不覆盖脚本异常）；
2. `^ERROR` 行按测试名对应的模式列表匹配，每模式带上限行数；不匹配任何模式的 ERROR 行 → FAIL；超上限 → FAIL；
3. 退出码非 0 → FAIL（不变）。

白名单模式（2026-10-04 实测原文）：

| 测试 | 模式（子串匹配） | 上限 |
| --- | --- | --- |
| stage6_regression_smoke.gd | `Parse JSON failed` | 3 |
| d41_audio_smoke.gd | `resources still in use at exit` | 1 |
| d53_login_panel_lifecycle.gd | `resources still in use at exit` | 1 |

d41／d53 的报错行数为 1（“N resources”中的 N 在消息文本内，不是行数）。模式化后天然消除 .ps1/.sh 双轨漂移：两份收集器共享同一张模式表（各自语言实现一份，模式字符串逐字相同）。

### 2.2 收集器负向测试：`tools/collector_negative_check.ps1` ＋ `.sh`

沙箱三例（stub godot 可执行按脚本名参数回放预置输出，退出码 0）：

| 例 | stub 行为 | 期望 |
| --- | --- | --- |
| N1 | 白名单测试 stage6 名下输出 3 条 `Parse JSON failed` ＋ **1 条 `SCRIPT ERROR`** | 收集器退出非 0，且 FAIL 指向该测试 |
| N2 | 仅 3 条 `Parse JSON failed` | `REGRESSION_ALL_PASS`，退出 0 |
| N3 | 非白名单测试输出 1 条无关 `ERROR:` | 退出非 0 |

即复核关闭标准“任何 SCRIPT ERROR 都失败＋白名单按内容匹配＋负向测试要求收集器退出非 0”三项全落地。沙箱：临时目录内 `tools/run_regression.*` ＋ `tests/*.gd` 假文件＋stub 可执行，不触碰项目本体。

## 3. F-10：三处文档口径同步

按“功能实现／自动化通过／实机验收”三层改写，历史报告不回写：

1. `README.md` 第 5 段：改为“第二大阶段功能已交付、自动化回归通过（含 2026-10-02 复核遗留 F-03／F-06 于本轮关闭）；线上版 M0～M2＋R0～R7 已实现，实机复验与真人双机公网验收进行中”，并保留指向 docs/testing 的链接。
2. 修复计划 §“P1 状态”：改写为复核后口径——F-01～F-13 在 d996462 复核时 3 项部分完成，F-03／F-06 按复核关闭标准于 2026-10-04 补齐（链接本计划与实施提交），F-10 同步完成；实机验收单列。
3. 总计划开头现状段与 §16：改为“2.1～2.9 已全部实施交付（见 archive 各交付报告）；本文转为阶段基线，现行状态以 docs/README.md 与【主要】联网规划为准”。
4. `docs/README.md` 【重要】复核条目：追加“F-03／F-06／F-10 已于 2026-10-04 按关闭标准处理（见本计划）”。

## 4. 验收

1. `d31_coop_depart_ui_smoke` 全场景过（含新场景三断言）。
2. `tools/collector_negative_check.ps1` 与 `.sh` 三例全过（N1/N3 收集器退出非 0、N2 通过）。
3. 全量回归 `bash tests/run_regression.sh` → `REGRESSION_ALL_PASS`（≥60 项），d26/d27/d34（兼容层）零改动通过。
4. F-10 三处文档不再含“P1 清零／尚未实施”与实际矛盾的表述。

## 5. 非目标与后续

- 不改服务端逻辑与线上（M 系）代码；D-01 修复（f9c3393）只过了 headless 回归，**实机复验（T-A07 后半、T-C01~C07、T-A08）不在本轮**。
- 生产服务器升级（PROTO 2 → v4＋拜访命令组）沿用 [M1 部署记录 §3](../testing/Farm_M1_部署与公网自测_2026-10-03.md) 流程：`--export-release "Linux Server"` 重建三件套 → scp 覆盖 `/opt/farm-m1/` → `pkill -9` → 同参数 nohup 重启（`--tag r7`；DB schema v3 与当前代码一致，玩家档零影响）。本轮代码验收后执行，部署后健康探针确认 `proto=4`。
- 真人双机公网验收（R6 起挂起）：需用户参与，不在本轮。
