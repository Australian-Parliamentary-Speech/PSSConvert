export TableNode

# #100 (decided by Pat 15/11/2026): a table is one non-speech row, nonspeech_type `table`, with the id of the speech or
# answer it is part of. Cells are joined by " | " and table rows by " / ", so the text can be split back into a table
# (see docs/tables.md). A cell's own "|" becomes "¦" and the spaces around a "/" in a cell are dropped ("and / or"
# becomes "and/or"), so "|" always ends a cell and " / " always ends a table row;
# tabs, line breaks and other control characters become spaces, so every row is plain text on one line. A table inside
# a division (the 1981-1997 vote counts) stays part of the division row (#118).
abstract type TableNode{P} <: AbstractNode{P} end

function get_xpaths(::Type{<:TableNode})
    return ["table"]
end

const TABLE_CELLS = ("entry", "td", "th")
const TABLE_ROWS = ("row", "tr")
# control characters and the Unicode line and paragraph separators
const TABLE_CONTROL = Regex("[\\x00-\\x1f\\x7f\u2028\u2029]")

function table_cell_text(c)
    t = replace(nodecontent(c), TABLE_CONTROL => " ")
    t = replace(strip(replace(t, r"\s+" => " ")), "|" => "¦")
    return replace(t, r"\s*/\s*" => "/")
end

"The rows of this table (not of a table nested in it), each as its cells' text"
function table_rows(x)
    rows = Vector{Vector{String}}()
    function walk(e)
        for c in eachelement(e)
            name = nodename(c)
            name == "table" && continue
            if name in TABLE_ROWS
                cells = [table_cell_text(d) for d in eachelement(c) if nodename(d) in TABLE_CELLS]
                any(!isempty, cells) && push!(rows, cells)
            else
                walk(c)
            end
        end
    end
    walk(x)
    return rows
end

table_text(x) = join((join(r, " | ") for r in table_rows(x)), " / ")

function in_division(e)
    while hasparentnode(e)
        e = parentnode(e)
        nodetype(e) == EzXML.DOCUMENT_NODE && return false
        startswith(nodename(e), "division") && return true
    end
    return false
end

function parse_node(node::Node{<:TableNode}, node_tree, io)
    in_division(node.node) && return
    phase = get_phasetype(node)
    h = node.headers_dict
    if !isempty(node_tree)
        parent = node_tree[end]
        sections = (SpeechNode, QuestionNode, AnswerNode, BusinessNode, DebateNode, SubdebateNode, DebateTextNode)
        any(t -> parent isa Node{<:t}, sections) && get_talker_from_parent(node, parent)
    end
    for flag in ("question_flag", "answer_flag", "interjection_flag", "speech_flag", "petition_flag", "quote_flag", "motionnospeech_flag")
        h[flag] = 0
    end
    find_chamber(node, node_tree)
    h["content"] = table_text(node.node)
    h["subdebateinfo"] = find_section_title(node_tree, node.soup, SubdebateNode{phase})
    h["debateinfo"] = find_section_title(node_tree, node.soup, DebateNode{phase})
    h["path"] = node.node.path
    isempty(h["content"]) && return
    row = [r isa Int ? r : clean_text(r) for r in values(h)]
    write_row_to_io(io, row)
end
