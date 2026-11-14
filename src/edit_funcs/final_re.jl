function final_re(input_fn,output_fn,::Type{<:AbstractEditPhase})
    csvfile = CSV.File(input_fn)
    headers_ = copy(propertynames(csvfile))
    header_to_num = edit_set_up(headers_)
    # rows are read in full first, so the day's named Speaker or President can fill rows that only say "The SPEAKER"
    rows = [Vector{Any}((@. collect(row))[1]) for row in eachrow(csvfile)]
    house = CURRENT_HOUSE[]
    date = something(match(r"\d{4}-\d{2}-\d{2}", basename(input_fn)), (match="N/A",)).match
    heads = day_heads(rows, header_to_num, house, date)
    dids = day_ids(rows, header_to_num)

    open(output_fn, "w") do io
        write_row_to_io(io,[string.(headers_)..., "presiding_phid", "nonspeech_type", "turn_no"])
        turn, last_key, prev_wa, doc, tabler, presenter, notice, notice_last = 0, nothing, nothing, nothing, nothing, nothing, nothing, ""
        built = Vector{Vector{Any}}()
        for row in rows
            # #139: a heading, salutation or link taken as the speaker's name is no name
            name_ = row[header_to_num[:name]]
            if !isna(name_) && isna(row[header_to_num[Symbol("name.id")]]) && !looks_like_speaker(name_)
                row[header_to_num[:name]] = "N/A"
            end
            row = if_speaker_then_speech(row,header_to_num)
            row = final_add_from_Speaker(row,header_to_num)
            row = edit_row_final(row,header_to_num)
            # #136: a member named with no id gets the id from the same day or the members list
            fill_id!(row,header_to_num,house,date,dids)
            presiding = presiding_phid!(row,header_to_num,house,date,heads)
            presiding = presiding_id!(row,header_to_num,presiding)
            nonspeech_type = apply_conventions!(row,header_to_num)
            prev_wa = nonspeech_type == "written_answer" ? written_answer_id!(row,header_to_num,prev_wa) : nothing
            nonspeech_type, doc = incorporated!(row,header_to_num,nonspeech_type,doc,presenter)
            # #142: a printed notice of motion is the member's, and so is its text on the rows after it
            nonspeech_type, this_notice = printed_notice!(row,header_to_num,nonspeech_type,house,date,dids)
            if !isnothing(this_notice)
                notice = this_notice
            elseif !isnothing(notice) && nonspeech_type in ("other", "procedural") && isna(row[header_to_num[:name]]) && isna(row[header_to_num[Symbol("name.id")]]) &&
                   !occursin(NOTICE_STOP, strip(string(row[header_to_num[:content]]))) && !is_procedural(strip(string(row[header_to_num[:content]])))
                row[header_to_num[:name]], row[header_to_num[Symbol("name.id")]] = notice
                nonspeech_type = "other"
            else
                notice = nothing
            end
            notice_last = strip(string(row[header_to_num[:content]]))
            nid = string(row[header_to_num[Symbol("name.id")]])
            spoken_ = any(f -> isflag(row,header_to_num,f), SPOKEN_FLAGS)
            # a bill link is not a member (#122)
            if spoken_ && !isna(nid) && !(nid in GENERIC_IDS) && !occursin(BILL_LINK, nid)
                tabler = nid
            end
            # #134: a document belongs to whoever presented it (§3): the last member to speak, or the Speaker or
            # President when they say "I present"; a presiding officer who only grants leave tables nothing
            if spoken_
                # a presiding officer who has said "I present" stays the presenter while they go on speaking
                presenter = nid == "10000" && (occursin(PRESENTS, string(row[header_to_num[:content]])) || presenter == "10000") ? "10000" : tabler
            end
            # #137: a speaker heading printed in the text starts a new speech by that member
            segs = SPLIT_TYPES(row, header_to_num, nonspeech_type) ?
                   speaker_segments(row[header_to_num[:content]], house, date, dids) : [(row[header_to_num[:content]], nothing, nothing)]
            for (k, (stext, sid, sname)) in enumerate(segs)
            srow, stype, spres = row, nonspeech_type, presiding
            if length(segs) > 1 || !isnothing(sid)
                srow = copy(row)
                srow[header_to_num[:content]] = stext
                if !isnothing(sid)
                    set_type!(srow, header_to_num, :speech_flag)
                    srow[header_to_num[:name]] = sname
                    srow[header_to_num[Symbol("name.id")]] = sid
                    for col in (:electorate, :party, :role)
                        haskey(header_to_num, col) && (srow[header_to_num[col]] = "N/A")
                    end
                    stype, spres = "N/A", "N/A"
                    tabler, presenter = sid, sid
                end
            end
            content = srow[header_to_num[:content]]
            # #108: stage directions inside a spoken row become rows of their own
            pieces = any(f -> isflag(srow,header_to_num,f), SPOKEN_FLAGS) ? motion_pieces(document_pieces(stage_pieces(content))) :
                     isflag(srow,header_to_num,:motionnospeech_flag) ? motion_pieces([(content, false)]) :
                     stype == "procedural" ? procedural_pieces(content) : [(content, false)]
            for (text, stage) in pieces
                piece, ptype, pres = srow, stype, spres
                if length(pieces) > 1
                    piece = copy(srow)
                    piece[header_to_num[:content]] = text
                    if stage === :motion
                        # #142: the text moved is a quote by the mover
                        set_type!(piece, header_to_num, :quote_flag)
                        ptype, pres = "N/A", "N/A"
                    elseif stage === :note
                        # #134: the note is a row of its own, and the rows after it are the document (#105)
                        set_type!(piece, header_to_num, :non_speech_flag)
                        piece[header_to_num[:name]] = "N/A"
                        piece[header_to_num[Symbol("name.id")]] = "N/A"
                        ptype, pres = "procedural", "N/A"
                        doc = (presenter, 0)
                    elseif stage === :document
                        # #134: the document after "The document read as follows" is the tabling member's (§3)
                        set_type!(piece, header_to_num, :non_speech_flag)
                        piece[header_to_num[Symbol("name.id")]] = isnothing(presenter) ? "N/A" : presenter
                        ptype, pres = "incorporated", "N/A"
                        doc = (presenter, 1)
                    elseif stage
                        set_type!(piece, header_to_num, :non_speech_flag)
                        piece[header_to_num[:name]] = "N/A"
                        piece[header_to_num[Symbol("name.id")]] = "N/A"
                        ptype, pres = occursin(DIVISION, text) ? "division" : "procedural", "N/A"
                    end
                end
                # #138: a row with no words (an empty paragraph, written as "N/A") is not kept
                isna(strip(string(piece[header_to_num[:content]]))) || push!(built, Any[piece, pres, ptype])
            end
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

