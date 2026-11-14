# Speakers named by the printed text rather than by an id in the source: #136 fills the id of a named spoken
# row from the same day or the members list; #137 splits a row where a speaker heading is printed in its text.

const SPEAKER_TITLE = r"^(?:(?:his|her)\s+(?:excellency|majesty|royal\s+highness)\b|(?:the\s+)?(?:rt\.?\s+|right\s+)?hon(?:ou?rable)?\b|(?:the\s+)?(?:mr|mrs|ms|miss|dr|sir|senator|col|colonel|major|general|captain|lt|dame|madam|lady|prof)(?:\b|(?=(?-i:[A-Z]))))"i
const NOT_A_PERSON = r"(?i)'s\b|’s\b|\bdepartment\b|^\s*(?:dear|to|by|from|according\s+to|advise|let\s+me|yours)\b|\b(?:said|says|wrote|writes|replied|stated|states|asked|added|continued)\b|https?|www\.|\.gov\b|\.au\b|^[\W\d]*$"
const ID_TITLES = Set(["mr", "mrs", "ms", "miss", "dr", "sir", "senator", "hon", "honourable", "honorable", "the", "dame",
                       "madam", "lady", "rt", "col", "colonel", "major", "general", "captain", "lt", "prof", "mp"])

"#139: does `name` read as a person (a title and a name, or a presiding office), not a heading, salutation or link?"
function looks_like_speaker(name)
    s = strip(string(name))
    isempty(s) && return false
    occursin(NOT_A_PERSON, s) && return false
    return occursin(SPEAKER_TITLE, s) || !isnothing(presiding_office(s)) || !isnothing(collective_id(s)) ||
           occursin(r"^[A-Z][A-Za-z'’\-]+,\s", s) || occursin(r"(?i)^(?:the\s+)?(?:prime\s+|honorary\s+|assistant\s+)?minister\b(?!'s)", s)
end

"""The name words of a printed speaker name, titles and brackets taken out: "Mr. CONROY (Werriwa)" → ["CONROY"],
"SenatorSir FREDERICK SARGOOD" → ["FREDERICK", "SARGOOD"], "CONROY, Alfred" → ["Alfred", "CONROY"] (surname last)."""
function name_words(name)
    s = string(name)
    s = replace(s, r"\([^)]*\)?" => " ", r"\[[^\]]*\]?" => " ", r"[\"“”]" => " ")
    # titles run onto the next word in the OCR text: "SenatorSir", "Mr.Isaacs", "SirWilliam"
    for _ in 1:2
        s = replace(s, r"\b(Mr|Mrs|Ms|Dr|Sir|Senator|Col|Hon)\.?(?=[A-Z])" => s"\1 ")
    end
    if occursin(",", s)
        a, b = split(s, ","; limit=2)
        s = b * " " * a
    end
    toks = [strip(t, ['\'', '’', '-']) for t in split(s, r"[\s.,:;]+")]
    return [t for t in toks if length(t) > 1 && !(lowercase(t) in ID_TITLES) && occursin(r"^[A-Za-z'’\-]+$", t)]
end

surname_key(name) = (w = name_words(name); isempty(w) ? "" : lowercase(w[end]))

"Surname → the ids it goes with among the day's rows that have a member's own id"
function day_ids(rows, h)
    d = Dict{String,Set{String}}()
    nid = Symbol("name.id")
    for r in rows
        id = string(r[h[nid]])
        (isna(id) || id in GENERIC_IDS) && continue
        name = string(r[h[:name]])
        (isna(name) || !isnothing(presiding_office(name))) && continue
        k = surname_key(name)
        isempty(k) || push!(get!(d, k, Set{String}()), id)
    end
    return d
end

"""#136: the id of the member a printed name stands for, or nothing: the one id that surname has elsewhere in the day,
else the one member of `house` with that surname serving on `date` (a first name in the text may pick between several)."""
function resolve_id(name, house, date, dids)
    s = strip(string(name))
    (isna(s) || !looks_like_speaker(s) || !isnothing(presiding_office(s)) || !isnothing(collective_id(s))) && return nothing
    w = name_words(s)
    isempty(w) && return nothing
    ids = get(dids, lowercase(w[end]), nothing)
    !isnothing(ids) && length(ids) == 1 && return first(ids)
    # several ids for the surname that day: a first name in the text may still pick one out
    # a two-word surname ("Stott Despoja", "Di Natale")
    if length(w) >= 2
        two = lowercase(w[end-1] * " " * w[end])
        cands = unique([p for (p, s, e, n) in get(members(), (house, two), []) if s <= date <= e])
        length(cands) == 1 && return cands[1]
    end
    p = member_by_surname(house, date, join(w, " "))
    !isnothing(p) && return p
    # #147: initials printed before the surname ("Mr. L. E. GROOM") choose between members who share it
    inits = [m.captures[1] for m in eachmatch(r"\b([A-Z])\.", replace(s, r"^(?:Mr|Mrs|Ms|Dr|Sir|Senator)\.?\s*" => ""))]
    isempty(inits) && return nothing
    cands = unique([(p, n) for (p, s0, e, n) in get(members(), (house, lowercase(w[end])), []) if s0 <= date <= e])
    given(n) = [t for t in split(replace(split(n, ","; limit=2)[end], r"\([^)]*\)" => ""), r"[\s.]+")
                if length(t) > 1 && !(t in ("the", "hon", "rt", "sir", "dr", "dame", "lady", "kc", "qc", "ac", "ao", "am"))]
    hit = [p for (p, n) in cands if length(given(n)) >= length(inits) &&
           all(lowercase(inits[i]) == string(given(n)[i][1]) for i in eachindex(inits))]
    return length(hit) == 1 ? hit[1] : nothing
end

"#136: fills name.id for a named spoken row that has none. Returns true if it did."
function fill_id!(row, h, house, date, dids)
    nid = Symbol("name.id")
    any(f -> isflag(row, h, f), SPOKEN_FLAGS) || return false
    isna(row[h[nid]]) || return false
    id = resolve_id(row[h[:name]], house, date, dids)
    isnothing(id) && return false
    row[h[nid]] = id
    return true
end

# #137: a speaker heading printed in the text, at the start of the row or of a sentence:
# title, name in capitals, then an optional electorate and time, then ".-" (or "." straight onto the next word)
# #147: the OCR often garbles "Mr." ("Mi.", "Mir.", "Mi-.", "Mr.-"), and a heading can give initials ("Mr. L. E. GROOM")
const HEAD_TITLE = raw"(?:Mr\.?\s*-\.?|Mir?\s*[.\-]{1,3}|Mir\b|Mr\.?|Mrs\.?|Dr\.?|Senator|Col\.?|Colonel|Major|Captain|General|Sir)(?:\s*(?:Sir|Major|Colonel|Col\.|Dr\.?|the\s+Hon\.?))?"
const HEAD_NAME = raw"(?:[A-Z]\.\s*){0,3}(?:Mc|Mac|O'|D')?[A-Z][A-Z'’\-]{2,}(?:\s+(?:Mc|Mac|O'|D')?[A-Z][A-Z'’\-]+){0,3}"
const GARBLED_MR = Regex("^(?:Mr\\.?\\s*-\\.?|Mir?\\s*[.\\-]{1,3}|Mir\\b)\\s*")
const HEAD_TAIL = raw"\s*(?:,?\s*\([^)]{2,40}\)?)?\s*(?:\[[^\]]{1,15}?\]?|\(\d{1,2}[.:]\s*\d{2}[^)]{0,8}\))?"
const SPEAKER_HEAD = Regex("(?:^|(?<=[.!?:\"'”’)\\]])\\s+)(" * HEAD_TITLE * "\\s*" * HEAD_NAME * ")" * HEAD_TAIL *
                           raw"(?:\.?\s*[-—–]+\s*|\.(?=[A-Z]))")
# the SGML form "Mr REITH (Flinders) (3.04) Last night's ..." has no dash after the time
const SPEAKER_HEAD_SGML = Regex("(?:^|(?<=[.!?\"'”’)\\]])\\s+)(" * HEAD_TITLE * "\\s*" * HEAD_NAME * ")" *
                                raw"\s*\([^)]{2,40}\)\s*\(\d{1,2}[.:]\d{2}\)\s+(?=[A-Z])")
const NOT_HEAD_NAME = r"^(?:SPEAKER|PRESIDENT|CHAIRMAN|CHAIR|DEPUTY|ACTING|TEMPORARY|CLERK)\b"

"""#137: splits `content` where a member is named by a printed heading. Returns a vector of (text, id, name);
id and name are nothing for the text before the first heading. A heading is used only when its member is identified,
and it is taken out of the text. One piece with id nothing means no split."""
function speaker_segments(content, house, date, dids)
    text = string(content)
    heads = Tuple{Int,Int,String,String}[]   # (start, stop, id, name)
    for re in (SPEAKER_HEAD, SPEAKER_HEAD_SGML), m in eachmatch(re, text)
        # #147: a garbled "Mr." is read as "Mr"
        name = strip(replace(strip(m.captures[1]), GARBLED_MR => "Mr "))
        nm = replace(name, Regex("^" * HEAD_TITLE * "\\s*") => "")
        occursin(NOT_HEAD_NAME, nm) && continue
        id = resolve_id(name, house, date, dids)
        isnothing(id) && continue
        start = m.offset + (ncodeunits(m.match) - ncodeunits(lstrip(m.match)))
        push!(heads, (start, m.offset + ncodeunits(m.match), id, String(name)))
    end
    isempty(heads) && return [(text, nothing, nothing)]
    sort!(heads)
    out = Tuple{String,Any,Any}[]
    before = strip(text[1:prevind(text, heads[1][1])])
    isempty(before) || push!(out, (String(before), nothing, nothing))
    for (i, (s, e, id, name)) in enumerate(heads)
        i > 1 && s < heads[i-1][2] && continue
        stop = i < length(heads) ? prevind(text, heads[i+1][1]) : lastindex(text)
        piece = e <= stop ? strip(text[e:stop]) : ""
        isempty(piece) || push!(out, (String(piece), id, name))
    end
    return out
end

"#137: rows a printed speaker heading can be found in: spoken rows, and non-speech rows that are not a quote, petition,
document, division, heading or written answer"
function SPLIT_TYPES(row, h, nonspeech_type)
    any(f -> isflag(row, h, f), SPOKEN_FLAGS) && return true
    (isflag(row, h, :quote_flag) || isflag(row, h, :petition_flag) || string(row[h[:chamber_flag]]) == "3") && return false
    return nonspeech_type in ("other", "procedural", "N/A")
end
