# Mortgage Prepayment COVID Analysis

Julia pipeline for analyzing mortgage prepayment behavior during COVID-19 using Freddie Mac loan-level data.

## Requirements

- Julia 1.9+
- ~2GB RAM for panel construction
- ~16GB disk for Freddie Mac data

## Data Setup

1. Register at [Freddie Mac](https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset)
2. Download the **Sample Dataset** (not full dataset) for years 2016-2023
3. Extract and place files:
   ```
   data/raw/freddiemac/orig/sample_orig_YYYY.txt
   data/raw/freddiemac/svcg/sample_svcg_YYYY.txt
   ```

## Installation

```bash
git clone <repo-url>
cd pq_mortgage_prepay_covid
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Running the Pipeline

```bash
# 1. Load and validate data
julia --project=. 01_download_or_load_data.jl

# 2. Build loan-month panel
julia --project=. 02_build_panel.jl

# 3. Fit models (M0 baseline, M1 with COVID terms)
julia --project=. 03_fit_models.jl

# 4. Generate plots
julia --project=. 04_plots.jl

# 5. Exploratory analysis (optional)
julia --project=. 05_eda.jl
```

## Project Structure

```
├── 01_download_or_load_data.jl  # Data loading
├── 02_build_panel.jl            # Panel construction
├── 03_fit_models.jl             # Logistic regression models
├── 04_plots.jl                  # Visualizations
├── 05_eda.jl                    # Exploratory analysis
├── config/columns.jl            # Column mappings
└── data/                        # Data directory (gitignored)
```

## License

MIT
