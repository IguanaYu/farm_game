# 森林纸片攻击动画样稿

实际 Godot 窗口以固定 30 FPS 逐帧录制，原始画面 1280×800。

- `attack_demo.gif`：真实攻击牌挥砍 → 敌人真实回合射箭。
- `melee.gif` / `archer.gif`：两个动作的独立近景。
- 入口：首页 → 森林预览 → 进入森林试玩 → 攻击动画样稿。
- 单场景继续使用森林风格校准样稿；不替换全部区域或改动正式森林规则。
- 弓手外观沿用骷髅样例数值。箭矢是外观动作，不表示新增了射程规则。
- 当前使用整张纸片的位移、转动、受击回弹，加独立武器和箭矢；尚未拆手臂做骨骼拉弓。

验证：`capture_forest_attack_animation.gd` 检查真实出牌/敌方回合、状态不被动画修改、点击框不移动、取消后恢复原图、减少动态效果设置；15 项通过。已有森林玩法 smoke 119 项通过。

复现（请使用隔离 user:// 的 QA 工程）：

```powershell
godot --path <QA工程> --rendering-method gl_compatibility --fixed-fps 30 --script res://tests/capture_forest_attack_animation.gd
python tools/build_forest_attack_preview.py
```
