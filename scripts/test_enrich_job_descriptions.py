#!/usr/bin/env python3
import json
import unittest
from unittest.mock import patch

from enrich_job_descriptions import (
    JobPageParser, _ASHBY_CACHE, ashby_fields, description_quality_error, fetch_ashby_board, google_fields, greenhouse_fields, greenhouse_url,
    oracle_fields, smartrecruiters_fields, smartrecruiters_url, structured_fields, workday_fields, workday_url,
)


class JobDescriptionParserTest(unittest.TestCase):
    def test_json_ld_beats_page_chrome(self):
        page = f"""<html><nav>Navigation noise</nav><script type="application/ld+json">{json.dumps({
            '@type': 'JobPosting', 'description': '<h2>Role</h2><p>' + 'Build reliable products. ' * 12 + '</p>',
            'jobLocationType': 'TELECOMMUTE', 'datePosted': '2026-07-13',
            'baseSalary': {'currency': 'USD', 'value': {'minValue': 90000}},
        })}</script><footer>Footer noise</footer></html>"""
        parser = JobPageParser()
        parser.feed(page)
        result = structured_fields(parser)
        self.assertIn("Build reliable products", result["cleaned_description"])
        self.assertNotIn("Navigation noise", result["cleaned_description"])
        self.assertEqual(result["work_arrangement"], "TELECOMMUTE")

    def test_description_container_fallback(self):
        parser = JobPageParser()
        parser.feed("<nav>Noise</nav><main><div class='job-description'>" + "Own customer workflows. " * 12 + "</div></main>")
        result = structured_fields(parser)
        self.assertIn("Own customer workflows", result["cleaned_description"])
        self.assertNotIn("Noise", result["cleaned_description"])

    def test_oracle_detail_json(self):
        result = oracle_fields(json.dumps({"items": [{
            "ExternalDescriptionStr": "<p>Build data products. " * 12 + "</p>",
            "WorkplaceType": "Hybrid", "ExternalPostedStartDate": "2026-07-14T00:00:00Z",
        }]}))
        self.assertIn("Build data products", result["cleaned_description"])
        self.assertEqual(result["work_arrangement"], "Hybrid")

    def test_greenhouse_public_api(self):
        row = {"source_key": "example", "external_job_id": "123", "job_url": "https://company.test/jobs?gh_jid=123"}
        self.assertEqual(greenhouse_url(row), "https://boards-api.greenhouse.io/v1/boards/example/jobs/123")
        result = greenhouse_fields(json.dumps({"content": "<p>Build useful products. " * 12 + "</p>", "absolute_url": "https://example.test/job"}))
        self.assertIn("Build useful products", result["cleaned_description"])

    def test_smartrecruiters_public_api(self):
        row = {"source_key": "ExampleCo", "external_job_id": "abc", "job_url": "https://careers.smartrecruiters.com/ExampleCo"}
        self.assertEqual(smartrecruiters_url(row), "https://api.smartrecruiters.com/v1/companies/ExampleCo/postings/abc")
        result = smartrecruiters_fields(json.dumps({
            "jobAd": {"sections": {
                "jobDescription": {"title": "Responsibilities", "text": "<p>Own AI products. " * 30 + "</p>"},
                "qualifications": {"title": "Qualifications", "text": "Five years of product experience and AI skills."},
            }},
            "applyUrl": "https://example.test/apply", "releasedDate": "2026-07-14T00:00:00Z",
        }))
        self.assertIn("Own AI products", result["cleaned_description"])
        self.assertIn("Qualifications", result["cleaned_description"])

    def test_ashby_board_job(self):
        board = {"jobs": [
            {"id": "abc", "descriptionHtml": "<p>Own AI workflows. " * 12 + "</p>"},
            {"id": "other", "descriptionHtml": "<p>Unrelated posting.</p>"},
        ]}
        result = ashby_fields(json.dumps(board), "abc")
        self.assertIn("Own AI workflows", result["cleaned_description"])
        self.assertIn('"id":"abc"', result["_raw_html"])
        self.assertNotIn("Unrelated posting", result["_raw_html"])

    def test_ashby_board_is_downloaded_once_per_batch(self):
        class Headers:
            def get_content_charset(self): return "utf-8"
            def get(self, key, default=""): return "application/json" if key == "Content-Type" else default
        class Response:
            status = 200
            headers = Headers()
            def __enter__(self): return self
            def __exit__(self, *args): return None
            def read(self): return b'{"jobs":[]}'
        _ASHBY_CACHE.clear()
        with patch("enrich_job_descriptions.urlopen", return_value=Response()) as mocked:
            fetch_ashby_board("https://example.test/board", 10)
            fetch_ashby_board("https://example.test/board", 10)
        self.assertEqual(1, mocked.call_count)

    def test_workday_cxs_detail(self):
        row = {"job_url": "https://nike.wd1.myworkdayjobs.com/nke/job/Beaverton/Business-Analyst_R-1"}
        self.assertEqual(workday_url(row), "https://nike.wd1.myworkdayjobs.com/wday/cxs/nike/nke/job/Beaverton/Business-Analyst_R-1")
        result = workday_fields(json.dumps({"jobPostingInfo": {"jobDescription": "<p>Analyze product data. " * 12 + "</p>"}}))
        self.assertIn("Analyze product data", result["cleaned_description"])

    def test_rejects_false_success_pages(self):
        self.assertIn("redirect", description_quality_error(
            '{"widget":"redirect","url":"/site/job/example","externalSpa":true}'))
        self.assertEqual("login page", description_quality_error(
            "Sign in - Google Accounts Forgot email? Not your computer? " * 20))
        self.assertEqual("inactive career page", description_quality_error(
            "JazzHR - Inactive Career Page This account is no longer active. " * 20))
        self.assertIn("shorter", description_quality_error("Only a salary fragment."))

    def test_accepts_complete_jd(self):
        description = (
            "About the role. You will own the product roadmap and partner with engineering. "
            "Responsibilities include customer research, prioritization, and launch measurement. "
            "Qualifications: five years of product experience and strong communication skills. " * 4
        )
        self.assertEqual("", description_quality_error(description))

    def test_google_detail_removes_search_results_chrome(self):
        page = """<html><body>
        <div>Jobs search results Other unrelated job Showing 1 to 20 of 3000 rows</div>
        <main><h2>Minimum qualifications</h2><p>Five years of product experience and AI skills.</p>
        <h2>About the job</h2><p>You will own the product roadmap and partner with engineering.</p>
        <h2>Responsibilities</h2><p>Define strategy, interview users, and measure product quality.</p>
        <p>Qualifications include communication and technical product experience.</p>
        <p>""" + ("Build reliable AI products with customers. " * 12) + """</p>
        <p>Google is proud to be an equal opportunity employer.</p></main></body></html>"""
        result = google_fields(page)
        self.assertTrue(result["cleaned_description"].startswith("Minimum qualifications"))
        self.assertNotIn("Other unrelated job", result["cleaned_description"])
        self.assertNotIn("equal opportunity employer", result["cleaned_description"])


if __name__ == "__main__":
    unittest.main()
