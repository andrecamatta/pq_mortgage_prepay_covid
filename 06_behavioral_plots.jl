# =============================================================================
# 06_behavioral_plots.jl
# =============================================================================
# Visualizations for behavioral bias effects

using CSV, DataFrames, Arrow, Dates, Statistics
using StatsPlots, Plots

include("01_download_or_load_data.jl")

const PLOTS_DIR = joinpath(DATA_DIR, "plots")
const PANEL_PATH = joinpath(PROCESSED_DIR, "loan_month_panel.arrow")

"""
Create loan_age buckets.
"""
function add_age_bucket(df::DataFrame)
    df = copy(df)
    df.age_bucket = map(df.loan_age) do age
        if age <= 24 return "0-24"
        elseif age <= 48 return "25-48"
        elseif age <= 72 return "49-72"
        elseif age <= 96 return "73-96"
        else return "97+"
        end
    end
    return df
end

"""
Create credit_score buckets.
"""
function add_credit_bucket(df::DataFrame)
    df = copy(df)
    df.credit_bucket = map(df.credit_score) do score
        if ismissing(score) return missing
        elseif score < 660 return "<660"
        elseif score < 700 return "660-699"
        elseif score < 740 return "700-739"
        elseif score < 780 return "740-779"
        else return "780+"
        end
    end
    return df
end

"""
Plot 1: Sunk-Cost - Prepay by loan age, COVID vs non-COVID
"""
function plot_sunk_cost(panel::DataFrame)
    @info "Creating Sunk-Cost visualization..."
    
    df = add_age_bucket(panel)
    df.period = ifelse.(df.covid .== 1, "COVID", "Outros")
    
    agg = combine(groupby(df, [:age_bucket, :period]), 
        :y => mean => :prepay_rate)
    
    age_order = ["0-24", "25-48", "49-72", "73-96", "97+"]
    
    outros = Float64[]
    covid = Float64[]
    for age in age_order
        o = filter(r -> r.age_bucket == age && r.period == "Outros", agg)
        c = filter(r -> r.age_bucket == age && r.period == "COVID", agg)
        push!(outros, nrow(o) > 0 ? o.prepay_rate[1] * 100 : 0.0)
        push!(covid, nrow(c) > 0 ? c.prepay_rate[1] * 100 : 0.0)
    end
    
    p = groupedbar(age_order, [outros covid],
        label=["Outros períodos" "COVID"],
        color=[:steelblue :crimson],
        size=(800, 500),
        legend=:topright,
        xlabel="Idade do Empréstimo (meses)",
        ylabel="Taxa de Pré-pagamento (%)",
        title="Sunk-Cost: Empréstimos velhos responderam MENOS ao COVID\n(covid×loan_age = -0.0195)",
        bar_width=0.7)
    
    savefig(p, joinpath(PLOTS_DIR, "behavioral_01_sunk_cost.png"))
    @info "Saved"
    return p
end

"""
Plot 2: Overconfidence - Prepay by credit score, COVID vs non-COVID
"""
function plot_overconfidence(panel::DataFrame)
    @info "Creating Overconfidence visualization..."
    
    df = add_credit_bucket(panel)
    df = dropmissing(df, :credit_bucket)
    df.period = ifelse.(df.covid .== 1, "COVID", "Outros")
    
    agg = combine(groupby(df, [:credit_bucket, :period]), 
        :y => mean => :prepay_rate)
    
    credit_order = ["<660", "660-699", "700-739", "740-779", "780+"]
    
    outros = Float64[]
    covid = Float64[]
    for cs in credit_order
        o = filter(r -> r.credit_bucket == cs && r.period == "Outros", agg)
        c = filter(r -> r.credit_bucket == cs && r.period == "COVID", agg)
        push!(outros, nrow(o) > 0 ? o.prepay_rate[1] * 100 : 0.0)
        push!(covid, nrow(c) > 0 ? c.prepay_rate[1] * 100 : 0.0)
    end
    
    p = groupedbar(credit_order, [outros covid],
        label=["Outros períodos" "COVID"],
        color=[:steelblue :seagreen],
        size=(800, 500),
        legend=:topleft,
        xlabel="Credit Score",
        ylabel="Taxa de Pré-pagamento (%)",
        title="Overconfidence: Scores altos responderam MAIS ao COVID\n(covid×credit_score = +2.1e-5)",
        bar_width=0.7)
    
    savefig(p, joinpath(PLOTS_DIR, "behavioral_02_overconfidence.png"))
    @info "Saved"
    return p
end

"""
Plot 3: Diff-in-Diff style - lines showing interaction
"""
function plot_diff_in_diff(panel::DataFrame)
    @info "Creating Diff-in-Diff visualization..."
    
    df = copy(panel)
    df.high_age = df.loan_age .>= 48
    df.high_credit = df.credit_score .>= 740
    
    p = plot(layout=(1,2), size=(1000, 450), margin=5Plots.mm)
    
    # Left: Loan Age
    age_agg = combine(groupby(df, [:covid, :high_age]), :y => mean => :rate)
    sort!(age_agg, [:high_age, :covid])
    
    new_loan = filter(r -> !r.high_age, age_agg)
    old_loan = filter(r -> r.high_age, age_agg)
    
    plot!(p[1], ["Outros", "COVID"], new_loan.rate .* 100,
          label="Novo (<48m)", marker=:circle, ms=8, lw=3, color=:blue)
    plot!(p[1], ["Outros", "COVID"], old_loan.rate .* 100,
          label="Velho (≥48m)", marker=:square, ms=8, lw=3, color=:red)
    ylabel!(p[1], "Prepay Rate (%)")
    title!(p[1], "Sunk-Cost\n(Velhos respondem menos)")
    
    # Right: Credit Score
    credit_agg = combine(groupby(df, [:covid, :high_credit]), :y => mean => :rate)
    sort!(credit_agg, [:high_credit, :covid])
    
    low_cs = filter(r -> !r.high_credit, credit_agg)
    high_cs = filter(r -> r.high_credit, credit_agg)
    
    plot!(p[2], ["Outros", "COVID"], low_cs.rate .* 100,
          label="Score <740", marker=:circle, ms=8, lw=3, color=:orange)
    plot!(p[2], ["Outros", "COVID"], high_cs.rate .* 100,
          label="Score ≥740", marker=:square, ms=8, lw=3, color=:green)
    ylabel!(p[2], "Prepay Rate (%)")
    title!(p[2], "Overconfidence\n(Scores altos respondem mais)")
    
    savefig(p, joinpath(PLOTS_DIR, "behavioral_03_diff_in_diff.png"))
    @info "Saved"
    return p
end

"""
Plot 4: COVID multiplier by segment
"""
function plot_multiplier(panel::DataFrame)
    @info "Creating COVID multiplier visualization..."
    
    df = copy(panel)
    df.high_age = ifelse.(df.loan_age .>= 48, "Velho (≥48m)", "Novo (<48m)")
    df.high_credit = ifelse.(df.credit_score .>= 740, "Score ≥740", "Score <740")
    
    agg = combine(groupby(df, [:high_age, :high_credit, :covid]), 
        :y => mean => :rate)
    
    # Calculate multipliers
    segments = ["Novo, <740", "Novo, ≥740", "Velho, <740", "Velho, ≥740"]
    multipliers = Float64[]
    
    for (age, credit) in [("Novo (<48m)", "Score <740"), ("Novo (<48m)", "Score ≥740"),
                          ("Velho (≥48m)", "Score <740"), ("Velho (≥48m)", "Score ≥740")]
        outros = filter(r -> r.high_age == age && r.high_credit == credit && r.covid == 0, agg)
        covid_r = filter(r -> r.high_age == age && r.high_credit == credit && r.covid == 1, agg)
        if nrow(outros) > 0 && nrow(covid_r) > 0 && outros.rate[1] > 0
            push!(multipliers, covid_r.rate[1] / outros.rate[1])
        else
            push!(multipliers, 0.0)
        end
    end
    
    p = bar(segments, multipliers,
        color=[:steelblue, :seagreen, :coral, :crimson],
        size=(800, 500),
        legend=false,
        xlabel="Segmento",
        ylabel="Multiplicador COVID (COVID ÷ Outros)",
        title="Multiplicador COVID por Segmento\n(Maior = respondeu mais ao COVID)",
        bar_width=0.6,
        rotation=15)
    
    hline!([1.0], color=:gray, linestyle=:dash, label="")
    
    savefig(p, joinpath(PLOTS_DIR, "behavioral_04_multiplier.png"))
    @info "Saved"
    return p
end

function main()
    @info "=== 06_behavioral_plots.jl ==="
    mkpath(PLOTS_DIR)
    
    panel = Arrow.Table(PANEL_PATH) |> DataFrame
    @info "Loaded: $(nrow(panel)) observations"
    
    plot_sunk_cost(panel)
    plot_overconfidence(panel)
    plot_diff_in_diff(panel)
    plot_multiplier(panel)
    
    @info "All behavioral plots saved to $PLOTS_DIR"
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
