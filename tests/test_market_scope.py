import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from market_scope import classify_market_scope  # noqa: E402


class MarketScopeTest(unittest.TestCase):
    def test_explicit_us(self):
        self.assertEqual(classify_market_scope("Remote - United States"), "US")
        self.assertEqual(classify_market_scope("Chicago, IL"), "US")
        self.assertEqual(classify_market_scope("Austin / TX"), "US")
        self.assertEqual(classify_market_scope("New York, New York"), "US")

    def test_explicit_non_us(self):
        self.assertEqual(classify_market_scope("Toronto, Canada"), "non-US")
        self.assertEqual(classify_market_scope("London, United Kingdom"), "non-US")

    def test_ambiguous_stays_unknown(self):
        self.assertEqual(classify_market_scope("Remote"), "unknown")
        self.assertEqual(classify_market_scope("London"), "unknown")
        self.assertEqual(classify_market_scope(""), "unknown")


if __name__ == "__main__":
    unittest.main()
