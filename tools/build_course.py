"""Собирает content/*.txt в App/Resources/course.json и проверяет курс."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNIT_RE = re.compile(r"^# (\d+) \| (\S+) \| (.+?) \| (.+)$")


def parse(path, units, errors):
    unit = lesson = None
    tip = []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.rstrip()
        where = f"{path.name}:{n}"
        m = UNIT_RE.match(line)
        if m:
            unit = {"id": int(m[1]), "level": m[2], "title": m[3], "subtitle": m[4], "tip": "", "lessons": []}
            units.append(unit)
            tip = []
            lesson = None
        elif line.startswith("## "):
            unit["tip"] = "\n".join(tip).strip()
            lesson = {"id": f"u{unit['id']}l{len(unit['lessons']) + 1}", "title": line[3:].strip(),
                      "words": [], "sentences": [], "fills": []}
            unit["lessons"].append(lesson)
        elif line.startswith("#") or not line:
            continue
        elif line.startswith(">"):
            text = line[1:].strip()
            tip.append(text if text else "")
        elif line[:2] in ("w ", "s "):
            parts = [p.strip() for p in line[2:].split("|")]
            if len(parts) != 2 or not all(parts):
                errors.append(f"{where}: ожидалось «sk | ru»")
                continue
            key = "words" if line[0] == "w" else "sentences"
            lesson[key].append({"sk": parts[0], "ru": parts[1]})
        elif line.startswith("f "):
            parts = [p.strip() for p in line[2:].split("|")]
            if len(parts) != 4:
                errors.append(f"{where}: ожидалось «текст | ответ | варианты | перевод»")
                continue
            text, answer, wrong, ru = parts
            options = [o.strip() for o in wrong.split(",") if o.strip()]
            if text.count("___") != 1:
                errors.append(f"{where}: в тексте должен быть ровно один ___")
            if answer.lower() in (o.lower() for o in options) or len(set(options)) != len(options):
                errors.append(f"{where}: ответ среди неверных вариантов или повтор")
            lesson["fills"].append({"text": text, "answer": answer, "options": options, "ru": ru})
        else:
            errors.append(f"{where}: непонятная строка")


def main():
    units, errors = [], []
    for path in sorted((ROOT / "content").glob("*.txt")):
        parse(path, units, errors)
    for i, unit in enumerate(units, 1):
        if unit["id"] != i:
            errors.append(f"раздел {unit['id']}: ожидался номер {i}")
        for lesson in unit["lessons"]:
            sks = [w["sk"] for w in lesson["words"]]
            if len(sks) != len(set(sks)):
                errors.append(f"{lesson['id']}: повтор слова в уроке")
            if len(sks) < 6 or len(lesson["sentences"]) < 4:
                errors.append(f"{lesson['id']}: мало слов или предложений")
    if errors:
        print("\n".join(errors))
        sys.exit(1)
    out = ROOT / "App" / "Resources" / "course.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"units": units}, ensure_ascii=False, indent=1), encoding="utf-8")
    lessons = sum(len(u["lessons"]) for u in units)
    words = sum(len(l["words"]) for u in units for l in u["lessons"])
    print(f"OK: {len(units)} разделов, {lessons} уроков, {words} слов → {out}")


if __name__ == "__main__":
    main()
