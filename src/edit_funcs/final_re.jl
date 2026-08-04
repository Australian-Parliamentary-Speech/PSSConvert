function final_re(input_fn,output_fn,::Type{<:AbstractEditPhase})
    csvfile = CSV.File(input_fn)
    headers_ = copy(propertynames(csvfile))
    header_to_num = edit_set_up(headers_)
    rows = eachrow(csvfile)
  
    open(output_fn, "w") do io
        write_row_to_io(io,string.(headers_))
        for row in rows
            row_ = @. collect(row)
            row = row_[1]
            row = if_speaker_then_speech(row,header_to_num)
            row = final_add_from_Speaker(row,header_to_num)
            row = edit_row_final(row,header_to_num)
            content = row[header_to_num[:content]]
            if content != ""
                write_row_to_io(io,row)
            end
        end
    end
end

function final_add_from_Speaker(row,header_to_num)
    Speaker = row[header_to_num[:Speaker]] 
    if Speaker != "N/A" && row[header_to_num[:name]] == "N/A"
        row[header_to_num[:name]] = Speaker
    end
    return row
end


function if_speaker_then_speech(row,header_to_num)
    speaker, id = row[header_to_num[:name]],row[header_to_num[Symbol("name.id")]]
    if (speaker != "N/A" || id != "N/A") && (row[header_to_num[:chamber_flag]] != 3)
        if row[header_to_num[:non_speech_flag]] == 1
            row[header_to_num[:non_speech_flag]] = 0
            row[header_to_num[:speech_flag]] = 1
        end
    end
    return row
end


function edit_row_final(row,header_to_num)
    content_num = header_to_num[:content]
    content = row[content_num]
    #removes leading dashes or dots
    content = replace(content, r"^\s*[.\-—–]+\s*" => "")
    #removes spaces in the end.
    content = replace(content, r" +$" => "")
    #change double space to single space
    content = replace(content, r" +" => " ")
    #deletes space before and after -
    content = replace(content, r"\s*-\s*" => "-")
    row[content_num] = content
    return row
end

