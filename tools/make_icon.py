"""Рисует иконку приложения 1024×1024 (стилизованный герб + звёзды ЕС) и каталог ассетов для Xcode.

    python tools/make_icon.py            — вариант по умолчанию в App/Assets.xcassets
    python tools/make_icon.py preview    — превью всех вариантов в icon-preview.png
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App" / "Assets.xcassets"
ICONSET = ASSETS / "AppIcon.appiconset"
DEFAULT = "shield"

S = 4                      # рисуем в 4 раза крупнее и уменьшаем — гладкие края
SIZE = 1024 * S
EU_BLUE = (0, 51, 153)
EU_BLUE_LIGHT = (24, 86, 196)
GOLD = (255, 204, 0)
RED = (238, 28, 37)
SK_BLUE = (11, 78, 162)
WHITE = (255, 255, 255)


def gradient(top, bottom):
    img = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        t = y / SIZE
        draw.line([(0, y), (SIZE, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def star(draw, cx, cy, r, fill):
    points = []
    for i in range(10):
        angle = -math.pi / 2 + i * math.pi / 5
        radius = r if i % 2 == 0 else r * 0.4
        points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    draw.polygon(points, fill=fill)


def star_ring(draw, cx, cy, ring, r, fill=GOLD):
    for i in range(12):
        a = -math.pi / 2 + i * math.pi / 6
        star(draw, cx + ring * math.cos(a), cy + ring * math.sin(a), r, fill)


def shield_points(cx, top, w, h):
    """Щит: прямой верх, прямые бока, плавное сужение к острию."""
    left, right = cx - w / 2, cx + w / 2
    straight = top + h * 0.45
    pts = [(left, top), (right, top), (right, straight)]
    for i in range(1, 21):            # правая дуга к острию
        t = i / 20
        x = right - (w / 2) * (1 - math.cos(t * math.pi / 2))
        y = straight + (h - (straight - top)) * math.sin(t * math.pi / 2)
        pts.append((x, y))
    for i in range(19, 0, -1):        # левая дуга обратно
        t = i / 20
        x = left + (w / 2) * (1 - math.cos(t * math.pi / 2))
        y = straight + (h - (straight - top)) * math.sin(t * math.pi / 2)
        pts.append((x, y))
    pts.append((left, straight))
    return pts


def double_cross(draw, cx, top, height, fill=WHITE):
    """Двойной крест с расширенными концами (стилизованно)."""
    bar = height * 0.13
    draw.rectangle([cx - bar / 2, top, cx + bar / 2, top + height], fill=fill)
    for y, half in ((top + height * 0.22, height * 0.24), (top + height * 0.50, height * 0.36)):
        draw.rectangle([cx - half, y - bar / 2, cx + half, y + bar / 2], fill=fill)
        for end in (cx - half, cx + half):            # расширения на концах
            draw.rectangle([end - bar * 0.25, y - bar * 0.85, end + bar * 0.25, y + bar * 0.85], fill=fill)
    draw.rectangle([cx - bar * 0.85, top - bar * 0.25, cx + bar * 0.85, top + bar * 0.25], fill=fill)


def coat_of_arms(img, cx, top, w, h):
    """Стилизованный герб: красный щит, белый двойной крест на синих холмах."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(shield_points(cx, top, w, h), fill=255)
    layer = Image.new("RGB", img.size, RED)
    d = ImageDraw.Draw(layer)
    # Три холма: средний выше, на нём стоит крест; тонкая красная щель отделяет вершины.
    r = w * 0.2
    for hx, hy in ((cx - w * 0.34, top + h * 0.77), (cx + w * 0.34, top + h * 0.77), (cx, top + h * 0.69)):
        d.ellipse([hx - r - w * 0.012, hy - w * 0.012, hx + r + w * 0.012, hy + r * 3], fill=RED)
        d.ellipse([hx - r, hy, hx + r, hy + r * 3], fill=SK_BLUE)
    d.rectangle([cx - w, top + h * 0.90, cx + w, top + h * 2], fill=SK_BLUE)
    double_cross(d, cx, top + h * 0.10, h * 0.60)
    img.paste(layer, (0, 0), mask)
    # белая окантовка щита
    outline = Image.new("L", img.size, 0)
    od = ImageDraw.Draw(outline)
    od.line(shield_points(cx, top, w, h) + [shield_points(cx, top, w, h)[0]], fill=255, width=int(w * 0.035), joint="curve")
    img.paste(Image.new("RGB", img.size, WHITE), (0, 0), outline)


def variant_shield():
    """Синий фон ЕС, кольцо из 12 звёзд, в центре — герб."""
    img = gradient(EU_BLUE_LIGHT, EU_BLUE)
    d = ImageDraw.Draw(img)
    c = SIZE / 2
    star_ring(d, c, c, SIZE * 0.385, SIZE * 0.048)
    coat_of_arms(img, c, SIZE * 0.29, SIZE * 0.40, SIZE * 0.47)
    return img


def variant_bubble():
    """Синий фон со звёздами, белое облачко-реплика с гербом внутри — «язык + Словакия»."""
    img = gradient(EU_BLUE_LIGHT, EU_BLUE)
    d = ImageDraw.Draw(img)
    c = SIZE / 2
    star_ring(d, c, c, SIZE * 0.40, SIZE * 0.042)
    box = (SIZE * 0.22, SIZE * 0.24, SIZE * 0.78, SIZE * 0.70)
    d.rounded_rectangle(box, radius=SIZE * 0.12, fill=WHITE)
    d.polygon([(SIZE * 0.33, SIZE * 0.66), (SIZE * 0.29, SIZE * 0.80), (SIZE * 0.45, SIZE * 0.69)], fill=WHITE)
    coat_of_arms(img, c, SIZE * 0.29, SIZE * 0.27, SIZE * 0.33)
    return img


def variant_flag():
    """Триколор (белый-синий-красный) с гербом и короной из звёзд ЕС сверху."""
    img = Image.new("RGB", (SIZE, SIZE), WHITE)
    d = ImageDraw.Draw(img)
    d.rectangle([0, SIZE / 3, SIZE, SIZE * 2 / 3], fill=SK_BLUE)
    d.rectangle([0, SIZE * 2 / 3, SIZE, SIZE], fill=RED)
    c = SIZE / 2
    for i in range(12):                    # дуга звёзд над гербом
        a = math.pi + (i + 0.5) * math.pi / 12
        star(d, c + SIZE * 0.36 * math.cos(a), SIZE * 0.52 + SIZE * 0.36 * math.sin(a), SIZE * 0.035, GOLD)
    coat_of_arms(img, c, SIZE * 0.27, SIZE * 0.42, SIZE * 0.50)
    return img


VARIANTS = {"shield": ("Герб в звёздах ЕС", variant_shield),
            "bubble": ("Облачко с гербом", variant_bubble),
            "flag": ("Флаг с гербом", variant_flag)}


def render(name):
    return VARIANTS[name][1]().resize((1024, 1024), Image.LANCZOS)


def preview(path):
    tile, pad = 300, 30
    sheet = Image.new("RGB", (pad + len(VARIANTS) * (tile + pad), tile + 90), (245, 245, 247))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("segoeuib.ttf", 26)
    except OSError:
        font = ImageFont.load_default()
    for i, (name, (title, _)) in enumerate(VARIANTS.items()):
        icon = render(name).resize((tile, tile), Image.LANCZOS)
        mask = Image.new("L", (tile, tile), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, tile, tile], radius=tile * 0.22, fill=255)  # как на iPhone
        x = pad + i * (tile + pad)
        sheet.paste(icon, (x, pad), mask)
        d.text((x + tile / 2, tile + pad + 28), f"{i + 1}. {title}", fill=(30, 30, 30), font=font, anchor="mm")
    sheet.save(path)
    print("OK:", path)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        preview(Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "icon-preview.png")
        return
    name = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    ICONSET.mkdir(parents=True, exist_ok=True)
    render(name).save(ICONSET / "icon.png")
    (ICONSET / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    print("OK:", ICONSET / "icon.png", f"({VARIANTS[name][0]})")


if __name__ == "__main__":
    main()
