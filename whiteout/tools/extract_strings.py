#!/usr/bin/env python3
"""Extract every user-facing English string from the GDScript sources.

    tools/extract_strings.py            write locale/strings.pot
    tools/extract_strings.py --check    also report coverage of locale/vi.po (exit 1 if < 100%)
    tools/extract_strings.py --residual list string literals that look like prose but were NOT captured

msgid == the exact English string as it appears in code (GDScript escapes resolved).
Strings are captured by call context (toast / set_objective / say / note / interact /
title_card / show_note / set_prompt / tr / sign ...), by dict key (prompt, locked_msg ...),
by assignment (.text = / .prompt = / .objective =), all of core/items.gd name+desc fields and
all constants of levels/*_text.gd.
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# ---- call contexts -------------------------------------------------------------------------
ANY_ARG = {"toast", "set_objective", "title_card", "show_note", "set_prompt", "tr", "tf",
           "say", "dialogue", "_button", "_label", "_tip", "caption", "hint"}
NOTE_FN = {"note", "_note2"}                    # note(uid, pos, title, body, yaw): args >= 2
INTERACT_FN = {"interact"}            # interact(pos, prompt, action, r): arg 1
SIGN_FN = {"sign"}                    # Props.sign(parent, pos, yaw, text, ...): arg 3
DIALOGUE_FN = {"say", "dialogue"}
DICT_KEYS = {"prompt", "locked_msg", "one_way_msg", "talk_lines", "display_name", "title", "body"}
ASSIGN_RE = re.compile(r"\.(text|prompt|objective)\s*(=|\+=)")
WORLD_FN = {"sign"}
WORLD_HELPERS = {"sign", "_sign", "_block", "_dx", "_dz", "_containment", "label", "_label", "_lbl", "_disconnect"}

SKIP_FILES = ("tools/",)
# strings produced at runtime from non-literals (Game.health_state() etc.)
EXTRA = ["FINE", "CAUTION", "DANGER", "Talk to %s", "Examine %s"]
PROSE_RE = re.compile(r"[A-Za-z]{3,}")


def unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            m = {"n": "\n", "t": "\t", '"': '"', "'": "'", "\\": "\\", "r": "\r"}
            if n in m:
                out.append(m[n])
                i += 2
                continue
            if n == "u":
                out.append(chr(int(s[i + 2:i + 8], 16)) if len(s) >= i + 8 and re.fullmatch(r"[0-9a-fA-F]{6}", s[i + 2:i + 8]) else chr(int(s[i + 2:i + 6], 16)))
                i += 8 if re.fullmatch(r"[0-9a-fA-F]{6}", s[i + 2:i + 8] or "x") else 6
                continue
        out.append(c)
        i += 1
    return "".join(out)


def scan(src):
    """Yield dicts {value, line, ctx, stmt} for every string literal with its context."""
    i, n, line = 0, len(src), 1
    stack = []  # frames: dict(kind, fn, arg, key)
    last_ident = ""
    prev_tok = ""
    prev_str = None  # (value, end_index) of previous string when separated only by '+'
    stmt_start = 0
    results = []
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            if not stack:
                stmt_start = i
            continue
        if c == "#":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c.isspace():
            i += 1
            continue
        if c.isalpha() or c == "_":
            j = i
            while j < n and (src[j].isalnum() or src[j] == "_"):
                j += 1
            last_ident = src[i:j]
            prev_tok = "id"
            i = j
            continue
        if c == "(" or c == "[" or c == "{":
            stack.append({"kind": c, "fn": last_ident if (c == "(" and prev_tok == "id") else "", "arg": 0, "key": None})
            prev_tok = c
            i += 1
            continue
        if c in ")]}":
            if stack:
                stack.pop()
            prev_tok = c
            i += 1
            continue
        if c == ",":
            if stack:
                stack[-1]["arg"] += 1
            prev_tok = ","
            i += 1
            continue
        if c == ":" and stack and stack[-1]["kind"] == "{":
            prev_tok = ":"
            i += 1
            continue
        if src.startswith('"""', i) or c == '"' or c == "'":
            start = i
            if src.startswith('"""', i):
                j = src.index('"""', i + 3)
                raw = src[i + 3:j]
                end = j + 3
            else:
                j = i + 1
                while src[j] != c:
                    j += 2 if src[j] == "\\" else 1
                raw = src[i + 1:j]
                end = j + 1
            val = unescape(raw)
            sline = line
            line += src[i:end].count("\n")
            # dict key detection
            is_key = False
            k = end
            while k < n and src[k] in " \t":
                k += 1
            if stack and stack[-1]["kind"] == "{" and k < n and src[k] == ":" and prev_tok in ("{", ","):
                stack[-1]["key"] = val
                is_key = True
            if not is_key:
                # merge with previous literal joined by '+'
                merged = False
                if prev_tok == "+" and prev_str is not None and not any(ch in src[prev_str[1]:start] for ch in ",)(]["):
                    r = results[prev_str[2]]
                    r["value"] += val
                    merged = True
                if not merged:
                    results.append({"value": val, "line": sline, "stack": [dict(f) for f in stack],
                                    "stmt": src[stmt_start:start], "prev": prev_tok})
                    prev_str = (val, end, len(results) - 1)
                else:
                    prev_str = (val, end, prev_str[2])
            prev_tok = "str"
            i = end
            continue
        if c == "+":
            prev_tok = "+"
            i += 1
            continue
        prev_tok = c
        i += 1
    return results


def classify(r, rel):
    """Return None or ('ui'|'world', fn) when the literal is user-facing."""
    st = r["stack"]
    v = r["value"]
    if not PROSE_RE.search(v):
        return None
    if v.startswith("res://") or v.startswith("user://") or re.fullmatch(r"[a-z0-9_:.]+", v):
        return None
    # innermost call frame
    call = None
    for f in reversed(st):
        if f["fn"]:
            call = f
            break
    if any(f["fn"] in DIALOGUE_FN for f in st):
        return ("ui", "dialogue")
    for f in st:
        if f["kind"] == "{" and f["key"] in DICT_KEYS:
            return ("ui", "dict:" + str(f["key"]))
    if call is not None:
        fn = call["fn"]
        if fn in ANY_ARG:
            return ("ui", fn)
        if fn in NOTE_FN and call["arg"] >= 2:
            return ("ui", "note")
        if fn in INTERACT_FN and call["arg"] == 1:
            return ("ui", "interact")
        if fn in SIGN_FN and call["arg"] == 3:
            return ("world", "sign")
        if fn in WORLD_HELPERS and (re.search(r"[A-Z]{3,}|[A-Z][a-z]+ |\w+ \w+", v)) and "_" not in v:
            return ("world", fn)
        if fn in ("_spawn_ghost",) and call["arg"] == 2:
            return ("ui", "ghost")
        if fn == "set" and call["arg"] == 1 and st[-1]["fn"] == "set" and r["prev"] == "," and re.match(r"[A-Z]", v):
            return ("ui", "set")
    if ASSIGN_RE.search(r["stmt"] + "") or re.search(r"\.(text|prompt|objective)\s*=", r["stmt"].split("\n")[-1] if "\n" in r["stmt"] else r["stmt"]):
        return ("world" if rel.startswith("levels/") else "ui", "assign")
    # fallback: lowercase prose in gameplay scripts (objective strings held in variables etc.)
    if (rel.startswith(("levels/", "ui/", "core/")) or rel.startswith("actors/npc")) and re.search(r"[a-z]{3,} [a-z]{2,}", v) and len(v) > 8 \
            and not v.startswith("shader_type") and not any(f["fn"] in ("push_warning", "print", "push_error", "assert") for f in st):
        return ("ui", "prose")
    if rel == "actors/npc.gd" and v in ("Talk to", "Frozen miner", "Examine"):
        return ("ui", "npc")
    return None


def items_strings():
    out = []
    p = os.path.join(ROOT, "core/items.gd")
    s = open(p, encoding="utf-8").read()
    for m in re.finditer(r'"(name|desc)":\s*"((?:[^"\\]|\\.)*)"', s):
        out.append((unescape(m.group(2)), "core/items.gd", s[:m.start()].count("\n") + 1, "item"))
    return out


def text_file_strings(rel):
    out = []
    s = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    for r in scan(s):
        if PROSE_RE.search(r["value"]) and not r["value"].startswith("res://"):
            out.append((r["value"], rel, r["line"], "text"))
    return out


def collect(residual=False):
    found = {}   # msgid -> list of (file, line, kind)
    resid = []
    for p in sorted(glob.glob(os.path.join(ROOT, "**/*.gd"), recursive=True)):
        rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
        if rel.startswith(SKIP_FILES) or rel == "core/items.gd":
            continue
        if rel.endswith("_text.gd"):
            for v, f, l, k in text_file_strings(rel):
                found.setdefault(v, []).append((f, l, k))
            continue
        src = open(p, encoding="utf-8").read()
        for r in scan(src):
            c = classify(r, rel)
            if c:
                vals = r["value"].split("\n\n") if (rel == "ui/ui.gd" and c[1] == "prose") else [r["value"]]
                for vv in vals:
                    if vv.strip() and PROSE_RE.search(vv):
                        found.setdefault(vv, []).append((rel, r["line"], c[0] + ":" + c[1]))
            elif residual:
                v = r["value"]
                if len(v) > 8 and " " in v and re.search(r"[a-z]{3,} [a-z]{2,}", v) and not v.startswith("res://"):
                    resid.append((rel, r["line"], v))
    for v in EXTRA:
        found.setdefault(v, []).append(("core/game.gd", 1, "extra"))
    for v, f, l, k in items_strings():
        if v:
            found.setdefault(v, []).append((f, l, k))
    return found, resid


def po_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def po_block(key, s):
    if "\n" in s:
        parts = s.split("\n")
        lines = ['%s ""' % key]
        for i, ptxt in enumerate(parts):
            seg = ptxt + ("\n" if i < len(parts) - 1 else "")
            if seg:
                lines.append('"%s"' % po_escape(seg))
        return "\n".join(lines)
    return '%s "%s"' % (key, po_escape(s))


def write_pot(found):
    path = os.path.join(ROOT, "locale/strings.pot")
    out = ['# WHITEOUT: KETTLE FALLS - translation template (generated by tools/extract_strings.py)',
           'msgid ""', 'msgstr ""',
           '"Project-Id-Version: Whiteout Kettle Falls\\n"',
           '"Language: \\n"',
           '"MIME-Version: 1.0\\n"',
           '"Content-Type: text/plain; charset=UTF-8\\n"',
           '"Content-Transfer-Encoding: 8bit\\n"', ""]
    for v in sorted(found, key=lambda x: (found[x][0][0], found[x][0][1])):
        refs = " ".join("%s:%d" % (f, l) for f, l, k in found[v][:3])
        out.append("#: " + refs)
        if "%" in v and re.search(r"%[sdf0-9.]", v):
            out.append("#, c-format")
        out.append(po_block("msgid", v))
        out.append('msgstr ""')
        out.append("")
    open(path, "w", encoding="utf-8").write("\n".join(out))
    return path


def write_po(found, trans, path=None):
    """(Re)write locale/vi.po in .pot order from {msgid: msgstr}. Unknown msgids get an empty msgstr."""
    path = path or os.path.join(ROOT, "locale/vi.po")
    out = ['# Vietnamese (Tiếng Việt) translation for WHITEOUT: KETTLE FALLS',
           '# Glossary and style notes: locale/GLOSSARY.md',
           'msgid ""', 'msgstr ""',
           '"Project-Id-Version: Whiteout Kettle Falls\\n"',
           '"Language: vi\\n"',
           '"MIME-Version: 1.0\\n"',
           '"Content-Type: text/plain; charset=UTF-8\\n"',
           '"Content-Transfer-Encoding: 8bit\\n"',
           '"Plural-Forms: nplurals=1; plural=0;\\n"', ""]
    for v in sorted(found, key=lambda x: (found[x][0][0], found[x][0][1])):
        refs = " ".join("%s:%d" % (f, l) for f, l, k in found[v][:3])
        out.append("#: " + refs)
        if re.search(r"%[sdf0-9.]", v):
            out.append("#, c-format")
        out.append(po_block("msgid", v))
        out.append(po_block("msgstr", trans.get(v, "")))
        out.append("")
    open(path, "w", encoding="utf-8").write("\n".join(out))


def parse_po(path):
    """Minimal .po parser -> {msgid: msgstr}."""
    d = {}
    if not os.path.exists(path):
        return d
    cur = None
    mid, mstr = None, None

    def flush():
        if mid is not None and mstr is not None:
            d[mid] = mstr
    for raw in open(path, encoding="utf-8"):
        raw = raw.rstrip("\n")
        if raw.startswith("#") or not raw.strip():
            if raw.strip() == "" and cur is not None:
                pass
            continue
        m = re.match(r'(msgid|msgstr)\s+"(.*)"$', raw)
        if m:
            if m.group(1) == "msgid":
                flush()
                mid, mstr, cur = unesc_po(m.group(2)), None, "id"
            else:
                mstr, cur = unesc_po(m.group(2)), "str"
            continue
        m = re.match(r'"(.*)"$', raw)
        if m:
            if cur == "id":
                mid += unesc_po(m.group(1))
            elif cur == "str":
                mstr += unesc_po(m.group(1))
    flush()
    return d


def unesc_po(s):
    return re.sub(r'\\(n|t|"|\\)', lambda m: {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}[m.group(1)], s)


def placeholders(s):
    return sorted(re.findall(r"%[-+0-9.]*[sdf]|%%", s))


def main():
    found, resid = collect(residual="--residual" in sys.argv)
    pot = write_pot(found)
    if "--sync" in sys.argv:   # keep translations, add new msgids (empty), drop stale ones
        write_po(found, parse_po(os.path.join(ROOT, "locale/vi.po")))
        print("synced locale/vi.po")
    words = sum(len(v.split()) for v in found)
    print("wrote %s: %d msgids, %d English words" % (os.path.relpath(pot, ROOT), len(found), words))
    if "--residual" in sys.argv:
        for f, l, v in resid:
            print("%s:%d: %s" % (f, l, v[:110].replace("\n", "\\n")))
    if "--check" in sys.argv:
        po = parse_po(os.path.join(ROOT, "locale/vi.po"))
        missing = [v for v in found if not po.get(v)]
        bad = [v for v in found if po.get(v) and placeholders(v) != placeholders(po[v])]
        tags_bad = [v for v in found if po.get(v) and sorted(re.findall(r"\[/?[a-z]+\]", v)) != sorted(re.findall(r"\[/?[a-z]+\]", po[v]))]
        stale = [k for k in po if k and k not in found]
        total = len(found)
        done = total - len(missing)
        print("vi.po coverage: %d / %d = %.1f%%   (%d stale msgids in vi.po)" % (done, total, 100.0 * done / max(1, total), len(stale)))
        trans_words = sum(len(po[v].split()) for v in found if po.get(v))
        print("Vietnamese words: %d" % trans_words)
        for v in missing[:60]:
            print("  MISSING:", v[:100].replace("\n", "\\n"))
        for v in bad:
            print("  PLACEHOLDER MISMATCH:", v[:80].replace("\n", "\\n"), "->", po[v][:80].replace("\n", "\\n"))
        for v in tags_bad:
            print("  BBCODE MISMATCH:", v[:80].replace("\n", "\\n"))
        for v in stale[:20]:
            print("  STALE:", v[:80].replace("\n", "\\n"))
        if missing or bad or tags_bad:
            sys.exit(1)


if __name__ == "__main__":
    main()
