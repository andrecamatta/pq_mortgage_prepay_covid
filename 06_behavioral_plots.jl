# =============================================================================
# 06_behavioral_plots.jl
# =============================================================================
# Visualizations for behavioral bias effects (Continuous Interaction Curves)

using CSV, DataFrames, Arrow, Dates, Statistics
using StatsPlots, Plots

include("01_download_or_load_data.jl")
include("config/project.jl")

"""
Load M2 coefficients and return a helper function to get them.
"""
function load_m2_coefs()
    df = CSV.read(joinpath(RESULTS_DIR, "m2_coefficients.csv"), DataFrame)
    # Helper to safe get
    get_beta(term) = begin
        row = filter(r -> r.term == term, df)
        if nrow(row) == 0
            # Handle intercept if named differently
            if term == "Intercept"
                row = filter(r -> r.term == "(Intercept)", df)
            end
        end
        return row.estimate[1]
    end
    return get_beta
end

"""
Load M3 coefficients.
"""
function load_m3_coefs()
    df = CSV.read(joinpath(RESULTS_DIR, "m3_coefficients.csv"), DataFrame)
    get_beta(term) = begin
        row = filter(r -> r.term == term, df)
        if nrow(row) == 0
            if term == "Intercept"
                row = filter(r -> r.term == "(Intercept)", df)
            end
        end
        return isempty(row) ? 0.0 : row.estimate[1]
    end
    return get_beta
end

"""
Plot 1: Sunk Cost (Probability vs Loan Age)
Interaction: covid * loan_age
"""
function plot_sunk_cost_continuous()
    @info "Creating Sunk-Cost visualization (Continuous)..."
    
    get_beta = load_m2_coefs()
    
    # Base values
    intercept = get_beta("(Intercept)")
    b_incentive = get_beta("incentive")
    b_age = get_beta("loan_age")
    b_credit = get_beta("credit_score")
    b_ltv = get_beta("ltv")
    b_covid = get_beta("covid")
    b_covid_incentive = get_beta("covid_incentive")
    b_covid_age = get_beta("covid_loan_age")
    b_covid_credit = get_beta("covid_credit_score")
    
    # Fixed Covariates
    fixed_incentive = 0.5 # 50bps incentive
    fixed_credit = 720
    fixed_ltv = 80
    
    # Range
    ages = 0:1:120 # 0 to 10 years
    
    y_normal = Float64[]
    y_covid = Float64[]
    
    for age in ages
        # Core Logit (without COVID terms)
        core = intercept + b_incentive*fixed_incentive + b_age*age + b_credit*fixed_credit + b_ltv*fixed_ltv
        
        # Normal
        logit_0 = core
        prob_0 = 1 / (1 + exp(-logit_0))
        push!(y_normal, prob_0 * 100)
        
        # COVID
        # Add main covid term + interactions
        # covid=1, covid*incentive, covid*age, covid*credit
        logit_1 = core + b_covid*1 + b_covid_incentive*(1*fixed_incentive) + b_covid_age*(1*age) + b_covid_credit*(1*fixed_credit)
        prob_1 = 1 / (1 + exp(-logit_1))
        push!(y_covid, prob_1 * 100)
    end
    
    p = plot(size=(800, 500))
    
    plot!(p, ages, y_normal, label="Período Normal", color=:blue, linewidth=2.5)
    plot!(p, ages, y_covid, label="Período COVID", color=:red, linewidth=2.5)
    
    xlabel!("Idade do Empréstimo (Meses)")
    ylabel!("Probabilidade Prevista (%)")
    
    # Check slope difference manually to set title
    title_str = "Efeito Sunk-Cost: Empréstimos velhos respondem MENOS\n(Gap diminui ou inverte com a Idade)"
    title!(title_str, titlefontsize=10)
    
    savefig(p, joinpath(PLOTS_DIR, "behavioral_01_sunk_cost_continuous.png"))
    @info "Saved Sunk Cost Plot"
    return p
end

"""
Plot 2: Overconfidence (Probability vs Credit Score)
Interaction: covid * credit_score
"""
function plot_overconfidence_continuous()
    @info "Creating Overconfidence visualization (Continuous)..."
    
    get_beta = load_m2_coefs()
    
    # Base values
    intercept = get_beta("(Intercept)")
    b_incentive = get_beta("incentive")
    b_age = get_beta("loan_age")
    b_credit = get_beta("credit_score")
    b_ltv = get_beta("ltv")
    b_covid = get_beta("covid")
    b_covid_incentive = get_beta("covid_incentive")
    b_covid_age = get_beta("covid_loan_age")
    b_covid_credit = get_beta("covid_credit_score")
    
    # Fixed Covariates
    fixed_incentive = 0.5 
    fixed_age = 30
    fixed_ltv = 80
    
    # Range
    scores = 620:5:800
    
    y_normal = Float64[]
    y_covid = Float64[]
    
    for s in scores
        # Core
        core = intercept + b_incentive*fixed_incentive + b_age*fixed_age + b_credit*s + b_ltv*fixed_ltv
        
        # Normal
        logit_0 = core
        prob_0 = 1 / (1 + exp(-logit_0))
        push!(y_normal, prob_0 * 100)
        
        # COVID
        logit_1 = core + b_covid*1 + b_covid_incentive*(1*fixed_incentive) + b_covid_age*(1*fixed_age) + b_covid_credit*(1*s)
        prob_1 = 1 / (1 + exp(-logit_1))
        push!(y_covid, prob_1 * 100)
    end
    
    p = plot(size=(800, 500))
    
    plot!(p, scores, y_normal, label="Período Normal", color=:blue, linewidth=2.5)
    plot!(p, scores, y_covid, label="Período COVID", color=:seagreen, linewidth=2.5)
    
    xlabel!("Score de Crédito (FICO)")
    ylabel!("Probabilidade Prevista (%)")
    
    title!("Efeito Overconfidence: Scores altos respondem MAIS no COVID\n(Gap aumenta com o Score)", titlefontsize=10)
    
    savefig(p, joinpath(PLOTS_DIR, "behavioral_02_overconfidence_continuous.png"))
    @info "Saved Overconfidence Plot"
    return p
end

"""
Plot 4: Liquidity Friction (Empirical Probability vs LTV)
Bin LTV and compute actual prepayment rates.
"""
function plot_ltv_effect_empirical(panel::DataFrame)
    @info "Creating LTV Effect (Empirical) visualization..."
    
    # Filter valid LTV (exclude unrealistic values)
    df = filter(row -> !ismissing(row.ltv) && row.ltv > 0 && row.ltv <= 105, panel)
    
    # Bins of 5%
    df.ltv_bucket = floor.(df.ltv ./ 5) .* 5
    
    gd = groupby(df, [:ltv_bucket, :covid])
    agg = combine(gd, :y => mean => :prob, nrow => :n)
    
    # FILTER: Only buckets with N > 5000 to avoid noise
    agg = filter(r -> r.n >= 5000, agg)
    
    sort!(agg, :ltv_bucket)
    
    normal = filter(r -> r.covid == 0, agg)
    covid = filter(r -> r.covid == 1, agg)
    
    p = plot(size=(800, 500))
    
    plot!(p, normal.ltv_bucket, normal.prob .* 100, label="Período Normal", color=:blue, linewidth=2.5, marker=:circle, markersize=4)
    plot!(p, covid.ltv_bucket, covid.prob .* 100, label="Período COVID", color=:orange, linewidth=2.5, marker=:circle, markersize=4)
    
    xlabel!("LTV (Loan-to-Value) %")
    ylabel!("Probabilidade Observada (%)")
    
    title!("Efeito LTV no Pré-pagamento\n(Buckets com N > 5000 observações)", titlefontsize=10)
    
    savefig(p, joinpath(PLOTS_DIR, "behavioral_04_ltv_effect.png"))
    @info "Saved LTV Effect Plot"
    return p
end

function main()
    @info "=== 06_behavioral_plots.jl ==="
    mkpath(PLOTS_DIR)
    
    # Load Panel for Empirical Plots
    @info "Loading Panel Data for empirical plots..."
    panel = DataFrame(Arrow.Table(PANEL_PATH))
    @info "Panel loaded."

    # Check if M2 results exist for Model Plots
    if !isfile(joinpath(RESULTS_DIR, "m2_coefficients.csv"))
        @error "M2 coefficients not found. Please run 03_fit_models.jl first."
        return
    end

    plot_sunk_cost_continuous()
    plot_overconfidence_continuous()
    
    # Empirical LTV plot only (Size plot removed: current_upb = 0 at prepayment)
    plot_ltv_effect_empirical(panel)
    
    @info "All behavioral plots saved to $PLOTS_DIR"
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
