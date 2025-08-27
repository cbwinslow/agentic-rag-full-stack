"""Simple vector-based semantic search using TF-IDF."""
from __future__ import annotations

from dataclasses import dataclass
from typing import List, Tuple

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity


@dataclass
class SemanticSearch:
    """In-memory semantic search index."""

    documents: List[str]

    def __post_init__(self) -> None:
        self.vectorizer = TfidfVectorizer()
        self.matrix = self.vectorizer.fit_transform(self.documents)

    def query(self, text: str, top_k: int = 5) -> List[Tuple[int, float]]:
        """Return indices and similarity scores for top_k matching documents."""
        q = self.vectorizer.transform([text])
        sims = cosine_similarity(q, self.matrix).flatten()
        ranked = sorted(enumerate(sims), key=lambda x: x[1], reverse=True)
        return ranked[:top_k]
