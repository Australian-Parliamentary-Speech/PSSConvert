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
    elseif occursin(DIVISION, content) || occursin(r"/division(?:\[\d+\])?$", string(get(row, get(h, :path, 0), "")))
        return "division"
    elseif is_procedural(content)
        return "procedural"
    end
    return "other"
end

# anchored at the start, so a long row is still procedural when it carries the motion or clause text it reports
is_procedural(content) = occursin(PROCEDURAL_LINE, content) || occursin(PROCEDURAL_EXTRA, content) ||
                         (occursin(PROCEDURAL_QUALIFIED, content) && length(split(content)) <= 60)

# #146: the same record with a qualifier before the verb: "Amendment, by leave, withdrawn.", "Question, as amended,
# agreed to.", "Amendment (by Sir George Turner) agreed to-", "Proposed vote agreed to."
const PROCEDURAL_QUALIFIED = r"(?i)^(?:question|amendments?|(?:new\s+|postponed\s+)?(?:sub-?)?clauses?|motion|bill|schedule|title|preamble|requests?|proposed\s+votes?|votes?|items?|divisions?)\b(?:\s+[^\s,.!?()]+){0,4}?(?:\s*,[^,.!?]{1,40},)?(?:\s*\([^)]{1,60}\))?\s*,?\s*(?:agreed\s+to|negatived|withdrawn|reported|not\s+insisted\s+(?:on|upon)|insisted\s+(?:on|upon)|lapsed)\b"

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
    # a passage the presiding officer quotes or moves is theirs too, with 10000 (#148)
    spoken = any(f -> isflag(row, h, f), SPOKEN_FLAGS) || isflag(row, h, :quote_flag)
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
# a sentence ends at . ! ? or a closing bracket before a capital, an opening bracket or "by leave"; or at a dash before a
# capital, including a hyphen run onto the full stop when rows are joined ("affirmative.-I move")
const SENTENCE_BREAK = r"(?<=[.!?)\]}])\s+(?=[A-Z({\[]|by\s+leave)|(?<=[—–])\s*(?=[A-Z])|(?<=[.!?])-(?=[A-Z])"

"""#146: a procedural row that records several steps ("Amendment, as amended, agreed to. Clause, as amended, agreed to.
Title agreed to.") is one row per step, as stage directions are (§3), when every sentence in it is procedural."""
function procedural_pieces(content)
    text = strip(string(content))
    cuts = [0]
    for m in eachmatch(SENTENCE_BREAK, text)
        push!(cuts, m.offset + ncodeunits(m.match) - 1)
    end
    push!(cuts, ncodeunits(text))
    sents = [String(strip(text[nextind(text, cuts[i]):thisind(text, cuts[i+1])])) for i in 1:length(cuts)-1 if cuts[i] < cuts[i+1]]
    sents = [x for x in sents if !isempty(x)]
    (length(sents) < 2 || !all(x -> is_procedural(x) || occursin(STAGE_SENTENCE, x), sents)) && return [(String(text), false)]
    return [(x, true) for x in sents]
end

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

# a presiding officer presenting a paper ("I present the Selection Committee's report"), and a bill link used as an id
const PRESENTS = r"(?i)\bI\s+(?:now\s+)?(?:present|table|lay\s+on\s+the\s+table)\b"
const BILL_LINK = r"^[rs]\d+$"

# the editor's note that a document follows: in the past tense, or in brackets ("(The document reads as follows)");
# "The letter reads as follows" without brackets is spoken
const DOC_NOUN = raw"(?:document|answer|table|statement|speech|speeche|letter|list|schedule|report|eulogy|tribute|attachment|response|paper)s?"
const DOCUMENT_FOLLOWS = Regex(raw"(?:\(\s*The\s+(?:\w+\s+){0,2}?" * DOC_NOUN * raw"\s+reads?|\bThe\s+(?:\w+\s+){0,2}?" * DOC_NOUN *
                               raw"\s+read)\s+as\s+follows\s*\)?\s*[-—–:.]*")

"""#134: the note "The document read as follows" inside a spoken piece is split off as a row of its own (`:note`,
non-speech with no id, as gold codes it), and the words after it, if any, are the document (`:document`, §3). A piece
that is only the note is left alone: `incorporated!` already treats it as the note (#105)."""
function document_pieces(pieces)
    out = Tuple{String,Any}[]
    for (text, stage) in pieces
        m = stage ? nothing : match(DOCUMENT_FOLLOWS, text)
        isnothing(m) && (push!(out, (text, stage)); continue)
        cut = m.offset + ncodeunits(m.match)
        before = strip(text[1:prevind(text, m.offset)])
        note, after = strip(m.match), strip(text[cut:end])
        if length(split(after)) < 3
            # a stray bracket or dash after the note belongs to it
            note, after = strip(note * " " * after), ""
        end
        if isempty(before) && isempty(after)
            push!(out, (text, stage)); continue
        end
        isempty(before) || push!(out, (String(before), false))
        push!(out, (String(note), :note))
        isempty(after) || push!(out, (String(after), :document))
    end
    return out
end

const UPON_NOTICE = r"(?i)upon\s+notice"
const QUESTION_TIME = r"(?i)questions?\s+without\s+notice"
const GENERIC_IDS = ("10000", "UNKNOWN", "MEMBERS", "OPPOSITION", "GOVERNMENT", "GOVERNOR-GENERAL")
year_of(date) = something(tryparse(Int, first(string(date), 4)), 0)
spoken_row(r, h) = any(f -> isflag(r, h, f), SPOKEN_FLAGS)
real_id(r, h) = (nid = string(r[h[Symbol("name.id")]]); !isna(nid) && !(nid in GENERIC_IDS))

"""Rules that need the whole day, applied after every row is built. `rows` holds [row, presiding, nonspeech_type].
- Floor holder (all eras): an interjection by the member who holds the floor in that debate is their speech. Any
  speech, the chair's included, takes the floor.
- Questions upon notice (before 1981): a subdebate whose first spoken row is a question "upon notice" is a printed
  question and answer, quote rows included (#132): non-speech, chamber_flag 3, ids kept (§4, decided 2026-11-10; the question becomes
  written_question and the reply written_answer in written_questions!, #127), up to an
  oral supplementary ("Arising out of the answer ...").
- Question time in the 1981-1997 SGML conversion, where the source marks no questions or answers: in each
  Questions Without Notice subdebate the first member to speak asks (question); other members answer."""
function day_rules!(rows, h, date)
    yr = year_of(date)
    nid = Symbol("name.id")
    topic(r) = (string(r[h[:debateinfo]]), string(r[h[:subdebateinfo]]))
    # floor holder
    floor, ftopic = nothing, nothing
    for x in rows
        r = x[1]
        topic(r) != ftopic && (floor = nothing; ftopic = topic(r))
        if isflag(r, h, :speech_flag)
            # any speech, the chair's included, takes the floor; only a member's own id can hold it
            floor = real_id(r, h) ? string(r[h[nid]]) : nothing
        elseif isflag(r, h, :interjection_flag) && !isnothing(floor) && string(r[h[nid]]) == floor &&
               !occursin(r"(?i)interjecting", string(r[h[:content]]))
            set_type!(r, h, :speech_flag; clear=SPOKEN_FLAGS)
        end
    end
    speech_owner!(rows, h)
    # #142: the Governor-General's opening speech
    governor_general!(rows, h)
    groups = Dict{Tuple{String,String},Vector{Int}}()
    order = Tuple{String,String}[]
    for (i, x) in enumerate(rows)
        t = topic(x[1])
        haskey(groups, t) || push!(order, t)
        push!(get!(groups, t, Int[]), i)
    end
    for t in order
        idx = groups[t]
        spoken = [i for i in idx if spoken_row(rows[i][1], h) && string(rows[i][1][h[nid]]) != "10000"]
        isempty(spoken) && continue
        first_text = first(string(rows[spoken[1]][1][h[:content]]), 300)
        if yr < 1981 && occursin(UPON_NOTICE, first_text)
            for i in idx
                i < spoken[1] && continue
                r = rows[i][1]
                # the printed text of the question or answer can be a quote row (#132)
                ((spoken_row(r, h) && string(r[h[nid]]) != "10000") || isflag(r, h, :quote_flag)) || continue
                # an oral supplementary ("Arising out of the answer, may I ask ...") ends the printed answer
                occursin(r"(?i)^\s*arising\s+out\s+of", string(r[h[:content]])) && break
                set_type!(r, h, :non_speech_flag)
                r[h[:chamber_flag]] = 3
                rows[i][3] = "written_answer"
            end
        elseif 1981 <= yr <= 1997 && occursin(QUESTION_TIME, t[1]) && !occursin(QUESTION_TIME, t[2]) &&
               !any(i -> isflag(rows[i][1], h, :question_flag) || isflag(rows[i][1], h, :answer_flag), idx)
            asker = string(rows[spoken[1]][1][h[nid]])
            for i in spoken
                r = rows[i][1]
                isflag(r, h, :speech_flag) || continue
                set_type!(r, h, string(r[h[nid]]) == asker ? :question_flag : :answer_flag; clear=SPOKEN_FLAGS)
            end
        end
    end
    questions_on_notice!(rows, h)
    # words that lost their speaker, and petitions, before turns are merged
    last, ltopic, after_doc, in_list = nothing, nothing, false, false
    for x in rows
        r = x[1]
        topic(r) != ltopic && (last = nothing; ltopic = topic(r))
        content = string(r[h[:content]])
        unnamed_other = isflag(r, h, :non_speech_flag) && x[3] == "other" && isna(r[h[:name]]) && isna(r[h[nid]])
        if unnamed_other && occursin(r"(?i)petition", string(r[h[:debateinfo]])) && !occursin(STAGE_SENTENCE, strip(content))
            # petitions are petitions (decided 2026-11-10): the printed text in a Petitions debate
            set_type!(r, h, :petition_flag)
            x[3] = "N/A"
        elseif unnamed_other && !isnothing(last) && length(split(content)) >= 12 && !is_procedural(strip(content)) &&
               !occursin(READ_AS_FOLLOWS, strip(content)) && !after_doc && !(in_list && !occursin(r"\b(?:I|we|my|our|me|us)\b", content) && !occursin(r"^\s*\(\s*(?:\d{1,3}|[a-zA-Z]|[ivxIVX]{1,5})\s*\)", content)) && !occursin(r"^\s*That\b", content) &&
               !occursin(r"(?i)took\s+the\s+chair|suspended|standing\s+order|read\s+prayers", content) &&
               !any(p -> p[2] || occursin(STAGE_SENTENCE, p[1]), stage_pieces(content))
            # a spoken paragraph that lost its speaker: the member who was speaking continues
            set_type!(r, h, last[3]; clear=SPOKEN_FLAGS)
            r[h[:name]], r[h[nid]] = last[1], last[2]
            x[3] = "N/A"
        end
        # #137: the items of a list a speaker introduces with "the following …:" ("I present reports on the following
        # subjects:") are not their speech, unless the row speaks in the first person or is a numbered clause ("(a) …",
        # part of a motion or bill they read); the list runs while the rows after it are quotes or unnamed non-speech
        if spoken_row(r, h)
            in_list = occursin(r"(?i)\bthe\s+following\b[^.]{0,80}:\s*[-—–]?\s*$", content)
        elseif !(isflag(r, h, :quote_flag) || unnamed_other)
            in_list = false
        end
        if spoken_row(r, h) && !isna(r[h[:name]])
            flag = first(f for f in SPOKEN_FLAGS if isflag(r, h, f))
            last = flag in (:interjection_flag, :quote_flag) ? last : (string(r[h[:name]]), string(r[h[nid]]), flag)
        end
        after_doc = occursin(READ_AS_FOLLOWS, strip(content))
    end
    # #142: the text moved after "I move:" is a quote by the mover
    rows = motion_after!(rows, h)
    written_questions!(rows, h)
    return merge_turns(rows, h)
end

# a <speech> element, and what lies within it: "/speech[10]/interjection[44]/talk.start/para" -> ("…/speech[10]", "interjection[44]/…")
const SPEECH_PART = r"^(.*?/speech(?:\[\d+\])?)/(.*)$"

"""#135: the source often marks a member's own words inside their speech as an `<interjection>` by them, not a
`<continue>` (committee debates most of all). An interjection row inside a `<speech>` element, by the member who
opens that speech (its first talk.start or talk.text with a member's own id), is their speech (§1). Rows that say
"interjecting" are left alone."""
function speech_owner!(rows, h)
    haskey(h, :path) || return rows
    nid = Symbol("name.id")
    owner = Dict{String,String}()
    for x in rows
        r = x[1]
        m = match(SPEECH_PART, string(r[h[:path]]))
        isnothing(m) && continue
        el, rest = m.captures[1], m.captures[2]
        id = string(r[h[nid]])
        if !haskey(owner, el) && startswith(rest, "talk.") && spoken_row(r, h)
            owner[el] = real_id(r, h) ? id : ""
        elseif isflag(r, h, :interjection_flag) && startswith(rest, "interject") && get(owner, el, "") == id && id != "" &&
               !occursin(r"(?i)interjecting", string(r[h[:content]]))
            set_type!(r, h, :speech_flag; clear=SPOKEN_FLAGS)
        end
    end
    return rows
end

# "asked the Minister ..., upon notice", near the start (after "(Question No. 1109)" or a stray name fragment)
const ASKED = r"(?i)^.{0,40}?\basked\s+the\b"
# a minister reading a question out: "On the 28th March, Senator Dooley asked the following question, upon notice-"
const READS_OUT = r"(?i)\basked\s+the\s+following\s+questions?\b"
const READS_OUT_END = r"(?i)asked\s+the\s+following\s+questions?[\s,.:;—–-]*(?:upon\s+notice)?[\s,.:;—–-]*$"
# the start of a minister's reply, or a reply that still opens with the minister's name ("Mr. Fairbairn.-")
const ANSWER_TEXT = r"(?i)^(?:\s*(?:mr|mrs|dr|sir|senator)\.?\s*[a-z][\w'-]+\.?\s*[-—–]|.{0,160}?(?:\banswers?\s+to\s+the\s+(?:right\s+)?hono(?:u)?rable|\bhas\s+(?:now\s+)?(?:provided|supplied|furnished)\b|\bthe\s+answers?\s+(?:is|are)\b))"

# the first paragraph of a <question> element (in its talk.start or talk.text, perhaps after a <continue>);
# captures the parent element's path and the question element
const QUESTION_START = r"^(.*)/(question(?:\[\d+\])?)/(?:continue(?:\[\d+\])?/)?talk\.(?:start|text)\b"

"""#132: a printed question on notice that sits in a <question> element outside an answers-to-questions section
(after oral questions before 1981, in a `qwn` block or `rdi.item` in 1981-1997, in the Senate's Questions on
Notice debate from 1998). A spoken row that opens "asked the ..., upon notice" and is the first paragraph of a
<question> starts a printed question and answer: it and the spoken or quote rows after it under the same parent become non-speech,
chamber_flag 3, written_answer, until a different <question> begins, a spoken row under the parent is neither this
question nor an <answer>, the rows leave the parent, or an oral supplementary starts ("Arising out of ...").
Unnamed `other` rows in the block become written_answer too. written_questions! then splits question and answer."""
function questions_on_notice!(rows, h)
    haskey(h, :path) || return rows
    nid = Symbol("name.id")
    i = 1
    while i <= length(rows)
        r = rows[i][1]
        m = match(QUESTION_START, string(r[h[:path]]))
        content = first(string(r[h[:content]]), 300)
        if isnothing(m) || !spoken_row(r, h) || !occursin(ASKED, content) || !occursin(UPON_NOTICE, content)
            i += 1
            continue
        end
        parent, qel = m.captures[1] * "/", m.captures[2]
        j = i
        while j <= length(rows)
            x = rows[j]
            p = string(x[1][h[:path]])
            startswith(p, parent) || break
            child = first(split(p[length(parent)+1:end], '/'))
            if spoken_row(x[1], h) || isflag(x[1], h, :quote_flag)
                (child == qel || startswith(child, "answer")) || break
                j > i && occursin(r"(?i)^\s*arising\s+out\s+of", string(x[1][h[:content]])) && break
                set_type!(x[1], h, :non_speech_flag)
                x[1][h[:chamber_flag]] = 3
                x[3] = "written_answer"
            elseif x[3] == "other" && isna(x[1][h[:name]]) && isna(x[1][h[nid]])
                x[1][h[:chamber_flag]] = 3
                x[3] = "written_answer"
            end
            j += 1
        end
        i = max(j, i + 1)
    end
    return rows
end

"""#127: in a block of written questions and answers, the question is non-speech written_question and the
minister's reply stays written_answer. In order:
1. a minister reading a question out ("... asked the following question, upon notice") is the answer;
2. a row that starts "asked the ...", or follows a read-out, is a question;
3. a row that starts as a reply ("The answer to the honourable member's question", "has provided") is the answer;
4. the asker's later paragraphs are the question;
5. other paragraphs inside a <question> element are the question while one is open.
The <question> element alone does not start a question: some days' XML puts a reply inside one."""
function written_questions!(rows, h)
    nid = Symbol("name.id")
    asker, open_q, prev = nothing, false, ""
    for x in rows
        if x[3] != "written_answer"
            asker, open_q, prev = nothing, false, ""
            continue
        end
        r = x[1]
        path = haskey(h, :path) ? string(r[h[:path]]) : ""
        id = string(r[h[nid]])
        content = string(r[h[:content]])
        q = if occursin(READS_OUT, content)
            false
        elseif occursin(ASKED, content) || occursin(READS_OUT_END, prev)
            asker = id
            true
        elseif occursin(ANSWER_TEXT, content)
            false
        elseif open_q && !isna(id) && id == asker
            true
        else
            open_q && occursin(r"/question(?:\[\d+\])?/", path) && !occursin(r"/talk\.start/", path)
        end
        q && (x[3] = "written_question")
        open_q, prev = q, content
    end
    return rows
end

const TYPE_COLS = (:question_flag, :answer_flag, :interjection_flag, :speech_flag, :petition_flag, :quote_flag,
                   :motionnospeech_flag, :non_speech_flag)

"""§1: one row per turn. Consecutive rows with the same speaker (name and id), the same type, debate, subdebate and
chamber are one turn split by paragraph in the source, and become one row. Non-speech rows merge only when they are
paragraphs of one written answer or one incorporated document; procedural lines and headings stay one per row."""
function merge_turns(rows, h)
    nid = Symbol("name.id")
    sig(r) = (string(r[h[:name]]), string(r[h[nid]]), Tuple(haskey(h, c) ? string(r[h[c]]) : "" for c in TYPE_COLS),
              string(r[h[:debateinfo]]), string(r[h[:subdebateinfo]]), string(r[h[:chamber_flag]]))
    out = Vector{Vector{Any}}()
    for x in rows
        r, ptype = x[1], x[3]
        mergeable = ptype == "N/A" || ptype in ("written_answer", "written_question", "incorporated")
        if !isempty(out) && mergeable && out[end][3] == ptype && sig(out[end][1]) == sig(r) &&
           !(isna(r[h[:name]]) && isna(r[h[nid]]) && ptype == "N/A")
            prev = out[end][1]
            prev[h[:content]] = string(prev[h[:content]]) * " " * string(r[h[:content]])
        else
            push!(out, x)
        end
    end
    return out
end

"#97: the speaker a row belongs to for counting turns, or nothing for non-speech rows"
function turn_key(row, h)
    isflag(row, h, :non_speech_flag) && return nothing
    nid = string(row[h[Symbol("name.id")]])
    return isna(nid) || nid == "UNKNOWN" ? "name:" * string(row[h[:name]]) : nid
end
