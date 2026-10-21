# 固定主角：草帽小姑娘 · 原人物卡样稿

用户于 2026-10-21 明确以 `screenshots/cute_forest_girl/03_character_and_cards.png` 中的小姑娘为固定主角：棕色双辫、浅黄草帽、粉色丝带、叶芽别针、米色衬衣、绿色背带裙和棕色小靴子。卡面构图可以改变，人物外观必须沿用该基准。

六张卡由同一份主角 SVG 构造生成，姿势、道具和辅助符号分别对应射击、突刺、强射、敲击、守护铃、烟幕。卡面无费用/文字，仍由真实战斗 UI 绘制。

- 主角：`assets/characters/farmer_cute.svg` 为固定草帽小姑娘，保持 farmer 主题 ID 与共享 2D 控件。
- 卡牌：本目录六张 SVG 恢复为该小姑娘版本；新的功能构图样稿另存 `card_readability_v04/`。
- 构造源：`python tools/build_cute_forest_hero.py`；主角与卡牌共享同一个 `hero(pose)`。
- 主角基准与实机：`screenshots/cute_forest_girl/`。`star/`、`farmer_star.svg` 和照片参考截图仅保留为旧实验资料，不是当前主角，也不在试玩中提供切换。
- 捕获与视觉接线检查：`tests/capture_cute_forest_hero.gd`。

足底仍在 200 单位画布的 y=188，主角按 2 倍密度导入，保持现有落地阴影与攻击轴点。原有整片前冲、箭矢、受击和减少动态效果设置继续工作。
