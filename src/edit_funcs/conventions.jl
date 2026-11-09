# Corpus conventions decided by Pat and Marija on 2026-11-09, applied in the final edit step:
#   #93 presiding officers' words are speech, never interjections
#   #94 collective voices get a generic id: OPPOSITION, GOVERNMENT, or MEMBERS as the residual
#   #95 spoken rows whose source names no one get name.id UNKNOWN (trial)
#   #96 unspoken words are non-speech even with an id; nonspeech_type says what kind
#   #97 turn_no counts changes of speaker (speaker_no stays the source order)
#   #89 procedural lines with no speaker are non-speech

const TYPE_FLAGS = [:question_flag, :answer_flag, :interjection_flag, :speech_flag, :petition_flag, :quote_flag, :motionnospeech_flag]
const SPOKEN_FLAGS = [:question_flag, :answer_flag, :interjection_flag, :speech_flag]
const NA_VALUES = ("", "N/A", "NA")

const COLLECTIVE = r"(?i)^(?:an?\s+|some\s+|several\s+|other\s+)?(?:hono(?:u)?rable\s+|hon\.?\s+)?(?:(opposition|government)\s+)?(?:members?|senators?|supporters?)(?:\s+of\s+the\s+(opposition|government))?(?:\s+interjecting)?[\s.:,—–-]*$"
const NOT_PRESIDING = r"(?i)vice[\s-]*president|executive\s+council"
const INCORPORATED = r"(?i)^(?:the\s+)?(?:\w+\s+){0,3}(?:read|reads|incorporated)\s+as\s+follows|^\(?(?:speech|quote|document|table)\s+incorporated\)?"
const DIVISION = r"(?i)^(?:the\s+(?:house|senate|committee)\s+divided|(?:ayes|noes|pairs)\b[^a-z]{0,20}$)"
const PROCEDURAL_LINE = r"(?i)^(?:question\s+(?:put|agreed\s+to|resolved\s+in\s+the\s+(?:affirmative|negative)|negatived|so\s+resolved)|debate\s+(?:adjourned|interrupted|resumed)|leave\s+granted|motion\s+(?:agreed\s+to|negatived)|amendments?\s+(?:agreed\s+to|negatived)|clauses?\s+[\w\s,]{0,30}agreed\s+to|bill(?:,\s+as\s+amended,)?\s+(?:read\s+a\s+(?:first|second|third)\s+time|agreed\s+to|reported)|bill\s*(?:-|—|–)?\s*by\s+leave\s*(?:-|—|–)?\s*read\s+a\s+\w+\s+time|sitting\s+suspended|standing\s+(?:and\s+sessional\s*\.?\s+)?orders\s+suspended|ordered\s+that|resolution\s+reported|in\s+committee|progress\s+reported|(?:the\s+)?(?:house|senate)\s+adjourned|(?:mr\.?\s+|madam\s+)?(?:deputy\s+)?(?:speaker|president)\s+(?:\([^)]*\)\s+)?took\s+the\s+chair)"
const PROCEDURAL_MAXLEN = 200

isflag(row, h, f) = haskey(h, f) && string(row[h[f]]) == "1"
isna(x) = string(x) in NA_VALUES

function set_type!(row, h, flag)
    for f in TYPE_FLAGS
        haskey(h, f) && (row[h[f]] = 0)
    end
    if flag == :non_speech_flag
        row[h[:non_speech_flag]] = 1
    else
        row[h[:non_speech_flag]] = 0
        row[h[flag]] = 1
    end
end

"#94: OPPOSITION, GOVERNMENT or MEMBERS for a voice that is not one person, otherwise nothing"
function collective_id(name)
    m = match(COLLECTIVE, strip(string(name)))
    isnothing(m) && return nothing
    side = lowercase(something(m.captures[1], m.captures[2], ""))
    return side == "opposition" ? "OPPOSITION" : side == "government" ? "GOVERNMENT" : "MEMBERS"
end

"#96: what kind of non-speech row this is"
function nonspeech_kind(row, h)
    content = strip(string(row[h[:content]]))
    if string(row[h[:chamber_flag]]) == "3" && !isna(row[h[Symbol("name.id")]])
        return "written_answer"
    elseif occursin(INCORPORATED, content)
        return "incorporated"
    elseif occursin(DIVISION, content)
        return "division"
    elseif length(content) <= PROCEDURAL_MAXLEN && occursin(PROCEDURAL_LINE, content)
        return "procedural"
    end
    for col in (:subdebateinfo, :debateinfo)
        if haskey(h, col) && lowercase(content) == lowercase(strip(string(row[h[col]])))
            return "heading"
        end
    end
    return "other"
end

"Applies #93, #94, #89, #96 and #95 to one row and returns its nonspeech_type"
function apply_conventions!(row, h)
    name, nid = row[h[:name]], string(row[h[Symbol("name.id")]])
    spoken = any(f -> isflag(row, h, f), SPOKEN_FLAGS)
    content = strip(string(row[h[:content]]))

    # #93: the Speaker, President and Chair have the floor as of right
    if spoken && (nid == "10000" || isna(nid)) && !isnothing(presiding_office(name)) && !occursin(NOT_PRESIDING, string(name))
        set_type!(row, h, :speech_flag)
    end

    # #94: collective voices are interjections with a generic id
    cid = isna(nid) ? collective_id(name) : nothing
    if !isnothing(cid) && string(row[h[:chamber_flag]]) != "3"
        row[h[Symbol("name.id")]] = cid
        set_type!(row, h, :interjection_flag)
        spoken = true
    end

    # #96: tabled or incorporated documents were not spoken
    if spoken && occursin(INCORPORATED, content)
        set_type!(row, h, :non_speech_flag)
        spoken = false
    end

    # #89: a short procedural line with no speaker is a stage direction
    if spoken && isna(name) && isna(row[h[Symbol("name.id")]]) && length(content) <= PROCEDURAL_MAXLEN &&
            (occursin(PROCEDURAL_LINE, content) || occursin(DIVISION, content))
        set_type!(row, h, :non_speech_flag)
        spoken = false
    end

    # #95 (trial): a spoken row whose source names no one
    if spoken && isna(name) && isna(row[h[Symbol("name.id")]])
        row[h[Symbol("name.id")]] = "UNKNOWN"
    end

    return isflag(row, h, :non_speech_flag) ? nonspeech_kind(row, h) : "N/A"
end

"#97: the speaker a row belongs to for counting turns, or nothing for non-speech rows"
function turn_key(row, h)
    isflag(row, h, :non_speech_flag) && return nothing
    nid = string(row[h[Symbol("name.id")]])
    return isna(nid) || nid == "UNKNOWN" ? "name:" * string(row[h[:name]]) : nid
end
