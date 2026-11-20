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
    # #87: a curly apostrophe ("O’Neil") is the members list's straight one
    s = replace(string(name), '’' => '\'')
    # #87: an opening bracket with no closing one is OCR noise before the surname ("Mr. (Poynton", "Sir JOHN (FORREST")
    s = replace(s, r"\((?![^)]*\))" => " ", r"/" => " ")
    s = replace(s, r"\([^)]*\)?" => " ", r"\[[^\]]*\]?" => " ", r"[\"“”]" => " ")
    # titles run onto the next word in the OCR text: "SenatorSir", "Mr.Isaacs", "SirWilliam"
    for _ in 1:2
        s = replace(s, r"\b(Mr|Mrs|Ms|Dr|Sir|Senator|Col|Hon)\.?(?=[A-Z])" => s"\1 ")
    end
    if occursin(",", s)
        a, b = split(s, ","; limit=2)
        s = b * " " * a
    end
    toks = [strip(t, ['\'', '’', '-', '—', '–']) for t in split(s, r"[\s.,:;]+")]
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
    # a formal motion moved without a speech (<motionnospeech>, 1998-2010) is the named member's too
    (any(f -> isflag(row, h, f), SPOKEN_FLAGS) || isflag(row, h, :motionnospeech_flag)) || return false
    isna(row[h[nid]]) || return false
    id = resolve_id(row[h[:name]], house, date, dids)
    isnothing(id) && return false
    row[h[nid]] = id
    return true
end

# #137: a speaker heading printed in the text, at the start of the row or of a sentence:
# title, name in capitals, then an optional electorate and time, then ".-" (or "." straight onto the next word)
# #147: the OCR often garbles "Mr." ("Mi.", "Mir.", "Mi-.", "Mr.-"), and a heading can give initials ("Mr. L. E. GROOM")
const HEAD_TITLE = raw"(?:Mr\.?\s*-\.?|Mir?\s*[.\-]{1,3}|Mir\b|M[xn][;:,.]|111-?\.|Mr[,;]|Mr\.?|Mrs\.?|Dr\.?|Senator|Col\.?|Colonel|Major|Captain|General|Sir)(?:\s*(?:Sir|Major|Colonel|Col\.|Dr\.?|the\s+Hon\.?))?"
const HEAD_NAME = raw"(?:[A-Z]\.\s*){0,3}(?:Mc|Mac|O'|D')?[A-Z][A-Z'’\-]{2,}(?:\s+(?:Mc|Mac|O'|D')?[A-Z][A-Z'’\-]+){0,3}"
const GARBLED_MR = Regex("^(?:Mr\\.?\\s*-\\.?|Mir?\\s*[.\\-]{1,3}|Mir\\b|M[xn][;:,.]|111-?\\.|Mr[,;])\\s*")
const HEAD_TAIL = raw"\s*(?:,?\s*\([^)]{2,40}\)?)?\s*(?:\[[^\]]{1,15}?\]?|\(\d{1,2}[.:]\s*\d{2}[^)]{0,8}\))?"
const SPEAKER_HEAD = Regex("(?:^|(?<=[.!?:\"'”’)\\]])\\s+)(" * HEAD_TITLE * "\\s*" * HEAD_NAME * ")" * HEAD_TAIL *
                           raw"(?:\.?\s*[-—–]+\s*|\.(?=[A-Z]))")
# the SGML form "Mr REITH (Flinders) (3.04) Last night's ..." has no dash after the time
const SPEAKER_HEAD_SGML = Regex("(?:^|(?<=[.!?\"'”’)\\]])\\s+)(" * HEAD_TITLE * "\\s*" * HEAD_NAME * ")" *
                                raw"\s*\([^)]{2,40}\)\s*\(\d{1,2}[.:]\d{2}\)\s+(?=[A-Z])")
# #107: with an electorate in brackets the heading is clear enough to allow the OCR's noise around it: a comma in
# the name ("Mr. WINTER, COOKE (Wannon)"), a garbled time ("[45l", "M.81."), and the words run on with or without a
# space ("(Wannon).Being", "(Western Australia). When", "[45lThe")
const HEAD_NAME_LOOSE = raw"(?:[A-Z]\.\s*){0,3}(?:Mc|Mac|O'|D')?[A-Z][A-Z'’\-]{2,}(?:,?\s+(?:Mc|Mac|O'|D')?[A-Z][A-Z'’\-]+){0,3}"
const SPEAKER_HEAD_BRACKET = Regex("(?:^|(?<=[.!?:\"'”’)\\]])\\s+)(" * HEAD_TITLE * "\\s*" * HEAD_NAME_LOOSE * ")" *
                                   raw"\s*,?\s*\([A-Z][^)]{1,40}\)(?:\s*[\[(|]?\s?[\dA-Za-z.:,]{1,8}?[\])|]?)?" *
                                   raw"(?:\.?\s*[-—–]+\s*|\.\s*(?=[A-Z\"“])|(?=[A-Z][a-z]))")
const NOT_HEAD_NAME = r"^(?:SPEAKER|PRESIDENT|CHAIRMAN|CHAIR|DEPUTY|ACTING|TEMPORARY|CLERK)\b"

"""#137: splits `content` where a member is named by a printed heading. Returns a vector of (text, id, name);
id and name are nothing for the text before the first heading. A heading is used only when its member is identified,
and it is taken out of the text. One piece with id nothing means no split."""
function speaker_segments(content, house, date, dids)
    text = string(content)
    heads = Tuple{Int,Int,String,String}[]   # (start, stop, id, name)
    for re in (SPEAKER_HEAD, SPEAKER_HEAD_SGML, SPEAKER_HEAD_BRACKET), m in eachmatch(re, text)
        # #147: a garbled "Mr." is read as "Mr"; #107: a comma inside a printed heading is OCR noise, not "Surname, Given"
        name = strip(replace(replace(strip(m.captures[1]), GARBLED_MR => "Mr "), "," => " "))
        nm = replace(name, Regex("^" * HEAD_TITLE * "\\s*") => "")
        occursin(NOT_HEAD_NAME, nm) && continue
        id = resolve_id(name, house, date, dids)
        isnothing(id) && continue
        start = m.offset + (ncodeunits(m.match) - ncodeunits(lstrip(m.match)))
        push!(heads, (start, m.offset + ncodeunits(m.match), id, String(name)))
    end
    isempty(heads) && return [(text, nothing, nothing)]
    # the same heading can be matched by more than one pattern: keep one head per place, the longest
    sort!(heads, by = x -> (x[1], -x[2]))
    kept = Tuple{Int,Int,String,String}[]
    for hd in heads
        (isempty(kept) || hd[1] >= kept[end][2]) && push!(kept, hd)
    end
    heads = kept
    out = Tuple{String,Any,Any}[]
    before = strip(text[1:prevind(text, heads[1][1])])
    isempty(before) || push!(out, (String(before), nothing, nothing))
    for (i, (s, e, id, name)) in enumerate(heads)
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

# #88: ParlInfo's old SGML-era speaker codes (mostly 1981-1997), mapped to Parliamentary Handbook ids by the reviewed
# table data/legacy_ids.csv (each mapping with its basis)
const LEGACY_IDS = Ref{Union{Nothing,Dict{String,Tuple{String,String}}}}(nothing)

function legacy_ids()
    if isnothing(LEGACY_IDS[])
        LEGACY_IDS[] = Dict(r.legacy_id => (r.phid, lowercase(strip(split(r.display_name, ",")[1])))
                            for r in CSV.File(joinpath(DATA_DIR, "legacy_ids.csv"); types=String))
    end
    return LEGACY_IDS[]
end

"""#88: replaces an old ParlInfo code in name.id with the member's Handbook id. A row whose printed name gives a
different surname keeps its code, in case the code was reused."""
function legacy_id!(row, h)
    nid = Symbol("name.id")
    m = get(legacy_ids(), strip(string(row[h[nid]])), nothing)
    isnothing(m) && return row
    w = name_words(string(row[h[:name]]))
    if !isempty(w) && isnothing(presiding_office(string(row[h[:name]]))) && lowercase(w[end]) != m[2] &&
       !endswith(m[2], " " * lowercase(w[end]))
        return row
    end
    row[h[nid]] = m[1]
    return row
end

"#195: a Handbook id written in lower case (\"e5z\") is the Handbook's upper-case id"
function upper_id!(row, h)
    nid = Symbol("name.id")
    id = strip(string(row[h[nid]]))
    u = uppercase(id)
    u != id && (is_phid(u) || haskey(legacy_ids(), u)) && (row[h[nid]] = u)
    return row
end

"#193, #199: the one member of `house` sitting on `date` that the printed name words `w` (lower case) give, or nothing"
function name_member(house, date, w)
    isempty(w) && return nothing
    if length(w) >= 2
        c = unique([q for (q, s, e, n) in get(members(), (house, w[end-1] * " " * w[end]), []) if s <= date <= e])
        length(c) == 1 && return c[1]
    end
    return member_by_surname(house, date, join(w, " "))
end

has_word(n, t) = occursin(Regex("\\b" * replace(t, r"([\\^$.|?*+()\[\]{}-])" => s"\\\1") * "\\b"), n)

"""#193: a row whose id is a member not sitting in this chamber on this date (Kilgariff's old ParlInfo code `8H7`
is Enderby's Handbook id; Senator Staniforth Smith carries the House's Sydney Smith) takes the id of the one sitting
member the printed name stands for. Left alone: a member within 250 days of a term (senators speak before their
recorded 1 July start), an id whose own member the printed name matches (a senator at a joint sitting), and names
that do not give exactly one sitting member.
#199: so does a row whose id is a sitting member but whose printed surname is someone else's ("FRASER, Malcolm"
carrying Holt's id; an interjection by Mr Hewson carrying the Prime Minister's)."""
function relink!(row, h, house, date)
    # #215: a relinked row may carry the printed party and electorate of the talker block it came in, often the speech
    # it interrupts ("Mr Sinclair interjecting--" inside Hand's speech): final_re clears them when they are that
    # member's (`relinked_details!`), and the member's own come from their other rows
    return relink_id!(row, h, house, date)
end

"""#215: rows relinked from `old` to another member keep their printed party and electorate unless these are the
ones `old`'s own rows that day carry, in which case they were the interrupted speaker's and become N/A. `relinked`
maps a row's index in `rows` to the id it had before relinking."""
function relinked_details!(rows, h, relinked)
    (isempty(relinked) || !haskey(h, :electorate) || !haskey(h, :party)) && return rows
    nid = h[Symbol("name.id")]
    own = Dict{String,Set{Tuple{String,String}}}()
    for (i, r) in enumerate(rows)
        haskey(relinked, i) && continue
        id = String(string(r[nid])); e, p = String(string(r[h[:electorate]])), String(string(r[h[:party]]))
        (is_phid(id) && !(isna(e) && isna(p))) || continue
        push!(get!(own, id, Set{Tuple{String,String}}()), (e, p))
    end
    for (i, old) in relinked
        r = rows[i]
        e, p = String(string(r[h[:electorate]])), String(string(r[h[:party]]))
        (isna(e) && isna(p)) && continue
        (e, p) in get(own, old, Set{Tuple{String,String}}()) && ((r[h[:electorate]], r[h[:party]]) = ("N/A", "N/A"))
    end
    return rows
end

function relink_id!(row, h, house, date)
    nid = Symbol("name.id")
    id = string(row[h[nid]])
    is_phid(id) || return row
    name = string(row[h[:name]])
    (isna(name) || !isnothing(presiding_office(name))) && return row
    # #109: "Opposition members" inside a minister's answer carried the minister's id (SGML era); the voice is collective
    cid = collective_id(name)
    if !isnothing(cid)
        row[h[nid]] = cid
        return row
    end
    w = [lowercase(replace(t, '’' => '\'')) for t in name_words(name)]
    isempty(w) && return row
    own = get(MEMBER_NAME, id, "")
    # #205: the id is a member not yet or no longer in Parliament ("PAGE, Earle" `C7E` in 1901): the printed surname
    # gives the one member of that surname sitting in this chamber, whatever the first name
    if !serving("house", id, date, 250) && !serving("senate", id, date, 250)
        p = member_by_surname(house, date, w[end])
        if !isnothing(p) && p != id && serving(house, p, date)
            row[h[nid]] = p
            return row
        end
    end
    if serving(house, id, date, 250)
        # #199: the printed surname must be another member's, and that member must be sitting
        surname = length(w) >= 2 && haskey(members(), (house, w[end-1] * " " * w[end])) ? w[end-1] * " " * w[end] : w[end]
        has_word(own, surname) && return row
        p = name_member(house, date, w)
        (isnothing(p) || p == id) && return row
        has_word(get(MEMBER_NAME, p, ""), surname) || return row
        row[h[nid]] = p
        return row
    end
    all(t -> occursin(t, own), w) && return row
    p = name_member(house, date, w)
    (isnothing(p) || p == id || !serving(house, p, date)) && return row
    row[h[nid]] = p
    return row
end

const KEEP_CODE = r"^[0-9A-Z]{3,6}$"
const JUNK_CODES = ("EOF", "CHAMBER")

"""#200: an id that is neither a Handbook id nor a documented code (`20000`, `Unknown`, an old ParlInfo code #88 could
not map, `#director`, a code read from a cut heading) takes what the printed name gives: one sitting member, a
collective voice, the Governor-General or the Clerk. Otherwise it is `N/A`, which the later steps fill from the name
(#136) or make `UNKNOWN` on a spoken row (#95). ParlInfo's own codes for non-members (visiting heads of state:
`009C3`, `G5F`, `GYB`) become `VISITOR` when the name gives nothing, and `N/A` with no printed name (#206)."""
function clean_id!(row, h, house, date)
    nid = Symbol("name.id")
    id = strip(string(row[h[nid]]))
    (isna(id) || id in GENERIC_IDS || is_phid(id)) && return row
    name = string(row[h[:name]])
    cid = isna(name) ? nothing : collective_id(name)
    if !isnothing(cid)
        row[h[nid]] = cid
    elseif occursin(r"(?i)governor[\s-]*general", name)
        row[h[nid]] = "GOVERNOR-GENERAL"
    elseif occursin(r"(?i)\bclerk\b", name) && !occursin(r"(?i)minister", name)
        row[h[nid]] = "10001"
    else
        w = isna(name) || !isnothing(presiding_office(name)) ? String[] :
            [lowercase(replace(t, '’' => '\'')) for t in name_words(name)]
        p = name_member(house, date, w)
        if !isnothing(p)
            row[h[nid]] = p
        elseif occursin(KEEP_CODE, id) && !occursin(r"^\d+$", id) && !(id in JUNK_CODES) &&
               !isna(name) && !occursin(r"(?i)^\s*unknown\s*$", name)
            row[h[nid]] = "VISITOR"
        else
            row[h[nid]] = "N/A"
        end
    end
    return row
end

# #201: the heading cut between `name` and `content`: "Senator" + "GALLAGHER: I welcome …", "The PRESIDE" + "NT: Senator …"
const CUT_NAME = r"^(?:Senator|Sen|Se|Mr|Ms|Mrs|Miss|Dr|Sir|Madam|The|The\s+[A-Z]{1,10})$"
const HEAD_REST = r"^((?:Mc|Mac|O'|O’)?[A-Z][A-Za-z'’\-]*(?:\s+(?:Mc|Mac|O'|O’)?[A-Z][A-Za-z'’\-]+){0,3})\s*(\([^)]{1,80}\))?\s*(?:\(\d{1,2}[:.]\d{2}\))?\s*:\s*"
const NAME_TITLE_WORDS = Set(["Senator", "Mr", "Ms", "Mrs", "Miss", "Dr", "Sir", "Madam", "The", "Hon"])

"#201: joins a speaker heading cut between `name` and `content`. Returns true if it did."
function join_cut_name!(row, h)
    name = strip(string(row[h[:name]]))
    (isna(name) || !occursin(CUT_NAME, name)) && return false
    content = string(row[h[:content]])
    m = match(HEAD_REST, content)
    if isnothing(m)
        # the rest of the heading is lost: a bare title with a member's id takes the member's Handbook surname
        id = string(row[h[Symbol("name.id")]])
        name in NAME_TITLE_WORDS && name != "The" && is_phid(id) || return false
        own = get(MEMBER_NAME, id, "")
        isempty(own) && return false
        row[h[:name]] = name * " " * uppercase(strip(split(own, ",")[1]))
        return true
    end
    last = split(name)[end]
    sep = last in NAME_TITLE_WORDS ? " " : ""
    joined = replace(name * sep * m.captures[1], r"^Sen?(?:ATOR|NATOR)\b"i => "Senator")
    row[h[:name]] = joined * (isnothing(m.captures[2]) ? "" : " " * m.captures[2])
    row[h[:content]] = content[m.offset + ncodeunits(m.match):end]
    return true
end

