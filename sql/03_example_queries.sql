-- Example range queries on hindcast nodes.
-- docker exec -i urop1000-postgis psql -U hindcast -d hindcast < sql/03_example_queries.sql

-- Full mesh
SELECT COUNT(*) AS total_nodes FROM nodes;

-- Example area range — tabular lon/lat
SELECT node_id, lon, lat
FROM nodes
WHERE lon BETWEEN 113.650220 AND 114.659994
  AND lat BETWEEN 22.030046 AND 22.699814;

-- Same range — PostGIS geometry
SELECT node_id, lon, lat
FROM nodes
WHERE geom && ST_MakeEnvelope(
  113.650220, 22.030046,
  114.659994, 22.699814,
  4326
);
