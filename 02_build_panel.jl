# =============================================================================
# 02_build_panel.jl
# =============================================================================
# Build the loan-month panel for hazard modeling.
# OPTIMIZED VERSION - uses vectorized operations and efficient joins

using CSV, DataFrames, Dates, Arrow, Statistics

include("01_download_or_load_data.jl")
include("config/project.jl")

# =============================================================================
# Panel Construction Functions (OPTIMIZED)
# =============================================================================

"""
    build_loan_month_panel(orig::DataFrame, perf::DataFrame, fred::DataFrame) -> DataFrame

Construct the loan-month panel with all covariates for hazard modeling.
OPTIMIZED: Uses innerjoin and vectorized operations.
"""
function build_loan_month_panel(orig::DataFrame, perf::DataFrame, fred::DataFrame)
    @info "Building loan-month panel (optimized)..."
    t0 = time()
    
    # ----- Step 1: Prepare origination data -----
    @info "  Step 1: Filtering origination data..."
    orig_cols = intersect([:loan_id, :credit_score, :upb, :ltv, :orig_rate, :orig_term, :dti, :state, :occupancy, :property_type], 
                          Symbol.(names(orig)))
    orig_subset = select(orig, orig_cols)
    
    # Filter to 30Y FRM (orig_term == 360) if column exists
    if :orig_term in names(orig_subset)
        orig_subset = subset(orig_subset, :orig_term => x -> coalesce.(x .== 360, false); skipmissing=false)
        @info "    After FRM 30Y filter: $(nrow(orig_subset)) loans"
    end
    @info "    Step 1 done in $(round(time() - t0, digits=1))s"
    
    # ----- Step 2: Prepare performance data -----
    @info "  Step 2: Preparing performance data..."
    t1 = time()
    perf_cols = intersect([:loan_id, :monthly_rpt_period, :current_upb, :loan_age, :zb_code, :current_rate],
                          Symbol.(names(perf)))
    perf_subset = select(perf, perf_cols)
    @info "    Performance records: $(nrow(perf_subset))"
    @info "    Step 2 done in $(round(time() - t1, digits=1))s"
    
    # ----- Step 3: INNERJOIN instead of filter -----
    @info "  Step 3: Joining performance with origination (innerjoin)..."
    t2 = time()
    # This is MUCH faster than filtering with Set membership
    panel = innerjoin(perf_subset, 
                      select(orig_subset, [:loan_id, :orig_rate, :credit_score, :ltv]),
                      on=:loan_id)
    @info "    After join: $(nrow(panel)) rows"
    @info "    Step 3 done in $(round(time() - t2, digits=1))s"
    
    # ----- Step 4: Join with FRED rates -----
    @info "  Step 4: Joining with FRED rates..."
    t3 = time()
    
    # Rename fred column for join
    fred_copy = copy(fred)
    if :year_month in Symbol.(names(fred_copy))
        rename!(fred_copy, :year_month => :monthly_rpt_period)
    end
    
    panel = leftjoin(panel, fred_copy, on=:monthly_rpt_period)
    @info "    Step 4 done in $(round(time() - t3, digits=1))s"
    
    # ----- Step 5: Feature engineering (VECTORIZED) -----
    @info "  Step 5: Feature engineering (vectorized)..."
    t4 = time()
    
    # y = prepayment indicator (zb_code == "01" or "1") - VECTORIZED
    # Note: Freddie Mac stores as integer, so it could be "1" or "01"
    panel.y = ifelse.(coalesce.(panel.zb_code .== "01", false) .| 
                      coalesce.(panel.zb_code .== "1", false), 1, 0)
    
    # incentive = orig_rate - market_rate - VECTORIZED
    panel.incentive = panel.orig_rate .- panel.market_rate
    
    # COVID dummy - VECTORIZED (uses config/project.jl constants)
    panel.covid = ifelse.((panel.monthly_rpt_period .>= COVID_START_INT) .& 
                          (panel.monthly_rpt_period .<= COVID_END_INT), 1, 0)
    
    # covid * incentive interaction - VECTORIZED
    panel.covid_incentive = panel.covid .* coalesce.(panel.incentive, 0.0)
    
    # Age buckets - VECTORIZED using cut-like logic
    panel.age_bucket = ifelse.(ismissing.(panel.loan_age), missing,
                        ifelse.(panel.loan_age .<= 12, "0-12",
                        ifelse.(panel.loan_age .<= 24, "13-24",
                        ifelse.(panel.loan_age .<= 36, "25-36",
                        ifelse.(panel.loan_age .<= 48, "37-48",
                        ifelse.(panel.loan_age .<= 60, "49-60", "60+"))))))
    
    @info "    Step 5 done in $(round(time() - t4, digits=1))s"
    
    # ----- Step 6: Drop rows with missing critical variables -----
    @info "  Step 6: Dropping missing values..."
    t5 = time()
    initial_rows = nrow(panel)
    panel = dropmissing(panel, [:loan_id, :monthly_rpt_period, :y, :incentive, :loan_age])
    @info "    Dropped $(initial_rows - nrow(panel)) rows with missing values"
    @info "    Step 6 done in $(round(time() - t5, digits=1))s"
    
    total_time = round(time() - t0, digits=1)
    @info "Panel construction complete in $(total_time)s"
    @info "  Final panel: $(nrow(panel)) loan-month observations"
    @info "  Unique loans: $(length(unique(panel.loan_id)))"
    @info "  Time range: $(minimum(panel.monthly_rpt_period)) to $(maximum(panel.monthly_rpt_period))"
    @info "  Prepayment events: $(sum(panel.y))"
    
    return panel
end

"""
    compute_aggregate_series(panel::DataFrame) -> DataFrame

Compute monthly aggregate prepayment rate for visualization.
"""
function compute_aggregate_series(panel::DataFrame)
    @info "Computing aggregate series..."
    
    # Group by month - use combine for efficiency
    agg = combine(groupby(panel, :monthly_rpt_period),
        :y => sum => :prepay_count,
        nrow => :alive_count,
        :market_rate => (x -> coalesce(first(skipmissing(x)), missing)) => :market_rate,
        :incentive => mean∘skipmissing => :avg_incentive,
    )
    
    # Compute prepay rate
    agg.prepay_rate = agg.prepay_count ./ agg.alive_count
    
    # Sort by period
    sort!(agg, :monthly_rpt_period)
    
    @info "  Aggregate series: $(nrow(agg)) months"
    
    return agg
end

"""
    split_data(panel::DataFrame) -> NamedTuple

Split panel into train/validation/test sets based on temporal cutoffs.
"""
function split_data(panel::DataFrame)
    train = subset(panel, :monthly_rpt_period => x -> x .< 202001)
    val = subset(panel, :monthly_rpt_period => x -> (x .>= 202001) .& (x .< 202201))
    test = subset(panel, :monthly_rpt_period => x -> x .>= 202201)
    
    @info "Data split:"
    @info "  Train (pre-2020): $(nrow(train)) observations"
    @info "  Validation (2020-2021): $(nrow(val)) observations"
    @info "  Test (2022+): $(nrow(test)) observations"
    
    return (train=train, val=val, test=test)
end

# =============================================================================
# Main execution
# =============================================================================

function main()
    @info "=== 02_build_panel.jl (OPTIMIZED) ==="
    
    # Load data from processed CSVs
    @info "Loading processed data..."
    fred_rates = CSV.read(joinpath(PROCESSED_DIR, "fred_rates.csv"), DataFrame)
    orig = CSV.read(joinpath(PROCESSED_DIR, "origination.csv"), DataFrame)
    perf = CSV.read(joinpath(PROCESSED_DIR, "performance.csv"), DataFrame; types=Dict(:zb_code => String))
    
    @info "  Origination: $(nrow(orig)) loans"
    @info "  Performance: $(nrow(perf)) records"
    @info "  FRED rates: $(nrow(fred_rates)) months"
    
    # Build panel
    panel = build_loan_month_panel(orig, perf, fred_rates)
    
    # Compute aggregate series
    agg_series = compute_aggregate_series(panel)
    
    # Save panel
    @info "Saving panel..."
    Arrow.write(PANEL_PATH, panel)
    CSV.write(joinpath(PROCESSED_DIR, "aggregate_series.csv"), agg_series)
    
    @info "Panel saved to $PANEL_PATH"
    @info "Aggregate series saved"
    
    # Split data
    splits = split_data(panel)
    
    return (panel=panel, agg=agg_series, splits=splits)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
