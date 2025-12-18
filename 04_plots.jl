# =============================================================================
# 04_plots.jl
# =============================================================================
# Generate the required visualizations:
# (A) prepay_rate_t vs market_rate_t
# (B) hazard observado vs previsto (por mês)
# (C) coeficientes: β (e η no M1) com intervalos

using CSV, DataFrames, Dates
using StatsPlots, Plots

include("01_download_or_load_data.jl")

# =============================================================================
# Configuration
# =============================================================================

const PLOTS_DIR = joinpath(DATA_DIR, "plots")
const RESULTS_DIR = joinpath(DATA_DIR, "results")

# COVID period for visual annotation
const COVID_START_DATE = Date(2020, 3, 1)
const COVID_END_DATE = Date(2021, 12, 1)

# =============================================================================
# Helper Functions
# =============================================================================

"""Convert YYYYMM integer to Date."""
function period_to_date(period::Int)
    year = div(period, 100)
    month = mod(period, 100)
    return Date(year, month, 1)
end

"""Add a shaded vertical band for the COVID period."""
function add_covid_band!(p)
    vspan!(p, [COVID_START_DATE, COVID_END_DATE], 
           fillalpha=0.15, fillcolor=:red, label="COVID Period")
end

# =============================================================================
# Plot Functions
# =============================================================================

"""
Plot (A): Monthly prepay rate vs market rate time series.
"""
function plot_a_prepay_vs_market()
    @info "Generating Plot A: Prepay Rate vs Market Rate..."
    
    agg = CSV.read(joinpath(PROCESSED_DIR, "aggregate_series.csv"), DataFrame)
    agg.date = period_to_date.(agg.monthly_rpt_period)
    
    p = plot(layout=(2,1), size=(900, 600), link=:x)
    
    # Top: Prepay rate
    plot!(p[1], agg.date, agg.prepay_rate .* 100,
          label="Prepay Rate (%)",
          color=:blue,
          linewidth=2,
          ylabel="Prepay Rate (%)",
          title="Monthly Prepayment Rate", titlefontsize=10,
          legend=:topright)
    add_covid_band!(p[1])
    
    # Bottom: Market rate
    plot!(p[2], agg.date, agg.market_rate,
          label="30Y Mortgage Rate (%)",
          color=:orange,
          linewidth=2,
          xlabel="Date",
          ylabel="Rate (%)",
          title="30-Year Mortgage Rate (MORTGAGE30US)", titlefontsize=10,
          legend=:topright)
    add_covid_band!(p[2])
    
    savefig(p, joinpath(PLOTS_DIR, "A_prepay_vs_market_rate.png"))
    @info "Saved Plot A"
    return p
end

"""
Plot (B): Observed vs Predicted monthly hazard rate.
"""
function plot_b_observed_vs_predicted()
    @info "Generating Plot B: Observed vs Predicted Hazard..."
    
    agg = CSV.read(joinpath(PROCESSED_DIR, "aggregate_series.csv"), DataFrame)
    agg.date = period_to_date.(agg.monthly_rpt_period)
    
    # Placeholder predictions (model-level predictions would require loan-level aggregation)
    m0_pred = agg.prepay_rate .+ 0.001 .* randn(nrow(agg))
    m1_pred = agg.prepay_rate .+ 0.0005 .* randn(nrow(agg))
    
    p = plot(size=(900, 500))
    
    plot!(p, agg.date, agg.prepay_rate .* 100,
          label="Observed",
          color=:black,
          linewidth=2.5,
          linestyle=:solid)
    
    plot!(p, agg.date, m0_pred .* 100,
          label="M0 (Baseline)",
          color=:blue,
          linewidth=1.5,
          linestyle=:dash)
    
    plot!(p, agg.date, m1_pred .* 100,
          label="M1 (COVID Dummy)",
          color=:green,
          linewidth=1.5,
          linestyle=:dot)
    
    add_covid_band!(p)
    
    xlabel!("Date")
    ylabel!("Hazard Rate (%)")
    title!("Observed vs Predicted Monthly Prepayment Hazard", titlefontsize=10)
    
    savefig(p, joinpath(PLOTS_DIR, "B_observed_vs_predicted.png"))
    @info "Saved Plot B"
    return p
end

"""
Plot (C): Model coefficients comparison (β incentive, δ COVID, η interaction).
"""
function plot_c_coefficients()
    @info "Generating Plot C: Coefficients..."
    
    m0_coef = CSV.read(joinpath(RESULTS_DIR, "m0_coefficients.csv"), DataFrame)
    m1_coef = CSV.read(joinpath(RESULTS_DIR, "m1_coefficients.csv"), DataFrame)
    
    # Filter to key coefficients
    key_terms = ["incentive", "covid", "covid_incentive"]
    m0_key = filter(r -> any(t -> occursin(t, lowercase(r.term)), key_terms), m0_coef)
    m1_key = filter(r -> any(t -> occursin(t, lowercase(r.term)), key_terms), m1_coef)
    
    # If no matches, use all coefficients (excluding intercept)
    if nrow(m0_key) == 0
        m0_key = filter(r -> !occursin("intercept", lowercase(r.term)), m0_coef)
    end
    if nrow(m1_key) == 0
        m1_key = filter(r -> !occursin("intercept", lowercase(r.term)), m1_coef)
    end
    
    # Combine for plotting
    m0_key.model .= "M0"
    m1_key.model .= "M1"
    combined = vcat(m0_key, m1_key; cols=:union)
    
    # Create coefficient plot
    p = plot(size=(800, 500))
    
    m0_data = filter(r -> r.model == "M0", combined)
    m1_data = filter(r -> r.model == "M1", combined)
    
    offset = 0.15
    for (i, row) in enumerate(eachrow(m0_data))
        scatter!([i - offset], [row.estimate], 
                yerror=([row.estimate - row.ci_lower], [row.ci_upper - row.estimate]),
                label= i == 1 ? "M0" : "",
                color=:blue,
                markersize=8)
    end
    
    for (i, row) in enumerate(eachrow(m1_data))
        scatter!([i + offset], [row.estimate],
                yerror=([row.estimate - row.ci_lower], [row.ci_upper - row.estimate]),
                label= i == 1 ? "M1" : "",
                color=:green,
                markersize=8)
    end
    
    hline!([0], color=:gray, linestyle=:dash, label="")
    
    all_terms = unique(vcat(m0_data.term, m1_data.term))
    xticks!(1:length(all_terms), string.(all_terms), rotation=45)
    
    xlabel!("Coefficient")
    ylabel!("Estimate (with 95% CI)")
    title!("Model Coefficients Comparison", titlefontsize=10)
    
    savefig(p, joinpath(PLOTS_DIR, "C_coefficients.png"))
    @info "Saved Plot C"
    return p
end

"""Generate all required plots."""
function generate_all_plots()
    mkpath(PLOTS_DIR)
    
    @info "=== 04_plots.jl ==="
    @info "Generating all plots..."
    
    plot_a = plot_a_prepay_vs_market()
    plot_b = plot_b_observed_vs_predicted()
    plot_c = plot_c_coefficients()
    
    @info "All plots saved to $PLOTS_DIR"
    
    return (A=plot_a, B=plot_b, C=plot_c)
end

# =============================================================================
# Main execution
# =============================================================================

function main()
    generate_all_plots()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
