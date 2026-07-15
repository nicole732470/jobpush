#!/usr/bin/env python3

import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from verify_closed_job_links import INACTIVE_PAGE, is_confirmed_closed


class VerifyClosedJobLinksTest(unittest.TestCase):
    def test_inactive_page_phrases(self):
        self.assertRegex("This job is no longer available", INACTIVE_PAGE)
        self.assertRegex("This position has been filled", INACTIVE_PAGE)
        self.assertNotRegex("Explore our available jobs", INACTIVE_PAGE)

    @patch("verify_closed_job_links.urlopen")
    def test_only_404_and_410_http_errors_confirm_closure(self, mocked_urlopen):
        for status, expected in ((404, True), (410, True), (403, False), (500, False)):
            mocked_urlopen.side_effect = HTTPError("https://example.com/job", status, "", {}, None)
            self.assertEqual(
                is_confirmed_closed({"job_url": "https://example.com/job"}, timeout=1), expected
            )


if __name__ == "__main__":
    unittest.main()
