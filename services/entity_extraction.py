"""Named entity extraction using spaCy."""
from __future__ import annotations

from typing import List, Tuple

import spacy

_nlp = spacy.load("en_core_web_sm")


def extract(text: str) -> List[Tuple[str, str]]:
    doc = _nlp(text)
    return [(ent.text, ent.label_) for ent in doc.ents]
