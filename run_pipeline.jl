# =============================================================================
# run_pipeline.jl
# =============================================================================
# Run the complete mortgage prepayment analysis pipeline.

using Pkg
Pkg.activate(@__DIR__)

@info "=== Mortgage Prepayment Pipeline ==="
@info "Starting full pipeline execution..."

# Step 1: Load/download data
@info "--- Step 1: Data Loading ---"
include("01_download_or_load_data.jl")
main()

# Step 2: Build panel
@info "--- Step 2: Panel Construction ---"
include("02_build_panel.jl")
main()

# Step 3: Fit models
@info "--- Step 3: Model Fitting ---"
include("03_fit_models.jl")
main()

# Step 4: Generate plots
@info "--- Step 4: Visualization ---"
include("04_plots.jl")
main()

@info "=== Pipeline Complete ==="
@info "Results saved to data/results/"
@info "Plots saved to data/plots/"
