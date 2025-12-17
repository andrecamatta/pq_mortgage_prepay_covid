# =============================================================================
# config/columns.jl
# =============================================================================
# Column indices based on Freddie Mac file_layout.xlsx
# Reference: https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset
#
# INSTRUCTIONS: 
# 1. Download file_layout.xlsx from Freddie Mac
# 2. Update indices below based on actual layout
# =============================================================================

using OrderedCollections: OrderedDict

# =============================================================================
# ORIGINATION FILE COLUMNS (sample_orig_YYYY.txt)
# =============================================================================
# Based on Freddie Mac Standard Loan-Level Dataset User Guide
# Pipe-delimited, NO header

const ORIG_COLUMNS = OrderedDict{Symbol, Int}(
    :credit_score         => 1,   # Credit Score (660-850, 9999=missing)
    :first_payment_date   => 2,   # YYYYMM
    :first_time_buyer     => 3,   # Y/N/9
    :maturity_date        => 4,   # YYYYMM
    :msa                  => 5,   # MSA code (or space)
    :mi_pct               => 6,   # Mortgage Insurance Percentage
    :units                => 7,   # Number of units
    :occupancy            => 8,   # P=Primary, S=Second, I=Investment
    :cltv                 => 9,   # Combined LTV
    :dti                  => 10,  # Debt-to-Income ratio
    :upb                  => 11,  # Original UPB
    :ltv                  => 12,  # Original LTV
    :orig_rate            => 13,  # Original Interest Rate
    :channel              => 14,  # R=Retail, B=Broker, C=Correspondent
    :ppm_flag             => 15,  # Prepayment Penalty Mortgage Flag
    :amort_type           => 16,  # FRM, ARM
    :state                => 17,  # Property State (2-letter)
    :property_type        => 18,  # SF, CO, CP, MH, PU
    :zip                  => 19,  # Postal Code (3-digit)
    :loan_id              => 20,  # Loan Sequence Number (PRIMARY KEY)
    :loan_purpose         => 21,  # P=Purchase, C=Cash-out Refi, N=No Cash-out Refi
    :orig_term            => 22,  # Original Loan Term (months)
    :num_borrowers        => 23,  # Number of Borrowers
    :seller               => 24,  # Seller Name
    :servicer             => 25,  # Servicer Name
)

# Minimal subset for efficient loading
const ORIG_MINIMAL = OrderedDict{Symbol, Int}(
    :loan_id              => 20,
    :credit_score         => 1,
    :first_payment_date   => 2,
    :orig_rate            => 13,
    :orig_term            => 22,
    :upb                  => 11,
    :ltv                  => 12,
    :dti                  => 10,
    :occupancy            => 8,
    :state                => 17,
    :property_type        => 18,
)

# Type hints for origination columns
const ORIG_TYPES = Dict{Symbol, Type}(
    :credit_score         => Int,
    :first_payment_date   => Int,
    :orig_rate            => Float64,
    :orig_term            => Int,
    :upb                  => Float64,
    :ltv                  => Int,
    :dti                  => Int,
)

# =============================================================================
# PERFORMANCE/SERVICING FILE COLUMNS (sample_svcg_YYYY.txt)
# =============================================================================

const SVCG_COLUMNS = OrderedDict{Symbol, Int}(
    :loan_id              => 1,   # Loan Sequence Number
    :monthly_rpt_period   => 2,   # Monthly Reporting Period (YYYYMM)
    :current_upb          => 3,   # Current Actual UPB
    :delinquency_status   => 4,   # Current Loan Delinquency Status
    :loan_age             => 5,   # Loan Age (months since origination)
    :remaining_months     => 6,   # Remaining Months to Maturity
    :repurchase_flag      => 7,   # Repurchase Flag
    :mod_flag             => 8,   # Modification Flag
    :zb_code              => 9,   # Zero Balance Code (01=Prepaid!!)
    :zb_date              => 10,  # Zero Balance Effective Date
    :current_rate         => 11,  # Current Interest Rate
    :current_deferred_upb => 12,  # Current Deferred UPB
    :ddlpi                => 13,  # Due Date of Last Paid Installment
    :mi_recoveries        => 14,  # MI Recoveries
    :net_proceeds         => 15,  # Net Sale Proceeds
    :non_mi_recoveries    => 16,  # Non MI Recoveries
    :expenses             => 17,  # Expenses
    :legal_costs          => 18,  # Legal Costs
    :maint_costs          => 19,  # Maintenance and Preservation Costs
    :taxes_insurance      => 20,  # Taxes and Insurance
    :misc_expenses        => 21,  # Miscellaneous Expenses
    :actual_loss          => 22,  # Actual Loss Calculation
    :mod_cost             => 23,  # Modification Cost
    :step_mod_flag        => 24,  # Step Modification Flag
    :deferred_payment_mod => 25,  # Deferred Payment Plan
    :eltv                 => 26,  # Estimated LTV
)

# Minimal subset for hazard modeling
const SVCG_MINIMAL = OrderedDict{Symbol, Int}(
    :loan_id              => 1,
    :monthly_rpt_period   => 2,
    :current_upb          => 3,
    :loan_age             => 5,
    :zb_code              => 9,
    :current_rate         => 11,
)

# Type hints for performance columns
const SVCG_TYPES = Dict{Symbol, Type}(
    :monthly_rpt_period   => Int,
    :current_upb          => Float64,
    :loan_age             => Int,
    :current_rate         => Float64,
)

# =============================================================================
# ZERO BALANCE CODES (zb_code)
# =============================================================================
# 01 = Prepaid or Matured (THIS IS OUR EVENT!)
# 02 = Third Party Sale
# 03 = Short Sale or Charge Off
# 06 = Repurchased
# 09 = REO Disposition
# 15 = Note Sale
# 16 = Reperforming Loan Sale
# 96 = Active loan termination (COVID-19)
# 97 = Active loan termination (Modification)

const PREPAY_CODE = "01"

# =============================================================================
# COHORT FILTERS
# =============================================================================
# Define which origination years to include

const COHORT_YEARS = 2016:2019
const CUTOFF_TRAIN = 202001
const CUTOFF_VAL = 202201
const COVID_START = 202003
const COVID_END = 202112
