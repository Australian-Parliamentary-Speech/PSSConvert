export DivisionNode

abstract type DivisionNode{P} <: AbstractNode{P} end


function get_xpaths(::Type{<:DivisionNode})
    return ["division"]
end

# One non-speech row per division (conventions §3, #118): the header ("The House divided."), the presiding
# officer, the counts and the result. The lists of names are out of scope, so inside <ayes>, <noes> and <pairs>
# only <num.votes> and <title> are kept, and only where the count is given as <num.votes>.
const DIVISION_SKIP = ("names", "name", "time.stamp", "talker")
const DIVISION_VOTES = ("ayes", "noes", "pairs")

function division_text(xml_node)
    buf = IOBuffer()
    function walk(x)
        for c in nodes(x)
            if istext(c)
                print(buf, nodecontent(c), " ")
            elseif iselement(c)
                name = nodename(c)
                name in DIVISION_SKIP && continue
                # 1901-1980: a bare "AYES" or "NOES" paragraph heads the list of names
                name == "para" && occursin(r"^\s*(?:AYES|NOES|PAIRS)\.?\s*$", nodecontent(c)) && continue
                if name in DIVISION_VOTES
                    votes = findfirst("num.votes", c)
                    if !isnothing(votes)
                        for v in elements(c)
                            nodename(v) in ("num.votes", "title") && print(buf, nodecontent(v), " ")
                        end
                    end
                else
                    walk(c)
                end
            end
        end
    end
    walk(xml_node)
    return replace(strip(String(take!(buf))), r"\s+" => " ")
end

function parse_node(node::Node{<:DivisionNode}, node_tree, io)
    phase = get_phasetype(node)
    h = node.headers_dict
    for flag in ("question_flag", "answer_flag", "interjection_flag", "speech_flag", "petition_flag", "quote_flag", "motionnospeech_flag")
        h[flag] = 0
    end
    find_chamber(node, node_tree)
    h["content"] = division_text(node.node)
    h["subdebateinfo"] = find_section_title(node_tree, node.soup, SubdebateNode{phase})
    h["debateinfo"] = find_section_title(node_tree, node.soup, DebateNode{phase})
    h["path"] = node.node.path
    isempty(h["content"]) && return
    row = [r isa Int ? r : clean_text(r) for r in values(h)]
    write_row_to_io(io, row)
end
