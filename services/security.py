"""Basic input validation and token auth."""
from __future__ import annotations

import os
from typing import Optional

from fastapi import Depends, HTTPException, Security
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field


class InputModel(BaseModel):
    query: str = Field(..., min_length=1, max_length=1000)


API_TOKEN = os.getenv("API_TOKEN", "secret")
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


def require_token(api_key: Optional[str] = Security(api_key_header)) -> None:
    if api_key != API_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid API Key")
