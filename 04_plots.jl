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
include("config/project.jl")

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
    vspan!(p, [COVID_START, COVID_END], 
           fillalpha=COVID_BAND_ALPHA, fillcolor=COVID_BAND_COLOR, label="Período COVID")
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
          label="Taxa de Pré-pagamento (%)",
          color=:blue,
          linewidth=2,
          ylabel="Taxa de Pré-pagamento (%)",
          title="Taxa de Pré-pagamento Mensal", titlefontsize=10,
          legend=:topright)
    add_covid_band!(p[1])
    
    # Bottom: Market rate
    plot!(p[2], agg.date, agg.market_rate,
          label="Taxa 30 Anos (%)",
          color=:orange,
          linewidth=2,
          xlabel="Data",
          ylabel="Taxa (%)",
          title="Taxa de Hipoteca 30 Anos (MORTGAGE30US)", titlefontsize=10,
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
    
    # Load actual predictions from step 03
    preds = CSV.read(joinpath(RESULTS_DIR, "monthly_predictions.csv"), DataFrame)
    preds.date = period_to_date.(preds.monthly_rpt_period)
    
    p = plot(size=(900, 500))
    
    plot!(p, preds.date, preds.observed .* 100,
          label="Observado",
          color=:black,
          linewidth=2.5,
          linestyle=:solid)
    
    plot!(p, preds.date, preds.m0_pred .* 100,
          label="M0 (Baseline)",
          color=:blue,
          linewidth=1.5,
          linestyle=:dash)
    
    plot!(p, preds.date, preds.m1_pred .* 100,
          label="M1 (Dummy COVID)",
          color=:green,
          linewidth=1.5,
          linestyle=:dot)
    
    add_covid_band!(p)
    
    xlabel!("Data")
    ylabel!("Taxa de Hazard (%)")
    title!("Hazard de Pré-pagamento Mensal: Observado vs Previsto", titlefontsize=10)
    
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
    
    xlabel!("Coeficiente")
    ylabel!("Estimativa (com IC 95%)")
    title!("Comparação dos Coeficientes do Modelo", titlefontsize=10)
    
    savefig(p, joinpath(PLOTS_DIR, "C_coefficients.png"))
    @info "Saved Plot C"
    return p
end

"""
Plot (D): Incentive Interaction Effect (Probability vs Incentive).
"""
function plot_d_incentive_interaction()
    @info "Generating Plot D: Incentive Interaction..."
    
    # Load coefficients
    m1_coef = CSV.read(joinpath(RESULTS_DIR, "m1_coefficients.csv"), DataFrame)
    
    # Helper to get coef value
    get_beta(term) = m1_coef[m1_coef.term .== term, :estimate][1]
    
    intercept = get_beta("(Intercept)")
    b_incentive = get_beta("incentive")
    b_age = get_beta("loan_age")
    b_credit = get_beta("credit_score")
    b_ltv = get_beta("ltv")
    b_covid = get_beta("covid")
    b_covid_incentive = get_beta("covid_incentive")
    
    # Define grid
    incentive_range = -1.0:0.1:2.0
    
    # Fixed values for other covariates
    base_age = 30
    base_credit = 720
    base_ltv = 80
    
    # Calculate logit
    # logit = intercept + b_incentive*inc + ...
    base_logit = intercept + b_age*base_age + b_credit*base_credit + b_ltv*base_ltv
    
    y_normal = Float64[]
    y_covid = Float64[]
    
    for inc in incentive_range
        # Normal (COVID=0)
        logit_0 = base_logit + b_incentive * inc
        prob_0 = 1 / (1 + exp(-logit_0))
        push!(y_normal, prob_0 * 100) # %
        
        # COVID (COVID=1)
        logit_1 = base_logit + b_incentive * inc + b_covid * 1 + b_covid_incentive * (1 * inc)
        prob_1 = 1 / (1 + exp(-logit_1))
        push!(y_covid, prob_1 * 100) # %
    end
    
    p = plot(size=(800, 500))
    
    plot!(p, incentive_range, y_normal,
          label="Pré-COVID / Normal",
          color=:blue,
          linewidth=2.5)
          
    plot!(p, incentive_range, y_covid,
          label="Período COVID",
          color=:red,
          linewidth=2.5)
    
    xlabel!("Incentivo (%) (Taxa Contrato - Taxa Mercado)")
    ylabel!("Probabilidade Prevista de Pré-pagamento (%)")
    title!("Efeito do COVID na Sensibilidade ao Incentivo\n(Curva COVID é mais alta, porém mais plana)", titlefontsize=10)
    
    # Add vertical line at 0 incentive
    vline!([0.0], color=:gray, linestyle=:dash, label="")
    
    savefig(p, joinpath(PLOTS_DIR, "D_incentive_interaction.png"))
    @info "Saved Plot D"
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
    plot_d = plot_d_incentive_interaction()
    
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
