"""Собирает content/*.txt и content/hints/*.txt в App/Resources/course.json и проверяет курс."""
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNIT_RE = re.compile(r"^# (\d+) \| (\S+) \| (.+?) \| (.+)$")
TRIM = ".,!?;:„“\"”«»…()–—"   # то же, что ExerciseFactory.trimSet в приложении


def norm(token):
    return token.strip(TRIM).lower()


def tokens(text):
    return [t for t in (norm(w) for w in text.split()) if t]


# ---------- курс ----------

def parse_course(path, units, errors):
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
            tip.append(line[1:].strip())
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


# ---------- подсказки ----------

def parse_hints(path, alignments, tips, errors):
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        where = f"{path.name}:{n}"
        if line.startswith("a "):
            chunks = []
            for part in line[2:].split(" | "):
                if " = " not in part:
                    errors.append(f"{where}: часть без « = »: {part}")
                    break
                sk, ru = (x.strip() for x in part.split(" = ", 1))
                chunks.append((sk, ru))
            else:
                key = tuple(t for sk, _ in chunks for t in tokens(sk))
                alignments[key] = (chunks, where)
        elif line.startswith("h "):
            if " => " not in line:
                errors.append(f"{where}: правило без « => »")
                continue
            text, tip = (x.strip() for x in line[2:].split(" => ", 1))
            tips.setdefault(text, []).append(tip)  # одинаковые задания — по порядку
        elif line and not line.startswith("#"):
            errors.append(f"{where}: непонятная строка")


def is_note(ru):
    return ru.startswith("(") and ru.endswith(")")


def annotate(sentence, chunks, where, errors):
    """Каждому слову предложения — подсказка (перевод части) и номер части."""
    sk_words = []
    queue = [(i, t) for i, (sk, _) in enumerate(chunks) for t in tokens(sk)]
    for word in sentence["sk"].split():
        t = norm(word)
        if not t:
            sk_words.append({"t": word, "h": "", "g": -1})
            continue
        if not queue:
            errors.append(f"{where}: в разборе не хватает слова «{t}»")
            break
        i, expected = queue.pop(0)
        if expected != t:
            errors.append(f"{where}: «{t}» ≠ «{expected}»")
        ru = chunks[i][1]
        sk_words.append({"t": word, "h": ru[1:-1] if is_note(ru) else ru, "g": i})

    available = [(i, t) for i, (_, ru) in enumerate(chunks) if not is_note(ru) for t in tokens(ru)]
    ru_words = []
    for word in sentence["ru"].split():
        t = norm(word)
        match = next((pair for pair in available if pair[1] == t), None)
        if match:
            available.remove(match)
            ru_words.append({"t": word, "h": chunks[match[0]][0], "g": match[0]})
        else:
            ru_words.append({"t": word, "h": "", "g": -1})
    for i, t in available:
        errors.append(f"{where}: слова «{t}» нет в переводе «{sentence['ru']}»")
    sentence["skw"] = sk_words
    sentence["ruw"] = ru_words


def main():
    units, errors = [], []
    for path in sorted((ROOT / "content").glob("*.txt")):
        parse_course(path, units, errors)
    alignments, tips = {}, {}
    for path in sorted((ROOT / "content" / "hints").glob("*.txt")):
        parse_hints(path, alignments, tips, errors)

    used_alignments = set()
    dict_sk, dict_ru = {}, {}
    sk_votes, ru_votes = Counter(), Counter()
    missing_align = missing_tips = 0

    for i, unit in enumerate(units, 1):
        if unit["id"] != i:
            errors.append(f"раздел {unit['id']}: ожидался номер {i}")
        for lesson in unit["lessons"]:
            sks = [w["sk"] for w in lesson["words"]]
            if len(sks) != len(set(sks)):
                errors.append(f"{lesson['id']}: повтор слова в уроке")
            if len(sks) < 6 or len(lesson["sentences"]) < 4:
                errors.append(f"{lesson['id']}: мало слов или предложений")
            for w in lesson["words"]:
                if len(w["sk"].split()) == 1:
                    sk_votes[(w["sk"].lower(), w["ru"])] += 3
            for s in lesson["sentences"]:
                key = tuple(tokens(s["sk"]))
                if key in alignments:
                    chunks, where = alignments[key]
                    used_alignments.add(key)
                    annotate(s, chunks, where, errors)
                    for sk, ru in chunks:
                        if len(tokens(sk)) == 1 and not is_note(ru):
                            sk_votes[(tokens(sk)[0], ru)] += 1
                        if len(tokens(ru)) == 1 and not is_note(ru):
                            ru_votes[(tokens(ru)[0], sk)] += 1
                else:
                    missing_align += 1
            for f in lesson["fills"]:
                if tips.get(f["text"]):
                    f["tip"] = tips[f["text"]].pop(0)
                else:
                    missing_tips += 1

    for (form, ru), _ in sk_votes.most_common():
        dict_sk.setdefault(form, ru)
    for (form, sk), _ in ru_votes.most_common():
        dict_ru.setdefault(form, sk)

    # Подсказки для предложений с пропуском — по словарю форм.
    for unit in units:
        for lesson in unit["lessons"]:
            for f in lesson["fills"]:
                f["w"] = [{"t": w, "h": "" if "___" in w else dict_sk.get(norm(w), ""), "g": -1}
                          for w in f["text"].split()]

    for key in set(alignments) - used_alignments:
        errors.append(f"{alignments[key][1]}: разбор не подходит ни к одному предложению")
    for text, left in tips.items():
        if left:
            errors.append(f"правило к несуществующему заданию: {text}")

    # Узел «Повторение» в конце каждого раздела.
    for unit in units:
        lessons = unit["lessons"]
        words = list({w["sk"]: w for l in lessons for w in l["words"]}.values())
        unit["lessons"].append({
            "id": f"u{unit['id']}r", "title": "Повторение", "review": True, "words": words,
            "sentences": [s for l in lessons for s in l["sentences"]],
            "fills": [f for l in lessons for f in l["fills"]],
        })

    if errors:
        print("\n".join(errors))
        sys.exit(1)
    out = ROOT / "App" / "Resources" / "course.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    course = {"units": units, "dictSk": dict_sk, "dictRu": dict_ru}
    out.write_text(json.dumps(course, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    lessons = sum(len(u["lessons"]) for u in units)
    words = sum(len(l["words"]) for u in units for l in u["lessons"] if not l.get("review"))
    print(f"OK: {len(units)} разделов, {lessons} уроков (вкл. повторения), {words} слов, "
          f"словарь подсказок {len(dict_sk)}/{len(dict_ru)} → {out.name}")
    if missing_align or missing_tips:
        print(f"Без разбора: {missing_align} предложений, без правила: {missing_tips} заданий")


if __name__ == "__main__":
    main()
