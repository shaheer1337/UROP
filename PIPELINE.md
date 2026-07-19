# Pipeline: nodes into PostGIS

## What we did

1. Read `node_infos.mat` / `TIME.mat` (SharePoint; kept local under `data/`).
2. Convert to Parquet (`scripts/mat_to_parquet.py` → `processed/`).
3. Run PostGIS in Docker (`docker compose up -d`).
4. Load into DB (`scripts/load_postgis.py`).
5. Visualise / filter in QGIS via PostGIS connection.

## Data loaded

| Table | Rows | Notes |
|-------|-----:|-------|
| `nodes` | 15,523 | `node_id`, `lon`, `lat`, `geom` (EPSG:4326) |
| `mesh_faces` | 29,039 | triangles |
| `times` | 464,591 | hourly UTC, 1970–2022 |

Indexes: GIST on `geom`, B-tree on `(lon, lat)`.

## Run

```bash
docker compose up -d
python3 scripts/mat_to_parquet.py
python3 scripts/load_postgis.py
```

**QGIS:** Layer → Add PostGIS Layer → `localhost:5432`, db/user/password `hindcast`. Add `nodes`.

## Example area query (HK bbox)

```sql
SELECT node_id FROM nodes
WHERE lon BETWEEN 113.650220 AND 114.659994
  AND lat BETWEEN 22.030046 AND 22.699814;
-- → 7362 nodes
```

Same idea with PostGIS: `geom && ST_MakeEnvelope(...)`. See `sql/03_example_queries.sql`.

## Status

Done: nodes in PostGIS, range queries, QGIS map.  
Not yet: HS/TP/… hindcast fields (~90 GB).
