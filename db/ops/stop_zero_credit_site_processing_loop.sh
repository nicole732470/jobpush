#!/usr/bin/env bash
set -euo pipefail

pkill -f "run_zero_credit_site_processing_loop\\.sh" || true
pkill -f "run_due_crawl_batch\\.sh" || true
pkill -f "run_structured_adapter_pilot\\.sh" || true
pgrep -af "run_zero_credit_site_processing_loop|run_due_crawl_batch|run_structured_adapter" || true
