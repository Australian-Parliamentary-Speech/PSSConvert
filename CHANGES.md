# Changes to the output CSVs

For the downstream database developers: every change to the columns of the `*_edit_step8.csv` files, or to
what a column means, with the issue that records the decision. New columns are always added at the end of
the row, so existing columns keep their positions.

## Unreleased

### New columns (at the end, in this order)
| Column | Values | Issue |
|---|---|---|
| `presiding_phid` | The presiding officer's own Handbook id where it is known reliably, otherwise `N/A`. `name.id` stays `10000` for every presiding officer. | Australian-Parliamentary-Speech/PSSConvert#90 |
| `nonspeech_type` | On non-speech rows: `written_question`, `written_answer`, `incorporated`, `procedural`, `division`, `heading`, `table`, `petition`, `motion` or `other`. `N/A` on all other rows. | Australian-Parliamentary-Speech/PSSConvert#96, Australian-Parliamentary-Speech/PSSConvert#100, Australian-Parliamentary-Speech/PSSConvert#196 |
| `turn_no` | Counts turns: increases by one when the speaker changes. Non-speech rows keep the number of the turn before them. `0` before the first speaker. | Australian-Parliamentary-Speech/PSSConvert#97 |

### Changed meanings and flags
- Petition rows (`petition_flag = 1`) and motions moved without a speech (`motionnospeech_flag = 1`) are now
  `non_speech_flag = 1`, with `nonspeech_type` `petition` or `motion`; both keep their flag and the member's id. Before,
  they were `non_speech_flag = 0`, so filtering on `non_speech_flag` counted 177,582 of them as speech
  (Australian-Parliamentary-Speech/PSSConvert#196).
- From 2011 petitions carry the id of the Petitions Committee chair who presented them ("On behalf of the Standing
  Committee on Petitions … I present the following petitions"). They had `N/A` (85,238 rows)
  (Australian-Parliamentary-Speech/PSSConvert#194).
- A speaker id for a member who was not sitting in that chamber on that date is replaced by the id of the one sitting
  member the printed name stands for: Senator Kilgariff carried Enderby's `8H7` (ParlInfo's old code for him is
  Enderby's Handbook id), Senator Staniforth Smith the House's Sydney Smith, Senator Kathy Martin the House's
  Vincent Martin, and Kent Hughes Billy Hughes after his death. Ids within 250 days of a term, and ids whose own
  member the printed name matches, are left as they are (Australian-Parliamentary-Speech/PSSConvert#193).
- A speaker id whose member is not the one printed is replaced by the member the printed name stands for, where it
  gives exactly one sitting member: "FRASER, Malcolm" carried Holt's `KHQ` (1956–58), and interjections by Hewson,
  Carlton, Ruddock and others carried the Prime Minister's or a minister's id (1981–99)
  (Australian-Parliamentary-Speech/PSSConvert#199).
- `name.id` values that were neither a Handbook id nor a documented code are resolved from the printed name: a
  sitting member, a collective voice (`OPPOSITION`, `GOVERNMENT`, `MEMBERS`), `GOVERNOR-GENERAL` or the Clerk's
  `10001`; otherwise `UNKNOWN` on a spoken row and `N/A` on others. This covers `20000` (1901–77), `Unknown`, old
  ParlInfo codes #88 could not map, and leftovers such as `#director`. ParlInfo's own codes for visiting heads of
  state (`009C3` Bush, `G5F` Harper, `GYB` Obama) were kept (Australian-Parliamentary-Speech/PSSConvert#200); they
  are now the generic code `VISITOR`, for a person who is not a member and speaks by invitation; the printed name
  stays in `name` (17 rows; Australian-Parliamentary-Speech/PSSConvert#206).
- A speaker heading cut between `name` and `content` ("Senator" + "GALLAGHER: I welcome …", "The PRESIDE" +
  "NT: …") is joined back into `name` and taken out of `content`; a bare title with a member's id takes the member's
  surname (Australian-Parliamentary-Speech/PSSConvert#201).
- `party`, `electorate` and `page.no` are filled on far more rows. From 2011 a speaker read from the paragraph takes
  them from the speech's talker; in every era a member's party and electorate are carried to their other rows that
  day, and a row with no page takes the page its turn started on. Before, they were `N/A` on 85–99.5% of spoken rows
  from 2012 (Australian-Parliamentary-Speech/PSSConvert#187).
- `presiding_phid` is also set on the non-speech "Mr SPEAKER (…) took the chair" lines, which name the person in
  the chair; there `name.id` is `N/A` (Australian-Parliamentary-Speech/PSSConvert#197).
- `presiding_phid` holds only Handbook ids: values such as `UNKNOWN`, `1000`, `10000DEPUTY` and `10000Collins` are
  `N/A`. Handbook ids written in lower case (`e5z`) are upper case in `name.id` and `presiding_phid`
  (Australian-Parliamentary-Speech/PSSConvert#195).
- `speaker_no` numbers the speech elements of the source in order. It never goes down, and it starts a new number
  at every new source element and at every change of speaker (`turn_no`). Rows split from one source element with
  the same speaker (a quote, a stage direction, a table or document taken out of a speech) share its number. Before
  1.18 it did not change on 21,532 rows where the speaker did, because later steps split rows and change names
  after it is set (Australian-Parliamentary-Speech/PSSConvert#97, Australian-Parliamentary-Speech/PSSConvert#197,
  Australian-Parliamentary-Speech/PSSConvert#204).
- `presiding_phid` is filled from ausPH's presiding-officer terms (`getPresidingOfficers()`, 1.1.1). A row under a
  clean "Mr SPEAKER", "The PRESIDENT", "The CHAIRMAN" or "SPEAKER, Mr" (and in the Senate "The DEPUTY PRESIDENT"
  before 1970) takes the one holder of the office on that date, unless an acting Speaker or President served that
  day or the day's rows name someone else under that title. Deputy Speakers after 1960, the Speaker's panel,
  acting and temporary chairs are filled only where the row names the person, now on either side of the bracket
  ("Quick, Harry (Mr DEPUTY SPEAKER)"). Johnson was given as Speaker from 08/10/1914 to 26/03/1917, when McDonald
  held the office; a garbled "MrDEPUTY SPEAKER (Mr Millar)" or "The DEPUTY-PRESIDENT (Senator Newlands)" could set
  the day's Speaker or President; and SGML-era rows such as "Mr DEPUTY SPEAKER (Mr Nehl)" carried the id of the
  member speaking around them. On a sample of every 15th day, filled chair rows rise from 65% to 79% (House) and
  from 61% to 78% (Senate) (Australian-Parliamentary-Speech/PSSConvert#186).
- A collective voice ("Opposition members", "Government senators", "Honourable members") carrying one member's
  Handbook id, copied from the speech it interrupts (4,625 rows, mostly 1981–97), takes `OPPOSITION`, `GOVERNMENT`
  or `MEMBERS` (Australian-Parliamentary-Speech/PSSConvert#109). The party and electorate on such a row, often the
  day's only print of them, are that member's: they fill the member's other rows that day, and the collective row
  has `N/A` (Australian-Parliamentary-Speech/PSSConvert#211).
- An id whose member was not in Parliament within 250 days of the date is replaced by the one member of the printed
  surname sitting in that chamber, even if the first name differs: "PAGE, Earle" in 1901 is James Page `KXO`
  (55 rows). Ids for which no such member sits are kept; most are letters or statements of a former member read
  out (Australian-Parliamentary-Speech/PSSConvert#205).
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
- Each table printed in Hansard is now one row, `non_speech_flag = 1` and `nonspeech_type = table`, with the id of
  the speech, answer or document it is part of. Before, table text was left out. Cells are separated by ` | ` and
  table rows by ` / `. The row comes straight after the row of text the table is printed in. docs/tables.md shows
  how to turn a row back into a table (Australian-Parliamentary-Speech/PSSConvert#100,
  Australian-Parliamentary-Speech/PSSConvert#178).
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
- Short procedural lines worded with a qualifier ("Amendment, by leave, withdrawn.", "Question, as amended,
  agreed to.", "Amendment (by Sir George Turner) agreed to-") are non-speech `procedural` with no id, one row per
  step, instead of spoken rows with `UNKNOWN` (Australian-Parliamentary-Speech/PSSConvert#146).
- A speaker heading whose title the OCR garbled ("Mi-. THOMSON.-", "Mir. DEAKIN.-", "Mr.-KELLY.-") or that gives
  initials ("Mr. L. E. GROOM") now starts a turn with the member's id, as in Australian-Parliamentary-Speech/PSSConvert#137
  (Australian-Parliamentary-Speech/PSSConvert#147).
- Convention decided on 14/11/2026: a passage a member quotes in a speech, question or answer is
  `quote_flag = 1` with the member's `name` and `name.id`, in every era. From 2011, where the XML prints it in
  small type, the parser finds it when it opens with a quotation mark or an ellipsis or follows a paragraph that
  ends in a colon (Australian-Parliamentary-Speech/PSSConvert#148).
- Petitions carry the id of whoever presented them: the presenter the XML gives (`<petition nameids>` in the SGML conversion, `<petitioninfo>` in ParlInfo XML), or the first member named in the petition's "by …" line, and the Clerk's fixed `name.id` `10001` where no member is named. The Clerk's own rows have `10001`. A petition of several paragraphs is one row (Australian-Parliamentary-Speech/PSSConvert#157).
- ParlInfo's old SGML-era speaker codes (mostly 1981-1997) are replaced by Parliamentary Handbook ids from the reviewed table `src/data/legacy_ids.csv`: 169 codes, about 37,700 rows (Australian-Parliamentary-Speech/PSSConvert#88).
- A speech that goes on after an interruption keeps its speaker: a printed heading with an electorate is read through OCR noise, and a paragraph straight under a `<speech>` with no speaker of its own is the words of the member who opened it (Australian-Parliamentary-Speech/PSSConvert#107).
