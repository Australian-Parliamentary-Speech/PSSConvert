# Presiding officers (#90): name.id stays 10000; `role` gives the office, and `presiding_phid` gives the
# person's own Handbook id where it is reliable, otherwise N/A. Reliable means the row names the person in
# brackets ("The DEPUTY SPEAKER (Mr Vasta)"), or the row is the Speaker, President or Chair of Committees,
# whose holder on that date is in data/office_holders.csv. Deputies and acting chairs are never guessed.

using CSV

# Set by RunModule before the edit steps run, since the edit steps only see file names
const CURRENT_HOUSE = Ref("house")

const PRESIDING_OFFICE = r"(?i)\b((?:acting\s+|temporary\s+)?(?:deputy\s+)?(?:speaker|president|chair(?:man)?))\b"
const PRESIDING_BRACKET = r"\(([^)]{2,80})\)"
const NAME_TITLES = Set(["mr", "mrs", "ms", "miss", "dr", "sir", "senator", "hon", "the", "dame", "madam", "lady", "rt"])
const DATA_DIR = joinpath(@__DIR__, "..", "data")

const OFFICE_HOLDERS = Ref{Union{Nothing,Dict{Tuple{String,String,String},String}}}(nothing)
const MEMBERS = Ref{Union{Nothing,Dict{Tuple{String,String},Vector{Tuple{String,String,String,String}}}}}(nothing)

function office_holders()
    if isnothing(OFFICE_HOLDERS[])
        d = Dict{Tuple{String,String,String},String}()
        for r in CSV.File(joinpath(DATA_DIR, "office_holders.csv"); types=String)
            d[(r.chamber, r.office, r.date)] = r.phid
        end
        OFFICE_HOLDERS[] = d
    end
    return OFFICE_HOLDERS[]
end

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
    return replace(uppercase(replace(m.captures[1], r"\s+" => " ")), "CHAIRMAN" => "CHAIR")
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

"Speaker, President and Chair of Committees named in brackets anywhere in the day (they do not change within a day)"
function day_heads(rows, header_to_num, house, date)
    heads = Dict{String,String}()
    for row in rows
        name = string(row[header_to_num[:name]])
        office = presiding_office(name)
        b = match(PRESIDING_BRACKET, name)
        if !isnothing(office) && office in ("SPEAKER", "PRESIDENT", "CHAIR") && !isnothing(b)
            p = member_by_surname(house, date, b.captures[1])
            !isnothing(p) && (heads[office] = p)
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
    b = match(PRESIDING_BRACKET, string(name))
    if !isnothing(b)
        p = member_by_surname(house, date, b.captures[1])
        !isnothing(p) && return p
    end
    if office in ("SPEAKER", "PRESIDENT", "CHAIR")
        return get(heads, office, get(office_holders(), (house, office, date), "N/A"))
    end
    return "N/A"
end
