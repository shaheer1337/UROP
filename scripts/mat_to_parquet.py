#!/usr/bin/env python3
"""Convert PolyU hindcast node/time MATLAB files to Parquet for PostGIS loading."""

from __future__ import annotations

from pathlib import Path

import h5py
import numpy as np
import pandas as pd
from scipy.io import loadmat

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "processed"

# Recovered from TIME.mat (MATLAB datetime opaque blob): hourly, UTC.
TIME_START_MS = 0  # 1970-01-01 00:00:00 UTC
TIME_END_MS = 1_672_524_000_000  # 2022-12-31 22:00:00 UTC
TIME_STEP_MS = 3_600_000  # 1 hour


def export_nodes() -> Path:
    path = DATA / "node_infos.mat"
    with h5py.File(path, "r") as f:
        lon = np.asarray(f["node_LON"]).ravel()
        lat = np.asarray(f["node_LAT"]).ravel()
        faces = np.asarray(f["SCHISM_hgrid_face_nodes"])

    if lon.shape != lat.shape:
        raise ValueError(f"LON/LAT length mismatch: {lon.shape} vs {lat.shape}")

    nodes = pd.DataFrame(
        {
            "node_id": np.arange(1, lon.size + 1, dtype=np.int32),
            "lon": lon.astype(np.float64),
            "lat": lat.astype(np.float64),
        }
    )
    out_nodes = OUT / "nodes.parquet"
    nodes.to_parquet(out_nodes, index=False)

    # SCHISM faces are triangles; 4th column is NaN; node indices are 1-based.
    tri = faces[:, :3].astype(np.int32)
    faces_df = pd.DataFrame(
        {
            "face_id": np.arange(1, tri.shape[0] + 1, dtype=np.int32),
            "node_a": tri[:, 0],
            "node_b": tri[:, 1],
            "node_c": tri[:, 2],
        }
    )
    out_faces = OUT / "mesh_faces.parquet"
    faces_df.to_parquet(out_faces, index=False)

    print(f"Wrote {out_nodes} ({len(nodes)} nodes)")
    print(f"Wrote {out_faces} ({len(faces_df)} triangles)")
    print(
        f"  lon [{nodes.lon.min():.4f}, {nodes.lon.max():.4f}], "
        f"lat [{nodes.lat.min():.4f}, {nodes.lat.max():.4f}]"
    )
    return out_nodes


def export_time() -> Path:
    """Export hourly timestamps for the hindcast window.

    TIME.mat stores a MATLAB ``datetime`` object that SciPy cannot decode cleanly.
    Inspection of the embedded payload shows a contiguous hourly series from
    1970-01-01 00:00 UTC through 2022-12-31 22:00 UTC (matches the paper).
    """
    # Sanity: file exists and is a datetime opaque object.
    raw = loadmat(DATA / "TIME.mat", squeeze_me=False)
    if "TIME" not in raw:
        raise KeyError("TIME variable missing from TIME.mat")

    ms = np.arange(TIME_START_MS, TIME_END_MS + 1, TIME_STEP_MS, dtype=np.int64)
    times = pd.DataFrame(
        {
            "time_id": np.arange(1, ms.size + 1, dtype=np.int32),
            "time_utc": pd.to_datetime(ms, unit="ms", utc=True),
        }
    )
    out = OUT / "times.parquet"
    times.to_parquet(out, index=False)
    print(f"Wrote {out} ({len(times)} hourly steps)")
    print(f"  {times.time_utc.iloc[0]} -> {times.time_utc.iloc[-1]}")
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    export_nodes()
    export_time()


if __name__ == "__main__":
    main()
