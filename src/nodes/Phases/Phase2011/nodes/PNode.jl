"""
get_xpaths(::Type{PNode{Phase2011}})

"para" as accepted xpaths for PNode.
"""
function get_xpaths(::Type{PNode{Phase2011}})
    return ["para"]
end

"""
get_sections(::Type{PNode{Phase2011}})

Allowed sections for PNodes.
"""
function get_sections(::Type{PNode{Phase2011}})
    return [Node{<:SpeechNode},Node{<:QuestionNode},Node{<:AnswerNode},Node{<:BusinessNode},Node{<:InterjectionNode},Node{<:MotionnospeechNode},Node{<:DebateNode},Node{<:QuoteNode_},Node{<:PetitionNode},Node{<:InterTalkNode},Node{<:SubdebateNode},Node{<:AdjournmentNode}]
end

"""
is_first_node_type(node::Node{PNode{Phase2011}},parent_node,allowed_names,node_tree)

A different method to detect if the pnode is the first pnode for this phase
"""
function is_first_node_type(node::Node{PNode{Phase2011}},parent_node,allowed_names,node_tree)

    if typeof(parent_node) <: Node{<:MotionnospeechNode}
        return true
    end
    # a <talk.start> holding only the <talker>: the turn's first paragraph follows it (#130)
    if hasprevelement(node.node)
        prev = prevelement(node.node)
        if nodename(prev) == "talk.start" && !any(c -> nodename(c) == "para", eachelement(prev))
            return true
        end
    end
    if !hasprevnode(node.node)
        return true
    else
        if nodename(prevnode(node.node)) == "talker"
            return true
        end
    end
    if hasprevnode(prevnode(node.node))
        if nodename(prevnode(prevnode(node.node))) == "talker"
            return true
        else
            return false
        end
    else
        return false
    end
end


function is_nodetype(node, node_tree, nodetype::Type{<:PNode},phase::Type{Phase2011},soup, args...; kwargs...) 
    nodetype = nodetype{phase}
    allowed_names = get_xpaths(nodetype)
    name = nodename(node)
    if name in allowed_names
        if length(node_tree) == 0
            return true
        else
            section_types = get_sections(nodetype)
            parent_node = node_tree[end]
            is_parent = any(section_node -> (typeof(parent_node) <: section_node), section_types)
            return is_parent
        end
    else
        return false
    end
end

function find_parent(node::Node{PNode{Phase2011}},node_tree)
    if hasprevelement(node.node)
        prev_node = prevelement(node.node)
        PrevNodeType = detect_node_type(prev_node, node_tree,node.soup,Phase2011)
        #dummy node
        if !isnothing(PrevNodeType)
            prev_node = Node{PrevNodeType{Phase2011}}(prev_node,1,node.date,node.soup,node.headers_dict)
            section_types = get_sections(typeof(node).parameters[1])
            is_prev_node_parent = any(section_node -> (typeof(prev_node) <: section_node), section_types)
            if is_prev_node_parent
                parent_node = prev_node
                return parent_node
            end
        end
    end
    return node_tree[end]
end


function process_node(node::Node{PNode{Phase2011}},node_tree)
    nodetype = typeof(node).parameters[1]
    allowed_names = get_xpaths(nodetype)
    if length(node_tree) > 0
        parent_node = find_parent(node,node_tree)
        c = node.node.content

        """otherwise it might go below and find the first speaker from below, essentially, if para lives under debate, there is no speaker"""

        """quote acts like a para node"""
        if typeof(node_tree[end]) <: Node{<:QuoteNode_}
            talker_parent = node_tree[end-1]
        else
            talker_parent = parent_node
        end


        p_interjecting_name(node::Node{<:PNode},parent_node)
        if node.headers_dict["name"] == "N/A"
            find_talker_in_p(node)
            if node.headers_dict["name"] != "N/A"
                if is_name(node.headers_dict["name"])
                    edge_case = "PNode_name_in_pnode"
                    write_test_xml(node,parent_node,edge_case)                
                end
            end
        end

        if node.headers_dict["name"] == "N/A"
           #only the first node takes after the name in the parent node
           if is_first_node_type(node,parent_node,allowed_names,node_tree)
               get_talker_from_parent(node,parent_node)
                if !(is_free_node(node,parent_node))
                    if node.headers_dict["name"] == "N/A"
                        name = findfirst_in_subsoup(parent_node.node.path,"//name",node.soup)
                        if !isnothing(name)
                            node.headers_dict["name"] = name.content           
                            edge_case = "PNode_first_node_in_parent"
                            write_test_xml(node,parent_node,edge_case)                    
                        end
                    end
                elseif is_free_node(node,parent_node) && node.headers_dict["name"] == "N/A"
                    node.headers_dict["name"] = "FREE NODE"
                    edge_case = "PNode_FREE_NODE"
                    write_test_xml(node,parent_node,edge_case) 
                end
            end 
        end


        if typeof(node_tree[end]) <: Node{<:InterTalkNode} && length(node_tree)>1
            flag_parent = node_tree[end-1]
        else
            flag_parent = node_tree[end]
        end

        define_flags(node,flag_parent,node_tree)
    else
        define_flags(node,node,node_tree)
    end
    return construct_row(node,node_tree)
end




