#!/usr/bin/env python3
import unittest

from crawl_lever import api_origin, company_token


class LeverEndpointTest(unittest.TestCase):
    def test_us_api_origin(self):
        self.assertEqual(api_origin("https://jobs.lever.co/acme"), "https://api.lever.co")

    def test_eu_api_origin(self):
        self.assertEqual(api_origin("https://jobs.eu.lever.co/acme"), "https://api.eu.lever.co")

    def test_company_token(self):
        self.assertEqual(company_token("https://jobs.eu.lever.co/acme"), "acme")


if __name__ == "__main__":
    unittest.main()
