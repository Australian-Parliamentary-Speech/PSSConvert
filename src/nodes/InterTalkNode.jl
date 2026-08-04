export InterTalkNode

abstract type InterTalkNode{P} <: AbstractNode{P} end

"""
get_xpaths(::Type{<:InterTalkNode})

The default setting for what nodenames are allowed for intertalknode.
"""
function get_xpaths(::Type{<:InterTalkNode})
    return ["talk.start"]
end

function process_node(node::Node{<:InterTalkNode},node_tree)
    nothing
end

function parse_node(node::Node{<:InterTalkNode},node_tree,io)
    nothing
end


function is_nodetype(node, node_tree, nodetype::Type{<:InterTalkNode}, phase::Type{<:AbstractPhase}, soup, args...; kwargs...)
    NP = nodetype{phase}
    allowed_names = get_xpaths(NP)
    name = nodename(node)
    return name in allowed_names
end

