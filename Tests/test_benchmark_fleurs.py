"""Checks for the benchmark's word error scoring rules."""

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/benchmark-fleurs.py"
spec = importlib.util.spec_from_file_location("benchmark_fleurs", SCRIPT)
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class BenchmarkScoringTests(unittest.TestCase):
    def test_word_score_ignores_punctuation_and_case(self):
        reference = benchmark.normalized_words("Bonjour, l'été !")
        hypothesis = benchmark.normalized_words("BONJOUR l'été")
        self.assertEqual(0, benchmark.edit_distance(reference, hypothesis))

    def test_word_score_counts_insertions_deletions_and_substitutions(self):
        self.assertEqual(1, benchmark.edit_distance(["a", "b"], ["a", "x", "b"]))
        self.assertEqual(1, benchmark.edit_distance(["a", "b"], ["a"]))
        self.assertEqual(1, benchmark.edit_distance(["a", "b"], ["a", "c"]))

    def test_accents_and_cyrillic_are_preserved(self):
        self.assertEqual(["über", "été"], benchmark.normalized_words("Über, ÉTÉ!"))
        self.assertEqual(["привет", "мир"], benchmark.normalized_words("Привет, мир!"))


if __name__ == "__main__":
    unittest.main()
