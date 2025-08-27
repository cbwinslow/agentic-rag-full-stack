"""Simple analytics tracking and visualization."""
from __future__ import annotations

from collections import Counter
from typing import Dict

import matplotlib.pyplot as plt


class Analytics:
    def __init__(self) -> None:
        self.counter = Counter()

    def track(self, event: str) -> None:
        self.counter[event] += 1

    def report(self) -> Dict[str, int]:
        return dict(self.counter)

    def plot(self, path: str) -> None:
        events = list(self.counter.keys())
        counts = [self.counter[e] for e in events]
        plt.bar(events, counts)
        plt.savefig(path)
        plt.close()
