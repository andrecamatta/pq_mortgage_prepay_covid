# =============================================================================
# 03_fit_models.jl
# =============================================================================
# Fit M0 (baseline) and M1 (dummy COVID) logistic regression models.

using CSV, DataFrames, Arrow, Dates
using GLM, StatsModels, StatsBase
using Distributions: Chisq, cdf
using Random: shuffle

include("01_download_or_load_data.jl")

# =============================================================================
# Configuration
# =============================================================================

const RESULTS_DIR = joinpath(DATA_DIR, "results")
const PANEL_PATH = joinpath(PROCESSED_DIR, "loan_month_panel.arrow")

# =============================================================================
# Model Definitions
# =============================================================================

"""
    fit_m0(train::DataFrame) -> GLM model

M0: Baseline logistic regression (no COVID term)

logit(p_{i,t}) = α + β * incentive + γ * loan_age + δ * credit_score + ε * ltv
"""
function fit_m0(train::DataFrame)
    @info "Fitting M0 (Baseline)..."
    
    formula = @formula(y ~ incentive + loan_age + credit_score + ltv)
    model = glm(formula, train, Binomial(), LogitLink())
    
    @info "M0 fitted. Deviance: $(deviance(model))"
    return model
end

"""
    fit_m1(train_val::DataFrame) -> GLM model

M1: Dummy COVID model with interaction

logit(p_{i,t}) = α + β * incentive + γ * loan_age + δ * credit_score + ε * ltv 
                 + η * covid + θ * (covid * incentive)

- η: level shift during COVID
- θ: change in incentive sensitivity during COVID
"""
function fit_m1(train_val::DataFrame)
    @info "Fitting M1 (Dummy COVID)..."
    
    formula = @formula(y ~ incentive + loan_age + credit_score + ltv + covid + covid_incentive)
    model = glm(formula, train_val, Binomial(), LogitLink())
    
    @info "M1 fitted. Deviance: $(deviance(model))"
    return model
end

"""
    fit_m2(train_val::DataFrame) -> GLM model

M2: Behavioral Bias Model with heterogeneous COVID effects

logit(p_{i,t}) = α + β * incentive + γ * loan_age + δ * credit_score + ε * ltv 
                 + η * covid + θ * (covid * incentive)
                 + λ * (covid * loan_age)      # Sunk-cost proxy
                 + μ * (covid * credit_score)  # Overconfidence proxy

Tests:
- λ > 0: COVID effect increases with loan age → sunk-cost weakened during COVID
- μ > 0: COVID effect increases with credit score → overconfidence amplified
"""
function fit_m2(train_val::DataFrame)
    @info "Fitting M2 (Behavioral Bias Interactions)..."
    
    # Create interaction terms
    data = copy(train_val)
    data.covid_loan_age = data.covid .* data.loan_age
    data.covid_credit_score = data.covid .* data.credit_score
    
    formula = @formula(y ~ incentive + loan_age + credit_score + ltv + 
                           covid + covid_incentive + 
                           covid_loan_age + covid_credit_score)
    model = glm(formula, data, Binomial(), LogitLink())
    
    @info "M2 fitted. Deviance: $(deviance(model))"
    return model
end

# =============================================================================
# Evaluation Functions
# =============================================================================

"""
    compute_predictions(model, data::DataFrame) -> Vector{Float64}

Compute predicted probabilities from GLM model.
"""
function compute_predictions(model, data::DataFrame)
    return predict(model, data)
end

"""
    compute_log_loss(y::Vector, p::Vector) -> Float64

Compute log loss (cross-entropy) for predictions.
"""
function compute_log_loss(y::Vector, p::Vector)
    ε = 1e-15
    p_clipped = clamp.(p, ε, 1 - ε)
    return -mean(y .* log.(p_clipped) .+ (1 .- y) .* log.(1 .- p_clipped))
end

"""
    evaluate_model(model, train::DataFrame, val::DataFrame, test::DataFrame) -> NamedTuple

Evaluate model on all splits and return metrics.
"""
function evaluate_model(model, train::DataFrame, val::DataFrame, test::DataFrame)
    train_pred = compute_predictions(model, train)
    val_pred = compute_predictions(model, val)
    test_pred = compute_predictions(model, test)
    
    train_ll = compute_log_loss(train.y, train_pred)
    val_ll = compute_log_loss(val.y, val_pred)
    test_ll = compute_log_loss(test.y, test_pred)
    
    return (
        train_logloss = train_ll,
        val_logloss = val_ll,
        test_logloss = test_ll,
        train_pred = train_pred,
        val_pred = val_pred,
        test_pred = test_pred,
    )
end

# =============================================================================
# Main execution
# =============================================================================

function main()
    @info "=== 03_fit_models.jl ==="
    
    mkpath(RESULTS_DIR)
    
    # Load panel
    panel = Arrow.Table(PANEL_PATH) |> DataFrame
    @info "Loaded panel: $(nrow(panel)) observations"
    
    # Split data
    train = filter(r -> r.monthly_rpt_period < 202001, panel)
    val = filter(r -> r.monthly_rpt_period >= 202001 && r.monthly_rpt_period < 202201, panel)
    test = filter(r -> r.monthly_rpt_period >= 202201, panel)
    
    @info "Train: $(nrow(train)), Val: $(nrow(val)), Test: $(nrow(test))"
    
    # ===== M0: Baseline =====
    m0 = fit_m0(train)
    m0_eval = evaluate_model(m0, train, val, test)
    @info "M0 Log Loss - Train: $(round(m0_eval.train_logloss, digits=4)), Val: $(round(m0_eval.val_logloss, digits=4)), Test: $(round(m0_eval.test_logloss, digits=4))"
    
    # Save M0 coefficients
    m0_coef = DataFrame(
        term = coefnames(m0),
        estimate = coef(m0),
        std_error = stderror(m0),
    )
    m0_coef.ci_lower = m0_coef.estimate .- 1.96 .* m0_coef.std_error
    m0_coef.ci_upper = m0_coef.estimate .+ 1.96 .* m0_coef.std_error
    CSV.write(joinpath(RESULTS_DIR, "m0_coefficients.csv"), m0_coef)
    
    # ===== M1: Dummy COVID =====
    train_val = vcat(train, val)
    m1 = fit_m1(train_val)
    m1_eval = evaluate_model(m1, train, val, test)
    @info "M1 Log Loss - Train: $(round(m1_eval.train_logloss, digits=4)), Val: $(round(m1_eval.val_logloss, digits=4)), Test: $(round(m1_eval.test_logloss, digits=4))"
    
    # Save Predictions for Plotting (Monthly Aggregates)
    # We use the full dataset (train_val + test) to get the complete time series
    # But wait, M1 was fit on train_val only. We should predict on everything to see full series.
    # Note: Using M1 fit on train_val to predict on test is correct for "out of sample" check,
    # but for the "Observed vs Predicted" plot we often want to see the fit across the board.
    # Let's combine everything for prediction generation.
    
    all_data = vcat(train, val, test)
    
    # Add predictions to a copy
    pred_df = select(all_data, :monthly_rpt_period, :y)
    pred_df.m0_pred = predict(m0, all_data)
    pred_df.m1_pred = predict(m1, all_data)
    
    # Aggregate by month
    monthly_agg = combine(groupby(pred_df, :monthly_rpt_period),
        :y => mean => :observed,
        :m0_pred => mean => :m0_pred,
        :m1_pred => mean => :m1_pred
    )
    sort!(monthly_agg, :monthly_rpt_period)
    
    CSV.write(joinpath(RESULTS_DIR, "monthly_predictions.csv"), monthly_agg)
    @info "Saved monthly aggregated predictions to monthly_predictions.csv"

    
    # Save M1 coefficients
    m1_coef = DataFrame(
        term = coefnames(m1),
        estimate = coef(m1),
        std_error = stderror(m1),
    )
    m1_coef.ci_lower = m1_coef.estimate .- 1.96 .* m1_coef.std_error
    m1_coef.ci_upper = m1_coef.estimate .+ 1.96 .* m1_coef.std_error
    CSV.write(joinpath(RESULTS_DIR, "m1_coefficients.csv"), m1_coef)
    
    # ===== M2: Behavioral Bias Model =====
    # Create interaction terms for M2
    train_val_m2 = copy(train_val)
    train_val_m2.covid_loan_age = train_val_m2.covid .* train_val_m2.loan_age
    train_val_m2.covid_credit_score = train_val_m2.covid .* train_val_m2.credit_score
    
    m2 = fit_m2(train_val)
    
    # Evaluate M2 (need to add interaction terms to test sets)
    test_m2 = copy(test)
    test_m2.covid_loan_age = test_m2.covid .* test_m2.loan_age
    test_m2.covid_credit_score = test_m2.covid .* test_m2.credit_score
    
    train_m2 = copy(train)
    train_m2.covid_loan_age = train_m2.covid .* train_m2.loan_age
    train_m2.covid_credit_score = train_m2.covid .* train_m2.credit_score
    
    val_m2 = copy(val)
    val_m2.covid_loan_age = val_m2.covid .* val_m2.loan_age
    val_m2.covid_credit_score = val_m2.covid .* val_m2.credit_score
    
    m2_eval = evaluate_model(m2, train_m2, val_m2, test_m2)
    @info "M2 Log Loss - Train: $(round(m2_eval.train_logloss, digits=4)), Val: $(round(m2_eval.val_logloss, digits=4)), Test: $(round(m2_eval.test_logloss, digits=4))"
    
    # Save M2 coefficients
    m2_coef = DataFrame(
        term = coefnames(m2),
        estimate = coef(m2),
        std_error = stderror(m2),
    )
    m2_coef.ci_lower = m2_coef.estimate .- 1.96 .* m2_coef.std_error
    CSV.write(joinpath(RESULTS_DIR, "m2_coefficients.csv"), m2_coef)

    # ===== Likelihood Ratio Tests =====
    m0_full = fit_m0(train_val)
    
    ll_m0 = loglikelihood(m0_full)
    ll_m1 = loglikelihood(m1)
    ll_m2 = loglikelihood(m2)
    
    lr_stat_m1 = 2 * (ll_m1 - ll_m0)
    df_m1 = 2
    p_value_m1 = 1 - cdf(Chisq(df_m1), lr_stat_m1)
    
    @info "===== Likelihood Ratio Test: M0 vs M1 ====="
    @info "  LR Statistic: $(round(lr_stat_m1, digits=2)), df=$df_m1, p=$(p_value_m1 < 1e-10 ? "<1e-10" : round(p_value_m1, sigdigits=3))"
    
    # LRT: M1 vs M2
    lr_stat_m2 = 2 * (ll_m2 - ll_m1)
    df_m2 = 2  # covid_loan_age and covid_credit_score
    p_value_m2 = 1 - cdf(Chisq(df_m2), lr_stat_m2)
    
    @info "===== Likelihood Ratio Test: M1 vs M2 (Behavioral Bias) ====="
    @info "  Log-Likelihood M1: $(round(ll_m1, digits=2))"
    @info "  Log-Likelihood M2: $(round(ll_m2, digits=2))"
    @info "  LR Statistic: $(round(lr_stat_m2, digits=2))"
    @info "  Degrees of Freedom: $df_m2"
    @info "  P-value: $(p_value_m2 < 1e-10 ? "<1e-10" : round(p_value_m2, sigdigits=3))"
    @info "  Conclusion: $(p_value_m2 < 0.05 ? "REJECT H0 - Behavioral interactions are SIGNIFICANT" : "Fail to reject H0")"
    
    # Interpret behavioral coefficients
    covid_loan_age_coef = m2_coef[m2_coef.term .== "covid_loan_age", :estimate][1]
    covid_credit_coef = m2_coef[m2_coef.term .== "covid_credit_score", :estimate][1]
    
    @info "===== Behavioral Bias Interpretation ====="
    @info "  covid×loan_age = $(round(covid_loan_age_coef, digits=4))"
    if covid_loan_age_coef > 0
        @info "    → POSITIVE: COVID effect INCREASES with loan age → Sunk-cost fallacy WEAKENED"
    else
        @info "    → NEGATIVE: COVID effect DECREASES with loan age → Sunk-cost fallacy STRENGTHENED"
    end
    
    @info "  covid×credit_score = $(round(covid_credit_coef, digits=6))"
    if covid_credit_coef > 0
        @info "    → POSITIVE: COVID effect INCREASES with credit score → Overconfidence AMPLIFIED"
    else
        @info "    → NEGATIVE: COVID effect DECREASES with credit score → Overconfidence NOT confirmed"
    end
    
    # Save evaluation metrics
    metrics = DataFrame(
        model = ["M0", "M1", "M2"],
        train_logloss = [m0_eval.train_logloss, m1_eval.train_logloss, m2_eval.train_logloss],
        val_logloss = [m0_eval.val_logloss, m1_eval.val_logloss, m2_eval.val_logloss],
        test_logloss = [m0_eval.test_logloss, m1_eval.test_logloss, m2_eval.test_logloss],
    )
    CSV.write(joinpath(RESULTS_DIR, "model_metrics.csv"), metrics)
    
    # Save LRT results
    lrt_results = DataFrame(
        test = ["M0 vs M1", "M1 vs M2"],
        lr_statistic = [lr_stat_m1, lr_stat_m2],
        df = [df_m1, df_m2],
        p_value = [p_value_m1, p_value_m2],
        significant = [p_value_m1 < 0.05, p_value_m2 < 0.05],
    )
    CSV.write(joinpath(RESULTS_DIR, "lrt_results.csv"), lrt_results)
    
    @info "Results saved to $RESULTS_DIR"
    
    return (m0=m0, m1=m1, m2=m2, metrics=metrics)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
