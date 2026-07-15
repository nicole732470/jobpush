#!/usr/bin/env python3
import unittest

from crawl_icims import search_url
from crawl_rippling import board_url
from crawl_workday import workday_applied_facets, workday_site_from_path


class AdapterNormalizationTest(unittest.TestCase):
    def test_icims_detail_becomes_search(self):
        self.assertEqual(search_url("https://careers-example.icims.com/jobs/123/role/login?foo=1"),
                         "https://careers-example.icims.com/jobs/search")

    def test_icims_legacy_becomes_search(self):
        self.assertEqual(search_url("https://example.icims.com/icims2/servlet/icims2"),
                         "https://example.icims.com/jobs/search")

    def test_rippling_embed_becomes_board(self):
        self.assertEqual(board_url("https://ats.rippling.com/acme/embed/jobs/abc"),
                         "https://ats.rippling.com/acme/jobs")

    def test_workday_locale_and_detail(self):
        self.assertEqual(workday_site_from_path("/en-US/acme/job/Chicago/R-1"), "acme")

    def test_tjx_uses_corporate_source_filter(self):
        facets = workday_applied_facets("tjx", "TJX_EXTERNAL")
        self.assertEqual(len(facets["jobFamilyGroup"]), 4)
        self.assertEqual(workday_applied_facets("acme", "Jobs"), {})


if __name__ == "__main__":
    unittest.main()
