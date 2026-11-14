# Conventions decided 14/11/2026 (#142):
#   1. the text moved after "I move:" is `quote`, with the mover's name and id;
#   2. a printed notice of motion ("Senator X to move on the next day of sitting: …") is non-speech `other` with the
#      member's id; a spoken notice ("I give notice that …") stays the member's speech;
#   3. the Governor-General's opening speech is `speech` with the fixed id GOVERNOR-GENERAL (the House's reprint
#      of it is an incorporated document with that id).

const GOVERNOR_GENERAL = "GOVERNOR-GENERAL"

const I_MOVE = raw"\bI\s+(?:now\s+|formally\s+|therefore\s+|accordingly\s+|also\s+)?move\s*(?:,?\s*(?:as\s+an\s+amendment|by\s+leave|in\s+(?:its|his|her)\s+place)\b[^:—–\-]{0,40}?)?\s*[:—–\-]+\s*"
# the first words of the text moved
const MOTION_START = raw"(?:That\b|\(\s*(?:\d{1,2}|[a-z]|[ivx]{1,4})\s*\)|Schedule\b|Clause\b|Page\b|Omit\b|Item\b|Leave\s+out\b|Insert\b|At\s+the\s+end\b)"
const I_MOVE_END = Regex("(?i)" * I_MOVE * raw"$")
const I_MOVE_THEN = Regex("(?i:" * I_MOVE * ")(?=" * MOTION_START * ")")
const MOTION_FIRST = Regex("^" * MOTION_START)
const MOTION_ELEMENT = r"/(?:motion|amendments?)(?:\[\d+\])?(?:/|$)"
# words before a full stop that do not end a sentence
const NOT_SENTENCE_END = Set(["mr", "mrs", "ms", "dr", "st", "no", "nos", "hon", "sir", "messrs", "co", "ltd", "vol", "sec", "s",
                              "ss", "cl", "p", "pp", "art", "para", "sch", "vic", "qld", "tas", "nsw", "w.a", "s.a", "n.s.w"])

"""The end of the text moved, as a byte index into `text`: the first full stop followed by a capital that does not open
a numbered item ("… a second time. This bill …" ends; "… substitute "X". (2) Schedule 1 …" goes on), or the end."""
function motion_end(text)
    for m in eachmatch(r"[.!?][\"'”’]?\s+(?=[A-Z])", text)
        word = lowercase(something(match(r"([\w.]+)$", text[1:prevind(text, m.offset)]), (captures=[""],)).captures[1])
        (word in NOT_SENTENCE_END || (length(word) == 1 && isletter(word[1]))) && continue  # "Mr K. J. Thomson"
        # the last character of the motion (a closing quote such as ” takes several bytes)
        return thisind(text, m.offset + ncodeunits(rstrip(m.match)) - 1)
    end
    return lastindex(text)
end

"""#142: a spoken piece that goes on past "I move:" is split there: "I move:" stays with the speech, the text moved
is a `:motion` piece (a quote with the mover's id), and any words after it are speech again."""
function motion_pieces(pieces)
    out = Tuple{String,Any}[]
    for (text, stage) in pieces
        rest = text
        while stage === false && (m = match(I_MOVE_THEN, rest)) !== nothing
            cut = m.offset + ncodeunits(m.match)
            before = strip(rest[1:prevind(rest, cut)])
            tail = rest[cut:end]
            e = motion_end(tail)
            moved, after = strip(tail[1:e]), strip(tail[nextind(tail, e):end])
            isempty(before) || push!(out, (String(before), false))
            push!(out, (String(moved), :motion))
            rest = after
        end
        isempty(strip(rest)) || push!(out, (String(strip(rest)), stage))
    end
    return out
end

"""#142: after a spoken row that ends "I move:", the text moved in the next row (and the numbered items or motion
blocks that follow it) is a quote by the mover. Words after the motion in that row keep their type. `rows` holds
[row, presiding, nonspeech_type]; returns the new vector."""
function motion_after!(rows, h)
    nid = Symbol("name.id")
    out = Vector{Vector{Any}}()
    mover, first_ = nothing, false
    for x in rows
        r = x[1]
        content = strip(string(r[h[:content]]))
        if !isnothing(mover)
            unnamed = isna(r[h[:name]]) && isna(r[h[nid]])
            same = !isna(mover[2]) ? string(r[h[nid]]) == mover[2] : string(r[h[:name]]) == mover[1]
            fits = (isflag(r, h, :quote_flag) && (unnamed || same)) ||
                   (spoken_row(r, h) && same && !isflag(r, h, :interjection_flag)) ||
                   (isflag(r, h, :non_speech_flag) && x[3] == "other" && unnamed)
            opens = (occursin(MOTION_FIRST, content) || occursin(MOTION_ELEMENT, string(r[h[:path]]))) && !isflag(r, h, :petition_flag)
            if fits && (first_ ? opens : (occursin(r"^\(\s*(?:\d{1,2}|[a-z]|[ivx]{1,4})\s*\)", content) || occursin(MOTION_ELEMENT, string(r[h[:path]]))))
                e = (isflag(r, h, :quote_flag) || occursin(MOTION_ELEMENT, string(r[h[:path]]))) ? lastindex(content) : motion_end(content)
                moved, after = strip(content[1:e]), strip(content[nextind(content, e):end])
                q = copy(r)
                q[h[:content]] = moved
                set_type!(q, h, :quote_flag)
                q[h[:name]], q[h[nid]] = mover[1], mover[2]
                push!(out, Any[q, "N/A", "N/A"])
                if isempty(after)
                    first_ = false
                    continue
                end
                r[h[:content]] = after
                mover = nothing
                push!(out, x)
                continue
            end
            mover = nothing
        end
        push!(out, x)
        if ((spoken_row(r, h) && !isflag(r, h, :interjection_flag)) || isflag(r, h, :motionnospeech_flag)) && occursin(I_MOVE_END, content)
            mover, first_ = (string(r[h[:name]]), string(r[h[nid]])), true
        end
    end
    return out
end

# a printed notice: "Senator Siewert to move on the next day of sitting:", "Mr Hurford to move That …"
const NOTICE_PRINTED = r"^((?:Senator|Mr|Mrs|Ms|Miss|Dr)\.?\s+(?:the\s+Hon\.?\s+)?[A-Z][A-Za-z'’\-]+(?:\s+[A-Z][A-Za-z'’\-]+){0,2}?)\s+to\s+move\b"

"""#142: the member whose printed notice of motion this row is, as (name, id), or nothing. A spoken row that is a
printed notice is made non-speech `other`; the id comes from the same day or the members list (#136)."""
function printed_notice!(row, h, nonspeech_type, house, date, dids)
    content = strip(string(row[h[:content]]))
    m = match(NOTICE_PRINTED, content)
    isnothing(m) && return nonspeech_type, nothing
    (isflag(row, h, :quote_flag) || isflag(row, h, :petition_flag)) && return nonspeech_type, nothing
    spoken = any(f -> isflag(row, h, f), SPOKEN_FLAGS)
    (spoken || nonspeech_type in ("other", "procedural")) || return nonspeech_type, nothing
    name = String(m.captures[1])
    id = resolve_id(name, house, date, dids)
    set_type!(row, h, :non_speech_flag)
    row[h[:name]] = name
    row[h[Symbol("name.id")]] = isnothing(id) ? "N/A" : id
    return "other", (name, isnothing(id) ? "N/A" : id)
end

# the text of a printed notice runs on until another notice, a bill to be presented, a list of papers or a procedural line
const NOTICE_STOP = r"(?i)^(?:(?:senator|mr|mrs|ms|miss|dr)\b[^.]{0,80}?\bto\s+(?:move|present|ask)\b|the\s+following\s+papers|motion\s+\(by|question\s+(?:put|agreed|resolved)|ordered\b|notices?\s+of\s+motion|postponement|business\b|leave\s+granted|debate\s+(?:adjourned|resumed))"

const GG_START = r"(?i)(?:deliver|read)\w*\s+the\s+following\s+speech"
const GG_WHO = r"(?i)excellency|governor|deputy|administrator"
const GG_END = r"(?i)having\s+retired|retired\s+from\s+the\s+chamber|\bwithdrew\b|sitting\s+suspended|took\s+the\s+chair|having\s+withdrawn"
const GG_DEBATE = r"(?i)governor[- ]general'?s\s+speech"

"""#142: the Governor-General's opening speech. In the Senate, the paragraphs after "… was pleased to deliver the
following speech:" up to "having retired" or "Sitting suspended" are speech by GOVERNOR-GENERAL. In the House,
the speech as reprinted after the Speaker's report is an incorporated document with that id."""
function governor_general!(rows, h)
    nid = Symbol("name.id")
    on = false
    for x in rows
        r = x[1]
        c = string(r[h[:content]])
        if on && (occursin(GG_END, c) || (spoken_row(r, h) && !isna(r[h[nid]]) && string(r[h[nid]]) != "UNKNOWN"))
            on = false
        end
        if on && ((isflag(r, h, :non_speech_flag) && x[3] in ("other", "incorporated")) || isflag(r, h, :quote_flag) ||
                  (spoken_row(r, h) && (isna(r[h[nid]]) || string(r[h[nid]]) == "UNKNOWN")))
            set_type!(r, h, :speech_flag)
            r[h[:name]], r[h[nid]] = GOVERNOR_GENERAL, GOVERNOR_GENERAL
            x[2], x[3] = "N/A", "N/A"
        end
        if occursin(GG_START, c) && occursin(GG_WHO, c)
            on = true
        end
        if x[3] == "incorporated" && occursin(GG_DEBATE, string(r[h[:debateinfo]])) &&
           !occursin(r"(?i)address", string(r[h[:debateinfo]]) * " " * string(r[h[:subdebateinfo]]))
            r[h[:name]], r[h[nid]] = GOVERNOR_GENERAL, GOVERNOR_GENERAL
        end
    end
    return rows
end
