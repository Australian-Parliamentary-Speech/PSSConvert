# Reference data for the edit steps

- `presiding_terms.csv`: every term in a presiding office of either chamber (Speaker, President, Chairman or Chair
  of Committees, deputies, acting and temporary chairs, the Speaker's panel), from ausPH 1.1.1
  `getPresidingOfficers()` (806 terms, scraped 2026-11-18). An empty `end` is a term still running. Used by
  `presiding_phid` (#90, #186) to fill a clean "Mr SPEAKER", "The PRESIDENT" or "The CHAIRMAN" with the office's one
  holder on the date. It replaces `office_holders.csv`, whose filling between named days gave Johnson as Speaker
  from 08/10/1914 to 26/03/1917, when McDonald held the office.
- `members_by_surname.csv`: each member's and senator's service periods by chamber and surname, from
  ausPH 1.0.1 (`getIndividuals()`, `getParlService()`), for turning a surname on a date into a Handbook id.
- `legacy_ids.csv`: ParlInfo's old SGML-era speaker codes (mostly 1981-1997) and the Parliamentary Handbook id each stands for, with the basis of each match, the names it is used with and the dates (Australian-Parliamentary-Speech/PSSConvert#88). Built from the full run by matching each code's surname to the one member serving in that chamber on the dates it is used; the five looser matches were checked by hand. Codes for visiting heads of state and other non-members are left out.
