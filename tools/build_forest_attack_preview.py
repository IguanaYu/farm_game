"""把 Godot 实际窗口帧制作成可回看的动画；不重绘游戏素材。"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "screenshots" / "forest_attack_animation"


def gif(name, paths, crop=None, size=(960, 600)):
    frames = []
    for path in paths:
        with Image.open(path) as source:
            frame = source.convert("RGB")
            if crop:
                frame = frame.crop(crop)
            frame = frame.resize(size, Image.Resampling.LANCZOS)
            frames.append(frame)
    frames[0].save(OUT / name, save_all=True, append_images=frames[1:],
                   duration=[33, 33, 34] * (len(frames) // 3) + [33] * (len(frames) % 3),
                   loop=0, optimize=True, disposal=2)


if __name__ == "__main__":
    paths = sorted(OUT.glob("frame_*.png"))
    if len(paths) != 129:
        raise SystemExit(f"Expected 129 captured frames, found {len(paths)}")
    gif("attack_demo.gif", paths)
    gif("melee.gif", paths[9:65], (310, 100, 970, 410), (792, 372))
    gif("archer.gif", paths[60:129], (310, 100, 970, 410), (792, 372))
    for index, name in [(29, "melee_impact.png"), (75, "arrow_flight.png")]:
        with Image.open(paths[index]) as source:
            source.save(OUT / name)
    print("Saved attack_demo.gif, melee.gif, archer.gif and two full-size screenshots")
