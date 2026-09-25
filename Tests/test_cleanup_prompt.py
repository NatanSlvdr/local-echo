"""Focused tests for transcript-cleanup instructions and text chunking."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources' / 'ModelRuntime'))
from worker import cleanup_chunks, cleanup_prompt


class CleanupPromptTests(unittest.TestCase):
    def test_defaults_apply_light_formatting(self):
        prompt = cleanup_prompt({})
        self.assertIn('Correct punctuation, capitalization, and spacing.', prompt)
        self.assertIn('Correct only obvious speech-recognition errors', prompt)
        self.assertIn('Keep filler words', prompt)
        self.assertIn('Keep existing paragraph breaks', prompt)
        self.assertIn('do not create lists or headings', prompt)

    def test_no_formatting_still_allows_other_edits(self):
        prompt = cleanup_prompt({
            'formatting_level': 'none',
            'correct_recognition_errors': 'false',
            'remove_fillers': 'true',
        })
        self.assertIn('Keep punctuation, capitalization, line breaks, and layout unchanged', prompt)
        self.assertIn('Do not correct suspected recognition errors', prompt)
        self.assertIn('Remove filler words', prompt)
        self.assertNotIn('Correct only obvious speech-recognition errors', prompt)

    def test_higher_levels_control_layout(self):
        polished = cleanup_prompt({'formatting_level': 'polished'})
        structured = cleanup_prompt({'formatting_level': 'structured'})
        self.assertIn('paragraph breaks at natural topic changes', polished)
        self.assertIn('Do not create lists or headings', polished)
        self.assertIn('Use a short list only when the speaker clearly enumerates', structured)
        self.assertIn('Do not invent items, headings, or content', structured)

    def test_chunks_preserve_whitespace(self):
        transcript = 'Bonjour  tout le monde.\n\nEncore une phrase avec des espaces.  '
        self.assertEqual(''.join(cleanup_chunks(transcript, limit=18)), transcript)


if __name__ == '__main__':
    unittest.main()
