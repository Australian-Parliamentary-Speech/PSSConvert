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
- A printed question on notice inside a `<question>` element ("Mr X asked the Minister, upon notice, …"),
  and the printed reply that follows it, are now `written_question` and `written_answer` (non-speech,
  `chamber_flag = 3`) in every era; before, they were `question` and `answer`. Quoted text inside an
  earlier-era written question or answer is now non-speech too. Across the corpus this moves 2.6 million
  words from spoken types to written ones on 4,240 days; no words are added or lost
  (Australian-Parliamentary-Speech/PSSConvert#132).
- A stage-direction phrase ("Senate adjourned", "Leave granted", …) no longer blanks a whole row wherever it
  appears: it counts at the start of a row, or anywhere in a row of 20 words or fewer, and inside a longer
  speech it is split off as its own row, so the speech keeps its speaker and type. The note "The document read
  as follows" inside a spoken row is now a non-speech row of its own with no id, and the document after it is
  `incorporated`, with the id of whoever presented it: the last member to speak, or `10000` when the Speaker or
  President says "I present" or "I table". About 1.56 million words, mostly tabled papers, ministry lists and
  Selection Committee reports, move from speech or quote to `incorporated`
  (Australian-Parliamentary-Speech/PSSConvert#134).
- A member's own words inside their speech that the source marks `<interjection>` are now `speech`, not
  `interjection`: about 476,000 words, most in the Senate before 1981; true interjections ("Mr X
  interjecting") are unchanged (Australian-Parliamentary-Speech/PSSConvert#135).
- A spoken row that names a member but has no `name.id` now gets the member's id: the one id that surname has
  elsewhere in the same day, else the one member of that chamber with that surname serving that day. Spoken
  words named but with no id fall from about 2.06 million to 254,000, most of them in the 1900s
  (Australian-Parliamentary-Speech/PSSConvert#136).
- A speaker heading printed inside the text ("Senator CLEMONS (Tasmania).-While I agree …") now starts a new
  `speech` row by that member, where the member can be identified, and the heading leaves `content` (about 32,000
  words of headings in the House). Words in rows that still start with a printed heading fall from about 963,000
  to 504,000 (Australian-Parliamentary-Speech/PSSConvert#137).
- Rows whose `content` was the literal text `N/A` (empty paragraphs in the source, about 48,000 rows) are no
  longer written (Australian-Parliamentary-Speech/PSSConvert#138).
- Department headings ("Prime Minister's Department"), letter salutations ("Dear Sir", "To Mr. Gregory"),
  reported speech ("Mr Bury said:") and web links are no longer taken as the speaker's `name` (about 200,000
  words); the text stays with the speaker or document it belongs to (Australian-Parliamentary-Speech/PSSConvert#139).
- Conventions decided on 14/11/2026 (Australian-Parliamentary-Speech/PSSConvert#142):
  - the text moved after "I move:" ("That this bill be now read a second time.", "Schedule 1, page 15, after
    line 8, insert: …") is a `quote_flag = 1` row with the mover's `name` and `name.id`; "I move:" stays in the
    speech, and words after the motion in the same paragraph stay speech;
  - a printed notice of motion ("Senator Siewert to move on the next day of sitting: …") is `non_speech_flag = 1`,
    `nonspeech_type = other`, with the member's id, and so is the motion text printed under it; a spoken notice
    ("I give notice that …") stays the member's speech;
  - the Governor-General's opening speech is `speech_flag = 1` with the new fixed `name.id` `GOVERNOR-GENERAL`, as
    presiding officers have `10000`; the House's reprint of it is `incorporated` with that id.
