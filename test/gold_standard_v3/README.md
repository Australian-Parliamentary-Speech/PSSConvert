# Gold standard v3: held-out check days

Eight sitting days, coded in November 2026 to the same conventions as v2 (`pipeline/notes/gold/conventions.md`, as decided to 15/11/2026). They are a **check set**: every change is scored on them, but no rule is designed from them. A fix is worked out on other days and then checked here, so these scores stay a fair measure for release notes (#162).

| Era | Day | Rows |
|---|---|---|
| OCR (Phase2011, `<para>`) | Senate 01/07/1910 | 184 |
| | House 24/03/1926 | 569 |
| | House 24/11/1953 | 396 |
| | Senate 01/05/1968 | 420 |
| 1981–1997 (PhaseSGML) | Senate 30/11/1982 | 474 |
| | House 17/05/1983 | 396 |
| | Senate 17/09/1992 | 386 |
| | House 06/09/1993 | 409 |

**How they were coded.**
- An independent AI coder (Claude Fable 5.2), working from the XML only and blind to the parser, coded each day; it was given the printed PDF as well for the four OCR days.
- Two days were coded a second time by a separate coder, to measure agreement:
  - House 17/05/1983: speaker 1.000, type 0.999, boundaries 0.997;
  - Senate 01/07/1910: speaker 1.000, type 0.987, boundaries 0.989.
- The briefs and both codings are in `pipeline/notes/gold/v3/` and `v3_second/`.
- The columns are those of v2, plus `xml_ref`, the XPath of the element each row comes from.

**Changes since coding.**
- House 17/05/1983: 14 petition rows are recoded to the convention decided on 15/11/2026 (#157). Each petition carries its first presenter's id, from the XML petition's `nameids`; the Clerk's lodging statement stays 10001.
- One old ParlInfo code (014, MacKellar) is mapped to 0I4 by `src/data/legacy_ids.csv`.
- Each row is logged in `../gold_standard_v3_notes/petitions_157.csv`.
- Restated motions (#169, decided 15/11/2026): the motion restated after "Debate resumed … on motion by X:" is non-speech `procedural` with no id. On Senate 01/05/1968 one row coded `motionnospeech` with the mover's id is recoded. It is logged in `../gold_standard_v3_notes/resumed_169.csv`.

- House 24/11/1953 (#202, 18/11/2026): one written answer printed as KENT HUGHES, Wilfrid was coded `DQC` (Billy Hughes), copied from the source XML; it is now `KEE`. Logged in `../gold_standard_v3_notes/kent_hughes_202.csv`.

**Scoring.** `python3 -I test/score_v2.py --house <house|senate> test/gold_standard_v3 test/gold_outputs/<house> test/gold_standard_v3/baseline.csv`. The tolerance is the same as for v2.
