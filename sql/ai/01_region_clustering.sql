-- Segment English regions by the SHAPE of their apprenticeship market, not
-- their size. Feature values are shares, so London does not simply cluster
-- with other large regions.
--
-- BQML k-means runs as ordinary BigQuery compute, so at this data volume it
-- sits inside the 1 TiB/month free query allowance.

CREATE OR REPLACE MODEL `dfe-apprenticeships-2026.gold.region_segments`
OPTIONS(
  model_type = 'KMEANS',
  num_clusters = 3,
  standardize_features = TRUE,
  kmeans_init_method = 'KMEANS++'
) AS
WITH regional AS (
  SELECT
    region_name,
    apprenticeship_level,
    SUM(start_count) AS starts
  FROM `dfe-apprenticeships-2026.gold.fct_apprenticeship_headline`
  WHERE is_current
    AND is_detail_grain
    AND geographic_level = 'Regional'
    AND region_name != 'Outside of England and unknown'  -- residual bucket, not a place
    AND NOT is_provisional                                -- exclude part-year 2025/26
    AND start_count IS NOT NULL
  GROUP BY region_name, apprenticeship_level
),
totals AS (
  SELECT region_name, SUM(starts) AS total_starts
  FROM regional GROUP BY region_name
)
SELECT
  r.region_name,
  -- Shares, so clustering reflects market composition rather than volume.
  SAFE_DIVIDE(SUM(IF(r.apprenticeship_level = 'Intermediate Apprenticeship', r.starts, 0)), t.total_starts) AS share_intermediate,
  SAFE_DIVIDE(SUM(IF(r.apprenticeship_level = 'Advanced Apprenticeship',     r.starts, 0)), t.total_starts) AS share_advanced,
  SAFE_DIVIDE(SUM(IF(r.apprenticeship_level = 'Higher Apprenticeship',       r.starts, 0)), t.total_starts) AS share_higher
FROM regional r
JOIN totals t USING (region_name)
GROUP BY r.region_name, t.total_starts;
