"""Check that a working copy of the inputs is exactly a published Zenodo version, before a pipeline run.

Usage: python3 -I verify_inputs.py <inputs_dir> [<zenodo_record_id>]

<inputs_dir> holds manifest.csv and {house,senate}_xmls/<year>/<YYYY_MM_DD>.xml. With a record id (any version of the
inputs record, e.g. 24077637), the published manifest.csv is fetched and must be byte-identical to the local one.
Then every file the manifest lists must exist with its sha256, and no other XML file may be present.
Exits 0 and prints PASS only if all of this holds. Nothing is changed on disk.
"""
import csv, hashlib, json, os, sys, urllib.request


def published_manifest(record):
    rec = json.load(urllib.request.urlopen(f"https://zenodo.org/api/records/{record}"))
    for f in rec["files"]:
        if f["key"] == "manifest.csv":
            data = urllib.request.urlopen(f["links"]["self"]).read()
            return rec["metadata"].get("version"), data
    sys.exit(f"record {record} has no manifest.csv")


def main(root, record=None):
    problems = []
    local = open(os.path.join(root, "manifest.csv"), "rb").read()
    if record:
        version, pub = published_manifest(record)
        if pub != local:
            problems.append(f"manifest.csv differs from Zenodo record {record} (version {version})")
        else:
            print(f"manifest.csv is Zenodo record {record}, version {version}")
    rows = list(csv.DictReader(local.decode("utf-8").splitlines()))
    listed = set()
    for r in rows:
        listed.add(r["file"])
        p = os.path.join(root, r["file"])
        if not os.path.exists(p):
            problems.append(f"missing: {r['file']}")
            continue
        h = hashlib.sha256()
        with open(p, "rb") as fh:
            for block in iter(lambda: fh.read(1 << 20), b""):
                h.update(block)
        if h.hexdigest() != r["sha256"]:
            problems.append(f"changed: {r['file']}")
    for d, _, files in os.walk(root):
        for f in files:
            rel = os.path.relpath(os.path.join(d, f), root)
            if rel.endswith(".xml") and rel not in listed:
                problems.append(f"not in manifest: {rel}")
    for p in problems[:50]:
        print(p)
    print(("FAIL: %d problems" % len(problems)) if problems else f"PASS: {len(rows)} files match")
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
