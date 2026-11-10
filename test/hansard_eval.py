"""Score a parser output CSV against a gold standard CSV, by aligning their text word by word.

Usage: python3 -I hansard_eval.py <gold.csv> <output.csv> [--json] [--conventions]

Both files are read by column name (older gold files' names are mapped to the current ones), then
each is flattened into a word stream where every word carries its row's attributes. The two streams
are aligned with difflib, and the aligned words are compared:

  text_recall      share of gold words found in the output
  text_precision   share of output words found in the gold standard
  speaker_acc      aligned words whose row has the gold name.id
  type_acc         aligned words whose row has the gold row type (speech, interjection, ...)
  boundary_p/r/f1  row starts in the output that match row starts in the gold standard
  type_confusion   gold type -> output type counts, for the aligned words

  nonspeech_p/r    of words the output (gold) calls non-speech, the share the gold (output) also does

--conventions recodes the gold standard to the definitional decisions of 2026-11-09 before scoring
(PSSConvert#93: presiding officers' words are speech; #94: collective voices are interjections with the ids
OPPOSITION, GOVERNMENT or MEMBERS; #96: documents "read as follows" or incorporated are non-speech), and
counts UNKNOWN as N/A (#95). Judgement calls (what is procedural,
what was incorporated) are not recoded: the gold standard decides those.

Because it compares words rather than rows, it counts merged and split rows and misattributed
text, which a row-by-row comparison hides.
"""
import collections
import csv
import difflib
import json
import re
import sys

csv.field_size_limit(10**9)
RENAME = {"stage_direction_flag": "non_speech_flag", "speech_no": "speaker_no"}
TYPES = ["question_flag", "answer_flag", "interjection_flag", "speech_flag",
         "petition_flag", "quote_flag", "motionnospeech_flag"]
NA = {"", "N/A", "NA", "nan"}
WORD = re.compile(r"[A-Za-z0-9]+")
SPOKEN = ["question_flag", "answer_flag", "interjection_flag", "speech_flag"]
OFFICE = re.compile(r"(?i)\b(?:acting\s+|temporary\s+)?(?:deputy\s+)?(?:speaker|president|chair(?:man)?)\b")
INCORPORATED = re.compile(r"(?i)^(?:the\s+)?(?!petition)(?:\w+\s+){0,3}(?:read|reads|incorporated)\s+as\s+follows|^\(?(?:speech|quote|document|table)\s+incorporated\)?")
# inside a gold row that also holds the speaker's own words: the document starts at the phrase
INCORPORATED_IN_ROW = re.compile(r"(?i)\b(?:the\s+)?(?!petition)(?:\w+\s+){0,3}(?:read|reads)\s+as\s+follows")
NOT_PRESIDING = re.compile(r"(?i)vice[\s-]*president|executive\s+council")
COLLECTIVE = re.compile(r"(?i)^(?:an?\s+|some\s+|several\s+|other\s+)?(?:hono(?:u)?rable\s+|hon\.?\s+)?(?:(opposition|government)\s+)?(?:members?|senators?|supporters?)(?:\s+of\s+the\s+(opposition|government))?(?:\s+interjecting)?[\s.:,—–-]*$")


def recode(r):
    """The 2026-11-09 definitional conventions, applied to a gold row"""
    nid, name = norm_id(r.get("name.id")), (r.get("name") or "").strip()
    spoken = any((r.get(k) or "").strip() == "1" for k in SPOKEN)
    if spoken and nid in ("10000", "N/A") and OFFICE.search(name) and not NOT_PRESIDING.search(name):
        for k in SPOKEN:
            r[k] = "0"
        r["speech_flag"] = "1"
    m = COLLECTIVE.match(name)
    if spoken and nid == "N/A" and m:
        side = (m.group(1) or m.group(2) or "").lower()
        r["name.id"] = {"opposition": "OPPOSITION", "government": "GOVERNMENT"}.get(side, "MEMBERS")
        for k in SPOKEN:
            r[k] = "0"
        r["interjection_flag"] = "1"
    if spoken and INCORPORATED.search((r.get("content") or "").strip()):
        for k in TYPES:
            r[k] = "0"
        r["non_speech_flag"] = "1"
    return r


def norm_id(v):
    v = (v or "").strip()
    if v in NA or v.upper() == "UNKNOWN":
        return "N/A"
    try:  # 9e+04 vs 9E4 and similar spreadsheet damage
        f = float(v)
        if f.is_integer() and "e" in v.lower():
            return v.upper().replace("+0", "").replace("+", "")
    except ValueError:
        pass
    return v.upper()


def row_type(r):
    t = [k[:-5] for k in TYPES if (r.get(k) or "").strip() == "1"]
    if len(t) > 1:
        return "+".join(t)
    if t:
        return t[0]
    return "nonspeech" if (r.get("non_speech_flag") or "").strip() == "1" else "none"


def stream(path, conventions=False):
    words, attrs, starts = [], [], []
    with open(path, encoding="utf-8-sig", errors="replace", newline="") as f:
        rd = csv.reader(f)
        head = [RENAME.get(h.strip(), h.strip()) for h in next(rd)]
        for i, cells in enumerate(rd):
            r = dict(zip(head, cells))
            if conventions:
                r = recode(r)
            ws = WORD.findall((r.get("content") or "").lower())
            if not ws or (r.get("content") or "").strip() in NA:
                continue
            starts.append(len(words))
            a = (i, norm_id(r.get("name.id")), row_type(r))
            m = INCORPORATED_IN_ROW.search(r.get("content") or "") if conventions and a[2] != "nonspeech" else None
            if m:      # #96: the incorporated document within the row is non-speech
                k = len(WORD.findall((r.get("content") or "")[:m.start()].lower()))
                words.extend(ws)
                attrs.extend([a] * k + [(i, a[1], "nonspeech")] * (len(ws) - k))
                continue
            words.extend(ws)
            attrs.extend([a] * len(ws))
    return words, attrs, set(starts)


def chars(path):
    """double quotes, and rows with white space at either end of the content"""
    with open(path, encoding="utf-8-sig", errors="replace", newline="") as f:
        rows = [r for r in csv.DictReader(f)]
    content = [(r.get("content") or "") for r in rows]
    return sum(c.count('"') for c in content), sum(1 for c in content if c and c != c.strip()), len(content)


def first_aligned(starts, aligned, n):
    """each row start moved to the row's first aligned word; a row with no aligned word keeps its start"""
    order = sorted(starts)
    out = set()
    for k, s in enumerate(order):
        end = order[k + 1] if k + 1 < len(order) else n
        out.add(next((w for w in range(s, end) if w in aligned), s))
    return out


def score(gold, out, conventions=False):
    gw, ga, gs = stream(gold, conventions)
    ow, oa, os_ = stream(out)
    sm = difflib.SequenceMatcher(None, gw, ow, autojunk=False)
    pairs = [(b.a + k, b.b + k) for b in sm.get_matching_blocks() for k in range(b.size)]
    n = len(pairs)
    spk = sum(ga[i][1] == oa[j][1] for i, j in pairs)
    typ = sum(ga[i][2] == oa[j][2] for i, j in pairs)
    conf = collections.Counter((ga[i][2], oa[j][2]) for i, j in pairs)
    # row starts: a gold start is found if the aligned output word also starts a row. A row that begins with
    # words the other side lacks (a list label "(a)" one side kept) starts, for this purpose, at its first
    # aligned word: missing or extra text is counted by text_recall and text_precision, not as a boundary.
    a2b = dict(pairs)
    b2a = {j: i for i, j in pairs}
    gs, os_ = first_aligned(gs, a2b, len(gw)), first_aligned(os_, b2a, len(ow))
    g_found = sum(1 for s in gs if s in a2b and a2b[s] in os_)
    o_ok = sum(1 for s in os_ if s in b2a and b2a[s] in gs)
    g_ns = sum(1 for i, j in pairs if ga[i][2] == "nonspeech")
    o_ns = sum(1 for i, j in pairs if oa[j][2] == "nonspeech")
    both_ns = sum(1 for i, j in pairs if ga[i][2] == "nonspeech" and oa[j][2] == "nonspeech")
    br = g_found / len(gs) if gs else 1.0
    bp = o_ok / len(os_) if os_ else 1.0
    return {
        "gold_rows": len(gs), "output_rows": len(os_), "gold_words": len(gw), "output_words": len(ow),
        "text_recall": n / len(gw) if gw else 1.0,
        "text_precision": n / len(ow) if ow else 1.0,
        "speaker_acc": spk / n if n else 0.0,
        "type_acc": typ / n if n else 0.0,
        "boundary_p": bp, "boundary_r": br,
        "boundary_f1": 2 * bp * br / (bp + br) if bp + br else 0.0,
        "nonspeech_p": both_ns / o_ns if o_ns else 1.0,
        "nonspeech_r": both_ns / g_ns if g_ns else 1.0,
        "quote_recall": min(oq, gq) / gq if (gq := chars(gold)[0]) and (oq := chars(out)[0]) is not None else 1.0,
        "untrimmed_rows": chars(out)[1] / max(1, chars(out)[2]),
        "type_confusion": {f"{a}->{b}": c for (a, b), c in conf.most_common() if a != b},
    }


if __name__ == "__main__":
    res = score(sys.argv[1], sys.argv[2], "--conventions" in sys.argv)
    if "--json" in sys.argv:
        print(json.dumps(res, indent=1))
    else:
        for k, v in res.items():
            print(f"{k:16} {v:.3f}" if isinstance(v, float) else f"{k:16} {v}")
