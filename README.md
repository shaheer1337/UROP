# PolyU SCS hindcast nodes (PostGIS + QGIS)

Manage SCHISM/WWMIII hindcast **mesh nodes** in PostgreSQL/PostGIS, query by geographic range (e.g. Hong Kong), and visualise in QGIS.

## Documents for review

| Doc | Contents |
|-----|----------|
| [PIPELINE.md](PIPELINE.md) | Full workflow: `.mat` → Parquet → Docker PostGIS → QGIS |
| [BENCHMARK.md](BENCHMARK.md) | Timing + **tabular lon/lat vs PostGIS** comparison |

## Quick start (after cloning)

Source `.mat` files are **not** in this repo (too large / SharePoint). Place them under `data/` locally, then:

```bash
pip install -r requirements.txt
docker compose up -d
python3 scripts/mat_to_parquet.py
python3 scripts/load_postgis.py
```

See `PIPELINE.md` for connection details and example SQL.

## What’s in the repo

- `scripts/` — conversion and DB load
- `sql/` — schema, Hong Kong view, example + benchmark queries
- `docker-compose.yml` — PostGIS 16

## What’s not in the repo

- `data/` — SharePoint `.mat` / PDF sources  
- `processed/` — generated Parquet files
