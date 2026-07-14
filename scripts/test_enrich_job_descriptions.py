#!/usr/bin/env python3
import json
import unittest

from enrich_job_descriptions import JobPageParser, oracle_fields, structured_fields


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


if __name__ == "__main__":
    unittest.main()
