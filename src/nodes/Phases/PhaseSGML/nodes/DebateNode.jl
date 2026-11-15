function get_section_title_path(::Type{DebateNode{PhaseSGML}})
    return "/title"
end


function get_xpaths(::Type{DebateNode{PhaseSGML}})
#    return ["qwn"]
    # #86: a suspension of standing orders (<sso>, with its own <title>) holds speeches like a debate
    return ["debate","qwn","answer.to.qon","sso"]
end

