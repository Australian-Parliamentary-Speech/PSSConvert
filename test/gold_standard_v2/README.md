# Gold standard v2

There is one CSV per gold day, coded to the output conventions decided on 2026-11-09 and 2026-11-10. These conventions are in `CHANGES.md` at the top of the repo, and in Australian-Parliamentary-Speech/PSSConvert#93 to #98 and #103. There are 28 days: House 15 and Senate 13. The gold test (`runtests.jl`, `score_v2.py`) scores the parser against these files, and fails if any day falls below `baseline.csv`.

## How the files were made
- **The 19 days that have a human gold standard** (v1 in `../gold_standard/<house>/original/`) were recoded to the conventions by an independent model, Fable 5.1 (#103).
  - The coder saw only v1, the source XML and the written conventions: no parser code and no parser output.
  - Every v1 word is kept, in order. Every changed row cites a convention section in `v2_change`, and every row without one is identical to v1.
  - `v1_row` gives the v1 row each row's text came from.
- **9 Senate days, one for each decade the Senate gold lacked** (1904, 1916, 1923, 1935, 1949, 1967, 1989, 2006 and 2023), were built from the source XML in the same way (#112). Each covers at least 99.9% of the day's text, and `xml_ref` locates each row in the XML.
  - Two of these days were coded twice, by separate coders, as a reliability check. The two versions agree on speakers (1923: 1.000; 2006: 0.995) and speech types (0.994; 0.991).
  - The remaining disagreements are mostly over notices of motion and printed motion text, which the conventions don't settle.
- **Decided after coding, and applied to every day:**
  - "(Time expired)" stays inside the speech row;
  - petitions are `petition`;
  - questions upon notice printed in earlier eras' proceedings are non-speech, with the answers `written_answer`;
  - a question on notice is `written_question` and the minister's reply `written_answer` (Australian-Parliamentary-Speech/PSSConvert#127, decided 12/11/2026 after the human check of the pilot);
  - "Leave not granted." and "having risen in their places" are stage directions (§3).

- **Corrected after review** (Australian-Parliamentary-Speech/PSSConvert#141, 14/11/2026): 84 rows on 10 days that went against the conventions: speaker ids on House 22/01/1902, a spoken tabling statement on House 21/03/1968, type flags and a speech on House 24/02/1987, and a member's own words inside their own speech on 8 days. Each row is listed in `../gold_standard_v2_notes/corrections_141.csv`.

The coders' notes, their lists of suspected errors in v1, and the checks are kept with the project notes (`pipeline/notes/gold/v2/`).

## Scores
`score_v2.py` aligns each output with its gold day word by word (`hansard_eval.py`), and reports:
- `speaker_acc`: words with the gold speaker ID;
- `type_acc`: words with the gold row type;
- `boundary_f1`: row starts;
- `nonspeech_p` and `nonspeech_r`: precision and recall of non-speech words.

A day fails if any score is more than 0.005 below `baseline.csv`. When a change improves scores, rewrite the baseline with `--write-baseline`, and say so in the pull request.
