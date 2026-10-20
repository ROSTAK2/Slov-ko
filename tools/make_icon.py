"""Рисует иконку приложения 1024×1024 и каталог ассетов для Xcode."""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App" / "Assets.xcassets"
ICONSET = ASSETS / "AppIcon.appiconset"
SIZE = 1024
BLUE_TOP, BLUE_BOTTOM = (47, 128, 255), (20, 88, 214)
RED = (229, 72, 77)


def font(size):
    for name in ("seguibl.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    img = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):  # вертикальный градиент
        t = y / SIZE
        draw.line([(0, y), (SIZE, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BLUE_TOP, BLUE_BOTTOM)))

    # Облачко-реплика
    box = (170, 220, 854, 760)
    draw.rounded_rectangle(box, radius=170, fill="white")
    draw.polygon([(300, 720), (250, 880), (440, 750)], fill="white")

    text = "Sk"
    f = font(330)
    left, top, right, bottom = draw.textbbox((0, 0), text, font=f)
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    draw.text((cx - (right - left) / 2 - left, cy - (bottom - top) / 2 - top), text, font=f, fill=BLUE_BOTTOM)

    # Красная точка — как у талисмана в приложении
    draw.ellipse((770, 150, 900, 280), fill=RED, outline="white", width=18)

    ICONSET.mkdir(parents=True, exist_ok=True)
    img.save(ICONSET / "icon.png")
    (ICONSET / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    print("OK:", ICONSET / "icon.png")


if __name__ == "__main__":
    main()
