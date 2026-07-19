# Benchmark: tabular vs PostGIS range queries

Goal: return `node_id`s for a lon/lat box efficiently. Only the **nodes** table (~15k rows, ~3 MB) — no HS/TP yet.

## Tabular vs PostGIS

| | Tabular | PostGIS |
|--|---------|---------|
| Storage | `lon`, `lat` columns | `geom` point (EPSG:4326) |
| Query | `WHERE lon BETWEEN … AND lat BETWEEN …` | `WHERE geom && ST_MakeEnvelope(...)` |
| Best for | Simple rectangles | Rectangles + distance, polygons, QGIS |

We keep **both** on `nodes`.

## Why times are low

Tiny table (15,523 points). All range lookups finish in milliseconds. Cost grows later when joining large hindcast values — then filter `node_id`s first.

## Ranges (small → large)

| Range | Nodes | Tabular (median) | PostGIS `&&` (median) |
|-------|------:|-----------------:|----------------------:|
| Tiny harbour | 159 | 0.24 ms | 0.18 ms |
| Small inner HK | 2,585 | 0.81 ms | 0.61 ms |
| Supervisor HK box | **7,362** | **0.56 ms** | **1.64 ms** |
| Medium GBA | 10,942 | 0.78 ms | 1.72 ms |
| Large coastal | 12,504 | 0.80 ms | 1.55 ms |
| Full mesh | 15,523 | 0.34 ms | — |

50 runs each; script: `sql/05_tabular_vs_postgis.sql`.

## Preference right now

- **Simple bbox → node IDs:** tabular `lon`/`lat` (slightly faster here).
- **Maps / richer spatial ops:** PostGIS `geom`.
- Gap is ~2–3× on the HK box but still &lt; 2 ms — not a bottleneck.

```sql
-- preferred for axis-aligned boxes today
SELECT node_id FROM nodes
WHERE lon BETWEEN 113.650220 AND 114.659994
  AND lat BETWEEN 22.030046 AND 22.699814;
```
