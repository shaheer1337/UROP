# UROP1000 — PostGIS mesh nodes

Manage PolyU SCS hindcast **nodes** in PostGIS; visualise in QGIS; query by lon/lat range.

| Doc | Contents |
|-----|----------|
| [PIPELINE.md](PIPELINE.md) | `.mat` → Parquet → Docker PostGIS → QGIS |
| [BENCHMARK.md](BENCHMARK.md) | Timing + tabular vs PostGIS |

```bash
pip install -r requirements.txt
docker compose up -d
# put node_infos.mat + TIME.mat in data/ (not in git)
python3 scripts/mat_to_parquet.py
python3 scripts/load_postgis.py
```

`data/` and `processed/` are gitignored.
