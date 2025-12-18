# =============================================================================
# 07_quantify_biases.jl
# =============================================================================
# Quantify the "net impact" of behavioral biases by comparing:
# A) M2 Predicted Probability (Actual)
# B) Counterfactual Probability (setting interaction terms to zero)

using CSV, DataFrames, Statistics, Arrow, Dates

include("config/project.jl")

function sigmoid(x)
    return 1.0 / (1.0 + exp(-x))
end

function main()
    @info "=== 07_quantify_biases.jl (Counterfactual) ==="
    
    # 1. Load Coefficients
    m2_coefs_path = joinpath(RESULTS_DIR, "m2_coefficients.csv")
    if !isfile(m2_coefs_path)
        error("File not found: $m2_coefs_path. Please run 03_fit_models.jl first.")
    end
    m2_coefs = CSV.read(m2_coefs_path, DataFrame)
    
    # Helper to get coefficient
    get_beta(term) = begin
        # Handle exact match first
        r = filter(r -> r.term == term, m2_coefs)
        # Handle intercept specifically if needed
        if nrow(r) == 0 && term == "Intercept"
            r = filter(r -> r.term == "(Intercept)", m2_coefs)
        end
        if isempty(r)
            @warn "Coefficient for '$term' not found, assuming 0.0"
            return 0.0
        end
        return r.estimate[1]
    end
    
    b_int = get_beta("(Intercept)")
    b_inc = get_beta("incentive")
    b_age = get_beta("loan_age")
    b_score = get_beta("credit_score")
    b_ltv = get_beta("ltv")
    b_covid = get_beta("covid")
    b_cov_inc = get_beta("covid_incentive")
    b_cov_age = get_beta("covid_loan_age")     # The Bias Terms
    b_cov_score = get_beta("covid_credit_score") # The Bias Terms
    
    @info "Loaded Coefficients:"
    @info "  Bias Age (Sunk Cost Proxy): $b_cov_age"
    @info "  Bias Score (Overconfidence Proxy): $b_cov_score"
    
    # 2. Load Data (COVID Period Only for efficiency)
    panel_path = joinpath(PROCESSED_DIR, "loan_month_panel.arrow")
    @info "Loading panel data from $panel_path..."
    panel = Arrow.Table(panel_path) |> DataFrame
    
    # Filters: COVID period is defined as March 2020 (202003) to Dec 2021 (202112) in this study
    covid_data = filter(r -> r.monthly_rpt_period >= 202003 && r.monthly_rpt_period <= 202112, panel)
    
    n = nrow(covid_data)
    @info "Analyzing $n observations during COVID period."
    
    # 3. Calculate Logits
    # Base part (common to both)
    # Note: data columns must match names used here
    base_logit = b_int .+ 
                 b_inc .* covid_data.incentive .+ 
                 b_age .* covid_data.loan_age .+ 
                 b_score .* covid_data.credit_score .+ 
                 b_ltv .* covid_data.ltv .+
                 b_covid .* covid_data.covid .+
                 b_cov_inc .* (covid_data.covid .* covid_data.incentive)
                 
    # Scenario A: With Biases (Full Model)
    bias_part = b_cov_age .* (covid_data.covid .* covid_data.loan_age) .+
                b_cov_score .* (covid_data.covid .* covid_data.credit_score)
                
    logit_A = base_logit .+ bias_part
    prob_A = sigmoid.(logit_A)
    
    # Scenario B: Without Biases (Counterfactual)
    logit_B = base_logit # bias terms are zero
    prob_B = sigmoid.(logit_B)
    
    # 4. Aggregates
    mean_prob_A = mean(prob_A)
    mean_prob_B = mean(prob_B)
    
    # Total monthly rate %
    rate_A = mean_prob_A * 100
    rate_B = mean_prob_B * 100
    
    diff = rate_A - rate_B
    rel_change = (diff / rate_B) * 100
    
    @info "--- Counterfactual Results (Average Monthly Prepayment Rate) ---"
    @info "Scenario A (Actual/Biased): $(round(rate_A, digits=3))%"
    @info "Scenario B (No Behavioral Biases): $(round(rate_B, digits=3))%"
    @info "Difference: $(round(diff, digits=3)) percentage points"
    
    if diff < 0
        @info "Conclusion: Biases acted as a DRAG on prepayment."
        @info "Without these biases (Sunk Cost/Inertia), prepayment volume would have been $(round(abs(rel_change), digits=1))% HIGHER."
    else
        @info "Conclusion: Biases AMPLIFIED prepayment."
        @info "Without these biases, prepayment volume would have been $(round(abs(rel_change), digits=1))% LOWER."
    end
    
    # Save results to analyze later if needed
    results = DataFrame(
        metric = ["Rate Actual (Scenario A)", "Rate NoBias (Scenario B)", "Difference", "Relative Impact %"],
        value = [rate_A, rate_B, diff, rel_change]
    )
    CSV.write(joinpath(RESULTS_DIR, "quantification_results.csv"), results)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
