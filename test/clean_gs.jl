# The column names and order of the current CSV outputs. Gold standard files are rewritten to this
# order before comparison, because the comparison looks columns up by position (#78).
const OUTPUT_HEADERS = ["question_flag", "answer_flag", "interjection_flag", "speech_flag", "petition_flag",
    "quote_flag", "motionnospeech_flag", "chamber_flag", "non_speech_flag", "speaker_no", "name", "name.id",
    "electorate", "party", "role", "page.no", "content", "subdebateinfo", "debateinfo", "path", "Speaker",
    "Time", "Other"]
# Older names used in some gold standard files
const GS_RENAMES = Dict("stage_direction_flag" => "non_speech_flag", "speech_no" => "speaker_no")

function clean_gs_files(gold_standard_path)
    original_gs_dir = joinpath([gold_standard_path,"original"])
    gs_csvs = get_all_csvnames(original_gs_dir)
    for gs_csv in gs_csvs
        csvfile = CSV.File(gs_csv)
        names_ = [get(GS_RENAMES, string(h), string(h)) for h in propertynames(csvfile)]
        header_to_num = edit_set_up(Symbol.(OUTPUT_HEADERS))
        output_fn = joinpath([gold_standard_path,basename(gs_csv)])
        open(output_fn, "w") do io
            write_row_to_io(io, OUTPUT_HEADERS)
            for row in csvfile
                cells = Dict(zip(names_, [row[i] for i in 1:length(names_)]))
                # columns missing from an older gold file are N/A; extra columns are dropped
                row = Any[get(cells, h, missing) for h in OUTPUT_HEADERS]
                row = edit_row_gs(row,header_to_num)
                write_row_to_io(io,row)
            end
        end
    end
end

function edit_row_gs(row,header_to_num)
    content_num = header_to_num[:content]
    content = ismissing(row[content_num]) ? "N/A" : string(row[content_num])
    #removes trailing spaces in the end
    content = replace(content, r" +$" => "")
    #removes leading dashes or dots
    content = replace(content, r"^\s*[.\-—–]+\s*" => "")
    #change any double space to single space
    content = replace(content, r" +" => " ")
    row[content_num] = content
    #replace missing values with "N/A"
    row = [ismissing(cell) ? "N/A" : cell for cell in row]
    return row
end
