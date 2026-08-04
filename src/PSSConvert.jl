module PSSConvert
using Reexport
using ArgParse
using DocStringExtensions
using BetterInputFiles
using PSSUtils

# Internal packages
include("RunModule.jl")
@reexport using .RunModule

# Exports
export main

"""
get_args()

Parse command-line arguments

This function sets up and parses command-line arguments using the `ArgParse` package. It defines the arguments that can be passed to the script, including options for verbosity and input file path.
"""
function get_args()
    s = ArgParseSettings()

    @add_arg_table! s begin
        "--verbose", "-v"
        action = :store_true
        help = "Increase logging verbosity"

        "--should_compress", "-c"
        action = :store_true
        help = "Compress output"

        "--skip", "-s"
        action = :store_true
        help = "Skip processing, usually combined with -c to compress a completed run"

        "input"
        help = "Path to input toml file. Can be relative or absolute."
        required = true
    end

    return parse_args(s; as_symbols=true)
end

"""
run(input, verbose)

Main function to initialize and execute the Parlinfo Speech Scraper Converter

This function initializes the input configuration from a TOML file specified by `toml_path` with optional verbosity controlled by `verbose`. It then runs PSSConvert using the configuration.

Inputs:
- `input`: Path to the TOML configuration file.
- `verbose`: Boolean flag indicating if logging verbosity should be increased.
"""
function run(; input::AbstractString, verbose::Bool, should_compress::Bool, skip::Bool)
    toml = setup_input(input, verbose)
    output_path = toml["GLOBAL"]["OUTPUT_PATH"]
    if !skip
        if isfile(output_path * ".tar.zst")
            @info "Decompressing previous run..."
            rm(output_path, force=true, recursive=true)
            decompress(output_path * ".tar.zst", output_path, clear=true)
        end
        @time run_PSSConvert(toml)
    end
    if should_compress
        compress(output_path, output_path * ".tar.zst", clear=true)
    end
    return true
end

function (@main)(_ARGS)
    return run(; get_args()...) ? 0 : 1
end


end
