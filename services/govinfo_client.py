"""Minimal GovInfo API client with scheduled updates."""
from __future__ import annotations

import os
from typing import Any, Dict

import requests
import schedule

API_BASE = "https://api.govinfo.gov"  # Public endpoint
API_KEY = os.getenv("GOVINFO_API_KEY", "DEMO_KEY")


def fetch_document(collection: str, doc_id: str) -> Dict[str, Any]:
    url = f"{API_BASE}/{collection}/{doc_id}?api_key={API_KEY}"
    resp = requests.get(url, timeout=10)
    resp.raise_for_status()
    return resp.json()


def schedule_update(collection: str, doc_id: str, interval_minutes: int = 60):
    schedule.every(interval_minutes).minutes.do(fetch_document, collection, doc_id)
