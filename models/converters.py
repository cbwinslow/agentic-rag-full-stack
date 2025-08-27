from __future__ import annotations
from typing import Any, Dict
from .schemas import Document, Chunk, Entity, Relation, Section, Action, Vote


def row_to_model(model_class, row: Dict[str, Any]):
    """Generic helper: create a Pydantic model instance from a DB row dict.

    It will ignore extra keys by default and perform basic conversions.
    """
    # Pydantic BaseModel can accept dicts; for nested or aliased fields, more logic
    # can be added here.
    return model_class.model_validate(row)


def document_from_row(row: Dict[str, Any]) -> Document:
    return row_to_model(Document, row)


def chunk_from_row(row: Dict[str, Any]) -> Chunk:
    return row_to_model(Chunk, row)


def entity_from_row(row: Dict[str, Any]) -> Entity:
    return row_to_model(Entity, row)


def relation_from_row(row: Dict[str, Any]) -> Relation:
    return row_to_model(Relation, row)


def section_from_row(row: Dict[str, Any]) -> Section:
    return row_to_model(Section, row)


def action_from_row(row: Dict[str, Any]) -> Action:
    return row_to_model(Action, row)


def vote_from_row(row: Dict[str, Any]) -> Vote:
    return row_to_model(Vote, row)
