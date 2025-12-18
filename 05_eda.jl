# =============================================================================
# 05_eda.jl
# =============================================================================
# Exploratory Data Analysis for Mortgage Prepayment Study
# =============================================================================

using CSV, DataFrames, Dates, Arrow, Statistics
using StatsPlots, Plots

include("01_download_or_load_data.jl")
include("config/project.jl")

# Helper to convert YYYYMM to Date
period_to_date(p::Int) = Date(div(p, 100), mod(p, 100), 1)

# =============================================================================
# Load Data
# =============================================================================

function load_data()
    @info "Loading panel and aggregate data..."
    
    panel = Arrow.Table(joinpath(PROCESSED_DIR, "loan_month_panel.arrow")) |> DataFrame
    agg = CSV.read(joinpath(PROCESSED_DIR, "aggregate_series.csv"), DataFrame)
    
    # Add date column
    agg.date = period_to_date.(agg.monthly_rpt_period)
    
    @info "Loaded $(nrow(panel)) panel observations"
    @info "Loaded $(nrow(agg)) months of aggregate data"
    @info "Prepayment events: $(sum(panel.y))"
    
    return (panel=panel, agg=agg)
end

# =============================================================================
# EDA Plots
# =============================================================================

"""
Plot 1: Prepayment Rate vs Market Rate Over Time
Shows the relationship and COVID period impact
"""
function plot_prepay_vs_rate(agg::DataFrame)
    @info "Creating Plot 1: Prepay Rate vs Market Rate..."
    
    p = plot(layout=(2,1), size=(1000, 700), link=:x)
    
    # Top: Prepay rate with COVID shading
    plot!(p[1], agg.date, agg.prepay_rate .* 100,
          label="Taxa de Pré-pagamento Mensal (%)",
          color=:blue, linewidth=2,
          ylabel="Taxa de Pré-pagamento (%)",
          title="Taxa de Pré-pagamento ao Longo do Tempo", titlefontsize=10,
          legend=:topleft)
    
    # Add COVID shading
    vspan!(p[1], [COVID_START, COVID_END], fillalpha=0.2, fillcolor=:red, label="Período COVID")
    
    # Bottom: Market rate
    plot!(p[2], agg.date, agg.market_rate,
          label="Taxa Hipoteca 30 Anos (%)",
          color=:orange, linewidth=2,
          xlabel="Data", ylabel="Taxa (%)",
          title="Taxa de Hipoteca 30 Anos (FRED)", titlefontsize=10,
          legend=:topleft)
    vspan!(p[2], [COVID_START, COVID_END], fillalpha=0.2, fillcolor=:red, label="")
    
    savefig(p, joinpath(PLOTS_DIR, "eda_01_prepay_vs_rate.png"))
    return p
end

"""
Plot 2: Prepayment Rate by Period (Pre-COVID, COVID, Post-COVID)
"""
function plot_prepay_by_period(agg::DataFrame)
    @info "Creating Plot 2: Prepay by Period..."
    
    # Classify periods
    agg.period_type = ifelse.(agg.date .< COVID_START, "Pre-COVID",
                       ifelse.(agg.date .<= COVID_END, "COVID", "Post-COVID"))
    
    # Calculate stats by period
    period_stats = combine(groupby(agg, :period_type),
        :prepay_rate => mean => :mean_prepay,
        :prepay_rate => std => :std_prepay,
        :market_rate => mean => :mean_rate,
        nrow => :n_months
    )
    
    println("\n=== Prepayment by Period ===")
    println(period_stats)
    
    # Bar chart
    p = groupedbar(period_stats.period_type, 
                   [period_stats.mean_prepay .* 100 period_stats.mean_rate],
                   label=["Taxa Média de Pré-pagamento (%)" "Taxa Média de Mercado (%)"],
                   title="Taxas de Pré-pagamento e Mercado por Período", titlefontsize=10,
                   ylabel="Taxa (%)",
                   legend=:topright,
                   size=(800, 500),
                   bar_width=0.7,
                   color=[:blue :orange])
    
    savefig(p, joinpath(PLOTS_DIR, "eda_02_prepay_by_period.png"))
    return p
end

"""
Plot 3: Incentive (Rate Spread) vs Prepayment Rate
Key plot for understanding rate sensitivity
"""
function plot_incentive_analysis(agg::DataFrame)
    @info "Creating Plot 3: Incentive Analysis..."
    
    # Classify by incentive levels
    agg.incentive_bucket = ifelse.(agg.avg_incentive .< 0, "Negativo (<0%)",
                            ifelse.(agg.avg_incentive .< 1, "Baixo (0-1%)",
                            ifelse.(agg.avg_incentive .< 2, "Médio (1-2%)", "Alto (>2%)")))
    
    # Scatter plot with color by period
    agg.period_type = ifelse.(agg.date .< COVID_START, "Pré-COVID",
                       ifelse.(agg.date .<= COVID_END, "COVID", "Pós-COVID"))
    
    p = scatter(agg.avg_incentive, agg.prepay_rate .* 100,
                group=agg.period_type,
                xlabel="Incentivo Médio (Taxa Contrato - Taxa Mercado, %)",
                ylabel="Taxa de Pré-pagamento Mensal (%)",
                title="Sensibilidade do Pré-pagamento ao Incentivo de Refinanciamento", titlefontsize=10,
                legend=:topleft,
                markersize=6,
                alpha=0.7,
                size=(900, 600))
    
    # Add trend lines for each period
    for (period, color) in [("Pré-COVID", :blue), ("COVID", :red), ("Pós-COVID", :green)]
        sub = filter(r -> r.period_type == period, agg)
        if nrow(sub) > 2
            # Simple linear fit
            x = sub.avg_incentive
            y = sub.prepay_rate .* 100
            valid_idx = .!ismissing.(x) .& .!ismissing.(y)
            x_valid = x[valid_idx]
            y_valid = y[valid_idx]
            
            if length(x_valid) > 2
                β = cov(x_valid, y_valid) / var(x_valid)
                α = mean(y_valid) - β * mean(x_valid)
                x_range = range(minimum(x_valid), maximum(x_valid), length=50)
                plot!(p, x_range, α .+ β .* x_range, 
                      label="$(period) tendência", color=color, linewidth=2, linestyle=:dash)
            end
        end
    end
    
    savefig(p, joinpath(PLOTS_DIR, "eda_03_incentive_analysis.png"))
    return p
end

"""
Plot 4: Monthly Prepayment Counts with Annotations
"""
function plot_monthly_prepay_counts(agg::DataFrame)
    @info "Creating Plot 4: Monthly Prepay Counts..."
    
    p = plot(agg.date, agg.prepay_count,
             label="Contagem de Pré-pagamentos",
             color=:darkgreen, linewidth=2,
             xlabel="Data", ylabel="Número de Pré-pagamentos",
             title="Volume Mensal de Pré-pagamentos", titlefontsize=10,
             legend=:topright,
             size=(1000, 500))
    
    vspan!(p, [COVID_START, COVID_END], fillalpha=0.15, fillcolor=:red, label="Período COVID")
    
    # Add annotations for key events
    annotate!(p, [(Date(2020, 4, 1), maximum(agg.prepay_count) * 0.9, 
                   text("COVID\nLockdowns", 8, :red))])
    annotate!(p, [(Date(2021, 1, 1), maximum(agg.prepay_count) * 0.95, 
                   text("Taxas Baixas\nBoom de Refi", 8, :blue))])
    
    savefig(p, joinpath(PLOTS_DIR, "eda_04_monthly_prepay_counts.png"))
    return p
end

"""
Plot 5: COVID Impact - Prepay Rate vs Expected (counterfactual)
"""
function plot_covid_counterfactual(agg::DataFrame)
    @info "Creating Plot 5: COVID Counterfactual..."
    
    # Estimate pre-COVID relationship between incentive and prepay
    pre_covid = filter(r -> r.date < COVID_START, agg)
    
    x = pre_covid.avg_incentive
    y = pre_covid.prepay_rate
    valid_idx = .!ismissing.(x) .& .!ismissing.(y)
    x_valid = x[valid_idx]
    y_valid = y[valid_idx]
    
    # Simple linear model: prepay_rate = α + β * incentive
    β = cov(x_valid, y_valid) / var(x_valid)
    α = mean(y_valid) - β * mean(x_valid)
    
    @info "Pre-COVID model: prepay_rate = $(round(α*100, digits=3))% + $(round(β*100, digits=3))% × incentive"
    
    # Predict counterfactual for COVID period
    covid_period = filter(r -> r.date >= COVID_START && r.date <= COVID_END, agg)
    covid_period.predicted = α .+ β .* covid_period.avg_incentive
    
    # Plot
    p = plot(size=(1000, 500))
    
    # Actual prepay rate
    plot!(p, agg.date, agg.prepay_rate .* 100,
          label="Taxa Real de Pré-pagamento",
          color=:blue, linewidth=2)
    
    # Predicted (counterfactual) based on pre-COVID relationship
    agg.predicted_prepay = α .+ β .* agg.avg_incentive
    plot!(p, agg.date, agg.predicted_prepay .* 100,
          label="Esperado (Modelo Pré-COVID)",
          color=:gray, linewidth=2, linestyle=:dash)
    
    vspan!(p, [COVID_START, COVID_END], fillalpha=0.15, fillcolor=:red, label="Período COVID")
    
    xlabel!("Data")
    ylabel!("Taxa de Pré-pagamento (%)")
    title!("Taxa Real vs Esperada de Pré-pagamento\n(Gap = Efeito COVID)")
    
    savefig(p, joinpath(PLOTS_DIR, "eda_05_covid_counterfactual.png"))
    
    # Calculate COVID gap
    covid_actual = mean(filter(r -> r.date >= COVID_START && r.date <= COVID_END, agg).prepay_rate)
    covid_expected = mean(filter(r -> r.date >= COVID_START && r.date <= COVID_END, agg).predicted_prepay)
    
    @info "COVID Period Analysis:"
    @info "  Actual avg prepay rate: $(round(covid_actual*100, digits=2))%"
    @info "  Expected avg prepay rate: $(round(covid_expected*100, digits=2))%"
    @info "  Gap (COVID effect): $(round((covid_actual - covid_expected)*100, digits=2))%"
    
    return p
end

"""
Generate summary statistics table
"""
function generate_summary_stats(panel::DataFrame, agg::DataFrame)
    @info "Generating summary statistics..."
    
    println("\n" * "="^60)
    println("EXPLORATORY DATA ANALYSIS SUMMARY")
    println("="^60)
    
    println("\n--- Data Overview ---")
    println("Total loan-month observations: $(nrow(panel))")
    println("Unique loans: $(length(unique(panel.loan_id)))")
    println("Time period: $(minimum(panel.monthly_rpt_period)) to $(maximum(panel.monthly_rpt_period))")
    println("Total prepayment events: $(sum(panel.y))")
    println("Overall prepayment rate: $(round(mean(panel.y)*100, digits=3))%")
    
    println("\n--- COVID Period Analysis ---")
    agg.period_type = ifelse.(agg.date .< COVID_START, "Pré-COVID",
                       ifelse.(agg.date .<= COVID_END, "COVID", "Pós-COVID"))
    
    for period in ["Pré-COVID", "COVID", "Pós-COVID"]
        sub = filter(r -> r.period_type == period, agg)
        if nrow(sub) > 0
            # Weighted average calculation
            total_events = sum(sub.prepay_count)
            # We don't have total_loans in agg directly? 
            # agg comes from: combine(groupby(panel...), :y => sum => :prepay_count, :y => mean => :prepay_rate)
            # So prepay_rate = count / n_loans => n_loans = count / prepay_rate
            # But safer to just load panel? No, function receives panel too.
            
            # Using panel directly would be best, but 'agg' is passed here.
            # Let's check if we can pass panel to a helper or compute from panel in `generate_summary_stats`
            # The function signature is `generate_summary_stats(panel::DataFrame, agg::DataFrame)`
            # So we HAVE the panel! Let's use it.
            
            panel_sub = filter(r -> 
                (period == "Pré-COVID" && r.monthly_rpt_period < 202003) ||
                (period == "COVID" && r.monthly_rpt_period >= 202003 && r.monthly_rpt_period <= 202112) ||
                (period == "Pós-COVID" && r.monthly_rpt_period > 202112), 
                panel
            )
            
            weighted_rate = mean(panel_sub.y) * 100
            
            println("\n$period:")
            println("  Meses: $(nrow(sub))")
            println("  Taxa Média Ponderada (Portfolio): $(round(weighted_rate, digits=2))%")
            println("  Taxa Média Simples (Mensal): $(round(mean(sub.prepay_rate)*100, digits=2))%")
            println("  Taxa Média de Mercado: $(round(mean(skipmissing(sub.market_rate)), digits=2))%")
            println("  Incentivo Médio: $(round(mean(skipmissing(sub.avg_incentive)), digits=2))%")
            println("  Total de Pré-pagamentos: $(sum(sub.prepay_count))")
        end
    end
    
    println("\n" * "="^60)
end

# =============================================================================
# Main
# =============================================================================

function main()
    @info "=== 05_eda.jl - Exploratory Data Analysis ==="
    
    mkpath(PLOTS_DIR)
    
    # Load data
    data = load_data()
    
    # Generate plots
    plot_prepay_vs_rate(data.agg)
    plot_prepay_by_period(data.agg)
    plot_incentive_analysis(data.agg)
    plot_monthly_prepay_counts(data.agg)
    plot_covid_counterfactual(data.agg)
    
    # Summary stats
    generate_summary_stats(data.panel, data.agg)
    
    @info "EDA complete! Plots saved to $PLOTS_DIR"
    
    return data
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
