# Reproducing a release

Each published version of the speech-level CSVs (Zenodo concept 10.5281/zenodo.24082346) was made by one PSSConvert commit from one published version of the inputs (Zenodo concept 10.5281/zenodo.24077636). This folder reruns that, on any computer, from a fresh clone (Australian-Parliamentary-Speech/PSSConvert#183).

## Steps
1. Install [Julia 1.12](https://julialang.org/downloads/), Python 3, git and `zstd`:
   - macOS: `brew install zstd`;
   - Linux: `apt install zstd`;
   - Windows: `winget install zstd`, and use **Git Bash** ([Git for Windows](https://git-scm.com/downloads/win)) for the commands below.
2. Clone PSSConvert and check out the commit the release names. The release's README gives it, and so does `code/COMMIT.txt` inside its archive:
   ```
   git clone https://github.com/Australian-Parliamentary-Speech/PSSConvert.git
   cd PSSConvert
   git checkout <commit>
   ```
3. Run:
   ```
   bash replicate/replicate.sh --out ../pssconvert-run
   ```
   The script:
   - downloads the inputs version in `replicate/INPUTS_RECORD` from Zenodo (about 2 GB) and checks every part against Zenodo's checksums;
   - unpacks it and checks every input file against the published `manifest.csv`;
   - installs the exact Julia packages in `replicate/Manifest.toml`;
   - runs the House, then the Senate.

   The CSVs are in `../pssconvert-run/outputs/{house,senate}/<year>/<date>_edit_step8.csv`. `RUN.txt` records the commit, the inputs record and the times.

If you already have the inputs unpacked, pass `--inputs <folder>`; the folder is the one holding `manifest.csv` and `house_xmls/`. It is still checked against Zenodo before the run. To try it quickly first, `--years 2026,2026 --chamber senate` runs one year of one chamber, in a minute or two.

## What it needs
- **Disk:** about 12 GB for the inputs (2 GB of downloaded parts, which you can delete afterwards, and 9.9 GB unpacked, mostly the raw sources) and 7 GB for the outputs.
- **Time:** a full run takes about 1 to 1.5 hours on a recent laptop with 8 or more cores. Julia uses all cores (`--threads=auto`).
- **Memory:** 16 GB is comfortable.

## Checking the result
The CSVs should match the release's files byte for byte. Compare them with `diff -r`, or with the release's `SHA256SUMS` after unpacking. A difference means the commit, the inputs version or the Julia packages differ from the release's. `RUN.txt` and the release's `code/` folder show which.

The versions before 1.16 were run before this folder existed. Their environments named local folders, but used the same package versions as `replicate/Manifest.toml` at the commit they name, with PSSUtils at e2488be (the same as PSSUtils main, apart from its LICENSE file).

## Other routes
`make run` in [ParlinfoSpeechScraper](https://github.com/Australian-Parliamentary-Speech/ParlinfoSpeechScraper) downloads the transcripts fresh from ParlInfo. That gives today's ParlInfo files, which change as proofs become official Hansard, so it does not reproduce a release.
