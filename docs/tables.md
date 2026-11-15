# Tables in the output CSVs

From version 1.15, each table printed in Hansard is one row of its own (Australian-Parliamentary-Speech/PSSConvert#100). Most are in answers to questions on notice. Before 1.15, table text was left out of the CSVs.

## How a table row looks
| Column | Value |
|---|---|
| `non_speech_flag` | `1` |
| `nonspeech_type` | `table` |
| `name`, `name.id` | The member whose speech, question or answer the table is part of. For a written answer, this is the minister answering. |
| `chamber_flag` | As for the rows around it (`3` for answers to questions on notice). |
| `content` | The whole table on one line. |
| `path` | The XPath of the `<table>` element in the source XML. |

Within `content`:
- **Cells** are separated by ` | ` (a vertical bar between spaces).
- **Table rows** are separated by ` / ` (space, slash, space).
- Header rows come first, as in the source. Nothing marks them as headers.
- A cell's own vertical bar is written `¦` (U+00A6), and the spaces around a slash inside a cell are dropped ("and / or" becomes "and/or"). So a `|` always ends a cell, and ` / ` always ends a table row.
- Tabs, line breaks and other control characters are replaced by spaces, and runs of spaces become one. The text is UTF-8.
- An empty cell is kept, as nothing between two bars: `a | | c`. Split a row on `|` and trim each cell, and every row keeps its number of cells.
- Merged cells (spanning rows or columns) are not expanded, so a row can have fewer cells than the others.

Example, Senate 02/03/2004:
```
Detention Location Type | 2001-2002 | 2002-2003 | 2003-31/10/03 | Total / Both Prison and Detention Centres | 6 | 11 | 0 | 17 / …
```

Not included: tables inside a division (the vote counts of 1981–1997) are part of the division row, as before (#118). Division name lists are still left out by design.

## Turning a row back into a table
**Python**
```python
import csv

def table(content):
    """The table in one row's content, as a list of rows, each a list of cells."""
    return [[cell.strip() for cell in row.split("|")] for row in content.split(" / ")]

with open("2004-03-02_edit_step8.csv", newline="", encoding="utf-8") as f:
    for r in csv.DictReader(f):
        if r["nonspeech_type"] == "table":
            rows = table(r["content"])
            print(r["name.id"], len(rows), "rows")
            for row in rows:
                print(row)
```

**R**
```r
library(readr)
day <- read_csv("2004-03-02_edit_step8.csv", col_types = cols(.default = "c"))
tables <- day[day$nonspeech_type == "table", ]
to_table <- function(content) {
  rows <- strsplit(content, " / ", fixed = TRUE)[[1]]
  lapply(strsplit(rows, "|", fixed = TRUE), trimws)
}
to_table(tables$content[1])
```

To restore a vertical bar inside a cell, replace `¦` with `|` after splitting.

## In a database
- The `content` field is plain text on one line. It holds no tabs, newlines or control characters, so it loads as an ordinary text column.
- The CSV is standard: every field is in double quotes, and a double quote inside a field is written twice.
- As with any text, load it with parameters or a CSV loader (`COPY`, `LOAD DATA`, `read_csv`). Never paste it into an SQL string, because content can contain `'`, `;`, `--` and `%`.
- To count or search table text separately from speech, filter on `nonspeech_type = 'table'`.
