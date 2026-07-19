-- Hong Kong study-area subset (supervisor-defined bbox).
-- Lon: 113.650220 E – 114.659994 E
-- Lat: 22.030046 N – 22.699814 N

CREATE OR REPLACE VIEW nodes_hong_kong AS
SELECT
    node_id,
    lon,
    lat,
    geom
FROM nodes
WHERE lon BETWEEN 113.650220 AND 114.659994
  AND lat BETWEEN 22.030046 AND 22.699814;

COMMENT ON VIEW nodes_hong_kong IS
    'Mesh nodes inside the Hong Kong bounding box (supervisor filter).';
