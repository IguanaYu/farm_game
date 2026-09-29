# farm 低多边形美术

- `farm_asset_pack/`：33 个独立资产。`glb/` 是 3D 模型，`sprites/` 是透明背景的 2D 图片，`farm_asset_library.blend` 是可编辑资源库。详细清单见其中的 `README.md` 和 `manifest.json`。
- `showcase/`：之前展示的六块地农场场景，含 `.blend` 文件、两张预览图和生成脚本。

`farm` 目前还没有 `project.godot`。建立工程后，二维界面可以优先使用 `farm_asset_pack/sprites/` 中的图片；需要 3D 场景时可导入相应的 GLB。胡萝卜和六位客人的形象目前是美术草案，待玩法设计确定后可替换。

完整图片文件清单与以后导出时的命名、规格约定见 `EXPORT_GUIDE.md`。
