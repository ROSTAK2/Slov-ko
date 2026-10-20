"""Синтезирует короткие звуки интерфейса (WAV, 44.1 кГц) в App/Resources/Sounds."""
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "App" / "Resources" / "Sounds"
RATE = 44100


def tone(freq, dur, volume=0.5, decay=6.0, harmonics=((1, 1.0), (2, 0.25), (3, 0.08)), sweep_to=None):
    """Нота с мягкой атакой и экспоненциальным затуханием."""
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq if sweep_to is None else freq + (sweep_to - freq) * (i / n)
        phase += 2 * math.pi * f / RATE
        attack = min(1.0, t / 0.006)
        env = attack * math.exp(-decay * t)
        sample = sum(a * math.sin(k * phase) for k, a in harmonics)
        out.append(volume * env * sample)
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


def mix(*tracks):
    length = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(length)]


def offset(track, dur):
    return silence(dur) + track


def save(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * scale * 32767)) for s in samples))
    print(f"{name}.wav  {len(samples) / RATE:.2f} с")


def main():
    # Правильно: светлый восходящий «динь-дилинь» (A5 → E6).
    save("correct", mix(tone(880, 0.25, 0.45, 9), offset(tone(1318.5, 0.45, 0.5, 6), 0.09)))

    # Ошибка: мягкий нисходящий низкий звук, без резкости.
    soft = ((1, 1.0), (2, 0.15))
    save("wrong", mix(tone(311, 0.22, 0.45, 8, soft), offset(tone(233, 0.4, 0.5, 6, soft), 0.13)))

    # Конец урока: арпеджио до мажор и аккорд.
    notes = [523.25, 659.25, 783.99]
    parts = [offset(tone(f, 0.35, 0.4, 7), i * 0.11) for i, f in enumerate(notes)]
    chord = [offset(tone(f, 1.1, 0.28, 2.6), 0.36) for f in (523.25, 659.25, 783.99, 1046.5)]
    save("complete", mix(*parts, *chord))

    # Пара найдена / нажатие: короткий «поп».
    save("pop", tone(620, 0.09, 0.5, 30, ((1, 1.0),), sweep_to=980))

    # Серия правильных ответов: три быстрые восходящие ноты.
    save("combo", mix(*[offset(tone(f, 0.22, 0.38, 10), i * 0.07) for i, f in enumerate((987.77, 1174.66, 1567.98))]))


if __name__ == "__main__":
    main()
