# =============================================================================
# config/project.jl
# =============================================================================
# Centralized configuration for the mortgage prepayment analysis project.
# Single source of truth for paths, dates, and shared constants.

using Dates

# =============================================================================
# Paths
# =============================================================================
const PROJECT_DIR = dirname(@__DIR__)
const DATA_DIR = joinpath(PROJECT_DIR, "data")
const RAW_DIR = joinpath(DATA_DIR, "raw", "freddiemac")
const PROCESSED_DIR = joinpath(DATA_DIR, "processed")
const RESULTS_DIR = joinpath(DATA_DIR, "results")
const PLOTS_DIR = joinpath(DATA_DIR, "plots")

# Panel file
const PANEL_PATH = joinpath(PROCESSED_DIR, "loan_month_panel.arrow")
const AGG_SERIES_PATH = joinpath(PROCESSED_DIR, "aggregate_series.csv")

# =============================================================================
# COVID Period Definition
# =============================================================================
# Integer format (YYYYMM) for panel data filtering
const COVID_START_INT = 202003  # March 2020
const COVID_END_INT = 202112    # December 2021

# Date format for plotting
const COVID_START = Date(2020, 3, 1)
const COVID_END = Date(2021, 12, 31)

# =============================================================================
# Plot Settings
# =============================================================================
const DEFAULT_TITLEFONTSIZE = 10
const DEFAULT_PLOT_SIZE = (900, 500)
const COVID_BAND_COLOR = :red
const COVID_BAND_ALPHA = 0.15

# =============================================================================
# Model Settings
# =============================================================================
const TRAIN_CUTOFF = 201912  # Train: data before this
const VAL_CUTOFF = 202012    # Val: TRAIN_CUTOFF to this; Test: after this

# =============================================================================
# Utility Functions
# =============================================================================
"""
    add_covid_band!(p; color=COVID_BAND_COLOR, alpha=COVID_BAND_ALPHA)

Add COVID period shading to a plot.
"""
function add_covid_band!(p; color=COVID_BAND_COLOR, alpha=COVID_BAND_ALPHA, label="COVID Period")
    vspan!(p, [COVID_START, COVID_END], fillalpha=alpha, fillcolor=color, label=label)
end

"""
    ensure_dirs()

Create necessary directories if they don't exist.
"""
function ensure_dirs()
    mkpath(PROCESSED_DIR)
    mkpath(RESULTS_DIR)
    mkpath(PLOTS_DIR)
end

"""
    is_covid_period(period::Int) -> Bool

Check if a YYYYMM period is within COVID.
"""
is_covid_period(period::Int) = period >= COVID_START_INT && period <= COVID_END_INT

"""
    get_period_type(date::Date) -> String

Classify a date into Pre-COVID, COVID, or Post-COVID.
"""
function get_period_type(date::Date)
    if date < COVID_START
        return "Pre-COVID"
    elseif date <= COVID_END
        return "COVID"
    else
        return "Post-COVID"
    end
end
