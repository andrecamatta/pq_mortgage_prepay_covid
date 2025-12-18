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
          label="Monthly Prepay Rate (%)",
          color=:blue, linewidth=2,
          ylabel="Prepay Rate (%)",
          title="Prepayment Rate Over Time", titlefontsize=10,
          legend=:topleft)
    
    # Add COVID shading
    vspan!(p[1], [COVID_START, COVID_END], fillalpha=0.2, fillcolor=:red, label="COVID Period")
    
    # Bottom: Market rate
    plot!(p[2], agg.date, agg.market_rate,
          label="30Y Mortgage Rate (%)",
          color=:orange, linewidth=2,
          xlabel="Date", ylabel="Rate (%)",
          title="30-Year Mortgage Rate (FRED)", titlefontsize=10,
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
                   label=["Avg Prepay Rate (%)" "Avg Market Rate (%)"],
                   title="Prepayment and Market Rates by Period", titlefontsize=10,
                   ylabel="Rate (%)",
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
    agg.incentive_bucket = ifelse.(agg.avg_incentive .< 0, "Negative (<0%)",
                            ifelse.(agg.avg_incentive .< 1, "Low (0-1%)",
                            ifelse.(agg.avg_incentive .< 2, "Medium (1-2%)", "High (>2%)")))
    
    # Scatter plot with color by period
    agg.period_type = ifelse.(agg.date .< COVID_START, "Pre-COVID",
                       ifelse.(agg.date .<= COVID_END, "COVID", "Post-COVID"))
    
    p = scatter(agg.avg_incentive, agg.prepay_rate .* 100,
                group=agg.period_type,
                xlabel="Average Incentive (Orig Rate - Market Rate, %)",
                ylabel="Monthly Prepay Rate (%)",
                title="Prepayment Sensitivity to Refinancing Incentive", titlefontsize=10,
                legend=:topleft,
                markersize=6,
                alpha=0.7,
                size=(900, 600))
    
    # Add trend lines for each period
    for (period, color) in [("Pre-COVID", :blue), ("COVID", :red), ("Post-COVID", :green)]
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
                      label="$(period) trend", color=color, linewidth=2, linestyle=:dash)
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
             label="Prepayment Count",
             color=:darkgreen, linewidth=2,
             xlabel="Date", ylabel="Number of Prepayments",
             title="Monthly Prepayment Volume", titlefontsize=10,
             legend=:topright,
             size=(1000, 500))
    
    vspan!(p, [COVID_START, COVID_END], fillalpha=0.15, fillcolor=:red, label="COVID Period")
    
    # Add annotations for key events
    annotate!(p, [(Date(2020, 4, 1), maximum(agg.prepay_count) * 0.9, 
                   text("COVID\nLockdowns", 8, :red))])
    annotate!(p, [(Date(2021, 1, 1), maximum(agg.prepay_count) * 0.95, 
                   text("Low Rates\nRefi Boom", 8, :blue))])
    
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
          label="Actual Prepay Rate",
          color=:blue, linewidth=2)
    
    # Predicted (counterfactual) based on pre-COVID relationship
    agg.predicted_prepay = α .+ β .* agg.avg_incentive
    plot!(p, agg.date, agg.predicted_prepay .* 100,
          label="Expected (Pre-COVID Model)",
          color=:gray, linewidth=2, linestyle=:dash)
    
    vspan!(p, [COVID_START, COVID_END], fillalpha=0.15, fillcolor=:red, label="COVID Period")
    
    xlabel!("Date")
    ylabel!("Prepay Rate (%)")
    title!("Actual vs Expected Prepayment Rate\n(Gap = COVID Effect)")
    
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
    agg.period_type = ifelse.(agg.date .< COVID_START, "Pre-COVID",
                       ifelse.(agg.date .<= COVID_END, "COVID", "Post-COVID"))
    
    for period in ["Pre-COVID", "COVID", "Post-COVID"]
        sub = filter(r -> r.period_type == period, agg)
        if nrow(sub) > 0
            println("\n$period:")
            println("  Months: $(nrow(sub))")
            println("  Avg Prepay Rate: $(round(mean(sub.prepay_rate)*100, digits=2))%")
            println("  Avg Market Rate: $(round(mean(skipmissing(sub.market_rate)), digits=2))%")
            println("  Avg Incentive: $(round(mean(skipmissing(sub.avg_incentive)), digits=2))%")
            println("  Total Prepayments: $(sum(sub.prepay_count))")
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
