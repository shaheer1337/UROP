#!/usr/bin/env python3
"""Load processed Parquet files into local PostGIS."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
PROCESSED = ROOT / "processed"


def psql(sql: str) -> None:
    cmd = [
        "docker",
        "exec",
        "-i",
        "urop1000-postgis",
        "psql",
        "-U",
        "hindcast",
        "-d",
        "hindcast",
        "-v",
        "ON_ERROR_STOP=1",
    ]
    proc = subprocess.run(cmd, input=sql, text=True, capture_output=True)
    if proc.returncode != 0:
        print(proc.stdout)
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(proc.returncode)
    if proc.stdout.strip():
        print(proc.stdout)


def copy_csv(table: str, columns: list[str], df: pd.DataFrame) -> None:
    cols = ", ".join(columns)
    copy_sql = f"COPY {table} ({cols}) FROM STDIN WITH (FORMAT csv, HEADER true);"
    cmd = [
        "docker",
        "exec",
        "-i",
        "urop1000-postgis",
        "psql",
        "-U",
        "hindcast",
        "-d",
        "hindcast",
        "-v",
        "ON_ERROR_STOP=1",
        "-c",
        copy_sql,
    ]
    proc = subprocess.run(cmd, input=df.to_csv(index=False), text=True, capture_output=True)
    if proc.returncode != 0:
        print(proc.stdout)
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(proc.returncode)
    print(f"Loaded {len(df)} rows into {table}")


def main() -> None:
    psql((ROOT / "sql" / "01_schema.sql").read_text())
    psql("TRUNCATE mesh_faces, nodes, times RESTART IDENTITY CASCADE;")

    nodes = pd.read_parquet(PROCESSED / "nodes.parquet")
    psql(
        """
        DROP TABLE IF EXISTS nodes_staging;
        CREATE UNLOGGED TABLE nodes_staging (
            node_id integer,
            lon double precision,
            lat double precision
        );
        """
    )
    copy_csv("nodes_staging", ["node_id", "lon", "lat"], nodes)
    psql(
        """
        INSERT INTO nodes (node_id, lon, lat, geom)
        SELECT
            node_id,
            lon,
            lat,
            ST_SetSRID(ST_MakePoint(lon, lat), 4326)
        FROM nodes_staging
        ORDER BY node_id;
        DROP TABLE nodes_staging;
        """
    )

    faces = pd.read_parquet(PROCESSED / "mesh_faces.parquet")
    psql(
        """
        DROP TABLE IF EXISTS faces_staging;
        CREATE UNLOGGED TABLE faces_staging (
            face_id integer,
            node_a integer,
            node_b integer,
            node_c integer
        );
        """
    )
    copy_csv("faces_staging", ["face_id", "node_a", "node_b", "node_c"], faces)
    psql(
        """
        INSERT INTO mesh_faces (face_id, node_a, node_b, node_c, geom)
        SELECT
            f.face_id,
            f.node_a,
            f.node_b,
            f.node_c,
            ST_SetSRID(
                ST_MakePolygon(
                    ST_MakeLine(ARRAY[a.geom, b.geom, c.geom, a.geom])
                ),
                4326
            )
        FROM faces_staging f
        JOIN nodes a ON a.node_id = f.node_a
        JOIN nodes b ON b.node_id = f.node_b
        JOIN nodes c ON c.node_id = f.node_c
        ORDER BY f.face_id;
        DROP TABLE faces_staging;
        """
    )

    times = pd.read_parquet(PROCESSED / "times.parquet").copy()
    times["time_utc"] = (
        pd.to_datetime(times["time_utc"], utc=True)
        .dt.strftime("%Y-%m-%d %H:%M:%S+00")
    )
    copy_csv("times", ["time_id", "time_utc"], times[["time_id", "time_utc"]])

    psql((ROOT / "sql" / "02_hong_kong_view.sql").read_text())

    psql(
        """
        SELECT 'nodes' AS tbl, COUNT(*) AS n FROM nodes
        UNION ALL SELECT 'mesh_faces', COUNT(*) FROM mesh_faces
        UNION ALL SELECT 'times', COUNT(*) FROM times
        UNION ALL SELECT 'nodes_hong_kong', COUNT(*) FROM nodes_hong_kong;
        """
    )
    print(
        "Done. QGIS → PostGIS: host=localhost port=5432 database=hindcast "
        "user=hindcast password=hindcast"
    )


if __name__ == "__main__":
    main()
