function stage_direction(input_fn,output_fn,::Type{<:AbstractEditPhase})
    csvfile = CSV.File(input_fn)
    headers_ = copy(propertynames(csvfile))
    header_to_num = edit_set_up(headers_)
    rows = eachrow(csvfile)
    stage_directions = [
    r"(?i)A division having been called in the House of Representatives",
    r"(?i)Sitting suspended from",
    r"(?i)Debate adjourned",
    r"(?i)Federation Chamber adjourned at",
    r"(?i)Question agreed to",
    r"(?i)Question resolved in the affirmative",
    r"(?i)Bill read a second time",
    r"(?i)Message from the Governor-General recommending appropriation announced",
    r"(?i)Report adopted",
    r"(?i)Bill read a .+ time",
    r"(?i)Leave granted",
    r"(?i)Senate adjourned"
    ]
    opening = [Regex("^[\\s({\\[]*(?:" * sd.pattern * ")") for sd in stage_directions]

    open(output_fn, "w") do io
        write_row_to_io(io,string.(headers_))
        for row in rows
            row_ = @. collect(row)
            row = row_[1]
            content = row[header_to_num[:content]]
            # #134: a phrase counts where it opens the row, or anywhere in a short row; in a longer spoken
            # row it is left for stage_pieces (#108) to split off, so the speech keeps its speaker
            short = length(split(string(content))) <= 20
            for (sd, op) in zip(stage_directions, opening)
                hit = occursin(short ? sd : op, content)
                if hit || row[header_to_num[:chamber_flag]] == 3
                    flag_indices,all_flags = find_all_flags(row,header_to_num)
                    for i in flag_indices
                        row[i] = 0
                    end
                    if hit
                        row[header_to_num[:name]] = "N/A"
                        row[header_to_num[Symbol("name.id")]] = "N/A"
                    end
                end
            end
                
            if content != ""
                write_row_to_io(io,row)
            end
        end
    end
end

