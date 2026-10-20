# 森林插图 · 游戏接入与实机测试

2026-10-21，Godot 4.6.1 / OpenGL Compatibility / GTX 1650。以下 14 张均为实际引擎截图。1280×800 为主验收尺寸，另覆盖 1024×640 最小窗口。

入口：运行 `build/Farm.exe`，主菜单右下角打开「测试功能」→「森林预览」→「进入森林试玩」。选择区域和敌人外观，点击物件查看插图，点击「开始战斗」出牌。胜利后搜索遗骸并装包，返回林间后可继续战斗。

本入口沿用独立卡牌试玩的骷髅战斗与掉落规则，只替换场景和敌人外观；屏幕标题明确标注。临时配装、搜索和装包均使用真实领域逻辑，不写入农场或正式探险存档。正式森林的数值、搜索规则、路线及新物品/卡牌定义仍按 P1～P8 推进，章节出发开关继续关闭。

| 区域 | 林间画面 | 实际战斗 |
| --- | --- | --- |
| 林间古道 | [查看](explore_trail.png) | [查看](battle_trail.png) |
| 苔封神殿 | [查看](explore_temple.png) | [查看](battle_temple.png) |
| 空铃废塔 | [查看](explore_tower.png) | [查看](battle_tower.png) |
| 废弃伐木营地 | [查看](explore_camp.png) | [查看](battle_camp.png) |
| 荧沼湿地 | [查看](explore_wetland.png) | [查看](battle_wetland.png) |

- [获胜后的战场与遗骸](corpse_loot.png)
- [实际搜索与领取铜剑后的背包](search_and_pack.png)
- [1024×640 战斗](small_battle.png)
- [1024×640 林间画面](small_explore.png)
- [123 件插图的图鉴与敌人总览](../forest_art_2026-10-20/README.md)

接入范围：`ExpeditionArt` 持有实际 SVG 纹理，背景等比裁切，角色和物件等比缩放，遗骸保留旋转表现。`BattleScreen`、`ExpeditionLootPanel`、背包与搜索格使用登记插图。已存在的五件复用物品立即生效；新增物品及新牌在正式定义落地后按原 ID 自动匹配。未知 ID 或缺图保留原几何回退。

验证：

- `forest_art_smoke.gd`：123 张纹理、尺寸、透明边缘、缺图回退及图鉴最小窗口布局通过。
- `forest_gameplay_art_smoke.gd`：无头运行 119 项检查，窗口渲染运行 133 项检查通过；覆盖首页真实点击、五区切换、23 种敌人外观、43 个物件、出牌获胜、搜索、装包、携带装备续战、最小窗口和正式存档 SHA256 不变。
- 全量 `tests/run_regression.ps1`：74 项、失败 0 项，见 [回归输出](regression.txt)。使用独立临时项目和用户数据目录；项目目录映射包含音频总线和中继工具。测试项目内的客户端信任证书对齐本机自签测试服，原项目证书与服务器私钥未修改。
- Windows `build/Farm.exe` 已重新导出并通过主菜单启动；Godot 通过 `--main-pack build/Farm.exe` 加载实际导出包运行森林流程，119 项检查通过。导出包运行前后正式用户目录 140 个存档／配置文件摘要无变化，见 [导出验证](export_verification.txt)。

复现截图：用带渲染窗口的 Godot 运行 `res://tests/forest_gameplay_art_smoke.gd`。测试会写入本目录。全量规则测试包含主动损坏/重建存档用例，应在隔离用户目录运行。
