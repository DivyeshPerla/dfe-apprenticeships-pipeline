"""Client for the DfE Explore Education Statistics (EES) public API.

API base: https://api.education.gov.uk/statistics/v1
Docs:     https://dev.statistics.api.education.gov.uk/

Endpoints used (all verified against the live API):
  GET  /data-sets/{id}                      -> dataset summary + latestVersion
  GET  /data-sets/{id}/versions             -> full version history (paged)
  GET  /data-sets/{id}/meta                 -> filters, indicators, locations, timePeriods
  GET  /data-sets/{id}/csv?dataSetVersion=X -> gzipped flat CSV for a given version
  POST /data-sets/{id}/query                -> paged JSON query (paging goes in the BODY)
"""

from __future__ import annotations

import dataclasses
import logging
from typing import Any, Iterator

import requests

log = logging.getLogger(__name__)

BASE_URL = "https://api.education.gov.uk/statistics/v1"

# "Headline Full year - Starts, Achievements, Participation by Level, Levy,
#  Age, Region, Provider type"
APPRENTICESHIPS_DATASET_ID = "1d419801-a90e-f970-9335-a13623faccbe"


@dataclasses.dataclass(frozen=True)
class DataSetVersion:
    """One published version of a data set."""

    version: str
    type: str  # "Major" | "Minor" | "Patch"
    status: str
    published: str
    total_results: int
    time_period_start: str
    time_period_end: str

    @classmethod
    def from_api(cls, payload: dict[str, Any]) -> "DataSetVersion":
        periods = payload.get("timePeriods", {})
        return cls(
            version=payload["version"],
            type=payload.get("type", ""),
            status=payload.get("status", ""),
            published=payload.get("published", ""),
            total_results=payload.get("totalResults", 0),
            time_period_start=periods.get("start", ""),
            time_period_end=periods.get("end", ""),
        )


class DfEStatisticsClient:
    """Thin, retrying wrapper over the EES statistics API."""

    def __init__(
        self,
        dataset_id: str = APPRENTICESHIPS_DATASET_ID,
        base_url: str = BASE_URL,
        timeout: int = 120,
    ) -> None:
        self.dataset_id = dataset_id
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.session = requests.Session()
        # The API gzips large payloads; requests handles decoding transparently.
        self.session.headers.update(
            {
                "Accept-Encoding": "gzip, deflate",
                "User-Agent": "dfe-apprenticeships-pipeline/0.1 (+portfolio ETL)",
            }
        )

    # -- internals ---------------------------------------------------------

    @property
    def _dataset_url(self) -> str:
        return f"{self.base_url}/data-sets/{self.dataset_id}"

    def _get(self, path: str = "", **params: Any) -> requests.Response:
        url = self._dataset_url + path
        log.info("GET %s params=%s", url, params or {})
        resp = self.session.get(url, params=params or None, timeout=self.timeout)
        resp.raise_for_status()
        return resp

    # -- public API --------------------------------------------------------

    def get_summary(self) -> dict[str, Any]:
        """Dataset summary, including `latestVersion`."""
        return self._get().json()

    def get_latest_version(self) -> str:
        """Version string of the most recently published version, e.g. '2.0.2'."""
        return self.get_summary()["latestVersion"]["version"]

    def list_versions(self, page_size: int = 20) -> list[DataSetVersion]:
        """Full published version history, newest first.

        `pageSize` is capped at 20 by the API, so this follows pagination.
        """
        versions: list[DataSetVersion] = []
        page = 1
        while True:
            payload = self._get("/versions", page=page, pageSize=page_size).json()
            versions.extend(DataSetVersion.from_api(v) for v in payload["results"])
            paging = payload.get("paging", {})
            if page >= paging.get("totalPages", 0):
                return versions
            page += 1

    def get_meta(self) -> dict[str, Any]:
        """Filters, indicators, locations and time periods.

        This is the source of truth for building conformed dimension tables:
        the POST /query endpoint returns opaque filter/location IDs that only
        resolve to human labels via this payload.
        """
        return self._get("/meta").json()

    def download_csv(self, dest_path: str, version: str | None = None) -> str:
        """Stream the flat CSV for `version` (default: latest) to `dest_path`."""
        params = {"dataSetVersion": version} if version else {}
        url = f"{self._dataset_url}/csv"
        log.info("Downloading CSV version=%s -> %s", version or "latest", dest_path)
        with self.session.get(
            url, params=params or None, timeout=self.timeout, stream=True
        ) as resp:
            resp.raise_for_status()
            with open(dest_path, "wb") as fh:
                for chunk in resp.iter_content(chunk_size=1 << 20):
                    fh.write(chunk)
        return dest_path

    def query(
        self,
        criteria: dict[str, Any] | None = None,
        indicators: list[str] | None = None,
        page_size: int = 1000,
    ) -> Iterator[dict[str, Any]]:
        """Yield every result row matching `criteria`, following pagination.

        NOTE: `page` / `pageSize` must be sent in the JSON body, not as query
        string parameters -- the API rejects them as unknown fields otherwise.
        """
        url = f"{self._dataset_url}/query"
        page = 1
        while True:
            body: dict[str, Any] = {"page": page, "pageSize": page_size}
            if criteria:
                body["criteria"] = criteria
            if indicators:
                body["indicators"] = indicators

            resp = self.session.post(url, json=body, timeout=self.timeout)
            resp.raise_for_status()
            payload = resp.json()

            yield from payload.get("results", [])

            paging = payload.get("paging", {})
            if page >= paging.get("totalPages", 0):
                return
            page += 1
