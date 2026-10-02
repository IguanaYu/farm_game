# 音频轮：方案与执行计划 v0.1

编写日期：2026-10-02。状态：**已实施，d41 覆盖，待实机听感验收**（实施记录见 §7）。
定位：接上 d37 铺好的音频总线（Master/Music/SFX）与设置滑条，交付第一版全量音效与背景音乐占位。

## 1. 目标与非目标

**目标**：农场主循环全套音效（播种/浇水/施肥/收获/买/卖/回收/失败）、建筑点击与领取、战斗出牌与胜负、农场背景音乐循环；音量完全走既有设置（滑条持久化＋总线分贝＋0 静音）。

**非目标**：正式美术级音频（当前为程序化合成的占位资产）、战斗独立 BGM、地图移动/洞窟环境音（`move_step` 资产已备未接）、混响/EQ 等效果链。

## 2. 资产（tools/gen_sounds.py 程序化生成，可复现，同名可替换）

`assets/sounds/*.wav`（44.1kHz 16bit 单声道）：14 个音效（ui_click/plant/water/harvest/coins/buy/craft/open/warn/card_play/battle_hit/victory/defeat/move_step）＋ 1 首背景音乐 `farm_day`（90 BPM 八小节 C-Am-F-G，垫弦＋低音＋五声音阶拨弦，约 21.3 秒，小节对齐循环无爆音）。生成器入库，正式音频到位后直接替换同名文件。

## 3. 播放层（scripts/services/audio_kit.gd，无 autoload）

- `play(host, id)`：宿主节点下挂一次性 `AudioStreamPlayer`（SFX 总线，命名 `Sfx_<id>`），finished 自毁；缺文件只 push_warning 不建节点。
- `play_music(host, id, volume_db=-9)`：常驻播放器（Music 总线，命名 `MusicPlayer`，每宿主一个，重复调用先替换旧的），finished 后重播实现循环；`stop_music` 停播断流引用后 queue_free。
- **headless 抑制**：无头（测试/CI）下哑音频驱动播不出声，且成功启动的播放会在退出期报“resources still in use”，污染所有场景级测试的 ERROR 口径——`play/play_music` 在 `DisplayServer.get_name()=="headless"` 时直接返回 null；`headless_override` 供测试显式打开。
- 流缓存 `static _streams`＋`clear_cache()`（测试退出前清引用）。

## 4. 接线点

| 场景 | 位置 | 音效 |
| --- | --- | --- |
| 进农场 | `farm_world._ready` 末尾 | farm_day 循环 |
| 点建筑 | `farm_world._on_building_input` | ui_click |
| 播种/浇水/施肥 | `_on_plant_seed_requested` / `_on_water_requested` / `_on_fertilize_requested` | plant / water / water（失败 warn） |
| 收获（单个/一键） | `_do_harvest` / `_on_harvest_all_requested` | harvest（无成熟 warn） |
| 买种子/肥料/商店升级 | 对应 `_on_buy_*` / `_on_upgrade_shop_requested` | buy（失败 warn） |
| 出售/回收 | `_on_sell_*` / `_on_recycle_seed_requested` | coins |
| 领取待领取 | `_on_claim_pending_requested` | open（放不下 warn） |
| 出牌成功 | `battle_screen` 出牌本地裁定分支 | card_play |
| 战斗胜负 | `battle_screen._flash_events` outcome 事件 | victory / defeat |

音量链路不变：`SettingsStore.set_volume/apply_volumes`（滑条→总线分贝，0 静音），主菜单启动即应用。

## 5. 测试

`tests/d41_audio_smoke.gd`（26 断言）：总线存在；15 个资产全部可加载为 `AudioStreamWAV`；一次性播放器总线/流/命名/缺文件不建节点；音乐常驻、重复替换、finished 重播、stop 标记删除；音量设置往返与 `apply_volumes` 后总线分贝一致、0 静音/恢复。隔离备份恢复 `user://settings.cfg`。

## 6. 风险与已知限制

- 占位音色为合成音，实机听感需用户验收；不满意可改 `gen_sounds.py` 参数重生成或直接替换文件。
- 回归白名单新增 `d41_audio_smoke.gd = 1`：无头 dummy 驱动退出期的引擎级“resources still in use”提示（两个实际播放过的流被驱动侧持有至资源清理之后），脚本侧无法回收，实机无此问题。
- headless 抑制意味着 CI 里听不到也不验播；播放行为的回归只覆盖节点结构/状态，真实听感只能实机验收。

## 7. 实施记录（2026-10-02）

- 新增 `tools/gen_sounds.py`、`assets/sounds/`（15 wav＋.import）、`scripts/services/audio_kit.gd`、`tests/d41_audio_smoke.gd`；修改 `farm_world.gd`（15 处接线）、`battle_screen.gd`（2 处）、回归收集器 ×2（白名单）。
- 实施偏差与坑：①farm_world 自动播音乐会让所有进农场场景的测试背上退出期 ERROR——最终以“headless 抑制播放＋测试 override”解决；②同名 MusicPlayer 替换期间 `get_node` 会命中待删旧节点，测试改用返回值引用；③`stop_music` 原来只 queue_free，播放中的流引用要 stop＋置空后才释放。
- d41 单测 26 断言全过；全量回归 47 项全过（`REGRESSION_ALL_PASS`，d41 白名单 1 条）。证据 `docs/testing/audio_round_d41/`。
- 实机验收待用户：进农场听 BGM 循环接缝、各操作音效音色与音量平衡、0 音量静音、战斗胜负音。
