# Presiding officers (#90): name.id stays 10000; `role` gives the office, and `presiding_phid` gives the
# person's own Handbook id where it is reliable, otherwise N/A. Reliable means the row names the person in
# brackets ("The DEPUTY SPEAKER (Mr Vasta)", "Quick, Harry (Mr DEPUTY SPEAKER)"), or the row is the Speaker,
# President or Chair of Committees (and before 1970 the Senate's Deputy President, then the Chairman of Committees)
# under a clean printed title, and ausPH gives one holder of that office on the date (data/presiding_terms.csv, #186).
# Offices held by several people at once (deputy and temporary chairs, the Speaker's panel) are never guessed.

using CSV

# Set by RunModule before the edit steps run, since the edit steps only see file names
const CURRENT_HOUSE = Ref("house")

# #186: OCR breaks the title ("TEMPORARY-CHAIRMAN", "DEPUTY-PRESIDENT", "MrDEPUTY", "DEUPTY", "TEMPORAY"); a broken
# prefix read as missing would make a deputy or temporary chair the Speaker, President or Chairman
const PRESIDING_OFFICE = r"(?i)(?:\b|(?<=Mr))((?:acting[\s\-'’.^]*|tempora?r?y[\s\-'’.^]*)?(?:de?u?pu?ty[\s\-'’.^]*)?(?:speaker|president|chair(?:man)?))\b"
const PRESIDING_BRACKET = r"\(([^)]{2,80})\)"
const NAME_TITLES = Set(["mr", "mrs", "ms", "miss", "dr", "sir", "senator", "sen", "hon", "eon", "the", "dame", "madam", "lady", "rt",
                         # #186: post-nominals printed after the name ("Hon. Robert Halverson OBE")
                         "obe", "mbe", "cbe", "kbe", "am", "ao", "ac", "mc", "dso", "kcmg", "cmg", "qc", "kc", "oam", "mp"])
const DATA_DIR = joinpath(@__DIR__, "..", "data")

const MEMBERS = Ref{Union{Nothing,Dict{Tuple{String,String},Vector{Tuple{String,String,String,String}}}}}(nothing)

function members()
    if isnothing(MEMBERS[])
        d = Dict{Tuple{String,String},Vector{Tuple{String,String,String,String}}}()
        for r in CSV.File(joinpath(DATA_DIR, "members_by_surname.csv"); types=String)
            t = (r.phid, r.start, r.var"end", lowercase(coalesce(r.display_name, "")))
            push!(get!(d, (r.chamber, r.surname), Tuple{String,String,String,String}[]), t)
            # #193: "sullivan (formerly martin)" is found under either surname
            m = match(r"^(.*?)\s*\(formerly\s+([^)]+)\)\s*$", r.surname)
            if !isnothing(m)
                for k in (m.captures[1], m.captures[2])
                    push!(get!(d, (r.chamber, strip(k)), Tuple{String,String,String,String}[]), t)
                end
            end
        end
        MEMBERS[] = d
    end
    return MEMBERS[]
end

const MEMBER_NAME = Dict{String,String}()   # Handbook id → display name, lower case
const SERVICE = Ref{Union{Nothing,Dict{Tuple{String,String},Vector{Tuple{String,String}}}}}(nothing)

"(chamber, Handbook id) → the member's terms in that chamber, from data/members_by_surname.csv"
function service()
    if isnothing(SERVICE[])
        d = Dict{Tuple{String,String},Vector{Tuple{String,String}}}()
        for ((ch, _), v) in members(), (p, s, e, n) in v
            push!(get!(d, (ch, p), Tuple{String,String}[]), (s, e))
            MEMBER_NAME[p] = n
        end
        SERVICE[] = d
    end
    return SERVICE[]
end

"#195: is `id` a Handbook id of a member of either chamber? (upper case, as the Handbook writes them)"
is_phid(id) = haskey(service(), ("house", id)) || haskey(service(), ("senate", id))

"""#193: was member `id` serving in `house` within `slack` days of `date` (yyyy-mm-dd)?"""
function serving(house, id, date, slack=0)
    terms = get(service(), (house, id), nothing)
    isnothing(terms) && return false
    d = day_number(date)
    isnothing(d) && return true
    for (s, e) in terms
        ds, de = day_number(s), day_number(e)
        (isnothing(ds) || isnothing(de)) && continue
        ds - slack <= d <= de + slack && return true
    end
    return false
end

"Days since 0000-03-01 for a yyyy-mm-dd date, or nothing (no Dates dependency)"
function day_number(s)
    m = match(r"^(\d{4})-(\d{2})-(\d{2})", string(s))
    isnothing(m) && return nothing
    y, mo, d = parse.(Int, m.captures)
    mo <= 2 && (y -= 1; mo += 12)
    return 365y + y ÷ 4 - y ÷ 100 + y ÷ 400 + (153 * (mo - 3) + 2) ÷ 5 + d
end

"The presiding office named in `name` (\"DEPUTY SPEAKER\", \"CHAIR\", ...), or nothing"
function presiding_office(name)
    m = match(PRESIDING_OFFICE, string(name))
    isnothing(m) && return nothing
    o = uppercase(m.captures[1])
    o = replace(o, r"^ACTING[\s\-'’.^]*" => "ACTING ", r"^TEMPORA?R?Y[\s\-'’.^]*" => "TEMPORARY ", r"DE?U?PU?TY[\s\-'’.^]*" => "DEPUTY ")
    return replace(replace(o, r"\s+" => " "), "CHAIRMAN" => "CHAIR")
end

# #186: a title printed whole, with nothing garbled or added: only these take the office holder by date
# ("Mr SPEAKER", "The PRESIDENT", and from the 1970s the index form "SPEAKER, Mr", "PRESIDENT, The")
const CLEAN_TITLE = r"^(?:10000\s+)?(?:(?:the|mr\.?|madam|madame)\s*)?(speaker|president|chairman|chair|deputy president)(?:\s*,\s*(?:the|mr\.?|madam|madame))?\s*[.:,—–-]*\s*$"i
# ausPH offices whose one holder on a date is the person under each clean title, by chamber
const TITLE_OFFICES = Dict(
    ("house", "SPEAKER") => ("Speaker of the House of Representatives",),
    ("house", "CHAIR") => ("Chairman of Committees", "Deputy Speaker and Chairman of Committees"),
    ("senate", "PRESIDENT") => ("President of the Senate",),
    ("senate", "CHAIR") => ("Chairman of Committees", "Chair of Committees", "Deputy President and Chair of Committees"),
    # named rows agree 670 of 671 to 1969; from 1970 acting deputy presidents print as "The DEPUTY PRESIDENT"
    ("senate", "DEPUTY PRESIDENT") => ("Chairman of Committees",))
const TITLE_UNTIL = Dict(("senate", "DEPUTY PRESIDENT") => "1969-12-31")
# on a day in an acting term, "Mr SPEAKER" may be the acting Speaker
const ACTING_OFFICE = Dict("SPEAKER" => "Acting Speaker", "PRESIDENT" => "Acting President of the Senate")

"The office of a clean printed title (brackets holding a time or a name set aside), or nothing"
function clean_title(name)
    t = strip(replace(string(name), r"\([^)]*\)" => ""))
    m = match(CLEAN_TITLE, t)
    isnothing(m) && return nothing
    return replace(uppercase(replace(m.captures[1], r"\s+" => " ")), "CHAIRMAN" => "CHAIR")
end

const TERMS = Ref{Union{Nothing,Vector{NTuple{6,String}}}}(nothing)

"ausPH presiding-officer terms: (chamber, office, phid, surname, start, end); an empty end is open"
function presiding_terms()
    if isnothing(TERMS[])
        TERMS[] = [(r.chamber, r.office, r.phid, r.surname, r.start, coalesce(r.var"end", "9999-12-31"))
                   for r in CSV.File(joinpath(DATA_DIR, "presiding_terms.csv"); types=String)]
    end
    return TERMS[]
end

const SUCCESSIONS = Ref{Union{Nothing,Dict{Tuple{String,String,String},Set{String}}}}(nothing)

"(chamber, office, day) => the holders whose term starts that day"
function successions()
    if isnothing(SUCCESSIONS[])
        d = Dict{Tuple{String,String,String},Set{String}}()
        for t in presiding_terms()
            push!(get!(d, (t[1], t[2], t[5]), Set{String}()), t[3])
        end
        SUCCESSIONS[] = d
    end
    return SUCCESSIONS[]
end

"""A term covers `date`. #216: on the day one holder's term ends and another's starts, the office is the incoming
holder's (ausPH ends Parry's term as President and starts Ryan's on 13/11/2017, the day Ryan was elected)."""
function in_term(t, date)
    t[5] <= date <= t[6] || return false
    if date == t[6] && date != t[5]
        s = get(successions(), (t[1], t[2], date), nothing)
        !isnothing(s) && any(p -> p != t[3], s) && return false
    end
    return true
end

"#186: the one holder on `date` of the office a clean title stands for, or nothing"
function title_holder(house, title, date)
    offices = get(TITLE_OFFICES, (house, title), nothing)
    isnothing(offices) && return nothing
    date <= get(TITLE_UNTIL, (house, title), "9999-12-31") || return nothing
    acting = get(ACTING_OFFICE, title, nothing)
    !isnothing(acting) && any(t -> t[1] == house && t[2] == acting && in_term(t, date), presiding_terms()) && return nothing
    h = unique([t[3] for t in presiding_terms() if t[1] == house && t[2] in offices && in_term(t, date)])
    return length(h) == 1 ? h[1] : nothing
end

"""#186: the person a bracketed heading names, on either side of the bracket: "Mr DEPUTY SPEAKER (Mr Les Scott)",
"Quick, Harry (Mr DEPUTY SPEAKER)". A presiding officer of the chamber on the date is tried before all members."""
function presiding_named(house, date, name)
    name = string(name)
    b = match(PRESIDING_BRACKET, name)
    isnothing(b) && return nothing
    text = b.captures[1]
    if !isnothing(presiding_office(text))
        pre = strip(name[1:b.offset-1])
        parts = split(pre, ","; limit=2)
        text = length(parts) == 2 ? strip(parts[2]) * " " * strip(parts[1]) : pre
    end
    toks = [t for t in split(string(text), r"[\s.,]+") if !isempty(t) && !(lowercase(t) in NAME_TITLES) && length(t) > 1]
    isempty(toks) && return nothing
    surname = strip(lowercase(toks[end]), ['\'', '’'])
    c = unique([t[3] for t in presiding_terms() if t[1] == house && t[4] == surname && in_term(t, date)])
    length(c) == 1 && return c[1]
    return member_by_surname(house, date, join(toks, " "))
end

"""The one member of `house` serving on `date` whose surname ends `text`, or nothing. If several share
the surname, the other words in `text` (a first name) must pick out exactly one."""
function member_by_surname(house, date, text)
    toks = [t for t in split(string(text), r"[\s.,]+") if !isempty(t) && !(lowercase(t) in NAME_TITLES) && length(t) > 1]
    isempty(toks) && return nothing
    surname = strip(lowercase(toks[end]), ['\'', '’'])
    cands = unique([(p, n) for (p, s, e, n) in get(members(), (house, surname), []) if s <= date <= e])
    length(cands) == 1 && return cands[1][1]
    others = [lowercase(t) for t in toks[1:end-1]]
    picked = [p for (p, n) in cands if !isempty(others) && all(o -> occursin(o, n), others)]
    return length(picked) == 1 ? picked[1] : nothing
end

"""The person each clean title stands for on this day: the one person the day's rows name under that title, or with
none named, the office's one holder by date (#186). A title under which the day names two people is left out."""
function day_heads(rows, header_to_num, house, date)
    named = Dict{String,Set{String}}()
    for row in rows
        name = string(row[header_to_num[:name]])
        title = clean_title(name)
        (isnothing(title) || isnothing(match(PRESIDING_BRACKET, name))) && continue
        p = presiding_named(house, date, name)
        !isnothing(p) && push!(get!(named, title, Set{String}()), p)
    end
    heads = Dict{String,String}()
    for title in ("SPEAKER", "PRESIDENT", "CHAIR", "DEPUTY PRESIDENT")
        if haskey(named, title)
            length(named[title]) == 1 && (heads[title] = first(named[title]))
        else
            p = title_holder(house, title, date)
            !isnothing(p) && (heads[title] = p)
        end
    end
    return heads
end

"Sets `role` and returns the presiding_phid value for one row"
function presiding_phid!(row, header_to_num, house, date, heads=Dict{String,String}())
    name = row[header_to_num[:name]]
    nid = string(row[header_to_num[Symbol("name.id")]])
    office = presiding_office(name)
    if isnothing(office) || !(nid == "10000" || nid == "N/A")
        return "N/A"
    end
    if row[header_to_num[:role]] == "N/A"
        row[header_to_num[:role]] = titlecase(office)
    end
    p = presiding_named(house, date, name)
    !isnothing(p) && return p
    title = clean_title(name)
    return isnothing(title) ? "N/A" : get(heads, title, "N/A")
end
