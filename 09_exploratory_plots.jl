# =============================================================================
# 09_exploratory_plots.jl
# =============================================================================
# Generate exploratory plots to visualize:
# E) Geographic divergence (Hot vs Cold states) - Evidence of WFH/Migration
# F) Occupancy divergence (Primary vs Investment) - Evidence of Eviction Moratorium
# G) Decomposition of COVID excess (Total vs Geographic component)

using CSV, DataFrames, Dates, Arrow, Statistics
using StatsPlots, Plots

include("config/project.jl")

# Helper to convert YYYYMM to Date
function period_to_date(period::Int)
    year = div(period, 100)
    month = mod(period, 100)
    return Date(year, month, 1)
end

# Add COVID band
function add_covid_band!(p)
    vspan!(p, [COVID_START, COVID_END], 
           fillalpha=COVID_BAND_ALPHA, fillcolor=COVID_BAND_COLOR, label="Período COVID")
end

function main()
    @info "=== 09_exploratory_plots.jl ==="
    
    mkpath(PLOTS_DIR)
    
    # Load panel
    panel_path = joinpath(PROCESSED_DIR, "loan_month_panel.arrow")
    @info "Loading panel from $panel_path..."
    panel = Arrow.Table(panel_path) |> DataFrame
    
    # Define regions
    hot_states = ["FL", "TX", "AZ", "NV", "ID", "NC", "TN", "SC", "GA"]
    cold_states = ["CA", "NY", "IL", "MA", "NJ", "CT"]
    
    panel.region = ifelse.(in.(panel.state, Ref(hot_states)), "Hot/Inflow",
                   ifelse.(in.(panel.state, Ref(cold_states)), "Cold/Outflow", "Other"))
    
    # =========================================================================
    # Plot E: Geographic Divergence (WFH Evidence)
    # =========================================================================
    @info "Generating Plot E: Geographic divergence over time..."
    
    # Aggregate by month and region
    regional_ts = combine(groupby(panel, [:monthly_rpt_period, :region]),
        :y => mean => :prepay_rate,
        nrow => :count
    )
    
    # Filter to meaningful regions
    regional_ts = filter(r -> r.region in ["Hot/Inflow", "Cold/Outflow"], regional_ts)
    regional_ts.date = period_to_date.(regional_ts.monthly_rpt_period)
    regional_ts.prepay_rate .*= 100  # Convert to %
    
    p_geo = plot(size=(900, 500), legend=:topleft)
    
    for region in ["Cold/Outflow", "Hot/Inflow"]
        df_region = filter(r -> r.region == region, regional_ts)
        sort!(df_region, :date)
        
        # Create descriptive label with state examples
        if region == "Cold/Outflow"
            label_text = "Êxodo (CA, NY, IL, MA, NJ, CT)"
            color = :red
            style = :solid
        else
            label_text = "Destino (FL, TX, AZ, NV, ID, NC, TN, SC, GA)"
            color = :blue
            style = :dash
        end
        
        plot!(p_geo, df_region.date, df_region.prepay_rate,
              label=label_text,
              color=color,
              linestyle=style,
              linewidth=2.5)
    end
    
    add_covid_band!(p_geo)
    xlabel!(p_geo, "Data")
    ylabel!(p_geo, "Taxa de Pré-pagamento Mensal (%)")
    title!(p_geo, "Divergência Geográfica: Estados de Êxodo vs. Destino", 
           titlefontsize=11)
    
    savefig(p_geo, joinpath(PLOTS_DIR, "E_geographic_divergence.png"))
    @info "Saved Plot E"
    
    # =========================================================================
    # Plot F: Occupancy Divergence (Eviction Moratorium Evidence)
    # =========================================================================
    @info "Generating Plot F: Occupancy divergence over time..."
    
    # Aggregate by month and occupancy
    occupancy_ts = combine(groupby(panel, [:monthly_rpt_period, :occupancy]),
        :y => mean => :prepay_rate,
        nrow => :count
    )
    
    # Filter to P and I only
    occupancy_ts = filter(r -> r.occupancy in ["P", "I"], occupancy_ts)
    occupancy_ts.date = period_to_date.(occupancy_ts.monthly_rpt_period)
    occupancy_ts.prepay_rate .*= 100  # Convert to %
    
    p_occ = plot(size=(900, 500), legend=:topleft)
    
    for occ in ["P", "I"]
        df_occ = filter(r -> r.occupancy == occ, occupancy_ts)
        sort!(df_occ, :date)
        
        label_text = occ == "P" ? "Residência Primária" : "Investimento"
        color = occ == "P" ? :green : :orange
        style = occ == "P" ? :solid : :dash
        
        plot!(p_occ, df_occ.date, df_occ.prepay_rate,
              label=label_text,
              color=color,
              linestyle=style,
              linewidth=2.5)
    end
    
    add_covid_band!(p_occ)
    xlabel!(p_occ, "Data")
    ylabel!(p_occ, "Taxa de Pré-pagamento Mensal (%)")
    title!(p_occ, "Divergência por Ocupação: Residências vs. Investimentos\n(Evidência de Eviction Moratorium)", 
           titlefontsize=10)
    
    savefig(p_occ, joinpath(PLOTS_DIR, "F_occupancy_divergence.png"))
    @info "Saved Plot F"
    
    # =========================================================================
    # Plot G: Decomposition of COVID Excess
    # =========================================================================
    @info "Generating Plot G: Decomposition of COVID excess..."
    
    # Load M0 coefficients for baseline prediction
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
    
    # Filter COVID period
    covid_data = filter(r -> r.monthly_rpt_period >= 202003 && r.monthly_rpt_period <= 202112, panel)
    
    # Calculate M0 baseline prediction
    logit_m0 = b_int .+ 
               b_inc .* covid_data.incentive .+ 
               b_age .* covid_data.loan_age .+ 
               b_score .* covid_data.credit_score .+ 
               b_ltv .* covid_data.ltv
    covid_data.pred_m0 = 1.0 ./ (1.0 .+ exp.(-logit_m0))
    covid_data.excess = covid_data.y .- covid_data.pred_m0
    
    # Overall statistics
    overall_obs = mean(covid_data.y) * 100
    overall_exp = mean(covid_data.pred_m0) * 100
    overall_excess = mean(covid_data.excess) * 100
    
    # Geographic breakdown
    cold_data = filter(r -> r.region == "Cold/Outflow", covid_data)
    hot_data = filter(r -> r.region == "Hot/Inflow", covid_data)
    other_data = filter(r -> r.region == "Other", covid_data)
    
    cold_excess = mean(cold_data.excess) * 100
    hot_excess = mean(hot_data.excess) * 100
    other_excess = mean(other_data.excess) * 100
    
    # Weight by sample size
    n_cold = nrow(cold_data)
    n_hot = nrow(hot_data)
    n_other = nrow(other_data)
    n_total = n_cold + n_hot + n_other
    
    # Geographic contribution (weighted average of regional deviations from overall)
    # We use Cold as reference (positive excess), Hot as counterfactual
    geo_contribution = (n_cold / n_total) * (cold_excess - overall_excess) + 
                       (n_hot / n_total) * (hot_excess - overall_excess)
    
    residual = overall_excess - geo_contribution
    
    # Create decomposition bar chart
    p_decomp = plot(size=(700, 500), legend=:topright)
    
    categories = ["Excesso Total\nCOVID", "Componente\nGeográfico\n(WFH/Migração)", "Outros Fatores\n(Digitalização,\nLiquidez, etc.)"]
    values = [overall_excess, geo_contribution, residual]
    colors = [:purple, :red, :gray]
    
    bar!(p_decomp, categories, values,
         color=colors,
         alpha=0.7,
         legend=false,
         ylabel="Excesso de Prepay (pontos percentuais)",
         title="Decomposição do Excesso COVID\n(Observado - Esperado pelo M0)",
         titlefontsize=11)
    
    # Add value labels on bars
    for (i, v) in enumerate(values)
        annotate!(p_decomp, i, v + 0.02, text(string(round(v, digits=3), " p.p."), :center, 9))
    end
    
    hline!(p_decomp, [0], color=:black, linestyle=:dash, linewidth=1, label="")
    
    savefig(p_decomp, joinpath(PLOTS_DIR, "G_covid_decomposition.png"))
    @info "Saved Plot G"
    
    # Print summary
    @info "=== Decomposition Summary ==="
    @info "Total COVID Excess: $(round(overall_excess, digits=3)) p.p."
    @info "  - Geographic (WFH/Migration): $(round(geo_contribution, digits=3)) p.p. ($(round(100*geo_contribution/overall_excess, digits=1))%)"
    @info "  - Residual (Other factors): $(round(residual, digits=3)) p.p. ($(round(100*residual/overall_excess, digits=1))%)"
    
    @info "All exploratory plots saved to $PLOTS_DIR"
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
