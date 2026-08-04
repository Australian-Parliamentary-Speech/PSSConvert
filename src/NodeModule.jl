module NodeModule
using EzXML
using OrderedCollections
using InteractiveUtils
using ..XMLModule
using ..Utils

export detect_node_type
export Node
export GenericNode
export parse_node
export detect_phase
export GenericPhase
export AbstractPhase
export define_headers
export is_name

abstract type AbstractPhase end

abstract type GenericPhase <: AbstractPhase end

abstract type AbstractNode{P<:AbstractPhase} end

abstract type GenericNode{P} <: AbstractNode{P} end

struct Node{N<:AbstractNode}
    node::EzXML.Node
    index::Int64
    date::Float64
    soup
    headers_dict::OrderedDict{String,Any}
end

get_nodetype(::Node{N}) where {N} = N
get_phasetype(::Node{N}) where {P<:AbstractPhase,N<:AbstractNode{P}} = P

#Get Default Nodes
const node_path = joinpath(@__DIR__, "nodes")
for path in readdir(node_path, join=true)
    if isfile(path)
        include(path)
    end
end

# Included phases can add to this dictionary
date_to_phase = Dict()

date_to_phase_senate = Dict()

# Included phases can add to this dictionary
range_to_phase = Dict()

# Get Phase Overwrites
const phase_path = joinpath(node_path, "Phases")
for dir in readdir(phase_path, join=true)
    for path in readdir(dir, join=true)
        if isfile(path)
            include(path)
        end
    end
end

"""
detect_phase(date, which_house)

Inputs:
- `date`: A floating-point number representing the date to detect the phase for.
- `house`: A string that indicates either senate or house

Returns:
- The phase associated with the provided `date`, or `AbstractPhase` if no specific phase is found.
"""
function detect_phase(date, which_house)
    if which_house == "senate"
        phase = detect_phase_senate(date)
    elseif which_house == "house"
        phase = detect_phase_house(date)
    else
        @error "which_house is not correctly given"
    end
end

"""
    detect_phase_senate(date)

Looks up `date` in `date_to_phase_senate`; falls back to `detect_phase_house`
if no senate-specific phase is registered.
"""
function detect_phase_senate(date)
    phase = get(date_to_phase_senate, date, nothing)
    if !isnothing(phase)
        return phase
    end
    for (date_range, phase) in date_to_phase_senate
        min_date, max_date = date_range
        if min_date <= date <= max_date
            return phase
        end
    end
    if isnothing(phase)
        return detect_phase_house(date)
    end
end

"""
    detect_phase_house(date)

Looks up `date` in `date_to_phase` (exact match or within a registered
range); returns `AbstractPhase` if nothing matches.
"""
function detect_phase_house(date)
    # See if year has specific phase
    phase = get(date_to_phase, date, nothing)
    if !isnothing(phase)
        return phase
    end

    # See if date in range with phase
    for (date_range, phase) in date_to_phase
        min_date, max_date = date_range
        if min_date <= date <= max_date
            return phase
        end
    end

    # Any other logic you want can go here

    # No specific phase for this date
    return AbstractPhase
end

"""
    get_all_subtypes(type, st=[])

Get every subtype of the provided `type` parameter.

Inputs:
- `type`: the provided type
"""
function get_all_subtypes(type, st=[])
    for subt in subtypes(type)
        push!(st, subt)
        get_all_subtypes(subt, st)
    end
    return st
end

const all_subtypes = get_all_subtypes(AbstractNode)

"""
reverse_find_first_node_name(node_tree, names)

Inputs:
- `node_tree`: A vector representing a tree of nodes to search in reverse order.
- `names`: A collection of node names to search for.

Returns:
- The first node from `node_tree` in reverse order whose name is in the `names` collection, or `nothing` if no such node is found.
"""
function reverse_find_first_node_name(node_tree, names)
    reverse_node_tree = reverse(node_tree)
    index = findfirst(n -> nodename(n.node) ∈ names, reverse_node_tree)
    if isnothing(index)
        return nothing
    else
        return reverse_node_tree[index]
    end
end


"""
revers_find_first_node_not_name(node_tree, names)

Inputs:
- `node_tree`: A vector representing a tree of nodes to search in reverse order.
- `names`: A collection of node names. The function searches for the first node from `node_tree` in reverse order whose name is not in this collection.

Returns:
- The first node from `node_tree` in reverse order whose name is not in the `names` collection, or `nothing` if no such node is found.
"""
function reverse_find_first_node_not_name(node_tree, names)
    reverse_node_tree = reverse(node_tree)
    index = findfirst(n -> nodename(n.node) ∉ names, reverse_node_tree)
    if isnothing(index)
        return nothing
    else
        return reverse_node_tree[index]
    end
end

"""
detect_node_type(node, node_tree, date, soup, PhaseType)

default setting:

Inputs:
- `node`: The XML node to determine the type for.
- `node_tree`: A vector representing a tree of nodes
- `soup`: The root node.
- `PhaseType`: The phase type determined from the date of XML.

Returns:
- The detected node type (`NodeType`).
"""
function detect_node_type(node, node_tree, soup, PhaseType)
    for NodeType in all_subtypes
        if is_nodetype(node, node_tree, NodeType, PhaseType, soup)
            return NodeType
        end
    end
end

"""
parse_node(node::Node, node_tree, io)

default setting:

Inputs:
- `node`: xml node of Node struct
- `node_tree`: A vector representing a tree of nodes for context.
- `io`: The output stream where processed data is written.
"""
function parse_node(node::Node, node_tree, io)
    process_node(node, node_tree)
end

"""
process_node(node::Node, node_tree)

default setting:

Inputs:
- `node`: xml node of Node struct
- `node_tree`: A vector representing a tree of nodes for context.

Notes:
- This function is typically invoked when no specific processing behavior is defined for the `NodeType` associated with `node`.
- Users may customize or define specific behaviors for different `NodeType` instances within their implementation.
"""
function process_node(node::Node, node_tree)
    nothing
end


"""
is_nodetype(node, node_tree, nodetype::Type{<:AbstractNode}, phase::Type{<:AbstractPhase}, soup, args...; kwargs...)

default setting:

Inputs:
- `node`: The XML node to evaluate.
- `node_tree`: A vector representing a tree of nodes for context.
- `nodetype`: A subtype of `AbstractNode` representing the type of node to check against.
- `phase`: A subtype of `AbstractPhase` representing the phase associated with the node.
- `soup`: The root node.
- `args...`: Optional additional arguments.
- `kwargs...`: Optional keyword arguments.

Returns:
- `true` if the name of `node` is found in the allowed names associated with `nodetype` for the given `phase`, `false` otherwise.

Notes:
More specific detection method for nodes is defined in nodes/
"""
function is_nodetype(node, node_tree, nodetype::Type{<:AbstractNode}, phase::Type{<:AbstractPhase}, soup, args...; kwargs...)
    NP = nodetype{phase}
    allowed_names = get_xpaths(NP)
    name = nodename(node)
    return name in allowed_names
end

"""
get_xpaths(::Type{<:N}) where {N <: AbstractNode}

This function serves as a placeholder and returns an empty array, which is meant to provide the nodenames allowed for each type. For example, speech nodes can have names "speech" or "continue". 
"""
function get_xpaths(::Type{<:N}) where {N<:AbstractNode}
    return []
end

"""
get_talker_from_parent(node::Node,parent_node::Node)

It finds the speaker information from the parent node
"""
function get_talker_from_parent(node::Node, parent_node::Node)
    soup = parent_node.soup
    parent_node = parent_node.node
    talker_node = findfirst_in_subsoup(parent_node.path, "//talker", soup)
    function find_content(xpath)
        talker_content_node = findfirst_in_subsoup(talker_node.path, xpath, soup)
        if isnothing(talker_content_node)
            return "N/A"
        else
            return talker_content_node.content
        end
    end

    function find_id(node)
        if node.headers_dict["name.id"] == "N/A"
            talker = findfirst_in_subsoup(talker_node.path, "//name", soup)
            if !isnothing(talker)
                talker_id = findfirst_in_subsoup(talker.path, "/@nameid", soup)
                if !isnothing(talker_id)
                    node.headers_dict["name.id"] = clean_text(talker_id.content)
                end
            end
        end
    end
    function find_headers_from_node(node, parent_node, headers)
        talker_xpaths_nodes = ["/@speaker", "/@nameid", "/@electorate", "/@party", "/@role", "/@page"]
        header_and_xpath = zip(headers, talker_xpaths_nodes)
        for hx in header_and_xpath
            header, xpath = hx
            if node.headers_dict[header] == "N/A"
                info = findfirst_in_subsoup(parent_node.path, xpath, soup)
                if !isnothing(info)
                    #                    @debug info.content
                    node.headers_dict[header] = info.content
                end
            end
        end
    end

    talker_xpaths = ["//name", "//name.id", "//electorate", "//party", "//role", "//page.no"]
    headers = ["name", "name.id", "electorate", "party", "role", "page.no"]
    header_and_xpath = zip(headers, talker_xpaths)
    if !isnothing(talker_node)
        for hx in header_and_xpath
            header, xpath = hx
            talker_content = find_content(xpath)
            node.headers_dict[header] = talker_content
            find_id(node)
            find_headers_from_node(node, parent_node, headers)
        end

    end

end

"""
find_chamber(node, node_tree)

Identifies the type of chamber associated with the given XML `node`.

Inputs:
- `node`: The XML node 
- `node_tree`: A vector representing a tree of nodes for context.

Returns:
- An integer indicating the chamber type:
  - `2` for a federal chamber (`FedChamberNode`).
  - `1` for a chamber (`ChamberNode`).
  - `0` if no chamber node is found.
"""
function find_chamber(node, node_tree)
    chamber_node = reverse_find_first_node_name(node_tree, vcat(get_xpaths(ChamberNode), get_xpaths(FedChamberNode), get_xpaths(AnswersToQuestionsNode)))
    if chamber_node isa Node{<:FedChamberNode}
        return node.headers_dict["chamber_flag"] = 2
    elseif chamber_node isa Node{<:ChamberNode}
        return node.headers_dict["chamber_flag"] = 1
    elseif chamber_node isa Node{<:AnswersToQuestionsNode}
        return node.headers_dict["chamber_flag"] = 3
    else
        #        @error "no chamber is found"
        return node.headers_dict["chamber_flag"] = 0
    end
end

function free_node_parent_types(node::Node{<:AbstractNode{<:AbstractPhase}})
    #    return [DebateNode]
    return [DebateNode, SubdebateNode, SpeechNode]
end

"""
    is_free_node(node, parent_node)

True if `parent_node`'s type is one of `free_node_parent_types(node)`.
"""
function is_free_node(node::Node{<:AbstractNode{<:AbstractPhase}}, parent_node)
    """to toggle the free node feature"""
    if true
        ParentTypes = free_node_parent_types(node)
        for type in ParentTypes
            if parent_node isa Node{<:type}
                return true
            end
        end
    end
    return false
end
#

"""
define_flags(node::Node{<:AbstractNode{<:AbstractPhase}}, node_tree)

Generates flags based on the characteristics of the given `node`.

Inputs:
- `node`: A `Node` struct.
- `node_tree`: A vector representing a tree of nodes for context.

Returns:
- An array of flags indicating characteristics of `node`
"""
function define_flags(node::Node{<:AbstractNode{<:AbstractPhase}}, parent_node, node_tree)
    function is_interjecting(node)
        if node.headers_dict["interjection_flag"] == 1
            return true
        end
        a_soup = findfirst_in_subsoup(node.node.path, "//a", node.soup)
        if !isnothing(a_soup)
            p_talker = findfirst_in_subsoup(a_soup.path, "/@type", node.soup)
            if !isnothing(p_talker)
                if occursin("Interjecting", p_talker.content)
                    node.headers_dict["interjection_flag"] = 1
                    edge_case = "Interjecting_in_a"
                    write_test_xml(node, parent_node, edge_case)
                    return true
                end
            end
        else
        end
        return false
    end
    if !is_interjecting(node)
        ParentTypes = [QuestionNode, AnswerNode, InterjectionNode, SpeechNode, PetitionNode, QuoteNode_, MotionnospeechNode]
        headers = ["question_flag", "answer_flag", "interjection_flag", "speech_flag", "petition_flag", "quote_flag", "motionnospeech_flag"]
        flags = map(node_type -> parent_node isa Node{<:node_type} ? 1 : 0, ParentTypes)
        header_and_flag = zip(headers, flags)
        for couple in header_and_flag
            node.headers_dict[couple[1]] = couple[2]
        end
    else
        headers = ["question_flag", "answer_flag", "speech_flag", "petition_flag", "quote_flag", "motionnospeech_flag"]
        for header in headers
            node.headers_dict[header] = 0
        end
    end
    chamber = find_chamber(node, node_tree)
end

"""find_section_title(node_tree, soup, section_type)

Inputs:
- `node`: The XML node from which to extract the section title.
- `node_tree`: A vector representing a tree of nodes for context.
- `soup`: The root node of the XML document.
- `section_type`: The nodenames of the types of section nodes where the title is wanted. For example, "speech".

Returns:
- The title of the specified `section_type` found within the XML document, or "N/A" if not found.
"""
function find_section_title(node_tree, soup, section_type)
    section_node = reverse_find_first_node_name(node_tree, get_xpaths(section_type))
    if isnothing(section_node)
        return "N/A"
    end
    section_title_path = get_section_title_path(typeof(section_node).parameters[1])

    title = findfirst_in_subsoup(section_node.node.path, section_title_path, soup)
    if isnothing(title)
        return "N/A"
    else
        return clean_text(title.content)
    end
end

function find_p_node_parent(node::Node{<:PNode}, node_tree)
    return node_tree[end]
end

function define_headers(::Type{<:AbstractPhase})
    headers = ["question_flag", "answer_flag", "interjection_flag", "speech_flag", "petition_flag", "quote_flag", "motionnospeech_flag", "chamber_flag", "name", "name.id", "electorate", "party", "role", "page.no", "content", "subdebateinfo", "debateinfo", "path"]
    #    headers = ["question_flag","answer_flag","interjection_flag","speech_flag","chamber_flag","name","name.id","electorate","party","role","page.no","content","subdebateinfo","debateinfo","path"]
    headers_dict = OrderedDict(headers .=> ["N/A" for h in headers])
    return headers_dict
end

"""
    get_node_content(node, content)

Rebuilds `content` from `node`'s children, adding a space around any
`"inline"` child's text.
"""
function get_node_content(node::Node{<:AbstractNode{<:AbstractPhase}}, content)
    content = ""
    for element in nodes(node.node)
        if nodename(element) == "inline"
            ele_content = " $(nodecontent(element)) "
            content = content * ele_content
        else
            content = content * nodecontent(element)
        end
    end
    return content
end


"""
Writes the test xmls for all edge cases: it cannot handle dummy parent as root itself -- soup is getting passed and not document type
"""
function write_test_xml(trigger_node, parent_node, edge_case)
    if isnothing(edge_case)
        return
    end
    function get_relink(node)
        if hasprevnode(node)
            prev = prevnode(node)
            return n -> linknext!(prev, n)
        elseif hasnextnode(node)
            next = nextnode(node)
            return n -> linkprev!(next, n)
        end

        parent = parentnode(node)
        return n -> link!(parent, n)
    end
    log_node = string(nameof(get_nodetype(trigger_node)))
    log_phase = string(nameof(get_phasetype(trigger_node)))
    dir_name = joinpath(@__DIR__, "../test/xmls/$log_phase/")
    mkpath(dir_name)
    fn = "$(log_node)_$(edge_case).xml"
    fn_orig_doc = "$(log_node)_$(edge_case)_orig_doc.xml"
    fn_curr_doc = "$(log_node)_$(edge_case)_curr_doc.xml"
    fpath = joinpath(dir_name, fn)
    fpath_orig_doc = joinpath(dir_name, fn_orig_doc)
    fpath_curr_doc = joinpath(dir_name, fn_curr_doc)

    if !isfile(fpath)
        orig_doc = string(document(trigger_node.soup))
        write(fpath_orig_doc, orig_doc)
        #get time block
        soup = trigger_node.soup
        time_node = parentnode(findfirst("//session.header/date", soup))
        time_relink! = get_relink(time_node)

        doc = XMLDocument()
        elm = ElementNode("root")
        setroot!(doc, elm)

        unlink!(time_node)
        link!(elm, time_node)
        tree_parent = parent_node.node

        tree_parent_relink! = get_relink(tree_parent)
        unlink!(tree_parent)
        linknext!(time_node, tree_parent)

        node = trigger_node.node
        prev_siblings = []
        while (hasprevnode(node))
            prior = prevnode(node)
            push!(prev_siblings, prior)
            unlink!(prior)
        end

        next_siblings = []
        while (hasnextnode(node))
            next = nextnode(node)
            push!(next_siblings, next)
            unlink!(next)
        end

        write(fpath, doc)
        unlink!(time_node)
        time_relink!(time_node)

        unlink!(tree_parent)
        tree_parent_relink!(tree_parent)

        prev_siblings = prev_siblings
        post = node
        for prior in prev_siblings
            unlink!(prior)
            linkprev!(post, prior)
            post = prior
        end
        prior = node
        for next in next_siblings
            unlink!(next)
            linknext!(prior, next)
            prior = next
        end

        curr_doc = string(document(trigger_node.soup))
        write(fpath_curr_doc, curr_doc)
        @assert orig_doc == curr_doc
        rm(fpath_curr_doc)
        rm(fpath_orig_doc)
    end
end


"""
    is_name(name)

False if `name` is `nothing`, has more than 5 words, contains a digit, or is
`"Committee"`; true otherwise.
"""
function is_name(name)
    if isnothing(name)
        return false
    end

    number = length(split(name, " "))
    if number > 5
        return false
    end

    if occursin(r"\d", name)
        return false
    end

    occurs = @. occursin(["Committee"], name)
    return iszero(occurs)
end

function find_prev_node_from_tree(node_tree, node_type)
    for node in reverse(node_tree)
        if node isa Node{<:node_type}
            return node
        end
    end
    return missing
end


end
