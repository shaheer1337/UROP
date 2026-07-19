# Benchmark: finding target node IDs by area range

**Goal (supervisor):** given a geographic range (especially near Hong Kong), return target `node_id`s efficiently — and understand **tabular lon/lat** vs **PostGIS geometry** for the same query.

**Dataset under test:** mesh nodes from `node_infos.mat` only (no HS/TP/ELEV time series yet).

---

## 1. What we are managing

After the pipeline in [`PIPELINE.md`](PIPELINE.md), each mesh vertex lives in PostgreSQL/PostGIS as:

| Column | Type | Role |
|--------|------|------|
| `node_id` | `integer` | Stable ID (1 … 15,523), used later to join hindcast values |
| `lon` | `double precision` | Longitude (°E) — **tabular** coordinate |
| `lat` | `double precision` | Latitude (°N) — **tabular** coordinate |
| `geom` | `geometry(Point, 4326)` | Same location as a **PostGIS** point (WGS 84) |

**Attached features / indexes**

| Feature | Purpose |
|---------|---------|
| Primary key on `node_id` | Fast lookup by ID |
| GIST index `nodes_geom_gix` | Spatial queries on `geom` |
| B-tree index `nodes_lon_lat_idx` | Tabular range filters on `(lon, lat)` |
| View `nodes_hong_kong` | Named subset for the supervisor HK bbox |
| QGIS PostGIS connection | Visualise the same rows on a map |

So we are **not** choosing only one storage style: we keep **both** tabular columns and PostGIS geometry on the same table, which lets us compare them fairly.

---

## 2. Tabular vs PostGIS — what is the difference?

### Tabular way (two columns)

Location = two ordinary numbers per row.

```sql
SELECT node_id FROM nodes
WHERE lon BETWEEN 113.650220 AND 114.659994
  AND lat BETWEEN 22.030046 AND 22.699814;
```

- Mental model: spreadsheet / CSV with Lon and Lat.
- Query = filter numeric ranges (`BETWEEN`).
- Index = B-tree on `(lon, lat)` (optional but helpful).
- Excellent for **axis-aligned rectangles** (exactly the supervisor HK box).

### PostGIS way (geometry)

Location = one spatial object (still lon/lat underneath, plus CRS).

```sql
SELECT node_id FROM nodes
WHERE geom && ST_MakeEnvelope(
  113.650220, 22.030046,
  114.659994, 22.699814,
  4326
);
```

- Mental model: GIS layer of points.
- Query = spatial operators (`&&`, `ST_Intersects`, `ST_DWithin`, …).
- Index = GIST on `geom`.
- Needed for **distance, buffers, polygons, nearest neighbour**, and clean QGIS rendering — not only rectangles.

### Side-by-side

| | Tabular `lon` / `lat` | PostGIS `geom` |
|--|----------------------|----------------|
| Storage | Two floats | One `geometry(Point, 4326)` |
| Typical range query | `BETWEEN` on both columns | `&&` / `ST_Intersects` with envelope or polygon |
| Index | B-tree | GIST |
| Best for | Simple rectangles | Rectangles **and** real GIS operations |
| QGIS | Can plot from lon/lat, but awkward | Native spatial layer |

**They answer the same question for a rectangle** (“which node IDs fall in this box?”). PostGIS adds a proper spatial type so the database and QGIS speak GIS natively.

---

## 3. Why query times are so low

Even before comparing methods, absolute times are tiny. Reasons:

1. **Small table** — only **15,523** nodes (~1.3 MB heap, ~2.9 MB with indexes). The whole table fits in memory.
2. **No heavy payloads** — we are not reading HS/TP arrays yet; each row is just IDs + coordinates.
3. **Simple predicate** — a bbox filter is cheap compared to joins across hundreds of GB of hindcast values.
4. **Warm cache** — repeated runs hit shared buffers; first-touch cold starts are slightly slower but still milliseconds.

So: **working only with `node_infos` is not time-consuming.** Cost will rise later when we attach large time-series variables; the strategy then is still “get `node_id`s from the area first, then fetch values for those IDs only.”

---

## 4. Ranges tested (small → large)

| ID | Lon range (°E) | Lat range (°N) | Meaning |
|----|----------------|----------------|---------|
| A | 114.10–114.25 | 22.25–22.35 | Tiny (harbour-scale) |
| B | 113.90–114.40 | 22.15–22.50 | Small (inner HK) |
| C | 113.650220–114.659994 | 22.030046–22.699814 | **Supervisor Hong Kong bbox** |
| D | 112.5–115.5 | 21.5–23.5 | Medium (GBA / Pearl River) |
| E | 110–120 | 18–26 | Large northern SCS coastal band |
| F | — | — | Full mesh (all nodes) |

---

## 5. Timing method

- Database: Docker `postgis/postgis:16-3.4`, DB `hindcast`
- Metric: server-side wall time via `clock_timestamp()` around `SELECT COUNT(*)` of matching rows  
  (counts force the filter to run; avoids shipping large ID lists to the client)
- Repeats: **50** per (range × method); report **median**
- Scripts: `sql/04_benchmark_range_queries.sql`, `sql/05_tabular_vs_postgis.sql`

Methods compared on each bbox:

1. **`tabular_lon_lat`** — `lon`/`lat` `BETWEEN`
2. **`postgis_bbox`** — `geom && ST_MakeEnvelope(...)`
3. **`postgis_intersects`** — `ST_Intersects(geom, ST_MakeEnvelope(...))`

---

## 6. Results

### 6.1 Node counts returned

| Range | Nodes (tabular) | Notes |
|-------|----------------:|-------|
| A tiny | 159 | |
| B small | 2,585 | |
| C supervisor HK | **7,362** | Target demo box |
| D medium GBA | 10,942 | |
| E large coastal | 12,504 | |
| F full mesh | 15,523 | |

(`postgis_bbox` may differ by 1–2 nodes on boundaries due to float/envelope edge handling; `ST_Intersects` matches tabular counts on these tests.)

### 6.2 Median time — tabular vs PostGIS (50 runs)

| Range | Nodes | Tabular `lon`/`lat` | PostGIS `&&` bbox | PostGIS `ST_Intersects` | PostGIS bbox ÷ tabular |
|-------|------:|--------------------:|------------------:|------------------------:|-----------------------:|
| A tiny | 159 | **0.24 ms** | **0.18 ms** | 0.35 ms | 0.8× (PostGIS slightly faster) |
| B small | 2,585 | **0.81 ms** | **0.61 ms** | 0.94 ms | 0.8× |
| **C supervisor HK** | **7,362** | **0.56 ms** | **1.64 ms** | **2.84 ms** | **~3×** |
| D medium | 10,942 | **0.78 ms** | **1.72 ms** | 5.62 ms | ~2.2× |
| E large | 12,504 | **0.80 ms** | **1.55 ms** | 6.15 ms | ~1.9× |
| F full mesh | 15,523 | **0.34 ms** (full scan) | — | — | — |

### 6.3 What the numbers say

- **All methods are fast** on this node table: typically **&lt; 1 ms** tabular, **&lt; 3 ms** PostGIS bbox for the HK box, **&lt; 7 ms** even for `ST_Intersects` on large boxes.
- For **small** boxes, PostGIS bbox can be **similar or slightly faster** than tabular.
- For the **supervisor HK box and larger ranges**, **tabular `BETWEEN` is faster** (about **2–3×** vs `&&`, more vs `ST_Intersects`), because:
  - comparing two floats is cheaper than geometry operators;
  - with only 15k rows, a simple scan/filter wins often;
  - `ST_Intersects` does more work than a pure bbox overlap test.
- **Larger ranges return more IDs but barely change tabular time** — cost is dominated by “touch the small table,” not by box size.

---

## 7. Difference *right now* (practical)

| Question | Right now |
|----------|-----------|
| Can we find HK node IDs? | Yes — both styles |
| Which is faster for the supervisor rectangle? | **Tabular** (~0.56 ms vs ~1.6 ms PostGIS bbox) |
| Is the gap important to users? | **No** — both are sub‑3 ms |
| Do we need PostGIS anyway? | **Yes** — QGIS visualisation, spatial index API, future distance/polygon queries, consistent GIS stack |
| Is node-only work a bottleneck? | **No** |

---

## 8. What we prefer **right now**

**Prefer a hybrid — keep both; use each where it fits.**

| Use case | Preference |
|----------|------------|
| Supervisor “range → list of `node_id`s” (axis-aligned box) | **Tabular** `lon`/`lat` `BETWEEN` (or view `nodes_hong_kong`) — simplest and currently fastest |
| Map visualisation in QGIS | **PostGIS** `geom` layer |
| Distance / nearest / arbitrary polygon | **PostGIS** only |
| Long-term design for hindcast + spatial queries | **Keep `geom` + GIST**; keep `lon`/`lat` for clear tabular access and fast bbox filters |

**Recommendation to report:**

> We store nodes in a tabular way (`node_id`, `lon`, `lat`) **and** as PostGIS points (`geom`). For the same Hong Kong bounding-box query, both return the target node IDs in well under a few milliseconds; tabular filtering is slightly faster on this small table, while PostGIS is what enables QGIS visualisation and richer spatial queries. For efficiency today, resolve `node_id`s with a lon/lat (or PostGIS) bbox first; later restrict large HS/TP reads to those IDs.

---

## 9. Example queries to demo

**Tabular (preferred for simple HK box):**

```sql
SELECT node_id
FROM nodes
WHERE lon BETWEEN 113.650220 AND 114.659994
  AND lat BETWEEN 22.030046 AND 22.699814;
```

**PostGIS:**

```sql
SELECT node_id
FROM nodes
WHERE geom && ST_MakeEnvelope(
  113.650220, 22.030046,
  114.659994, 22.699814,
  4326
);
```

**Named HK subset:**

```sql
SELECT node_id FROM nodes_hong_kong;
```

---

## 10. Re-run benchmarks

```bash
docker compose up -d
docker exec -i urop1000-postgis psql -U hindcast -d hindcast < sql/04_benchmark_range_queries.sql
docker exec -i urop1000-postgis psql -U hindcast -d hindcast < sql/05_tabular_vs_postgis.sql
```

---

## 11. Next performance frontier

Node lookup is solved. Future time consumption will come from **large hindcast arrays** (HS, TP, …). The efficient pattern remains:

1. Query range → get `node_id` list (tabular or PostGIS) — **milliseconds**  
2. Fetch variable values only for those IDs (and selected times) — **this** will dominate runtime once those tables exist
