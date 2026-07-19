# PolyU Wave Hindcast — Spatial Node Pipeline (PostGIS + QGIS)

**Project:** UROP1000 — manage SCHISM/WWMIII hindcast mesh nodes with PostGIS; visualise in QGIS  
**Domain:** South China Sea unstructured mesh (paper: *A two-way coupled wave–current high resolution hindcast for the South China Sea*)  
**CRS:** WGS 84 / **EPSG:4326**

This note documents the workflow from SharePoint `.mat` files through Parquet, Dockerised PostgreSQL/PostGIS, spatial queries, and QGIS visualisation.

---

## 1. Goal (supervisor requirements)

| Requirement | How it is met |
|-------------|----------------|
| Manage nodes with PostGIS | Table `nodes` with `geometry(Point, 4326)` + GIST index |
| Support area-range queries | SQL bbox / `ST_MakeEnvelope` (e.g. Hong Kong) |
| Use QGIS with PostGIS for visualisation | QGIS PostGIS connection → map layers |

---

## 2. Source data (SharePoint → local)

From folder **PolyU_Hindcast** (~93 GB total). For the **node** pipeline we only need:

| File | Role |
|------|------|
| `node_infos.mat` | Node lon/lat + triangle connectivity |
| `TIME.mat` | Hindcast time axis (hourly, 1970–2022) |
| `metadata.txt` | Variable names (HS, TP, DM, ELEV) |
| `paper_document_for_data.pdf` | Scientific context / mesh description |

Large fields (`HS_*.mat`, `TP_*.mat`, …) are **not** ingested yet; they come after the node/query demo.

Placed under: `data/`

---

## 3. What is inside `node_infos.mat`

MATLAB v7.3 (HDF5):

| Variable | Shape | Meaning |
|----------|-------|---------|
| `node_LON` | 15,523 | Longitude (°E) |
| `node_LAT` | 15,523 | Latitude (°N) |
| `SCHISM_hgrid_face_nodes` | 29,039 × 4 | Triangle corners (1-based node ids; 4th column unused/NaN) |

Matches the paper mesh (~15,523 nodes, ~29,039 elements). Lon ≈ 105.7–122.8°E, lat ≈ 3.1–27.8°N.

---

## 4. Pipeline overview

```text
SharePoint .mat
      │
      ▼
scripts/mat_to_parquet.py          ← read .mat (h5py / scipy)
      │
      ▼
processed/*.parquet                ← nodes, mesh_faces, times
      │
      ▼
Docker: postgis/postgis:16-3.4     ← docker compose up -d
      │
      ▼
scripts/load_postgis.py            ← COPY + ST_MakePoint / polygons
      │
      ▼
PostgreSQL tables + PostGIS geom
      │
      ├── SQL area queries (proof)
      └── QGIS PostGIS layers (visualisation)
```

---

## 5. Step-by-step reproduction

### 5.1 Environment

- Docker + Docker Compose  
- Python 3 with packages in `requirements.txt` (`h5py`, `scipy`, `pandas`, `pyarrow`, `numpy`)

```bash
cd ~/Documents/UROP1000
pip install -r requirements.txt
```

### 5.2 Convert `.mat` → Parquet

```bash
python3 scripts/mat_to_parquet.py
```

**Outputs** (`processed/`):

| File | Rows | Contents |
|------|------|----------|
| `nodes.parquet` | 15,523 | `node_id`, `lon`, `lat` |
| `mesh_faces.parquet` | 29,039 | `face_id`, `node_a/b/c` |
| `times.parquet` | 464,591 | `time_id`, `time_utc` (hourly UTC, 1970-01-01 → 2022-12-31 22:00) |

**Note on `TIME.mat`:** it stores a MATLAB `datetime` object that SciPy cannot decode as a plain array. The export reconstructs the contiguous hourly series confirmed from the embedded payload and the paper’s 1970–2022 window.

### 5.3 Start PostgreSQL + PostGIS (Docker)

```bash
docker compose up -d
```

| Setting | Value |
|---------|--------|
| Image | `postgis/postgis:16-3.4` |
| Container | `urop1000-postgis` |
| Host port | `5432` |
| Database | `hindcast` |
| User / password | `hindcast` / `hindcast` |
| Data volume | `urop1000_postgis_data` (persists across restarts) |

Check:

```bash
docker ps --filter name=urop1000-postgis
docker exec urop1000-postgis pg_isready -U hindcast -d hindcast
```

Stop without deleting data: `docker compose stop`  
Remove container (volume kept): `docker compose down`  
**Do not** run `down` while using QGIS unless you intend to stop the DB.

### 5.4 Create schema and load data

```bash
python3 scripts/load_postgis.py
```

This applies `sql/01_schema.sql`, loads Parquet into PostGIS, and creates `nodes_hong_kong` (`sql/02_hong_kong_view.sql`).

**Tables**

| Table | Geometry | Index |
|-------|----------|--------|
| `nodes` | `Point`, EPSG:4326 | GIST on `geom` |
| `mesh_faces` | `Polygon` (triangles) | GIST on `geom` |
| `times` | — | btree on `time_utc` |

**View**

| View | Definition |
|------|------------|
| `nodes_hong_kong` | Nodes inside the supervisor Hong Kong bbox |

Loading steps inside `load_postgis.py`:

1. `CREATE EXTENSION postgis` + tables (`sql/01_schema.sql`)
2. Stage `nodes` from Parquet → `INSERT … ST_SetSRID(ST_MakePoint(lon, lat), 4326)`
3. Stage faces → build triangle polygons from node geometries
4. Load `times`

---

## 6. Proof: PostGIS area-range query (Hong Kong)

Supervisor bbox:

- Longitude: **113.650220°E – 114.659994°E**  
- Latitude: **22.030046°N – 22.699814°N**

```sql
SELECT COUNT(*) AS hk_nodes
FROM nodes
WHERE geom && ST_MakeEnvelope(
    113.650220, 22.030046,
    114.659994, 22.699814,
    4326
);
```

**Result:** **7,362** nodes (of 15,523 in the full SCS mesh).

Equivalent named object (same lon/lat bounds):

```sql
SELECT COUNT(*) FROM nodes_hong_kong;  -- 7362
```

More examples: `sql/03_example_queries.sql`.

Run from the project root:

```bash
docker exec -i urop1000-postgis psql -U hindcast -d hindcast < sql/03_example_queries.sql
```

---

## 7. QGIS visualisation (connects to PostGIS)

QGIS does not replace PostGIS; it **connects** to the same database to draw layers.

1. Ensure Docker is running: `docker compose up -d`
2. QGIS → **Layer → Add Layer → Add PostGIS Layers…**
3. New connection:

| Field | Value |
|-------|--------|
| Name | `hindcast` |
| Host | `localhost` |
| Port | `5432` |
| Database | `hindcast` |
| User | `hindcast` |
| Password | `hindcast` |

4. **Test Connection** → Connect  
5. Add layers: `nodes`, `mesh_faces`, and/or `nodes_hong_kong`  
6. Project CRS: **EPSG:4326**  
7. Right-click layer → **Zoom to Layer** if the map pans away from the SCS / HK extent  

**Demonstration for supervisor**

1. Load full `nodes` → zoom to layer → entire SCS mesh  
2. Load `nodes_hong_kong` (or filter `nodes` with the bbox) → Hong Kong waters only; land shows as gaps (Lantau, HK Island, etc.)  
3. Optionally show the same subset via **DB Manager → SQL Window** using the queries above  

Save the QGIS project (e.g. `hindcast.qgz`) so the connection is retained.

---

## 8. Repository layout

```text
UROP1000/
├── data/                     # source .mat + metadata + paper
├── processed/                # Parquet intermediates
├── scripts/
│   ├── mat_to_parquet.py     # .mat → Parquet
│   └── load_postgis.py       # Parquet → PostGIS
├── sql/
│   ├── 01_schema.sql
│   ├── 02_hong_kong_view.sql
│   └── 03_example_queries.sql
├── docker-compose.yml
├── requirements.txt
└── PIPELINE.md               # this document
```

---

## 9. Status vs next work

| Item | Status |
|------|--------|
| Node + mesh ingest to PostGIS | Done |
| Docker orchestration | Done |
| Area query (Hong Kong bbox) | Done |
| QGIS ↔ PostGIS visualisation | Done |
| Ingest HS / TP / DM / ELEV time series | **Not started** (large `.mat` files) |

**Suggested next step after this demo:** download one field (e.g. `HS_merged_hindcast_holland.mat`), inspect array shape, load a **time/region subset** keyed by `node_id` + `time_id`, then query e.g. significant wave height inside the Hong Kong bbox for a chosen period.

Timing of node-ID range queries (small → large boxes): see [`BENCHMARK.md`](BENCHMARK.md).

---

## 10. Quick command cheat sheet

```bash
# Start DB
docker compose up -d

# Rebuild Parquet + reload DB (includes Hong Kong view)
python3 scripts/mat_to_parquet.py
python3 scripts/load_postgis.py

# Demo queries
docker exec -i urop1000-postgis psql -U hindcast -d hindcast < sql/03_example_queries.sql

# Stop DB (keep data)
docker compose stop
```
