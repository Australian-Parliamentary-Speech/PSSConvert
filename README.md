# PSSConvert

`PSSConvert` parses raw Hansard XML files into structured CSV files, one row per speech, with columns for speaker, party, electorate, debate context, and more. It's one of four submodules that make up the [ParlinfoSpeechScraper](../../) pipeline, taking as input the XML produced by `PSSSourceXML` and `PSSSourceSGML`.

Processing happens in two stages:

- **XML parsing** — walks each XML document's node tree, using phase- and node-specific rules (Hansard's format changed multiple times over the decades) to extract the correct headers and content for each row.
- **CSV editing** — an ordered pipeline of edit steps (e.g. attributing free-floating speech to the last known speaker, flattening multi-row speeches into one, cleaning stage directions) refines the raw parsed output into the final CSV.

### Dates: filename vs. XML content

Every XML file has a date associated with two independent sources, which don't always agree:

- **Filename date** — parsed from the XML file's name, expected to follow the `YYYY_MM_DD.xml` pattern (e.g. `2020_02_12.xml`). This is the date used to name output files: the final CSV for a given sitting is written as `<filename_date>_edit_step<N>.csv`.
- **XML date** — parsed from the date recorded inside the XML content itself, either `session.header/date` or the `hansard/@date` attribute, depending on the document format.

Both dates are extracted for every file processed (`get_date` in `RunModule.jl`). When they disagree, a warning is logged, but processing continues using the **filename date** for naming output files and detecting which processing phase applies. To keep the XML-derived date available for auditing rather than discarding it once the filename date is chosen, every run writes `date_comparison.csv` to the top of `output_path`, with one row per XML file processed and two columns, `Filename Date` and `XML Date`. The test suite's dates summary test checks this file automatically and reports any mismatches - see [Usage](../../docs/src/usage.md#output-how-dates-are-determined) and [Testing](../../docs/src/test.md#dates-summary-test).

For install/run instructions, see the [top-level README](../../README.md) (`make run house`/`senate`/`all`) or the full [documentation](https://australian-parliamentary-speech.github.io/Scraper/), which also covers the test suite and how to extend the parser with new nodes, phases, or edit steps.

## Sample input TOML

PSSConvert is configured via a TOML file, for example:

```toml
[ global ]
    output_path = "../Outputs/HouseCSV/hansard"

[[ XML_DIR ]]
    path = "../../Download/house_xmls"

[[ XML_DIR ]]
    path = "../../sgml2xml/house_xmls"

[[ XML_DIR ]]
    path = "../../sgml2xml/house_reserve_xmls"

[ general_options ]
    which_house = "house"
    year = [1981, 1998]
    xml_parsing = true
    edit = ["speaker_time","re","stage_direction","free_node","flatten","flatten","column_decorate","final_re"]
    csv_edit = true
    run_xml_toggle = true
    sample = true
    remove_nums = [0,1,2,3,4,5,6,7]
    xml_name_clean = false
```

See [Usage](../../docs/src/usage.md) for a full explanation of each option.
