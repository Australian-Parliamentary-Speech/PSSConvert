import PSSConvert
using EzXML
using InteractiveUtils
using Test
using CSV, DataFrames
using Glob
using BetterInputFiles
using PSSUtils
using Dates
include(joinpath(@__DIR__, "utils.jl"))
include(joinpath(@__DIR__, "similarity_funcs.jl"))
include(joinpath(@__DIR__, "clean_gs.jl"))
include(joinpath(@__DIR__, "csv_test.jl"))
include(joinpath(@__DIR__, "read_dates.jl"))

const RunModule = PSSConvert.RunModule
using PSSConvert.RunModule.EditModule
using PSSConvert.RunModule.Utils


struct test_struct
    skip_cols::Vector{Any}
    which_test::Symbol
    #fuzzy_bar_length, fuzzy_interval 
    fuzzy_search::Vector{Int64}
    toml::Any
    which_house::String
end

function setup(which_house)
    tomlpath = joinpath("test_inputs", "$(which_house).toml")
    toml = setup_input(tomlpath, false)
    global_options = toml["GLOBAL"]
    outputpath = global_options["OUTPUT_PATH"]
    xml_path_toml = toml["XML_DIR"][1]
    xml_path = xml_path_toml["PATH"]
    inputpath = joinpath("test_inputs", xml_path)
    return inputpath, outputpath, toml
end

function ensure_decompressed(path)
    tarball = path * ".tar.zst"
    tmp = tempname(dirname(path); cleanup=false)
    @info "Decompressing $tarball into scratch dir $tmp (leaving the original tarball untouched)..."
    decompress(tarball, tmp, clear=false)
    return tmp
end

function cleanup_decompressed(path)
    @info "Removing scratch dir $path..."
    rm(path, force=true, recursive=true)
end

function test_input_setup()
    tomlpath = joinpath("test_inputs", "test.toml")
    toml = setup_input(tomlpath, false)
    test_params = toml["TEST_PARAMS"]
    skip_cols = @. Symbol(test_params["SKIP_COLS"])
    which_sim_test = Symbol(test_params["WHICH_SIM_TEST"])
    fuzzy_search = test_params["FUZZY_SEARCH"]
    which_house = test_params["WHICH_HOUSE"]
    which_tests = test_params["WHICH_TESTS"]
    return skip_cols, which_sim_test, fuzzy_search, which_house, which_tests
end

function find_date(str)
    m = match(r"\d+-\d+-\d+", str)
    return m.match
end


function from_gs_to_sample(gs_name, test_setup)
    function sample_name_(date, step_num)
        return "$(date)_edit_step$(step_num).csv"
    end

    general_options = test_setup.toml["GENERAL_OPTIONS"]
    remove_nums = general_options["REMOVE_NUMS"]
    step_num = length(remove_nums)
    date = find_date(gs_name)
    sample_name = sample_name_(date, step_num)
    return sample_name
end


function get_sample_csvs(outputpath, gold_standard_csvs, sample_dir, test_setup)
    for gs_csv in gold_standard_csvs
        gs_name = basename(gs_csv)
        year = split(gs_name, "-")[1]
        sample_name = from_gs_to_sample(gs_name, test_setup)
        sample_file_name = joinpath([outputpath, year, sample_name])
        dir_file_name = joinpath(sample_dir, sample_name)
        cp(sample_file_name, dir_file_name, force=true)
    end
end


function remove_files(output_path, remove_num)
    function remove_check(file, num)
        if num != 0
            return occursin("step$(num).csv", file)
        elseif num == 0
            return occursin(r"\d", file) && !(occursin("step", file))
        end
    end

    for num in remove_num
        for file in readdir(output_path)
            if remove_check(file, num)
                rm(joinpath(output_path, file))
            end
        end
    end
end


function compare_gold_standard(outputpath, testpath, test_setup, test_output_path_csv, gold_standard_csvs)
    sample_csv_path = joinpath([testpath, "sample_csv", test_setup.which_house])
    mkpath(sample_csv_path)
    get_sample_csvs(outputpath, gold_standard_csvs, sample_csv_path, test_setup)
    similarity_ratio(gold_standard_csvs, sample_csv_path, test_output_path_csv, test_setup)
end

function similarity_ratio(gold_standard_csvs, sample_csv_path, test_output_path, test_setup)
    fn = joinpath(test_output_path, "overall_score.csv")
    open(fn, "w") do io
        row = ["gs_name", "ratio", "max_ratio", "gs/max"]
        println(io, edit_row(row))
        for gs_csv in gold_standard_csvs
            gs_name = basename(gs_csv)
            sample_name = from_gs_to_sample(gs_name, test_setup)
            sample_csv = joinpath(sample_csv_path, sample_name)
            @show "Comparing now $gs_name to $sample_csv"
            ratio = similarity_csv(gs_csv, sample_csv, test_setup, test_output_path)
            max_ratio = similarity_csv(sample_csv, sample_csv, test_setup, test_output_path)
            @show ratio
            @show max_ratio
            row = edit_row([gs_name, ratio, max_ratio, ratio / max_ratio])
            println(io, row)
        end
    end
end


@testset verbose = true "Entire set" begin
    skip_cols, which_sim_test, fuzzy_search, which_house, which_tests = test_input_setup()
    inputpath, outputpath, toml = setup(which_house)
    needs_outputpath = ("gold_standard" ∈ which_tests) || ("summary" ∈ which_tests)
    if needs_outputpath
        outputpath = ensure_decompressed(outputpath)
    end
    input_scratch_dir = nothing
    if "summary" ∈ which_tests
        input_scratch_dir = ensure_decompressed(dirname(inputpath))
        inputpath = joinpath(input_scratch_dir, basename(inputpath))
    end
    try
    #gold standard
    if "gold_standard" ∈ which_tests
        @test begin
            print("Gold standard test running ...")
            test_output_path = joinpath([@__DIR__, "test_outputs", "gs_outputs", "$which_house"])
            mkpath(test_output_path)

            test_setup = test_struct(skip_cols, which_sim_test, fuzzy_search, toml, which_house)
            gold_standard_path = joinpath([@__DIR__, "gold_standard", "$which_house"])
            clean_gs_files(gold_standard_path)
            gold_standard_csvs = get_all_csvnames(gold_standard_path)
            test_output_path_csv = joinpath(test_output_path, "CSVs")
            mkpath(test_output_path_csv)

            if true
                compare_gold_standard(outputpath, @__DIR__, test_setup, test_output_path_csv, gold_standard_csvs)
            end

            if "MP_specific_gs" ∈ which_tests
                print("Gold standard MP-specific test running ...")
                dates = all_GS_dates(gold_standard_csvs)
                date_to_list = MPs_not_perfect(dates, test_output_path_csv)
                date_to_impfct_namedict = Date_to_ImpftDict(date_to_list)
                date_to_namedict = Date_to_Dict(gold_standard_csvs)
                for (date, dict) in date_to_impfct_namedict
                    names = []
                    ratios = []
                    wrongs = []
                    totals = []
                    date_test_output_path = joinpath(test_output_path, date)
                    mkpath(date_test_output_path)
                    name_to_total = date_to_namedict[date]
                    for (id, count) in name_to_total
                        name = id
                        wrong = get(dict, id, "N/A")
                        if wrong == "N/A"
                            wrong = 0
                        end
                        total = count
                        ratio = 1 - (wrong / total)
                        push!(names, name)
                        push!(ratios, ratio)
                        push!(wrongs, wrong)
                        push!(totals, total)
                    end
                    df = DataFrame(id=names, ratio=ratios, wrong=wrongs, total=totals)
                    if df != DataFrame()
                        CSV.write(joinpath(date_test_output_path, "$(date)_each_MP.csv"), df)
                    else
                        @show date
                    end
                end

            end
            true
        end

    end

    if "toy_xml_test" ∈ which_tests
        #Test XML samples
        @test begin
            print("Test XML test running ...")
            general_options = toml["GENERAL_OPTIONS"]
            edit_funcs = general_options["EDIT"]
            remove_nums = general_options["REMOVE_NUMS"]
            csv_edit = general_options["CSV_EDIT"]
            xml_parsing = general_options["XML_PARSING"]

            for Phase in ["AbstractPhase", "Phase2011", "PhaseSGML"]
                test_dir = joinpath(@__DIR__, "xmls/$(Phase)/")
                !isdir(test_dir) && continue
                files = filter(!isdir, readdir(joinpath(@__DIR__, "xmls/$(Phase)/")))
                test_output_path = joinpath([@__DIR__, "test_outputs", "xml_test_outputs", Phase])
                mkpath(test_output_path)
                for file in files
                    fn = joinpath(@__DIR__, "xmls/$(Phase)/$file")
                    date_float, date, soup = RunModule.get_date(fn)
                    date = RunModule.run_xml(fn, test_output_path, xml_parsing, csv_edit, edit_funcs, String(which_house), test_output_path, date, date_float, soup)
                    remove_files(test_output_path, remove_nums)
                    sample_file = filter(contains(date), readdir(test_output_path))[1]
                    mv(joinpath(test_output_path, sample_file), joinpath(test_output_path, "$(file[1:end-4])_sample.csv"), force=true)
                end

                gs_files = filter(f -> endswith(f, ".csv"), readdir(joinpath("xml_gold_standard", Phase)))
                gs_csvs = filter(f -> endswith(f, ".csv"), gs_files)
                for gs_csv in gs_csvs
                    curr = joinpath(test_output_path, gs_csv)
                    correct = joinpath(joinpath("xml_gold_standard", Phase), gs_csv)
                    pass = check_csv(curr, correct)
                    print("$(gs_csv) is $(pass) \n")
                end
            end
            true
        end
    end

    if false
        @test begin
            print("Test CSV test running ...")
            test_output_path = joinpath([@__DIR__, "test_outputs", "CSV_test_outputs"])
            mkpath(test_output_path)

            known_errors_csv(outputpath, test_output_path)
            true
        end
    end

    if "summary" ∈ which_tests
        print("Dates...")
        @test begin
            sitting_house, sitting_senate = read_sitting_dates(@__DIR__)
            csv_fn = get_all_csv_dates(outputpath, @__DIR__, which_house)
            xml_fn = get_all_xml_dates(inputpath, @__DIR__, which_house)

            xml = CSV.read(xml_fn, DataFrame, header=false)
            csv = CSV.read(csv_fn, DataFrame, header=false)

            xmls = xml[:, 2]
            csvs = csv[:, 2]
            only_in_xml = setdiff(xmls, csvs)
            only_in_csv = setdiff(csvs, xmls)
            if which_house == "senate"
                only_in_sitting_not_xml = setdiff(sitting_senate, xmls)
                only_in_sitting_not_csv = setdiff(sitting_senate, csvs)
            elseif which_house == "house"
                only_in_sitting_not_xml = setdiff(sitting_house, xmls)
                only_in_sitting_not_csv = setdiff(sitting_house, csvs)

            else
                @assert "which_house is ill-defined"
            end
            open(joinpath(["test_outputs", "dates", "only_in_xml_$(which_house).csv"]), "w") do io
                for date in only_in_xml
                    println(io, date)
                end
            end
            open(joinpath(["test_outputs", "dates", "only_in_sitting_not_xml_$(which_house).csv"]), "w") do io
                for date in only_in_sitting_not_xml
                    println(io, date)
                end
            end
            open(joinpath(["test_outputs", "dates", "only_in_sitting_not_csv_$(which_house).csv"]), "w") do io
                for date in only_in_sitting_not_csv
                    println(io, date)
                end
            end

            true
        end
    end
    finally
        if needs_outputpath
            cleanup_decompressed(outputpath)
        end
#        if !isnothing(input_scratch_dir)
#            cleanup_decompressed(input_scratch_dir)
#        end
    end
end

