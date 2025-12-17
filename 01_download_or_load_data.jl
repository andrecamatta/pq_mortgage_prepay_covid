# =============================================================================
# 01_download_or_load_data.jl
# =============================================================================
# Load Freddie Mac data (REAL DATA ONLY) and FRED mortgage rates.
#
# REQUIREMENTS:
# 1. Download Freddie Mac Sample Dataset from:
#    https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset
# 2. Place files in:
#    - data/raw/freddiemac/orig/ → sample_orig_*.txt files
#    - data/raw/freddiemac/svcg/ → sample_svcg_*.txt files
#    - data/raw/freddiemac/docs/ → file_layout.xlsx, user guide (optional)
# =============================================================================

using CSV, DataFrames, Dates, Downloads, Statistics
using Glob
using Arrow
using OrderedCollections: OrderedDict

# Load column configuration
include(joinpath(@__DIR__, "config", "columns.jl"))

# =============================================================================
# Configuration
# =============================================================================

const DATA_DIR = joinpath(@__DIR__, "data")
const RAW_DIR = joinpath(DATA_DIR, "raw")
const FREDDIE_DIR = joinpath(RAW_DIR, "freddiemac")
const INTERIM_DIR = joinpath(DATA_DIR, "interim")
const PROCESSED_DIR = joinpath(DATA_DIR, "processed")

# FRED MORTGAGE30US data
const FRED_MORTGAGE_URL = "https://fred.stlouisfed.org/graph/fredgraph.csv?bgcolor=%23e1e9f0&chart_type=line&drp=0&fo=open%20sans&graph_bgcolor=%23ffffff&height=450&mode=fred&recession_bars=on&txtcolor=%23444444&ts=12&tts=12&width=1318&nt=0&thu=0&trc=0&show_legend=yes&show_axis_titles=yes&show_tooltip=yes&id=MORTGAGE30US&scale=left&cosd=1971-04-02&coed=2099-01-01&line_color=%234572a7&link_values=false&line_style=solid&mark_type=none&mw=3&lw=2&ost=-99999&oet=99999&mma=0&fml=a&fq=Weekly%2C%20Ending%20Thursday&fam=avg&fgst=lin&fgsnd=2020-02-01&line_index=1&transformation=lin&vintage_date=2024-01-01&revision_date=2024-01-01&nd=1971-04-02"
const FRED_CSV_PATH = joinpath(RAW_DIR, "MORTGAGE30US.csv")

# =============================================================================
# Core Functions
# =============================================================================

"""
    ensure_dirs()

Create data directories if they don't exist.
"""
function ensure_dirs()
    for dir in [RAW_DIR, FREDDIE_DIR, INTERIM_DIR, PROCESSED_DIR,
                joinpath(FREDDIE_DIR, "orig"),
                joinpath(FREDDIE_DIR, "svcg"),
                joinpath(FREDDIE_DIR, "docs")]
        mkpath(dir)
    end
    @info "Data directories created/verified: $DATA_DIR"
end

"""
    read_freddie_pipe(file::AbstractString, idx::OrderedDict{Symbol,Int}; 
                      types::Dict{Symbol,Type}=Dict()) -> DataFrame

Read a Freddie Mac pipe-delimited file selecting only specific columns by index.

Arguments:
- `file`: Path to the pipe-delimited file
- `idx`: OrderedDict mapping column names to their 1-based index in the file
- `types`: Optional type hints for columns
"""
function read_freddie_pipe(file::AbstractString, idx::OrderedDict{Symbol,Int};
                           types::Dict{Symbol,Type}=Dict())
    select_idx = collect(values(idx))
    column_names = collect(keys(idx))
    
    tbl = CSV.File(file;
        delim='|',
        header=false,
        select=select_idx,
        missingstring=["", "NA", " "],
        pool=true,
        ignoreemptyrows=true,
    )
    
    df = DataFrame(tbl)
    
    # CSV.File with header=false returns columns named "Column1", "Column2", etc.
    # The columns are returned in SORTED ORDER by their original index, not in request order.
    # We need to map ColumnN -> desired_name based on which index N corresponds to which name.
    
    # Build a mapping from original column index to desired name
    idx_to_name = Dict(v => k for (k, v) in idx)
    
    # Build rename dict: "ColumnN" -> desired_name
    rename_dict = Dict{String, Symbol}()
    for col_name in names(df)
        # Extract the column number from "ColumnN"
        m = match(r"Column(\d+)", string(col_name))
        if m !== nothing
            col_num = parse(Int, m.captures[1])
            if haskey(idx_to_name, col_num)
                rename_dict[col_name] = idx_to_name[col_num]
            end
        end
    end
    
    rename!(df, rename_dict)
    
    # Apply type conversions
    for (k, T) in types
        if k in Symbol.(names(df))
            df[!, k] = passmissing(x -> convert(T, x)).(df[!, k])
        end
    end
    
    return df
end

"""
    download_fred_mortgage_rate()

Download MORTGAGE30US weekly data from FRED and save to CSV.
"""
function download_fred_mortgage_rate()
    if isfile(FRED_CSV_PATH)
        @info "FRED data already exists at $FRED_CSV_PATH"
        return
    end
    
    @info "Downloading MORTGAGE30US from FRED..."
    Downloads.download(FRED_MORTGAGE_URL, FRED_CSV_PATH)
    @info "Saved to $FRED_CSV_PATH"
end

"""
    load_fred_rates() -> DataFrame

Load FRED mortgage rates and aggregate to monthly average.
"""
function load_fred_rates()
    df = CSV.read(FRED_CSV_PATH, DataFrame; dateformat="yyyy-mm-dd")
    
    date_col = :DATE in Symbol.(names(df)) ? :DATE : Symbol(first(names(df)))
    rate_col = :MORTGAGE30US in Symbol.(names(df)) ? :MORTGAGE30US : Symbol(last(names(df)))
    
    rename!(df, date_col => :date, rate_col => :rate)
    
    df = dropmissing(df, :rate)
    # Handle string or numeric rates
    if eltype(df.rate) <: AbstractString
        df.rate = parse.(Float64, string.(df.rate))
    end
    
    # Aggregate to monthly
    df.year_month = year.(df.date) .* 100 .+ month.(df.date)
    monthly = combine(groupby(df, :year_month), :rate => mean => :market_rate)
    
    return monthly
end

# =============================================================================
# Real Data Loading Functions
# =============================================================================

"""
    find_freddie_files() -> NamedTuple

Search for Freddie Mac data files in the expected locations.
Returns paths to origination and servicing files.
"""
function find_freddie_files()
    orig_files = String[]
    svcg_files = String[]
    
    # Search in freddiemac/orig/ directory
    orig_dir = joinpath(FREDDIE_DIR, "orig")
    if isdir(orig_dir)
        for f in readdir(orig_dir)
            if endswith(f, ".txt") && occursin("orig", f)
                push!(orig_files, joinpath(orig_dir, f))
            end
        end
    end
    
    # Search in freddiemac/svcg/ directory
    svcg_dir = joinpath(FREDDIE_DIR, "svcg")
    if isdir(svcg_dir)
        for f in readdir(svcg_dir)
            if endswith(f, ".txt") && occursin("svcg", f)
                push!(svcg_files, joinpath(svcg_dir, f))
            end
        end
    end
    
    # Also search in RAW_DIR for backwards compatibility
    if isdir(RAW_DIR)
        for f in readdir(RAW_DIR)
            if endswith(f, ".txt")
                if occursin("orig", f) && !(joinpath(RAW_DIR, f) in orig_files)
                    push!(orig_files, joinpath(RAW_DIR, f))
                elseif occursin("svcg", f) && !(joinpath(RAW_DIR, f) in svcg_files)
                    push!(svcg_files, joinpath(RAW_DIR, f))
                end
            end
        end
    end
    
    sort!(orig_files)
    sort!(svcg_files)
    
    return (orig=orig_files, svcg=svcg_files)
end

"""
    load_origination_data() -> DataFrame

Load Freddie Mac origination files.
Raises an error if no files are found.
"""
function load_origination_data()
    files = find_freddie_files()
    
    if isempty(files.orig)
        error("""
        ==========================================
        NO ORIGINATION FILES FOUND!
        ==========================================
        
        Please download the Freddie Mac Sample Dataset from:
        https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset
        
        Then place the origination files (sample_orig_*.txt) in one of:
        - $(joinpath(FREDDIE_DIR, "orig"))
        - $RAW_DIR
        
        Expected files: sample_orig_2016.txt, sample_orig_2017.txt, etc.
        ==========================================
        """)
    end
    
    @info "Found $(length(files.orig)) origination files"
    
    dfs = DataFrame[]
    for f in files.orig
        @info "Loading origination: $(basename(f))"
        df = read_freddie_pipe(f, ORIG_MINIMAL; types=ORIG_TYPES)
        push!(dfs, df)
        
        # Save to interim as Arrow for faster reload
        arrow_path = joinpath(INTERIM_DIR, basename(f) * ".arrow")
        Arrow.write(arrow_path, df)
        @info "  → Saved to interim: $(basename(arrow_path))"
    end
    
    result = vcat(dfs...; cols=:union)
    @info "Total origination records: $(nrow(result))"
    return result
end

"""
    load_performance_data() -> DataFrame

Load Freddie Mac performance/servicing files.
Raises an error if no files are found.
"""
function load_performance_data()
    files = find_freddie_files()
    
    if isempty(files.svcg)
        error("""
        ==========================================
        NO PERFORMANCE FILES FOUND!
        ==========================================
        
        Please download the Freddie Mac Sample Dataset from:
        https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset
        
        Then place the performance files (sample_svcg_*.txt) in one of:
        - $(joinpath(FREDDIE_DIR, "svcg"))
        - $RAW_DIR
        
        Expected files: sample_svcg_2016.txt, sample_svcg_2017.txt, etc.
        ==========================================
        """)
    end
    
    @info "Found $(length(files.svcg)) performance files"
    
    dfs = DataFrame[]
    for f in files.svcg
        @info "Loading performance: $(basename(f))"
        df = read_freddie_pipe(f, SVCG_MINIMAL; types=SVCG_TYPES)
        
        # Ensure zb_code is String for proper handling
        if :zb_code in names(df)
            df.zb_code = string.(coalesce.(df.zb_code, ""))
            df.zb_code = replace.(df.zb_code, "" => missing)
        end
        
        push!(dfs, df)
        
        # Save to interim as Arrow
        arrow_path = joinpath(INTERIM_DIR, basename(f) * ".arrow")
        Arrow.write(arrow_path, df)
        @info "  → Saved to interim: $(basename(arrow_path))"
    end
    
    result = vcat(dfs...; cols=:union)
    @info "Total performance records: $(nrow(result))"
    return result
end

# =============================================================================
# Data Validation
# =============================================================================

"""
    validate_data(orig::DataFrame, perf::DataFrame)

Run validation checks on loaded data.
"""
function validate_data(orig::DataFrame, perf::DataFrame)
    @info "=== Data Validation ==="
    
    # Check unique loans
    orig_loans = length(unique(orig.loan_id))
    perf_loans = length(unique(perf.loan_id))
    @info "Unique loans in origination: $orig_loans"
    @info "Unique loans in performance: $perf_loans"
    
    # Check intersection
    common_loans = length(intersect(Set(orig.loan_id), Set(perf.loan_id)))
    @info "Loans in both files: $common_loans"
    
    # Check for prepayment events
    if :zb_code in names(perf)
        prepays = count(x -> !ismissing(x) && x == "01", perf.zb_code)
        @info "Prepayment events (zb_code=01): $prepays"
        
        if prepays == 0
            @warn "No prepayment events found! Check zb_code column parsing."
        end
    end
    
    # Check critical columns not all missing
    for col in [:loan_id, :monthly_rpt_period]
        if col in names(perf)
            missing_pct = count(ismissing, perf[!, col]) / nrow(perf) * 100
            if missing_pct > 50
                @warn "Column $col has $(round(missing_pct, digits=1))% missing values"
            elseif missing_pct > 0
                @info "Column $col: $(round(missing_pct, digits=1))% missing"
            else
                @info "Column $col: ✓ no missing values"
            end
        end
    end
    
    # Sample loan timeline check
    sample_loan = first(unique(perf.loan_id))
    loan_data = filter(r -> r.loan_id == sample_loan, perf)
    if nrow(loan_data) > 1
        periods = sort(loan_data.monthly_rpt_period)
        @info "Sample loan $sample_loan: $(length(periods)) months, $(first(periods)) to $(last(periods))"
    end
    
    @info "=== Validation Complete ==="
end

# =============================================================================
# Main Execution
# =============================================================================

function main()
    @info "=== 01_download_or_load_data.jl ==="
    @info "Mode: REAL DATA ONLY (no synthetic fallback)"
    
    ensure_dirs()
    download_fred_mortgage_rate()
    
    @info "Loading FRED rates..."
    fred_rates = load_fred_rates()
    @info "FRED rates: $(nrow(fred_rates)) monthly observations"
    @info "  Range: $(minimum(fred_rates.year_month)) to $(maximum(fred_rates.year_month))"
    
    # Load real Freddie Mac data (will error if not found)
    @info "Loading Freddie Mac origination data..."
    orig = load_origination_data()
    
    @info "Loading Freddie Mac performance data..."
    perf = load_performance_data()
    
    # Validate data
    validate_data(orig, perf)
    
    # Save processed data
    @info "Saving processed data..."
    CSV.write(joinpath(PROCESSED_DIR, "fred_rates.csv"), fred_rates)
    
    # Select columns that exist
    orig_save_cols = intersect([:loan_id, :credit_score, :upb, :ltv, :orig_rate, :orig_term, :dti, :state, :occupancy, :property_type, :first_payment_date], Symbol.(names(orig)))
    CSV.write(joinpath(PROCESSED_DIR, "origination.csv"), orig[!, orig_save_cols])
    
    perf_save_cols = intersect([:loan_id, :monthly_rpt_period, :current_upb, :loan_age, :zb_code, :current_rate], Symbol.(names(perf)))
    CSV.write(joinpath(PROCESSED_DIR, "performance.csv"), perf[!, perf_save_cols])
    
    @info "Data saved to $PROCESSED_DIR"
    @info "=== Data loading complete! ==="
    
    return (fred_rates=fred_rates, orig=orig, perf=perf)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
