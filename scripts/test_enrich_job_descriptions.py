#!/usr/bin/env python3
import json
import unittest

from enrich_job_descriptions import (
    JobPageParser, ashby_fields, greenhouse_fields, greenhouse_url,
    oracle_fields, structured_fields, workday_fields, workday_url,
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

    def test_ashby_board_job(self):
        result = ashby_fields(json.dumps({"jobs": [{"id": "abc", "descriptionHtml": "<p>Own AI workflows. " * 12 + "</p>"}]}), "abc")
        self.assertIn("Own AI workflows", result["cleaned_description"])

    def test_workday_cxs_detail(self):
        row = {"job_url": "https://nike.wd1.myworkdayjobs.com/nke/job/Beaverton/Business-Analyst_R-1"}
        self.assertEqual(workday_url(row), "https://nike.wd1.myworkdayjobs.com/wday/cxs/nike/nke/job/Beaverton/Business-Analyst_R-1")
        result = workday_fields(json.dumps({"jobPostingInfo": {"jobDescription": "<p>Analyze product data. " * 12 + "</p>"}}))
        self.assertIn("Analyze product data", result["cleaned_description"])


if __name__ == "__main__":
    unittest.main()
