-- Which of the publisher's revisions were unusual?
--
-- 11,497 figures were restated across six releases. Most are small corrections;
-- a few are large. Reviewing them by hand is not practical, and a fixed
-- threshold ("flag anything over 500") would be arbitrary and would drift as
-- the data grows.
--
-- Instead: cluster the revisions on their own shape, then let
-- ML.DETECT_ANOMALIES flag the ones that sit far from every cluster centroid.
-- This is AI serving data quality rather than decorating it -- the output is a
-- short review queue for a human, not a prediction.

CREATE OR REPLACE MODEL `dfe-apprenticeships-2026.gold.restatement_shape`
OPTIONS(
  model_type = 'KMEANS',
  num_clusters = 4,
  standardize_features = TRUE
) AS
SELECT
  ABS(start_count_delta)                        AS abs_delta,
  ABS(IFNULL(start_count_pct_change, 0))        AS abs_pct_change,
  IF(disclosure_status_changed, 1, 0)           AS disclosure_changed,
  IFNULL(start_count_before, 0)                 AS size_before
FROM `dfe-apprenticeships-2026.gold.mart_restatement_history`
WHERE start_count_delta IS NOT NULL;
