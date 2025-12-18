# =============================================================================
# 08_validate_drivers.jl
# =============================================================================
# Validation of Positive Drivers (WFH/Migration & Savings)
#
# Hypothesis 1: Migration Destination States (Hot) should have HIGHER excess prepay 
#               than Outflow States (Cold).
#               Excess Prepay = Observed - Predicted by M0 (Baseline)
#
# Hypothesis 2: Second Homes/Investment properties might behave differently 
#               (maybe higher turnover or cash-out behavior).
# 
# Hot States (Destinations): FL, TX, AZ, NV, ID, NC
# Cold States (Outflow): CA, NY, IL, MA, NJ

using CSV, DataFrames, Statistics, Arrow, Dates
using GLM, StatsModels

include("config/project.jl")

function main()
    @info "=== 08_validate_drivers.jl ==="
    
    # 1. Load Data
    panel_path = joinpath(PROCESSED_DIR, "loan_month_panel.arrow")
    @info "Loading panel from $panel_path..."
    panel = Arrow.Table(panel_path) |> DataFrame
    
    # Filter for COVID period
    covid_data = filter(r -> r.monthly_rpt_period >= 202003 && r.monthly_rpt_period <= 202112, panel)
    @info "Analyzing $(nrow(covid_data)) observations during COVID."
    
    # 2. Define Groups
    # Based on US Census & Real Estate Reposrts (2020-2021)
    hot_states = ["FL", "TX", "AZ", "NV", "ID", "NC", "TN", "SC", "GA"] # Sunbelt + Idaho
    cold_states = ["CA", "NY", "IL", "MA", "NJ", "CT"] # High col, high density
    
    covid_data.region_group = ifelse.(in.(covid_data.state, Ref(hot_states)), "Hot/Inflow",
                              ifelse.(in.(covid_data.state, Ref(cold_states)), "Cold/Outflow", "Other"))
                              
    # 3. Compute 'Excess' Prepayment
    # We need a baseline explanation (Incentive). 
    # Let's use the M0 model (fit on pre-covid) to predict what 'should' have happened.
    # To do this correctly, we need M0 coefficients.
    
    m0_coefs = CSV.read(joinpath(RESULTS_DIR, "m0_coefficients.csv"), DataFrame)
    get_beta(term) = begin
        r = filter(r -> r.term == term, m0_coefs)
        if nrow(r) == 0 && term == "Intercept"
            r = filter(r -> r.term == "(Intercept)", m0_coefs)
        end
        return isempty(r) ? 0.0 : r.estimate[1]
    end
    
    b_int = get_beta("(Intercept)")
    b_inc = get_beta("incentive")
    b_age = get_beta("loan_age")
    b_score = get_beta("credit_score")
    b_ltv = get_beta("ltv")
    
    # Predict M0 probability
    logit = b_int .+ 
            b_inc .* covid_data.incentive .+ 
            b_age .* covid_data.loan_age .+ 
            b_score .* covid_data.credit_score .+ 
            b_ltv .* covid_data.ltv
            
    covid_data.pred_m0 = 1.0 ./ (1.0 .+ exp.(-logit))
    
    # Excess = Observed (0/1) - Expected Prob
    # (Averaged over a group, this gives the excess rate)
    covid_data.excess = covid_data.y .- covid_data.pred_m0
    
    # 4. Group by Region and Calculate Stats
    @info "--- Analysis 1: Migration Impact (State Groups) ---"
    
    regional_stats = combine(groupby(covid_data, :region_group),
        :y => mean => :obs_rate,
        :pred_m0 => mean => :exp_rate,
        :excess => mean => :excess_rate,
        nrow => :count
    )
    
    # Convert to %
    regional_stats.obs_rate .*= 100
    regional_stats.exp_rate .*= 100
    regional_stats.excess_rate .*= 100
    
    sort!(regional_stats, :excess_rate, rev=true)
    println(regional_stats)
    
    # 5. Group by Occupancy
    @info "--- Analysis 2: Occupancy Type ---"
    # P = Primary, S = Second Home, I = Investment
    valid_occ = ["P", "S", "I"]
    occ_data = filter(r -> r.occupancy in valid_occ, covid_data)
    
    occ_stats = combine(groupby(occ_data, :occupancy),
        :y => mean => :obs_rate,
        :pred_m0 => mean => :exp_rate,
        :excess => mean => :excess_rate,
        nrow => :count
    )
    
    occ_stats.obs_rate .*= 100
    occ_stats.exp_rate .*= 100
    occ_stats.excess_rate .*= 100
    
    println(occ_stats)
    
    # Save validation results
    CSV.write(joinpath(RESULTS_DIR, "validation_regional.csv"), regional_stats)
    CSV.write(joinpath(RESULTS_DIR, "validation_occupancy.csv"), occ_stats)

end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
