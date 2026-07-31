function get_all_csv_dates(outputpath,testpath,which_house)
    function find_all_csv_dates(all_csv_names)
        simple_list = []
        for name in all_csv_names
            date_match = match(r"\d+-\d+-\d+",name)
            date = date_match.match
            push!(simple_list,date) 
        end
        return unique(simple_list)
    end
    all_csv_names = get_all_csv_subdir(outputpath)
    all_csv_dates = find_all_csv_dates(all_csv_names)
    years = [split(date,"-")[1] for date in all_csv_dates]
    fn = joinpath(testpath,"test_outputs","dates","all_csv_dates_$(which_house).csv")
    mkpath(dirname(fn))
    open(fn, "w") do io
        for (x,y) in zip(years, all_csv_dates)
            println(io, "$x,$y")
        end
    end
    return fn
end

function get_all_xml_dates(inputpaths,testpath,which_house)
    function find_all_xml_dates(all_xml_names)
        simple_list = []
        for name in all_xml_names
            date_match = match(r"\d+_\d+_\d+",name)
            date = date_match.match
            date = replace(date, "_" => "-")
            push!(simple_list,date)
        end
        return unique(simple_list)
    end
    all_xml_names = reduce(vcat, get_all_xml_subdir(inputpath) for inputpath in inputpaths)
    all_xml_dates = find_all_xml_dates(all_xml_names)
    years = [split(date,"-")[1] for date in all_xml_dates]
    fn = joinpath(testpath,"test_outputs","dates","all_xml_dates_$(which_house).csv")
    mkpath(dirname(fn))
    open(fn, "w") do io
        for (x,y) in zip(years, all_xml_dates)
            println(io, "$x,$y")
        end
    end
    return fn
end


function read_sitting_dates(testpath)
    csvfile = CSV.File(joinpath([testpath,"test_inputs","sitting_dates.csv"]))
    rows = eachrow(csvfile)
    house = []
    senate = []
    for row in rows
        row_ = @. collect(row)
        row = row_[1]
        date_ = row[1]
        year,month,day = Dates.year(date_), Dates.month(date_), Dates.day(date_)
        if month < 10
            month = "0$month"
        end
        if day < 10
            day = "0$day"
        end
        ##test##
#        if year == 1996 && month == 12 && day == 13
#            @show row
#        end
        #
        if_senate = row[3]
        if_house = row[2]
        if if_senate
            push!(senate,Date("$(year)-$(month)-$(day)"))
        end
        if if_house
            push!(house,Date("$(year)-$(month)-$(day)"))
        end 
    end
    return house, senate
end

