#!/usr/bin/env python3
import unittest

from crawl_google_jobs import public_job_url


class GoogleJobsTest(unittest.TestCase):
    def test_public_detail_url_does_not_require_sign_in(self):
        url = public_job_url("123456789", "Product Manager II, AI Quality")
        self.assertEqual(
            "https://www.google.com/about/careers/applications/jobs/results/123456789-product-manager-ii-ai-quality",
            url,
        )
        self.assertNotIn("signin", url)


if __name__ == "__main__":
    unittest.main()
