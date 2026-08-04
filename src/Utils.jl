module Utils

export write_row_to_io
export date_to_float
export edit_row

"""
    date_to_float(year, month, day)

Encode `year`/`month`/`day` as one sortable `Float64` (month and day packed
into the fractional part).
"""
function date_to_float(year, month, day)
    return round(year + month / 120 + day / 3100, digits=6)
end


function edit_row(row)
    edit_row = ""
    for i in row
        i = replace(string(i), "\"" => "\'")
        edit_row = edit_row * "\"$i\","
    end
    return edit_row[1:end-1]
end

function replace_empty_string(row)
    @assert length(collect(skipmissing(row))) == length(row)
    return map(x -> isempty(x) ? "N/A" : x, row)
end

function write_row_to_io(io, row)
    row = replace_empty_string(row)
    edit_row_ = edit_row(row)
    println(io, edit_row_)
end



end
