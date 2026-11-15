# Gold standard inputs

The input XML for each gold standard day in `../gold_standard/`, so the gold standard test can run
without a full download (#77). Layout: `<house>/<year>/<YYYY_MM_DD>.xml`, as PSSConvert reads it.

Copied 2026-11-03 from the project input archive (OneDrive `ARC Text project - Input files`), the inputs
the delivered outputs were made from. They were retrieved from ParlInfo in several runs, about Aug-Dec 2025.
House 1987-02-24 is the SGML-to-XML conversion of that day, as in the archive. `SHA256SUMS` lists each file.

Added 2026-11-10 (#112): the input for the nine Senate days that gold standard v2 adds, one for each decade the Senate
gold lacked (1904-11-10, 1916-09-13, 1923-06-13, 1935-04-03, 1949-06-09, 1967-11-06, 1989-12-06, 2006-11-07,
2023-09-04). They are the files of input version 2026.11 (doi:10.5281/zenodo.24077637); 1989-12-06 is the SGML-to-XML
conversion of that day.

Added 15/11/2026 (#162): the inputs for the eight held-out days of gold standard v3 (`../gold_standard_v3/`). These are House
1926-03-24, 1953-11-24, 1983-05-17 and 1993-09-06, and Senate 1910-07-01, 1968-05-01, 1982-11-30 and 1992-09-17. They are the files
of input version 2026.11; the 1981–1997 days are SGML-to-XML conversions.
