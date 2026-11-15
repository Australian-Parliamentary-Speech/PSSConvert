"""Download a published version of the Hansard inputs from Zenodo and unpack it (Australian-Parliamentary-Speech/PSSConvert#183).

Usage: python3 -I fetch_inputs.py <zenodo_record_id> <dest_dir>

Downloads every file of the record into <dest_dir>/download/, checks each against Zenodo's md5 and the record's
SHA256SUMS, joins the archive parts and unpacks them into <dest_dir>/. Prints the path of the unpacked inputs folder
(the one holding manifest.csv and {house,senate}_xmls/) on the last line. Files already downloaded and correct are
not fetched again, so an interrupted download can be resumed by running it again. Needs about 12 GB free:
2 GB of archive parts (delete download/ afterwards if you like) and 9.9 GB unpacked, most of it the raw sources. Unpacking needs the `zstd` program, or Python 3.14's compression.zstd.
"""
import hashlib, json, os, shutil, subprocess, sys, tarfile, threading, urllib.request


def digest(path, algo):
    h = hashlib.new(algo)
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def fetch(url, path):
    tmp = path + ".part-download"
    with urllib.request.urlopen(url) as r, open(tmp, "wb") as f:
        shutil.copyfileobj(r, f, 1 << 20)
    os.replace(tmp, path)


class Joined:
    """The archive parts read one after another as one file, hashed on the way (no joined copy on disk)."""
    def __init__(self, paths):
        self.paths, self.f, self.sha = list(paths), None, hashlib.sha256()
    def read(self, n=-1):
        while True:
            if self.f is None:
                if not self.paths:
                    return b""
                self.f = open(self.paths.pop(0), "rb")
            b = self.f.read(n if n and n > 0 else 1 << 20)
            if b:
                self.sha.update(b)
                return b
            self.f.close(); self.f = None


def unpack(parts, dest):
    """Unpacks the joined parts into dest; returns the sha256 of the joined archive."""
    src = Joined(parts)
    if shutil.which("zstd"):
        z = subprocess.Popen(["zstd", "-dc"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        def feed():
            for b in iter(lambda: src.read(1 << 20), b""):
                z.stdin.write(b)
            z.stdin.close()
        th = threading.Thread(target=feed); th.start()
        with tarfile.open(fileobj=z.stdout, mode="r|") as t:
            t.extractall(dest, filter="data")
        th.join()
        if z.wait() != 0:
            sys.exit("zstd failed")
        return src.sha.hexdigest()
    try:
        from compression import zstd  # Python 3.14+
    except ImportError:
        sys.exit("Install zstd (macOS: brew install zstd; Windows: winget install zstd; Linux: apt install zstd) and run again.")
    with zstd.ZstdFile(src) as z, tarfile.open(fileobj=z, mode="r|") as t:
        t.extractall(dest, filter="data")
    return src.sha.hexdigest()


def main(record, dest):
    rec = json.load(urllib.request.urlopen(f"https://zenodo.org/api/records/{record}"))
    version = rec["metadata"]["version"]
    dl = os.path.join(dest, "download")
    os.makedirs(dl, exist_ok=True)
    files = sorted(rec["files"], key=lambda f: f["key"])
    total = sum(f["size"] for f in files)
    print(f"Zenodo record {record}: inputs version {version}, {len(files)} files, {total / 1e9:.1f} GB", flush=True)
    for f in files:
        p = os.path.join(dl, f["key"])
        algo, want = f["checksum"].split(":", 1)
        if not (os.path.exists(p) and os.path.getsize(p) == f["size"] and digest(p, algo) == want):
            print(f"  downloading {f['key']} ({f['size'] / 1e6:.0f} MB)", flush=True)
            fetch(f["links"]["self"], p)
            if digest(p, algo) != want:
                sys.exit(f"{f['key']}: checksum does not match Zenodo's; delete it and run again")
    sums = {}
    for line in open(os.path.join(dl, "SHA256SUMS")):
        h, name = line.split()
        sums[name] = h
    parts = sorted(k for k in sums if ".tar.zst.part" in k)
    for k in parts:
        if digest(os.path.join(dl, k), "sha256") != sums[k]:
            sys.exit(f"{k}: sha256 does not match SHA256SUMS")
    name = parts[0].split(".part")[0]
    print(f"  unpacking {name}", flush=True)
    sha = unpack([os.path.join(dl, k) for k in parts], dest)
    if name in sums and sha != sums[name]:
        sys.exit(f"{name}: sha256 of the joined parts does not match SHA256SUMS")
    root = os.path.join(dest, name.replace(".tar.zst", ""))
    if not os.path.exists(os.path.join(root, "manifest.csv")):
        shutil.copy(os.path.join(dl, "manifest.csv"), root)
    print(root)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
