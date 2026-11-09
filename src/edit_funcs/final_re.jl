function final_re(input_fn,output_fn,::Type{<:AbstractEditPhase})
    csvfile = CSV.File(input_fn)
    headers_ = copy(propertynames(csvfile))
    header_to_num = edit_set_up(headers_)
    # rows are read in full first, so the day's named Speaker or President can fill rows that only say "The SPEAKER"
    rows = [Vector{Any}((@. collect(row))[1]) for row in eachrow(csvfile)]
    house = CURRENT_HOUSE[]
    date = something(match(r"\d{4}-\d{2}-\d{2}", basename(input_fn)), (match="N/A",)).match
    heads = day_heads(rows, header_to_num, house, date)

    open(output_fn, "w") do io
        write_row_to_io(io,[string.(headers_)..., "presiding_phid", "nonspeech_type", "turn_no"])
        turn, last_key = 0, nothing
        for row in rows
            row = if_speaker_then_speech(row,header_to_num)
            row = final_add_from_Speaker(row,header_to_num)
            row = edit_row_final(row,header_to_num)
            presiding = presiding_phid!(row,header_to_num,house,date,heads)
            nonspeech_type = apply_conventions!(row,header_to_num)
            content = row[header_to_num[:content]]
            if content != ""
                key = turn_key(row,header_to_num)
                if !isnothing(key) && key != last_key
                    turn += 1
                    last_key = key
                end
                write_row_to_io(io,[row..., presiding, nonspeech_type, turn])
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
    #removes white space at the start and end (PSSConvert#35, rules 5 and 6)
    content = strip(content)
    row[content_num] = content
    return row
end

