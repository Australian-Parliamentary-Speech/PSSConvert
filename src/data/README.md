# Reference data for the edit steps

- `office_holders.csv`: who held the Speaker's, President's and Chair of Committees' office on each sitting
  day. Built 2026-11-04 from the delivered outputs: every day whose Hansard names the holder in brackets
  ("Mr SPEAKER (Hon. Sir Littleton Groom) took the chair"), filled across days only where the same person
  is named on both sides (`basis` = `named` or `interpolated`). Days at a change of holder are absent.
  A leave-one-out test of the filling found 0 errors in 10,645 days (Speaker, President) and 1 in 356
  (Chair of Committees). Used by `presiding_phid` (#90).
- `members_by_surname.csv`: each member's and senator's service periods by chamber and surname, from
  ausPH 1.0.1 (`getIndividuals()`, `getParlService()`), for turning a surname on a date into a Handbook id.
- `legacy_ids.csv`: ParlInfo's old SGML-era speaker codes (mostly 1981-1997) and the Parliamentary Handbook id each stands for, with the basis of each match, the names it is used with and the dates (Australian-Parliamentary-Speech/PSSConvert#88). Built from the full run by matching each code's surname to the one member serving in that chamber on the dates it is used; the five looser matches were checked by hand. Codes for visiting heads of state and other non-members are left out.
