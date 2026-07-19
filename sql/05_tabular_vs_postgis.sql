-- Tabular (lon/lat) vs PostGIS (geom) timing comparison.
-- 50 runs per (range × method); median reported in application docs.

CREATE INDEX IF NOT EXISTS nodes_lon_lat_idx ON nodes (lon, lat);
ANALYZE nodes;

DROP TABLE IF EXISTS bench_cmp;
CREATE TEMP TABLE bench_cmp (
  range_name text,
  method text,
  n_nodes int,
  exec_ms double precision
);

DO $$
DECLARE
  i int; t0 timestamptz; t1 timestamptz; n int;
  ranges text[][] := ARRAY[
    ARRAY['A_tiny', '114.10', '22.25', '114.25', '22.35'],
    ARRAY['B_small', '113.90', '22.15', '114.40', '22.50'],
    ARRAY['C_hk_region', '113.650220', '22.030046', '114.659994', '22.699814'],
    ARRAY['D_medium_GBA', '112.5', '21.5', '115.5', '23.5'],
    ARRAY['E_large_coastal', '110.0', '18.0', '120.0', '26.0']
  ];
  r text[];
  xmin float8; ymin float8; xmax float8; ymax float8;
BEGIN
  PERFORM COUNT(*) FROM nodes;

  FOREACH r SLICE 1 IN ARRAY ranges LOOP
    xmin := r[2]::float8; ymin := r[3]::float8;
    xmax := r[4]::float8; ymax := r[5]::float8;

    FOR i IN 1..50 LOOP
      t0 := clock_timestamp();
      EXECUTE format(
        'SELECT COUNT(*) FROM nodes WHERE lon BETWEEN %s AND %s AND lat BETWEEN %s AND %s',
        xmin, xmax, ymin, ymax
      ) INTO n;
      t1 := clock_timestamp();
      INSERT INTO bench_cmp VALUES (r[1], 'tabular_lon_lat', n,
        EXTRACT(EPOCH FROM (t1 - t0)) * 1000);
    END LOOP;

    FOR i IN 1..50 LOOP
      t0 := clock_timestamp();
      EXECUTE format(
        'SELECT COUNT(*) FROM nodes WHERE geom && ST_MakeEnvelope(%s,%s,%s,%s,4326)',
        xmin, ymin, xmax, ymax
      ) INTO n;
      t1 := clock_timestamp();
      INSERT INTO bench_cmp VALUES (r[1], 'postgis_bbox', n,
        EXTRACT(EPOCH FROM (t1 - t0)) * 1000);
    END LOOP;

    FOR i IN 1..50 LOOP
      t0 := clock_timestamp();
      EXECUTE format(
        'SELECT COUNT(*) FROM nodes WHERE ST_Intersects(geom, ST_MakeEnvelope(%s,%s,%s,%s,4326))',
        xmin, ymin, xmax, ymax
      ) INTO n;
      t1 := clock_timestamp();
      INSERT INTO bench_cmp VALUES (r[1], 'postgis_intersects', n,
        EXTRACT(EPOCH FROM (t1 - t0)) * 1000);
    END LOOP;
  END LOOP;

  FOR i IN 1..50 LOOP
    t0 := clock_timestamp();
    SELECT COUNT(*) INTO n FROM nodes;
    t1 := clock_timestamp();
    INSERT INTO bench_cmp VALUES ('F_full_mesh', 'full_table', n,
      EXTRACT(EPOCH FROM (t1 - t0)) * 1000);
  END LOOP;
END $$;

\echo '=== Per-method medians (50 runs) ==='
SELECT
  range_name,
  method,
  n_nodes,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY exec_ms)::numeric, 3) AS median_ms,
  ROUND(AVG(exec_ms)::numeric, 3) AS avg_ms
FROM bench_cmp
GROUP BY range_name, method, n_nodes
ORDER BY
  CASE range_name
    WHEN 'A_tiny' THEN 1 WHEN 'B_small' THEN 2 WHEN 'C_hk_region' THEN 3
    WHEN 'D_medium_GBA' THEN 4 WHEN 'E_large_coastal' THEN 5 ELSE 6 END,
  CASE method
    WHEN 'tabular_lon_lat' THEN 1 WHEN 'postgis_bbox' THEN 2
    WHEN 'postgis_intersects' THEN 3 ELSE 4 END;

\echo ''
\echo '=== Side-by-side tabular vs PostGIS bbox ==='
SELECT
  t.range_name,
  t.n_nodes,
  ROUND(t.med::numeric, 3) AS tabular_ms,
  ROUND(p.med::numeric, 3) AS postgis_bbox_ms,
  ROUND(i.med::numeric, 3) AS postgis_intersects_ms,
  ROUND((p.med / NULLIF(t.med, 0))::numeric, 2) AS bbox_vs_tabular_x
FROM (
  SELECT range_name, n_nodes,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY exec_ms) AS med
  FROM bench_cmp WHERE method = 'tabular_lon_lat' GROUP BY 1, 2
) t
JOIN (
  SELECT range_name,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY exec_ms) AS med
  FROM bench_cmp WHERE method = 'postgis_bbox' GROUP BY 1
) p USING (range_name)
JOIN (
  SELECT range_name,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY exec_ms) AS med
  FROM bench_cmp WHERE method = 'postgis_intersects' GROUP BY 1
) i USING (range_name)
ORDER BY
  CASE t.range_name
    WHEN 'A_tiny' THEN 1 WHEN 'B_small' THEN 2 WHEN 'C_hk_region' THEN 3
    WHEN 'D_medium_GBA' THEN 4 WHEN 'E_large_coastal' THEN 5 ELSE 6 END;

\echo ''
\echo '=== Table / index footprint ==='
SELECT
  pg_size_pretty(pg_relation_size('nodes')) AS table_heap,
  pg_size_pretty(pg_total_relation_size('nodes')) AS table_plus_indexes,
  (SELECT COUNT(*) FROM nodes) AS n_rows;
