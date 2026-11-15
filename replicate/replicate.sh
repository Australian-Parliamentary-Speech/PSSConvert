#!/usr/bin/env bash
# Reproduce a PSSConvert run from a published Zenodo version of the inputs (Australian-Parliamentary-Speech/PSSConvert#183).
#
#   bash replicate/replicate.sh [--inputs DIR] [--out DIR] [--years FIRST,LAST] [--chamber house|senate]
#
# Without --inputs, the inputs version named in replicate/INPUTS_RECORD is downloaded from Zenodo into OUT/inputs/
# (about 2 GB, checked against Zenodo's checksums). With --inputs, DIR must be an unpacked copy of that version.
# Either way every input file is checked against the published manifest.csv before anything runs.
# The CSVs are written to OUT/outputs/{house,senate}/<year>/<date>_edit_step8.csv. OUT defaults to ./pssconvert-run.
# Needs Julia 1.12 (the version in replicate/Manifest.toml), Python 3, and zstd for the download. On Windows, run it
# in Git Bash.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
RECORD="$(tr -d '[:space:]' < "$HERE/INPUTS_RECORD")"
INPUTS=""; OUT="$PWD/pssconvert-run"; YEARS="1901,2026"; CHAMBERS="house senate"
while [ $# -gt 0 ]; do
  case "$1" in
    --inputs) INPUTS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --years) YEARS="$2"; shift 2 ;;
    --chamber) CHAMBERS="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || { echo "Python 3 is needed (python3 or python on the PATH)." >&2; exit 1; }
command -v julia >/dev/null || { echo "Julia is needed: https://julialang.org/downloads/ (version 1.12)." >&2; exit 1; }
# the python.org builds for macOS ship without root certificates: use the system's, unless one is set
if [ -z "${SSL_CERT_FILE:-}" ] && [ -f /etc/ssl/cert.pem ]; then export SSL_CERT_FILE=/etc/ssl/cert.pem; fi
# Julia and Python on Windows need Windows paths, not Git Bash's /c/...
native() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
if [ -z "$INPUTS" ]; then
  INPUTS="$("$PY" -I "$HERE/fetch_inputs.py" "$RECORD" "$(native "$OUT/inputs")" | tee /dev/stderr | tail -1)"
fi
INPUTS="$(cd "$INPUTS" && pwd)"
echo "Checking the inputs against Zenodo record $RECORD ..."
"$PY" -I "$HERE/verify_inputs.py" "$(native "$INPUTS")" "$RECORD"

export JULIA_LOAD_PATH="@:@stdlib" JULIA_PROJECT="$(native "$HERE")"
julia --startup-file=no -e 'using Pkg; Pkg.instantiate()'

COMMIT="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
DIRTY="$(git -C "$REPO" status --porcelain -- src replicate 2>/dev/null | head -1)"
{
  echo "PSSConvert commit $COMMIT${DIRTY:+ (with local changes)}"
  echo "inputs: Zenodo record $RECORD, $INPUTS"
  echo "years $YEARS, chambers $CHAMBERS"
  echo "started $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/RUN.txt"

for h in $CHAMBERS; do
  cat > "$OUT/$h.toml" <<T
# Written by replicate/replicate.sh: PSSConvert $COMMIT, inputs Zenodo record $RECORD
[ global ]
    output_path = "$(native "$OUT/outputs/$h")"
[[ XML_DIR ]]
    path = "$(native "$INPUTS/${h}_xmls")"
[ general_options ]
    which_house = "$h"
    year = [$YEARS]
    xml_parsing = true
    edit = ["speaker_time","re","stage_direction","free_node","flatten","flatten","column_decorate","final_re"]
    csv_edit = true
    run_xml_toggle = true
    sample = false
    remove_nums = [0,1,2,3,4,5,6,7]
    xml_name_clean = false
T
  echo "Running $h (logging to $OUT/run_$h.log) ..."
  julia --startup-file=no --threads=auto -e 'using PSSConvert, BetterInputFiles
    t = setup_input(ARGS[1], false)
    rm(t["GLOBAL"]["OUTPUT_PATH"], force=true, recursive=true); mkpath(t["GLOBAL"]["OUTPUT_PATH"])
    @time PSSConvert.RunModule.run_PSSConvert(t)' "$(native "$OUT/$h.toml")" > "$OUT/run_$h.log" 2>&1 \
    || { echo "$h failed; see $OUT/run_$h.log" >&2; exit 1; }
  echo "  $h: $(find "$OUT/outputs/$h" -name '*_edit_step8.csv' | wc -l | tr -d ' ') days"
done
echo "finished $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$OUT/RUN.txt"
echo "Done. CSVs are in $OUT/outputs/."
