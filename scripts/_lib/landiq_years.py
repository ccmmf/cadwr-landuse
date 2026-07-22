"""Discover annual LandIQ shapefiles under a drop directory.

Expected layout (matches CNRA / DWR releases)::

    <landiq-root-dir>/
      i15_Crop_Mapping_2016_SHP/i15_Crop_Mapping_2016.shp
      i15_Crop_Mapping_2023_Provisional_SHP/i15_Crop_Mapping_2023_Provisional.shp
      i15_Crop_Mapping_2024_Provisional_SHP/i15_Crop_Mapping_2024_Provisional.shp
      ...

When both final and provisional folders exist for the same year, the
non-provisional (final) folder wins.
"""

import logging
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

_FOLDER_RE = re.compile(
    r"^i15_Crop_Mapping_(\d{4})(_Provisional)?_SHP$",
    re.IGNORECASE,
)


def discover_landiq_shapefiles(
    landiq_root_dir,
    min_year=2016,
    max_year=None,
):
    # type: (Path, int, Optional[int]) -> Dict[str, Path]
    """Return ``{year_str: path_to_.shp}`` sorted by year.

    Raises ``FileNotFoundError`` if the root is missing or no years match.
    """
    root = Path(landiq_root_dir).expanduser().resolve()
    if not root.is_dir():
        raise FileNotFoundError("LandIQ shapefile root not found: {}".format(root))

    # year -> (prefer_score, path); prefer_score higher = better (final > provisional)
    best = {}  # type: Dict[str, Tuple[int, Path]]

    for folder in sorted(root.iterdir()):
        if not folder.is_dir():
            continue
        m = _FOLDER_RE.match(folder.name)
        if not m:
            continue
        year = m.group(1)
        year_i = int(year)
        if year_i < min_year:
            continue
        if max_year is not None and year_i > max_year:
            continue

        provisional = m.group(2) is not None
        prefer = 0 if provisional else 1

        if folder.name.upper().endswith("_SHP"):
            stem = folder.name[: -len("_SHP")]
        else:
            stem = folder.name
        exact = folder / "{}.shp".format(stem)
        if exact.is_file():
            shp = exact
        else:
            candidates = sorted(folder.glob("*.shp"))
            if not candidates:
                logger.warning("No .shp in %s - skipping", folder)
                continue
            shp = candidates[0]
            logger.warning("Expected %s; using %s", exact.name, shp.name)

        prev = best.get(year)
        if prev is None or prefer > prev[0]:
            best[year] = (prefer, shp)

    if not best:
        raise FileNotFoundError(
            "No i15_Crop_Mapping_*_SHP folders with .shp under {} "
            "(min_year={}, max_year={})".format(root, min_year, max_year)
        )

    files = {
        year: path
        for year, (_, path) in sorted(best.items(), key=lambda kv: int(kv[0]))
    }
    logger.info(
        "Discovered LandIQ years %s under %s",
        ", ".join(files.keys()),
        root,
    )
    for year, path in files.items():
        logger.info("  %s -> %s", year, path)
    return files


def ensure_metadata_year_columns(metadata, years, logger_=logger):
    # type: (object, List[int], logging.Logger) -> object
    """If a year is missing from CARB_Metadata_ref, copy keep-flags from the latest year column."""
    year_cols = [c for c in metadata.columns if str(c).isdigit()]
    if not year_cols:
        raise ValueError("CARB_Metadata_ref.csv has no year columns")
    latest = max(year_cols, key=lambda c: int(c))
    for year in years:
        ycol = str(year)
        if ycol in metadata.columns:
            continue
        logger_.warning(
            "CARB_Metadata_ref.csv has no column for %s; copying keep flags from %s. "
            "Update data/CARB_Metadata_ref.csv if this year's attributes differ.",
            ycol,
            latest,
        )
        metadata[ycol] = metadata[latest]
    return metadata
