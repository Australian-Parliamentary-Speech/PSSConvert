function flatten(input_fn, output_fn,::Type{<:AbstractEditPhase})
    csvfile= CSV.File(input_fn)
    headers_ = copy(propertynames(csvfile))
    header_to_num = edit_set_up(headers_)
    rows = eachrow(csvfile)
    row_index = 1
    is_written = Dict(number => false for number in 1:length(rows))
    content_pos = header_to_num[:content]
    # #149: the speaker of the last row written, for a paragraph split off after a lead-in
    ident = [c for c in (:name, Symbol("name.id"), :electorate, :party, :role) if haskey(header_to_num, c)]
    talker = nothing
    # #100: the speaker of a table just written, for the paragraph after it (the table kept the two apart)
    table_talker = nothing
    table_parent = ""
    path_pos = header_to_num[:path]

    open(output_fn, "w") do io
        write_row_to_io(io,string.(headers_))
        for row in rows
            if !is_written[row_index]
                if !is_stage_direction(row,header_to_num) && row_index < length(rows)
                    split_off = split_at_lead_in(row_index, rows, header_to_num)
                    row_ = @. collect(row)
                    row = row_[1]
                    if split_off && !isnothing(talker) && string(row[header_to_num[:name]]) == "N/A"
                        for (c, v) in zip(ident, talker)
                            row[header_to_num[c]] = v
                        end
                    elseif !isnothing(table_talker) && string(row[header_to_num[:name]]) == "N/A" &&
                           startswith(string(row[path_pos]), table_parent * "/")
                        for (c, v) in zip(ident, table_talker)
                            row[header_to_num[c]] = v
                        end
                    end
                    string(row[header_to_num[:name]]) != "N/A" && (talker = [row[header_to_num[c]] for c in ident])
                    row_content = row[content_pos]
                    children_content,is_written,deferred = find_all_child_speeches(row_index,rows,header_to_num,is_written)
                    if row_content != "N/A"
                        row[content_pos] = row_content*" $children_content"
                    else
                        row[content_pos] = children_content
                    end
                else
                    row_ = @. collect(row)
                    row = row_[1]
                    deferred = Int[]
                end
                write_row_to_io(io,row)
                # #178: a table printed inside the paragraphs just written comes straight after them
                for k in deferred
                    write_row_to_io(io, get_row(rows, k))
                end
                # #100: a table that starts its element passes its speaker to the next unnamed row of the same element
                table_talker = nothing
                if isempty(deferred) && is_table_row(row, header_to_num) && string(row[header_to_num[:name]]) != "N/A"
                    table_talker = [row[header_to_num[c]] for c in ident]
                    table_parent = parent_path(row[path_pos])
                end
            end
            row_index += 1
        end
    end
end


"""
function find_all_child_speeches(row_no,rows,header_to_num,is_written)

Find all the speeches that belong to a single talker. A table printed inside them (#178) does not end them: it is
returned in `deferred`, to be written straight after them.
"""
function find_all_child_speeches(row_no,rows,header_to_num,is_written)
    content = ""
    deferred = Int[]
    n = length(rows)
    last = row_no
    k = row_no + 1
    while k <= n
        if is_table_row(get_row(rows, k), header_to_num)
            j = k
            while j <= n && is_table_row(get_row(rows, j), header_to_num)
                j += 1
            end
            # the tables sit among this group's paragraphs: the same element holds them and the paragraph after them
            inside = j <= n && all(t -> table_inside(get_row(rows, last), get_row(rows, t), get_row(rows, j), header_to_num), k:j-1) &&
                     !stop_before_next_talker(j, rows, header_to_num; cur=last)
            inside || break
            for t in k:j-1
                push!(deferred, t)
                is_written[t] = true
            end
            k = j
        end
        stop_before_next_talker(k, rows, header_to_num; cur=last) && break
        content_ = get_row(rows, k)[header_to_num[:content]]
        if content_ != "N/A"
            content *= " $content_"
        end
        is_written[k] = true
        last = k
        k += 1
    end
    return content,is_written,deferred
end

"#100: the row is a table"
is_table_row(row, header_to_num) = occursin(r"/table(?:\[\d+\])?$", string(row[header_to_num[:path]]))

"the XML path of the element that holds this one"
parent_path(path) = (p = string(path); i = findlast('/', p); isnothing(i) ? p : p[1:i-1])

"#178: a table between two paragraphs of one group, in the same element as both"
function table_inside(before, table, after, header_to_num)
    pp = parent_path(table[header_to_num[:path]])
    within(r) = startswith(string(r[header_to_num[:path]]), pp * "/")
    same_topic(r) = r[header_to_num[:debateinfo]] == table[header_to_num[:debateinfo]] &&
                    r[header_to_num[:subdebateinfo]] == table[header_to_num[:subdebateinfo]]
    return within(before) && within(after) && same_topic(before) && same_topic(after)
end

function equiv(current_row,next_row,header_to_num)
    flag_indices, current_flags = find_all_flags(current_row,header_to_num)
    flag_indices, next_flags = find_all_flags(next_row,header_to_num)
    next_debate, next_subdebate = next_row[header_to_num[:debateinfo]],next_row[header_to_num[:subdebateinfo]]
    current_debate, current_subdebate = current_row[header_to_num[:debateinfo]],current_row[header_to_num[:subdebateinfo]]
    return current_flags == next_flags && current_debate == next_debate && current_subdebate == next_subdebate
end

"#149: the row starts only because the paragraph before it, or the one before that, ends in a lead-in"
function split_at_lead_in(row_no, rows, header_to_num)
    row_no < 2 && return false
    content_pos = header_to_num[:content]
    prev = get_row(rows, row_no - 1)
    this = get_row(rows, row_no)
    # unnamed, or already given the speaker's name by the first flatten pass
    name = string(this[header_to_num[:name]])
    (name == "N/A" || name == string(prev[header_to_num[:name]])) || return false
    equiv(prev, this, header_to_num) || return false
    # only a spoken paragraph: notices, lists and other non-speech rows are left as they were
    any(f -> haskey(header_to_num, f) && string(this[header_to_num[f]]) == "1", (:speech_flag, :question_flag, :answer_flag)) || return false
    (lead_in(strip(string(prev[content_pos]))) ||
     (row_no > 2 && lead_in(strip(string(get_row(rows, row_no - 2)[content_pos]))))) || return false
    # not inside an incorporated document ("The statement read as follows —", #105): it stays one non-speech row.
    # #178: look back through the whole run of paragraphs, however long the document (tables and the row just before
    # are passed over)
    k = row_no - 1
    while k >= 1
        r = get_row(rows, k)
        occursin(INCORPORATED, strip(string(r[content_pos]))) && return false
        (k == row_no - 1 || is_table_row(r, header_to_num) || equiv(r, this, header_to_num)) || break
        k -= 1
    end
    return true
end

function stop_before_next_talker(row_no,rows,header_to_num; cur=row_no - 1)
    current_row = get_row(rows,cur)
    content_pos = header_to_num[:content]
    if is_stage_direction(rows[row_no],header_to_num)
        return true
    # #149: a paragraph ending in a lead-in ("The article stated:") and the paragraph read out after it stay rows of
    # their own, so the passage can be made a quote; merge_turns joins them again where it is not
    elseif split_at_lead_in(row_no, rows, header_to_num)
        return true
    # #105: a printed notice ("Senator Woodley to move, on the next day of sitting:") is its member's, not the speech
    # or document before it in the same element
    elseif occursin(NOTICE_PRINTED, strip(string(get_row(rows,row_no)[content_pos])))
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


