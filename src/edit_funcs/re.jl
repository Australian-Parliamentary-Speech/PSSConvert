function re(input_fn,output_fn,::Type{<:AbstractEditPhase})
    csvfile = CSV.File(input_fn)
    headers_ = copy(propertynames(csvfile))
    header_to_num = edit_set_up(headers_)
    rows = eachrow(csvfile)
  
    open(output_fn, "w") do io
        write_row_to_io(io,string.(headers_))
        for row in rows
            row_ = @. collect(row)
            row = row_[1]
            row = edit_row(row,header_to_num)
            content = row[header_to_num[:content]]
            if content != ""
                write_row_to_io(io,row)
            end
        end
    end
end

function edit_row(row,header_to_num)
    row = find_speaker_content(row,header_to_num)
#    row = remove_the_speaker(row,header_to_num)
    row = delete_semicolon(row,header_to_num)
    row = edit_interjections(row,header_to_num)
    row = final_name_attempt(row,header_to_num)
    row = delete_talker_from_content(row,header_to_num)
    row = remove_bits(row,header_to_num)
    return row
end

function final_name_attempt(row,header_to_num)
    all_titles_ = all_titles()
    content = row[header_to_num[:content]]
    split_content = split(content,r"\.\s*-")
    maybe_name = clean_text(split_content[1])
    if length(split_content) == 2 && is_name(maybe_name) && row[header_to_num[:name]] == "N/A"
        occur = @. occursin(all_titles_, maybe_name)
        if !iszero(occur) && !(is_part_speech(maybe_name))
            row[header_to_num[:name]] = maybe_name
            content = replace_known_beginning(content,maybe_name)
            row[header_to_num[:content]] = content
        end
    end
    return row
end
function speaker_regs()
    res = [r"^(?:(?:(?:Th\s*e)|(?:Mr)|(?:Madam))\.?\s*)?DEPUTY\s*SPEAK\s*ER\s*(?:\([^)]+\))?:?",r"^(?:(?:(?:Th\s*e)|(?:Mr)|(?:Madam))\.?\s*)?SPEAKER\s*(?:\([^)]+\))?:?", r"^(?:(?:(?:Th\s*e)|(?:Mr)|(?:Madam))\.?\s*)?ACTING\s*(?:DEPUTY)?\s*SPEAKER\s*(?:\([^)]+\))?:?",r"^10000\s*SPEAKER",r"^Opposition\s+members",r"^(?:Mr|Mrs|Miss|Ms|Dr|Sir|Prof|Minister|The Hon|The Honourable)\.?\s*(?:[A-Za-z'-]+(?:\s+[A-Za-z'-]+){0,1})(?:\s*\([^)]*\))?:"]
    return res
end

function speaker_regs_anywhere()
    res = [r"(?:The\s*)?DEPUTY SPEAKER (?:\([^)]+\))?:?",r"(?:Mr\.?\s*)?DEPUTY SPEAKER (?:\([^)]+\))?:?",r"(?:The\s*)?SPEAKER (?:\([^)]+\))?:?", r"Mr\.?\s*SPEAKER\.?:?", r"Mr\.?\s*ACTING\s*DEPUTY\s*SPEAKER\.?:?",r"\(The\s*SPEAKER\)",r"\(The\s*DEPUTY\s*SPEAKER\)"]
    return res
end

function not_just_title(s)
    t = replace(s, "Mr" => "", "Mrs" => "", "Miss" => "", "Ms" => "", "Dr" => "")
    return occursin(r"[A-Za-z]", t) ? true : false
end

function is_part_speech(speaker)
    function get_next_word_after_speaker(line::String)
        pattern = r"\bspeaker\b,\s*(\w+)"i
        m = match(pattern, line)
        return m === nothing ? nothing : m.captures[1]
    end
    if occursin(r"speaker,"i,speaker)
        next_word = get_next_word_after_speaker(speaker)
        all_titles_ = all_titles()
        push!(all_titles_, "The")
        for title in all_titles_
            if occursin(Regex(next_word,"i"), title)
                return false
            end
        end
        return true
    else
        return false
    end
end

function find_speaker_content(row,header_to_num)
    content = row[header_to_num[:content]]
    res = speaker_regs()
    for re in res
        speaker = match(re,content)
        if !isnothing(speaker)
            speaker = speaker.match
            if !is_part_speech(speaker)
                row[header_to_num[:name]] = clean_text(speaker)
                content = replace_known_beginning(content,speaker)
                row[header_to_num[:content]] = content
            end
        end
    end
    return row 
end


function remove_the_speaker(row,header_to_num)
    name_num = header_to_num[:name]
    patterns = speaker_regs_anywhere()
    for pattern in patterns
        row[name_num] = replace(row[name_num], pattern => "")
    end
#    if row[name_num] != test
#        @show test
#    end
    return row
end



function has_letters(s::AbstractString)
    return occursin(r"[a-zA-Z]", s)
end

function edit_interjections(row,header_to_num)
    function edit_flag(row,header_to_num)
        flag_indices,all_flags = find_all_flags(row,header_to_num)
        for i in flag_indices
            row[i] = 0
        end
        row[header_to_num[:interjection_flag]] = 1 
    end
    content = row[header_to_num[:content]]
    if content != "N/A"
        m = match(r"[iI]nterjecting", content)
        if m != nothing && length(split(content," "))<5
            split_content = split(content,m.match)
            talker = split_content[1]
            row[header_to_num[:name]] = clean_text(talker)
            edit_flag(row,header_to_num)
       end
    elseif content == "N/A"
        talker = row[header_to_num[:name]]
        m = match(r"[iI]nterjecting", talker)
        if m != nothing 
            split_content = split(talker,m.match)
            row[header_to_num[:name]] = split_content[1]
            row[header_to_num[:content]] = clean_text(talker)
            edit_flag(row,header_to_num)
        end
    end
    return row
end

function replace_known_beginning(s,beginning)
    cell = try
        Regex("^\\Q$(beginning)\\E:?")
    catch e
        @show beginning
        @show e
    end

    regs = [cell, r"^The SPEAKER:",r"^Mr SPEAKER"]
    for reg in regs
        m = match(reg, s)
        if m !== nothing
            return replace(s, m.match => "")
        else
            continue
        end
    end

    return s
end

function delete_talker_from_content(row,header_to_num)
    talker = row[header_to_num[:name]]
    content = row[header_to_num[:content]]
    content = replace_known_beginning(content,talker)
    if occursin(r"\w+",content)
        row[header_to_num[:content]] = content
    end
    return row
end

function delete_semicolon(row,header_to_num)
    name = row[header_to_num[:name]]
    name = replace(name, ":" => "")
    row[header_to_num[:name]] = name
    return row
end

function remove_bits(row, header_to_num)
    content_num = header_to_num[:content]
    content = row[content_num]
    #removes leading dash and full stop
    content = replace(content, r"^ +\.?[ ]*-+" => "")
    #removes space before !
    content = replace(content, r" +(?=!)" => "")
    #removes space before ?
    content = replace(content, r" +(?=\?)" => "") 
    #adds space in front of ( if missing
    content = replace(content, r"(?<! )\(" => " (")
    #change pf to of
    content = replace(content, r" pf " => " of ")
    #no space before semicolon
    content = replace(content,r" +;" => ";")
    #no _ at end of speeches
    content = replace(content, r"_$" => "")
    #removes trailing spaces in the end
    content = replace(content, r" +$" => "")
    #removes leading spaces
    content = replace(content, r"^ +" => "") 
    #removes leading dashes or dots
    content = replace(content, r"^\s*[.\-—–]+\s*" => "")
    #removes leading =
    content = replace(content, r"\s*=\s*" => "")
    #removes a leading time stamp "( 16:10 ):" or "(Mr X):", but keeps list labels "(a)" and
    #stage directions "(Quorum formed)" (#119)
    content = replace(content, r"^\(\s*\d{1,2}\s*[:.]\s*\d{2}\s*\)\s*:?" => "")
    content = replace(content, r"^\([^)]+\)\s*:" => "")
    #removes '- 
    content = replace(content, r"^'-\s*" => "")
    row[content_num] = content
    return row
end

