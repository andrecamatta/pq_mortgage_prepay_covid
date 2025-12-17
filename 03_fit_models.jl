# =============================================================================
# 03_fit_models.jl
# =============================================================================
# Fit M0 (baseline) and M1 (dummy COVID) logistic regression models.

using CSV, DataFrames, Arrow, Dates
using GLM, StatsModels, StatsBase
using Distributions: Chisq, cdf

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
    
    # Save M1 coefficients
    m1_coef = DataFrame(
        term = coefnames(m1),
        estimate = coef(m1),
        std_error = stderror(m1),
    )
    m1_coef.ci_lower = m1_coef.estimate .- 1.96 .* m1_coef.std_error
    m1_coef.ci_upper = m1_coef.estimate .+ 1.96 .* m1_coef.std_error
    CSV.write(joinpath(RESULTS_DIR, "m1_coefficients.csv"), m1_coef)
    
    # ===== Likelihood Ratio Test: M0 vs M1 =====
    # H0: COVID terms do not improve the model (δ = η = 0)
    # We need to fit M0 on the same data as M1 for valid comparison
    m0_full = fit_m0(train_val)  # Refit M0 on train+val
    
    ll_m0 = loglikelihood(m0_full)
    ll_m1 = loglikelihood(m1)
    lr_stat = 2 * (ll_m1 - ll_m0)  # LR = 2 * (LL_unrestricted - LL_restricted)
    df = 2  # Number of additional parameters in M1 (covid, covid_incentive)
    p_value = 1 - cdf(Chisq(df), lr_stat)
    
    @info "===== Likelihood Ratio Test: M0 vs M1 ====="
    @info "  Log-Likelihood M0: $(round(ll_m0, digits=2))"
    @info "  Log-Likelihood M1: $(round(ll_m1, digits=2))"
    @info "  LR Statistic: $(round(lr_stat, digits=2))"
    @info "  Degrees of Freedom: $df"
    @info "  P-value: $(p_value < 1e-10 ? "<1e-10" : round(p_value, sigdigits=3))"
    @info "  Conclusion: $(p_value < 0.05 ? "REJECT H0 - COVID terms are SIGNIFICANT" : "Fail to reject H0")"
    
    # Save evaluation metrics
    metrics = DataFrame(
        model = ["M0", "M1"],
        train_logloss = [m0_eval.train_logloss, m1_eval.train_logloss],
        val_logloss = [m0_eval.val_logloss, m1_eval.val_logloss],
        test_logloss = [m0_eval.test_logloss, m1_eval.test_logloss],
    )
    CSV.write(joinpath(RESULTS_DIR, "model_metrics.csv"), metrics)
    
    # Save LRT results
    lrt_results = DataFrame(
        test = ["Likelihood Ratio Test"],
        lr_statistic = [lr_stat],
        df = [df],
        p_value = [p_value],
        significant = [p_value < 0.05],
    )
    CSV.write(joinpath(RESULTS_DIR, "lrt_results.csv"), lrt_results)
    
    @info "Results saved to $RESULTS_DIR"
    
    return (m0=m0, m1=m1, metrics=metrics)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
