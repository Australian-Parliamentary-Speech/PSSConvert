function flatten(input_fn, output_fn,::Type{<:AbstractEditPhase})
    csvfile= CSV.File(input_fn)
    headers_ = copy(propertynames(csvfile))
    header_to_num = edit_set_up(headers_)
    rows = eachrow(csvfile)
    row_index = 1
    is_written = Dict(number => false for number in 1:length(rows))
    content_pos = header_to_num[:content]

    open(output_fn, "w") do io
        write_row_to_io(io,string.(headers_))
        for row in rows
            if !is_written[row_index]
                if !is_stage_direction(row,header_to_num) && row_index < length(rows)
                    row_ = @. collect(row)
                    row = row_[1]
                    row_content = row[content_pos]
                    children_content,is_written = find_all_child_speeches(row_index,rows,header_to_num,is_written)
                    if row_content != "N/A"
                        row[content_pos] = row_content*" $children_content"
                    else
                        row[content_pos] = children_content
                    end
                else
                    row_ = @. collect(row)
                    row = row_[1]
                end
                write_row_to_io(io,row)
            end
            row_index += 1
        end
    end
end


"""
function find_all_child_speeches(row_no,rows,header_to_num,is_written)

Find all the speeches that belong to a single talker 
"""
function find_all_child_speeches(row_no,rows,header_to_num,is_written)
    #debug
    #    content_pos = header_to_num[:content]
    #    row = @. collect(rows[row_no])[1]
    #    log = false
    #    if occursin("On behalf of the Standing Committee on Petitions",row[content_pos])
    #        log = true
    #    end

    content = ""
    while !(stop_before_next_talker(row_no+1,rows,header_to_num)) && (row_no < length(rows))
        row = get_row(rows,row_no + 1)
        content_ = row[header_to_num[:content]]
        if content_ != "N/A"
            content *= " $content_"
        end
        row_no += 1
        is_written[row_no] = true
        if row_no == length(rows)
            return content,is_written
        end
    end
    return content,is_written
end

function equiv(current_row,next_row,header_to_num)
    flag_indices, current_flags = find_all_flags(current_row,header_to_num)
    flag_indices, next_flags = find_all_flags(next_row,header_to_num)
    next_debate, next_subdebate = next_row[header_to_num[:debateinfo]],next_row[header_to_num[:subdebateinfo]]
    current_debate, current_subdebate = current_row[header_to_num[:debateinfo]],current_row[header_to_num[:subdebateinfo]]
    return current_flags == next_flags && current_debate == next_debate && current_subdebate == next_subdebate
end

function stop_before_next_talker(row_no,rows,header_to_num)
    current_row = get_row(rows,row_no - 1)
    if is_stage_direction(rows[row_no],header_to_num)
        return true
    else
        next_row = get_row(rows,row_no)
        name_pos = header_to_num[:name]
        next_name = next_row[name_pos]
        now_name = current_row[name_pos]
#        if occursin("Abbott",next_name)
#            @show next_name
#            @show now_name
#        end
        if next_row[name_pos] != "N/A" && next_name != now_name
            return true
        else
            return !(equiv(current_row,next_row,header_to_num))
        end 
    end
    return false
end


function process_flag(flag)
    if typeof(flag) <: Int
        return flag
    else
        return parse(Int,flag)
    end
end


