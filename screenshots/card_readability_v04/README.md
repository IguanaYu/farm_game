# 三张卡牌识别度样稿

- `01_color_and_small_sizes.png`：三张彩色大图、128×80 实际卡图大小、64×40 彩色/灰度对照。
- `02_grayscale_compositions.png`：每张 A/B 两种构图对照。
- `03_in_game_before.png` / `04_in_game_study.png`：同一场战斗前后对照，只替换射击、守护铃、烟幕的纹理。
- `05_small_window_study.png`：真实下一回合的 1024×640 小窗口。
- 三张 `forest_*.png`：独立卡图大图。

这三张卡图先作独立视觉样稿，未替换游戏包中的原有人物卡。另按用户贴图要求，把主角恢复为草帽双辫小姑娘并更新游戏包；新卡图里的帽子与衣袖也沿用这一外观。卡牌规则不变，是否足够好认还需人工评判。

复现：先 `python tools/build_card_readability_study.py`，由 Godot 导入，然后带真实渲染运行 `tests/capture_card_readability_study.gd`。测试不会修改正式存档，应继续使用隔离 user:// 的 QA 工程。
