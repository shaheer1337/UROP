-- Example PostGIS queries for the PolyU SCS hindcast nodes.
-- Run in: QGIS DB Manager, psql, or: docker exec -i urop1000-postgis psql -U hindcast -d hindcast

-- 1) How many nodes in the full South China Sea mesh?
SELECT COUNT(*) AS total_nodes FROM nodes;

-- 2) Area-range query: Hong Kong bounding box (lon/lat filter)
SELECT COUNT(*) AS hk_nodes
FROM nodes
WHERE lon BETWEEN 113.650220 AND 114.659994
  AND lat BETWEEN 22.030046 AND 22.699814;

-- 3) Same filter using PostGIS envelope (uses spatial index)
SELECT COUNT(*) AS hk_nodes_spatial
FROM nodes
WHERE geom && ST_MakeEnvelope(
    113.650220, 22.030046,
    114.659994, 22.699814,
    4326
);

-- 4) Use the named Hong Kong view
SELECT COUNT(*) FROM nodes_hong_kong;

-- 5) Sample nodes in the Hong Kong area
SELECT node_id, lon, lat
FROM nodes_hong_kong
ORDER BY node_id
LIMIT 10;

-- 6) Nearest node to a point (approx. Victoria Harbour)
SELECT
    node_id,
    lon,
    lat,
    ST_Distance(
        geom::geography,
        ST_SetSRID(ST_MakePoint(114.17, 22.30), 4326)::geography
    ) AS dist_m
FROM nodes
ORDER BY geom <-> ST_SetSRID(ST_MakePoint(114.17, 22.30), 4326)
LIMIT 5;

-- 7) Mesh triangles that touch the Hong Kong bbox
SELECT COUNT(*) AS hk_faces
FROM mesh_faces
WHERE geom && ST_MakeEnvelope(
    113.650220, 22.030046,
    114.659994, 22.699814,
    4326
);
