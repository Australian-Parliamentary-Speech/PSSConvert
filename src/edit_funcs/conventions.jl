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
# petitions "read as follows" are left to the petition flag
const INCORPORATED = r"(?i)^(?:the\s+)?(?!petition)(?:\w+\s+){0,3}(?:read|reads|incorporated)\s+as\s+follows|^\(?(?:speech|quote|document|table)\s+incorporated\)?"
const DIVISION = r"(?i)^(?:the\s+(?:house|senate|committee)\s+divided|(?:ayes|noes|pairs)\b[^a-z]{0,20}$)"
const PROCEDURAL_LINE = r"(?i)^(?:question\s+(?:put|agreed\s+to|resolved\s+in\s+the\s+(?:affirmative|negative)|negatived|so\s+resolved)|debate\s+(?:adjourned|interrupted|resumed)|leave\s+granted|motion\s+(?:agreed\s+to|negatived)|amendments?\s+(?:agreed\s+to|negatived)|clauses?\s+[\w\s,]{0,30}agreed\s+to|bill(?:,\s+as\s+amended,)?\s+(?:read\s+a\s+(?:first|second|third)\s+time|agreed\s+to|reported)|bill\s*(?:-|—|–)?\s*by\s+leave\s*(?:-|—|–)?\s*read\s+a\s+\w+\s+time|sitting\s+suspended|standing\s+(?:and\s+sessional\s*\.?\s+)?orders\s+suspended|ordered\s+that|resolution\s+reported|in\s+committee|progress\s+reported|(?:the\s+)?(?:house|senate)\s+adjourned|(?:mr\.?\s+|madam\s+)?(?:deputy\s+)?(?:speaker|president)\s+(?:\([^)]*\)\s+)?took\s+the\s+chair)"
const PROCEDURAL_EXTRA = r"(?i)^(?:motion\s+\(by\s+[^)]{2,60}\)\s*(?:[-—–]\s*by\s+leave\s*[-—–]\s*)?proposed|bill\s+(?:presented|received\s+from)|ordered\s*[-—–]?\s*that|resolved\s*\(on\s+motion\s+by|(?:the\s+)?(?:house|senate)\s+adjourned\s+at|the\s+(?:honourable\s+|honorable\s+)?(?:member|senator)\s+for\s+[\w\s'-]{2,40}?\s+(?:then\s+|thereupon\s+)?(?:left|withdrew\s+from)\s+the\s+chamber)"
# a row whose text still starts with a speaker's name: the source names someone, the parser lost it (#87, #92)
const NAME_IN_TEXT = r"^(?:Mr|Mrs|Ms|Miss|Dr|Sir|Senator|Colonel|Major|General|Captain|Lt|An?\s+Hono(?:u)?rable)\.?\s*[-:.]*\s*(?:Sir\s+)?[A-Z][A-Z'\-]{1,}"

isflag(row, h, f) = haskey(h, f) && string(row[h[f]]) == "1"
isna(x) = string(x) in NA_VALUES

function set_type!(row, h, flag; clear=TYPE_FLAGS)
    for f in clear
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
    for col in (:subdebateinfo, :debateinfo)
        if haskey(h, col) && lowercase(content) == lowercase(strip(string(row[h[col]])))
            return "heading"
        end
    end
    # answers to questions on notice: only the first paragraph carries the member's id
    if string(row[h[:chamber_flag]]) == "3"
        return "written_answer"
    elseif occursin(INCORPORATED, content)
        return "incorporated"
    elseif occursin(DIVISION, content)
        return "division"
    elseif is_procedural(content)
        return "procedural"
    end
    return "other"
end

# anchored at the start, so a long row is still procedural when it carries the motion or clause text it reports
is_procedural(content) = occursin(PROCEDURAL_LINE, content) || occursin(PROCEDURAL_EXTRA, content)

"Applies #93, #94, #89, #96 and #95 to one row and returns its nonspeech_type"
function apply_conventions!(row, h)
    name, nid = row[h[:name]], string(row[h[Symbol("name.id")]])
    spoken = any(f -> isflag(row, h, f), SPOKEN_FLAGS)
    content = strip(string(row[h[:content]]))

    # #93: the Speaker, President and Chair have the floor as of right
    if spoken && (nid == "10000" || isna(nid)) && !isnothing(presiding_office(name)) && !occursin(NOT_PRESIDING, string(name))
        set_type!(row, h, :speech_flag; clear=SPOKEN_FLAGS)
    end

    # #94: collective voices are interjections with a generic id
    cid = isna(nid) ? collective_id(name) : nothing
    if spoken && !isnothing(cid)
        row[h[Symbol("name.id")]] = cid
        set_type!(row, h, :interjection_flag; clear=SPOKEN_FLAGS)
    end

    # #96: tabled or incorporated documents were not spoken
    if spoken && occursin(INCORPORATED, content)
        set_type!(row, h, :non_speech_flag)
        spoken = false
    end

    # #89: a short procedural line with no speaker is a stage direction
    if spoken && isna(name) && isna(row[h[Symbol("name.id")]]) && (is_procedural(content) || occursin(DIVISION, content))
        set_type!(row, h, :non_speech_flag)
        spoken = false
    end

    # #95 (trial): a spoken row whose source names no one
    if spoken && isna(name) && isna(row[h[Symbol("name.id")]]) && !isna(content) && !occursin(NAME_IN_TEXT, content)
        row[h[Symbol("name.id")]] = "UNKNOWN"
    end

    return isflag(row, h, :non_speech_flag) ? nonspeech_kind(row, h) : "N/A"
end

# "Mr President," / "Madam Speaker," as a row's name is a senator or member addressing the chair, not the chair
const VOCATIVE = r"(?i)^(?:mr|madam)\.?\s+(?:acting\s+)?(?:deputy\s+)?(?:speaker|president|chair(?:man)?)\s*,\s*$"

"""#104: every presiding officer's spoken row has name.id 10000 (§2). Where the row carried the person's
own id, it moves to presiding_phid. Returns the presiding_phid value."""
function presiding_id!(row, h, presiding)
    name = string(row[h[:name]])
    spoken = any(f -> isflag(row, h, f), SPOKEN_FLAGS)
    (spoken && !isnothing(presiding_office(name)) && !occursin(NOT_PRESIDING, name) && !occursin(VOCATIVE, name)) || return presiding
    nid = string(row[h[Symbol("name.id")]])
    if !(nid == "10000" || isna(nid)) && presiding == "N/A"
        presiding = nid
    end
    row[h[Symbol("name.id")]] = "10000"
    return presiding
end

"""#106: a written answer's later paragraphs carry no id in the source; they belong to the member whose
paragraph they follow, within the same question (subdebateinfo). `prev` is (subdebateinfo, name, id) or nothing."""
function written_answer_id!(row, h, prev)
    sub = string(row[h[:subdebateinfo]])
    nid = string(row[h[Symbol("name.id")]])
    if isna(nid) && !isnothing(prev) && prev[1] == sub
        row[h[Symbol("name.id")]] = prev[3]
        isna(row[h[:name]]) && (row[h[:name]] = prev[2])
        nid = prev[3]
    end
    return isna(nid) ? prev : (sub, string(row[h[:name]]), nid)
end

# "The document read as follows—" on a row of its own: the rows after it are the document (#105)
const READ_AS_FOLLOWS = r"(?i)^\(?\s*the\s+(?!petition)(?:\w+\s+){0,2}reads?\s+as\s+follows\s*\)?\s*[-—–:.]*\s*$"

"""#105: incorporated documents (§3). After a "… read as follows" row, the quote rows straight after it (or a
first row with no named speaker) are the document: non-speech `incorporated`, with the tabling member's id (the last member who spoke)
where the row has none. `state` is (tabler_id, rows_taken) while inside a document, otherwise nothing.
Returns (nonspeech_type, state)."""
function incorporated!(row, h, nonspeech_type, state, tabler)
    content = strip(string(row[h[:content]]))
    if occursin(READ_AS_FOLLOWS, content)
        return nonspeech_type, (tabler, 0)
    end
    nid = Symbol("name.id")
    # the document is a quote, or a row with no named speaker; a named member's speech right after "read as follows"
    # is the member resuming, because the document itself (often a table, #100) was not kept
    if !isnothing(state) && (isflag(row, h, :quote_flag) || (state[2] == 0 && isna(row[h[:name]]))) && !isflag(row, h, :petition_flag)
        set_type!(row, h, :non_speech_flag)
        isna(row[h[nid]]) && !isnothing(state[1]) && (row[h[nid]] = state[1])
        return "incorporated", (state[1], state[2] + 1)
    end
    if nonspeech_type == "incorporated" && isna(row[h[nid]]) && !isnothing(tabler)
        row[h[nid]] = tabler
    end
    return nonspeech_type, nothing
end

# #108: a whole sentence that is a stage direction, inside or at the end of a spoken row
const STAGE_SENTENCE = r"(?i)^(?:debate\s+(?:\(on\s+motion\s+by\s+[^)]{2,60}\)\s*)?(?:adjourned|interrupted|resumed)|question\s+(?:put|agreed\s+to|resolved\s+in\s+the\s+(?:affirmative|negative)|so\s+resolved\s+in\s+the\s+(?:affirmative|negative)|negatived)|(?:bill|motion|amendments?|clauses?[\w\s,]{0,30}|report|resolution)\s+(?:\(by\s+[^)]{2,60}\)\s*,?\s*)?(?:,?\s*by\s+leave,?\s*)?(?:agreed\s+to|negatived|withdrawn|amended\s+accordingly|adopted|reported)|amendment\s+\(by\s+[^)]{2,60}\)\s+proposed|leave\s+(?:not\s+)?granted|petition\s+received|progress\s+reported|ordered\s+that\s+the\s+report\s+be\s+(?:printed|made\s+a\s+parliamentary\s+paper)|report\s+made\s+a\s+parliamentary\s+paper|bill\s+read\s+a\s+(?:first|second|third)\s+time|more\s+than\s+the\s+number\s+of\s+(?:members|senators)\s+required\s+by\s+the\s+standing\s+orders?\s+having\s+risen|(?:the\s+)?(?:house|senate)\s+adjourned\s+at|[{(\[]?\s*sitting\s+suspended)"
# a sentence ends at . ! ? or a closing bracket before a capital, an opening bracket or "by leave"; or at a dash before a capital
const SENTENCE_BREAK = r"(?<=[.!?)\]}])\s+(?=[A-Z({\[]|by\s+leave)|(?<=[—–])\s*(?=[A-Z])"

"""#108: splits a spoken row's content into pieces, marking the whole sentences that are stage directions (§1, §3).
A sentence counts only if the stage-direction phrase covers all but at most 8 of its words. The spoken pieces
are cut from the original text, so they keep its exact characters. Returns a vector of (text, is_stage_direction);
a single piece means no split."""
function stage_pieces(content)
    text = strip(string(content))
    cuts = [0]
    for m in eachmatch(SENTENCE_BREAK, text)
        push!(cuts, m.offset + ncodeunits(m.match) - 1)
    end
    push!(cuts, ncodeunits(text))
    spans = [(nextind(text, cuts[i]), cuts[i+1]) for i in 1:length(cuts)-1 if cuts[i] < cuts[i+1]]
    sentence(sp) = strip(text[sp[1]:thisind(text, sp[2])])
    function stage(x)
        m = match(STAGE_SENTENCE, x)
        isnothing(m) && return false
        return length(split(x)) <= 40 && length(split(x[nextind(x, 0, length(m.match)):end])) <= 8
    end
    marks = [stage(sentence(sp)) for sp in spans]
    (length(spans) < 2 || !any(marks) || all(marks)) && return [(String(text), false)]
    pieces = Tuple{String,Bool}[]
    i = 1
    while i <= length(spans)
        j = i
        while j < length(spans) && marks[j+1] == marks[i] && !marks[i]
            j += 1
        end
        push!(pieces, (String(strip(text[spans[i][1]:thisind(text, spans[j][2])])), marks[i]))
        i = j + 1
    end
    return [p for p in pieces if !isempty(p[1])]
end

"#97: the speaker a row belongs to for counting turns, or nothing for non-speech rows"
function turn_key(row, h)
    isflag(row, h, :non_speech_flag) && return nothing
    nid = string(row[h[Symbol("name.id")]])
    return isna(nid) || nid == "UNKNOWN" ? "name:" * string(row[h[:name]]) : nid
end
