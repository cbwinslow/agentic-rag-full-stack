"""Retrieval-Augmented Generation stub using semantic search."""
from __future__ import annotations

from typing import List

from .semantic_search import SemanticSearch


class RAG:
    def __init__(self, documents: List[str]):
        self.docs = documents
        self.search = SemanticSearch(documents)

    def ask(self, question: str) -> str:
        best_idx, _score = self.search.query(question, top_k=1)[0]
        context = self.docs[best_idx]
        # Placeholder: In real system, generate answer using LLM with context
        return context
