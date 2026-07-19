CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS nodes (
    node_id integer PRIMARY KEY,
    lon double precision NOT NULL,
    lat double precision NOT NULL,
    geom geometry(Point, 4326) NOT NULL
);

CREATE TABLE IF NOT EXISTS mesh_faces (
    face_id integer PRIMARY KEY,
    node_a integer NOT NULL REFERENCES nodes (node_id),
    node_b integer NOT NULL REFERENCES nodes (node_id),
    node_c integer NOT NULL REFERENCES nodes (node_id),
    geom geometry(Polygon, 4326)
);

CREATE TABLE IF NOT EXISTS times (
    time_id integer PRIMARY KEY,
    time_utc timestamptz NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS nodes_geom_gix ON nodes USING GIST (geom);
CREATE INDEX IF NOT EXISTS nodes_lon_lat_idx ON nodes (lon, lat);
CREATE INDEX IF NOT EXISTS mesh_faces_geom_gix ON mesh_faces USING GIST (geom);
CREATE INDEX IF NOT EXISTS times_time_utc_idx ON times (time_utc);
