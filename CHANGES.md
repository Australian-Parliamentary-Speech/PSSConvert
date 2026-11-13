# Changes to the output CSVs

For the downstream database developers: every change to the columns of the `*_edit_step8.csv` files, or to
what a column means, with the issue that records the decision. New columns are always added at the end of
the row, so existing columns keep their positions.

## Unreleased

### New columns (at the end, in this order)
| Column | Values | Issue |
|---|---|---|
| `presiding_phid` | The presiding officer's own Handbook id where it is known reliably, otherwise `N/A`. `name.id` stays `10000` for every presiding officer. | Australian-Parliamentary-Speech/PSSConvert#90 |
| `nonspeech_type` | On non-speech rows: `written_question`, `written_answer`, `incorporated`, `procedural`, `division`, `heading` or `other`. `N/A` on all other rows. | Australian-Parliamentary-Speech/PSSConvert#96 |
| `turn_no` | Counts turns: increases by one when the speaker changes. Non-speech rows keep the number of the turn before them. `0` before the first speaker. | Australian-Parliamentary-Speech/PSSConvert#97 |

### Changed meanings and flags
- `speaker_no` is the row's order number in the source: it increases on every row, stage directions
  included. This was already so; it is now documented, and `turn_no` gives the count of turns
  (Australian-Parliamentary-Speech/PSSConvert#97).
- The Speaker, President and Chair (rows with `name.id = 10000`) are always `speech_flag = 1`, never
  `interjection_flag`, `question_flag` or `answer_flag`. This reverses the question-time rule of
  Australian-Parliamentary-Speech/PSSConvert#55 (Australian-Parliamentary-Speech/PSSConvert#93).
- Voices that are not one person ("Honourable members", "Opposition senators", "Government members") are
  `interjection_flag = 1` with `name.id` `OPPOSITION` or `GOVERNMENT` where the source says which side,
  otherwise `MEMBERS`. They were `N/A` (Australian-Parliamentary-Speech/PSSConvert#94).
- A spoken row whose source names no one has `name.id = UNKNOWN` instead of `N/A`, so `N/A` now means no
  speaker applies. This is a trial (Australian-Parliamentary-Speech/PSSConvert#95).
- A speaker id says whose words they are, not that they were spoken. Documents tabled or incorporated
  ("The document read as follows") are now `non_speech_flag = 1`, keeping the tabling member's id, like
  written answers to questions on notice (`chamber_flag = 3`), which were already non-speech
  (Australian-Parliamentary-Speech/PSSConvert#96).
- A question on notice is `written_question`, with the asker's id, and the minister's printed reply is
  `written_answer`, with the minister's id. Both are non-speech; before this both were `written_answer`
  (Australian-Parliamentary-Speech/PSSConvert#127).
- Short procedural lines with no speaker ("Question agreed to.", "Bill read a third time.") are
  `non_speech_flag = 1`; some were flagged as speech (Australian-Parliamentary-Speech/PSSConvert#89).
- `content` keeps double quotes (written as `""` inside the quoted CSV field) and has no leading or
  trailing spaces (Australian-Parliamentary-Speech/PSSConvert#83, Australian-Parliamentary-Speech/PSSConvert#84).
- The way a day's XML is read is chosen from the file's layout, with the date used only where the layout
  doesn't decide it. Five 1981-1997 days held as ParlInfo XML (House 13/05/1985, 13/05/1991, 30/05/1996,
  20/11/1996 and Senate 28/11/1996) were read as SGML conversions; they now gain interjection and petition
  rows, and up to 2.6 percentage points more of their XML's words (Australian-Parliamentary-Speech/PSSConvert#129).
- A turn whose first paragraph follows a `<talk.start>` that holds only the talker now gets that talker's
  name and id; before, the whole turn could have none (369 turns in 59 files, Senate 20/09/1907 most of
  all) (Australian-Parliamentary-Speech/PSSConvert#130).
