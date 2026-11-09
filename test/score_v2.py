"""Score PSSConvert's gold-day outputs against gold standard v2, and fail if any day falls below its baseline (#117).

Usage: python3 -I score_v2.py --house <house|senate> <gold_standard_v2_dir> <gold_outputs_dir> <baseline.csv> [--write-baseline]

For each <gold_standard_v2_dir>/<house>/<date>.csv, the output <gold_outputs_dir>/<year>/<date>_edit_step8.csv is
scored word by word (hansard_eval.py): speaker_acc, type_acc, boundary_f1, nonspeech_p, nonspeech_r. Exit status 1
if any score is more than TOLERANCE below the baseline for that day, or an output is missing.
"""
import csv, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hansard_eval as H

KEYS = ["speaker_acc", "type_acc", "boundary_f1", "nonspeech_p", "nonspeech_r"]
TOLERANCE = 0.005


def main(argv):
    house = argv[argv.index("--house") + 1]
    args = [a for a in argv if not a.startswith("--") and a != house]
    gold_dir, outs, baseline_fn = args[:3]
    write = "--write-baseline" in argv
    base = {}
    if os.path.exists(baseline_fn):
        base = {(r["house"], r["date"]): r for r in csv.DictReader(open(baseline_fn))}
    rows, falls = [], []
    for f in sorted(os.listdir(os.path.join(gold_dir, house))):
        if not f.endswith(".csv"):
            continue
        d = f[:-4]
        out = os.path.join(outs, d[:4], f"{d}_edit_step8.csv")
        if not os.path.exists(out):
            falls.append(f"{house} {d}: no output"); continue
        s = H.score(os.path.join(gold_dir, house, f), out, False)
        rows.append({"house": house, "date": d, **{k: f"{s[k]:.4f}" for k in KEYS}})
        b = base.get((house, d))
        line = f"{house} {d}: " + "  ".join(f"{k}={s[k]:.3f}" + (f" (baseline {float(b[k]):.3f})" if b else "") for k in KEYS)
        print(line)
        if b:
            falls += [f"{house} {d}: {k} {s[k]:.4f} < baseline {float(b[k]):.4f}" for k in KEYS if s[k] < float(b[k]) - TOLERANCE]
    if write:
        keep = [r for r in base.values() if r["house"] != house]
        with open(baseline_fn, "w", newline="") as fh:
            w = csv.DictWriter(fh, ["house", "date"] + KEYS); w.writeheader()
            w.writerows(sorted(keep + rows, key=lambda r: (r["house"], r["date"])))
        print(f"wrote {baseline_fn}")
    for x in falls:
        print("FALL:", x)
    return 1 if falls else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
