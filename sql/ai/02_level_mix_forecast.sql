-- When do Higher apprenticeships overtake Advanced?
--
-- In 2025/26 the two are 0.7 percentage points apart (Advanced 41.7%, Higher
-- 41.0%) after an eight-year convergence. For a training provider the crossover
-- year is a planning input, so it is worth forecasting -- carefully.
--
-- METHOD AND ITS LIMITS, stated up front:
--   * Only 8 complete academic years are available. That is very few for a
--     time-series model, and ARIMA cannot identify seasonality from annual
--     data at all -- it is fitting a trend with uncertainty, nothing more.
--   * The model is trained on COMPLETE years only (2017/18 - 2024/25).
--     2025/26 is provisional (three quarters) and is deliberately held out,
--     so its actual value is a genuine out-of-sample check rather than a
--     point the model already saw.
--   * Shares are modelled, not volumes. Shares are bounded and smooth;
--     volumes are noisy and policy-driven.

CREATE OR REPLACE MODEL `dfe-apprenticeships-2026.gold.forecast_higher_share`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'yr',
  time_series_data_col = 'share',
  data_frequency = 'YEARLY',
  horizon = 4,
  auto_arima = TRUE
) AS
SELECT
  DATE(academic_year_start, 9, 1) AS yr,     -- academic year starts in September
  SAFE_DIVIDE(
    SUM(IF(apprenticeship_level = 'Higher Apprenticeship', start_count, 0)),
    SUM(start_count)
  ) AS share
FROM `dfe-apprenticeships-2026.gold.fct_apprenticeship_headline`
WHERE is_current
  AND is_detail_grain
  AND geographic_level = 'National'
  AND apprenticeship_level != 'Unknown'
  AND NOT is_provisional                      -- hold 2025/26 out
GROUP BY yr;
