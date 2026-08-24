-- The headline finding: naive aggregation over this source overstates by ~24x.
--
-- Every one of the 5 filter dimensions carries its own 'Total' member, so the
-- published extract mixes detail rows with subtotals at every level of the
-- hierarchy. SUM() over the raw table therefore counts the same apprenticeship
-- starts once per subtotal combination it appears in.
--
-- `agg_depth` = how many dimensions are rolled up on a given row.
--   0 = true detail grain, 5 = the single grand-total row.
--
-- Result (version 2.0.2, England, 2024/25):
--   NAIVE   SUM(all rows)       8,484,310   576 rows
--   CORRECT detail grain only     353,500   126 rows
--   OFFICIAL published total      353,500     1 row   <- exact reconciliation
--
-- The detail-grain sum matching the published grand total is the proof that
-- agg_depth = 0 is the correct analytical grain.

WITH latest AS (
  SELECT *
  FROM `dfe-apprenticeships-2026.bronze.raw_apprenticeships`
  WHERE version = '2.0.2'
    AND time_period = '202425'
    AND geographic_level = 'National'
),
scored AS (
  SELECT
    -- SAFE_CAST is load-bearing: 'low'/'c'/'z' suppression markers live in
    -- these columns and must become NULL, never 0.
    SAFE_CAST(start_count AS INT64) AS starts,
    (
      IF(apprenticeship_level = 'Total', 1, 0)
      + IF(age_youth_adult    = 'Total', 1, 0)
      + IF(age_group          = 'Total', 1, 0)
      + IF(funding_type       = 'Total', 1, 0)
      + IF(provider_type      = 'Total', 1, 0)
    ) AS agg_depth
  FROM latest
)
SELECT 'NAIVE  SUM(all rows)'      AS method, SUM(starts) AS total_starts, COUNT(*) AS rows_used FROM scored
UNION ALL
SELECT 'CORRECT detail grain only', SUM(starts), COUNT(*) FROM scored WHERE agg_depth = 0
UNION ALL
SELECT 'OFFICIAL published total',  SUM(starts), COUNT(*) FROM scored WHERE agg_depth = 5
ORDER BY total_starts DESC;
