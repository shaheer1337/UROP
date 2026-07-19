-- Benchmark: find node_ids in geographic ranges (small → large).
-- Goal: show PostGIS can return target node IDs efficiently from node_infos.

\timing on
\pset tuples_only on

-- Warm up spatial index / caches
SELECT COUNT(*) FROM nodes WHERE geom && ST_MakeEnvelope(114.0, 22.2, 114.3, 22.4, 4326);

\echo ''
\echo '=== A) Tiny box (~central HK harbour) ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT node_id FROM nodes
WHERE lon BETWEEN 114.10 AND 114.25
  AND lat BETWEEN 22.25 AND 22.35;

\echo ''
\echo '=== B) Small box (inner HK) ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT node_id FROM nodes
WHERE lon BETWEEN 113.90 AND 114.40
  AND lat BETWEEN 22.15 AND 22.50;

\echo ''
\echo '=== C) HK region bbox ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT node_id FROM nodes
WHERE lon BETWEEN 113.650220 AND 114.659994
  AND lat BETWEEN 22.030046 AND 22.699814;

\echo ''
\echo '=== D) Medium (GBA / Pearl River estuary scale) ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT node_id FROM nodes
WHERE lon BETWEEN 112.5 AND 115.5
  AND lat BETWEEN 21.5 AND 23.5;

\echo ''
\echo '=== E) Large (northern SCS coastal band) ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT node_id FROM nodes
WHERE lon BETWEEN 110.0 AND 120.0
  AND lat BETWEEN 18.0 AND 26.0;

\echo ''
\echo '=== F) Full mesh (all nodes) ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT node_id FROM nodes;

\echo ''
\echo '=== C2) HK region bbox via PostGIS envelope + GIST ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT node_id FROM nodes
WHERE geom && ST_MakeEnvelope(
    113.650220, 22.030046,
    114.659994, 22.699814,
    4326
);

\pset tuples_only off
\echo ''
\echo '=== Result counts (same ranges) ==='
SELECT 'A_tiny' AS rng, COUNT(*) AS n FROM nodes
WHERE lon BETWEEN 114.10 AND 114.25 AND lat BETWEEN 22.25 AND 22.35
UNION ALL SELECT 'B_small', COUNT(*) FROM nodes
WHERE lon BETWEEN 113.90 AND 114.40 AND lat BETWEEN 22.15 AND 22.50
UNION ALL SELECT 'C_hk_region', COUNT(*) FROM nodes
WHERE lon BETWEEN 113.650220 AND 114.659994 AND lat BETWEEN 22.030046 AND 22.699814
UNION ALL SELECT 'D_medium_GBA', COUNT(*) FROM nodes
WHERE lon BETWEEN 112.5 AND 115.5 AND lat BETWEEN 21.5 AND 23.5
UNION ALL SELECT 'E_large_coastal', COUNT(*) FROM nodes
WHERE lon BETWEEN 110.0 AND 120.0 AND lat BETWEEN 18.0 AND 26.0
UNION ALL SELECT 'F_full_mesh', COUNT(*) FROM nodes
ORDER BY 1;
