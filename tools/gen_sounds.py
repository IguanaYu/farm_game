#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""小小农场·程序化音频资产生成器（音频轮）。

用纯标准库合成全部音效与背景音乐占位（44.1kHz 16bit 单声道 WAV），
不依赖 numpy；全部确定性生成，可反复运行得到相同文件。
用法：python tools/gen_sounds.py   （输出到 assets/sounds/）
正式美术音频就位后可直接替换同名文件，本脚本保留作为占位资产的出处。
"""
import math
import os
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")


def write_wav(name, samples):
    path = os.path.join(OUT_DIR, name + ".wav")
    os.makedirs(OUT_DIR, exist_ok=True)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            s = max(-1.0, min(1.0, s))
            frames += struct.pack("<h", int(s * 32767))
        w.writeframes(bytes(frames))
    print("  %s.wav  %.2fs" % (name, len(samples) / SR))


def silence(dur):
    return [0.0] * int(SR * dur)


def mix(base, add, at=0.0):
    start = int(SR * at)
    if len(base) < start + len(add):
        base.extend([0.0] * (start + len(add) - len(base)))
    for i, v in enumerate(add):
        base[start + i] += v
    return base


def tone(f0, f1, dur, vol=0.4, decay=8.0, harmonics=()):
    """频率从 f0 滑到 f1 的正弦（可叠加谐波 (倍频, 音量)），指数衰减。"""
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t
        phase += 2.0 * math.pi * f / SR
        amp = vol * math.exp(-decay * i / SR)
        s = math.sin(phase)
        for mult, hv in harmonics:
            s += hv * math.sin(phase * mult)
        out.append(s)
    return out


def noise_burst(dur, vol=0.3, decay=10.0, cutoff=0.25, sweep_to=None):
    """简单一阶低通噪声（cutoff 0~1），可从 cutoff 扫到 sweep_to。"""
    import random
    rng = random.Random(20261002)
    n = int(SR * dur)
    out = []
    y = 0.0
    for i in range(n):
        t = i / n
        c = cutoff if sweep_to is None else cutoff + (sweep_to - cutoff) * t
        x = rng.uniform(-1.0, 1.0)
        y += c * (x - y)
        out.append(y * vol * math.exp(-decay * i / SR))
    return out


def fade_in_out(samples, fin=0.004, fout=0.03):
    n = len(samples)
    a = int(SR * fin)
    b = int(SR * fout)
    for i in range(min(a, n)):
        samples[i] *= i / max(1, a)
    for i in range(min(b, n)):
        samples[n - 1 - i] *= i / max(1, b)
    return samples


def build():
    # —— 短音效 ——
    write_wav("ui_click", fade_in_out(tone(950, 700, 0.05, 0.32, 60)))
    write_wav("plant", mix(tone(175, 120, 0.14, 0.5, 16), noise_burst(0.05, 0.18, 26, 0.12)))
    write_wav("water", noise_burst(0.24, 0.42, 9, 0.5, 0.1))
    write_wav("harvest", mix(fade_in_out(tone(520, 520, 0.08, 0.42, 22, ((2, 0.25),))),
                             fade_in_out(tone(700, 700, 0.09, 0.4, 20, ((2, 0.25),))), at=0.06))
    write_wav("coins", mix(fade_in_out(tone(990, 990, 0.08, 0.34, 14, ((2, 0.3),))),
                           fade_in_out(tone(1480, 1480, 0.09, 0.3, 12, ((2, 0.3),))), at=0.05))
    click = tone(950, 700, 0.045, 0.26, 60)
    coin = fade_in_out(tone(1100, 1100, 0.09, 0.34, 13, ((2, 0.3),)))
    write_wav("buy", mix(click, coin, at=0.05))
    knock = lambda: mix(tone(190, 150, 0.07, 0.5, 26), noise_burst(0.02, 0.2, 40, 0.5))
    write_wav("craft", mix(knock(), knock(), at=0.12))
    write_wav("open", fade_in_out(tone(320, 590, 0.13, 0.3, 6), 0.03, 0.06))
    write_wav("warn", fade_in_out(tone(215, 178, 0.18, 0.4, 9, ((2, 0.4),))))
    write_wav("card_play", fade_in_out(noise_burst(0.07, 0.5, 16, 0.85), 0.002, 0.03))
    write_wav("battle_hit", mix(tone(130, 80, 0.1, 0.55, 20), noise_burst(0.03, 0.3, 30, 0.4)))
    arpeggio = silence(0)
    for i, f in enumerate([523, 659, 784, 1047]):
        arpeggio = mix(arpeggio, fade_in_out(tone(f, f, 0.1, 0.34, 12, ((2, 0.2),))), at=0.085 * i)
    write_wav("victory", arpeggio)
    write_wav("defeat", mix(fade_in_out(tone(196, 196, 0.2, 0.34, 7)),
                            fade_in_out(tone(155, 155, 0.26, 0.34, 6)), at=0.18))
    write_wav("move_step", fade_in_out(tone(640, 560, 0.05, 0.28, 40)))
    build_farm_day()


def build_farm_day():
    """背景音乐占位：90 BPM 八小节（C-Am-F-G 各两小节），
    垫弦＋低音＋五声音阶拨弦；段落包络对齐小节边界，循环接缝无爆音。约 21.3 秒。"""
    bpm = 90.0
    beat = 60.0 / bpm
    bar = beat * 4
    total = int(SR * bar * 8)
    out = [0.0] * total
    chords = [
        ("C", [261.63, 329.63, 392.00], 130.81),
        ("Am", [220.00, 261.63, 329.63], 110.00),
        ("F", [174.61, 220.00, 261.63], 87.31),
        ("G", [196.00, 246.94, 293.66], 98.00),
    ]
    for ci, (_, notes, bass) in enumerate(chords):
        seg_start = ci * 2 * bar
        seg_n = int(SR * 2 * bar)
        # 垫弦：小节窗内正弦包络（首尾归零），轻微失谐加厚。
        for f in notes:
            for i in range(seg_n):
                t = i / seg_n
                win = math.sin(math.pi * t) ** 2
                s = 0.085 * win * (math.sin(2 * math.pi * f * (seg_start + i) / SR)
                                   + 0.4 * math.sin(2 * math.pi * f * 1.003 * (seg_start + i) / SR))
                out[int(seg_start * SR) + i] += s
        # 低音：每小节一个根音，拨弦衰减。
        for b in range(2):
            at = seg_start + b * bar
            n = int(SR * bar * 0.95)
            for i in range(n):
                s = 0.12 * math.exp(-2.2 * i / SR) * math.sin(2 * math.pi * bass * (at + i) / SR)
                out[int(at * SR) + i] += s
    # 拨弦旋律：五声音阶（C D E G A），确定性序列，落在拍点上。
    scale = {"C5": 523.25, "D5": 587.33, "E5": 659.26, "G5": 783.99, "A5": 880.00,
             "C6": 1046.50, "B4": 493.88}
    melody = [
        (0, 0, "E5"), (0, 1.5, "G5"), (0, 2.5, "C6"), (0, 3, "A5"),
        (1, 0, "G5"), (1, 2, "E5"), (1, 3, "D5"),
        (2, 0, "A5"), (2, 1, "C6"), (2, 2.5, "E5"), (2, 3.5, "G5"),
        (3, 0, "D5"), (3, 1.5, "E5"), (3, 2, "G5"), (3, 3, "B4"),
        (4, 0, "C6"), (4, 1, "A5"), (4, 2.5, "G5"),
        (5, 0, "E5"), (5, 1.5, "C5"), (5, 3, "D5"),
        (6, 0, "E5"), (6, 1, "G5"), (6, 2, "A5"), (6, 3, "C6"),
        (7, 0, "B4"), (7, 1, "D5"), (7, 2.5, "E5"),
    ]
    for bar_i, beat_i, name in melody:
        at = bar_i * bar + beat_i * beat
        f = scale[name]
        n = int(SR * 0.5)
        for i in range(n):
            s = 0.14 * math.exp(-5.0 * i / SR) * (
                math.sin(2 * math.pi * f * (at + i) / SR)
                + 0.25 * math.sin(2 * math.pi * f * 2 * (at + i) / SR))
            out[int(at * SR) + i] += s
    # 总线轻限幅。
    out = [max(-0.92, min(0.92, s)) for s in out]
    write_wav("farm_day", out)


if __name__ == "__main__":
    print("生成占位音频 → %s" % os.path.normpath(OUT_DIR))
    build()
    print("完成。")
