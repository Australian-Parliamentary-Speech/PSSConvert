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
        turn, last_key, prev_wa, doc, tabler = 0, nothing, nothing, nothing, nothing
        built = Vector{Vector{Any}}()
        for row in rows
            row = if_speaker_then_speech(row,header_to_num)
            row = final_add_from_Speaker(row,header_to_num)
            row = edit_row_final(row,header_to_num)
            presiding = presiding_phid!(row,header_to_num,house,date,heads)
            presiding = presiding_id!(row,header_to_num,presiding)
            nonspeech_type = apply_conventions!(row,header_to_num)
            prev_wa = nonspeech_type == "written_answer" ? written_answer_id!(row,header_to_num,prev_wa) : nothing
            nonspeech_type, doc = incorporated!(row,header_to_num,nonspeech_type,doc,tabler)
            nid = string(row[header_to_num[Symbol("name.id")]])
            if any(f -> isflag(row,header_to_num,f), SPOKEN_FLAGS) && !isna(nid) && !(nid in ("10000","UNKNOWN","MEMBERS","OPPOSITION","GOVERNMENT"))
                tabler = nid
            end
            content = row[header_to_num[:content]]
            # #108: stage directions inside a spoken row become rows of their own
            pieces = any(f -> isflag(row,header_to_num,f), SPOKEN_FLAGS) ? document_pieces(stage_pieces(content)) : [(content, false)]
            for (text, stage) in pieces
                piece, ptype, pres = row, nonspeech_type, presiding
                if length(pieces) > 1
                    piece = copy(row)
                    piece[header_to_num[:content]] = text
                    if stage === :document
                        # #134: the document after "The document read as follows" is the tabling member's (§3)
                        set_type!(piece, header_to_num, :non_speech_flag)
                        piece[header_to_num[Symbol("name.id")]] = isnothing(tabler) ? "N/A" : tabler
                        ptype, pres = "incorporated", "N/A"
                    elseif stage
                        set_type!(piece, header_to_num, :non_speech_flag)
                        piece[header_to_num[:name]] = "N/A"
                        piece[header_to_num[Symbol("name.id")]] = "N/A"
                        ptype, pres = occursin(DIVISION, text) ? "division" : "procedural", "N/A"
                    end
                end
                piece[header_to_num[:content]] != "" && push!(built, Any[piece, pres, ptype])
            end
        end
        built = day_rules!(built, header_to_num, date)
        for (piece, pres, ptype) in built
            key = turn_key(piece,header_to_num)
            if !isnothing(key) && key != last_key
                turn += 1
                last_key = key
            end
            write_row_to_io(io,[piece..., pres, ptype, turn])
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

