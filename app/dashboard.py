from __future__ import annotations

from datetime import datetime, timedelta
import os
from pathlib import Path
import subprocess
from urllib.parse import parse_qs, quote_plus, urlparse, urlunparse
from urllib.request import urlopen
from zoneinfo import ZoneInfo

import pandas as pd
import streamlit as st

from db import execute, query


CAREER_TERMS = ("career", "careers", "jobs", "job", "join", "opportunities", "openings")
SUPPORTED_SOURCE_TYPES = {
    "amazon_jobs",
    "apple_jobs",
    "cognizant_jobs",
    "eightfold",
    "google_jobs",
    "uber_jobs",
    "greenhouse",
    "icims",
    "oracle_cloud",
    "workday",
    "lever",
    "ashby",
    "smartrecruiters",
    "workable",
    "jobvite",
    "paylocity",
    "rippling",
}
LOCAL_FILTER_SOURCE_TYPES = {
    "greenhouse",
    "lever",
    "ashby",
    "smartrecruiters",
    "workable",
    "jobvite",
    "paylocity",
    "rippling",
    "icims",
    "workday",
}
APPLICATION_STATUS_OPTIONS = {
    "New": "new",
    "Apply Next": "apply_next",
    "Referred": "referred",
    "Applied": "applied",
    "Dismiss": "dismissed",
    "Saved (legacy)": "saved",
}
OPEN_APPLICATION_STATUSES = ("new", "saved", "apply_next", "referred")
PROFILE_YAML_URL = "https://raw.githubusercontent.com/nicole732470/joblens/main/evals/golden_set/candidate_profile.yaml"


st.set_page_config(page_title="JobPush Ops", page_icon="↗", layout="wide")
st.markdown(
    """
    <style>
      .stApp {background: linear-gradient(180deg,#fbfcff 0%,#f6f8fb 42%,#f7f7f4 100%);}
      .block-container {padding-top: 1.4rem; padding-bottom: 3rem; max-width: 1500px;}
      [data-testid="stMetric"] {background:rgba(255,255,255,.92);border:1px solid #e4e7ec;
        border-radius:14px;padding:10px 12px;box-shadow:0 6px 18px rgba(16,24,40,.04); min-height:106px;}
      [data-testid="stMetric"] [data-testid="stMetricDelta"] {min-height:18px;}
      [data-testid="stMetric"] label {font-size:.78rem !important;}
      h1 {letter-spacing:-0.045em; margin-bottom:.15rem;}
      h2, h3 {letter-spacing:-0.025em;}
      .quiet {color:#667085;font-size:.92rem;}
      .hero {padding:14px 18px;border-radius:20px;background:linear-gradient(135deg,#111827 0%,#25314a 58%,#43506b 100%);
        color:#fff;margin-bottom:18px;box-shadow:0 16px 38px rgba(17,24,39,.16);}
      .hero .quiet {color:#d0d5dd;}
      .section-card {background:rgba(255,255,255,.8);border:1px solid #eaecf0;border-radius:18px;padding:14px 16px;}
      div[data-testid="stDataFrame"] {border-radius:16px; overflow:hidden;}
      div[role="radiogroup"] {gap:0;background:#eef2f6;border:1px solid #d0d5dd;border-radius:14px;padding:4px;}
      div[role="radiogroup"] label {
        background:transparent;border:0;border-radius:10px;padding:.38rem .72rem;
        box-shadow:none;color:#344054;
      }
      div[role="radiogroup"] label:has(input:checked) {
        background:#fff;color:#111827;border-color:#fff;box-shadow:0 4px 14px rgba(16,24,40,.08);
      }
      div[role="radiogroup"] label:has(input:checked) * {color:#111827 !important;}
      div[role="radiogroup"] label:has(input:checked) svg {fill:#111827 !important;}
      div[role="radiogroup"] label:hover {background:#fff;color:#111827;}
      div[data-baseweb="tag"] {background:#111827 !important;color:#fff !important;border-color:#111827 !important;}
      div[data-baseweb="tag"] * {color:#fff !important;fill:#fff !important;}
      [aria-selected="true"] {color:#fff !important;}
      [data-testid="stSidebar"] {background:#f8fafc;}
      [data-baseweb="select"], [data-testid="stTextInput"] input, [data-testid="stDateInput"] input {
        background:#fff;border-radius:12px;
      }
    </style>
    """,
    unsafe_allow_html=True,
)


@st.cache_data(ttl=60)
def apply_job_summary(tiers: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        WITH chicago_day AS (
            SELECT ((NOW() AT TIME ZONE 'America/Chicago')::date AT TIME ZONE 'America/Chicago') AS start_at
        ), open_jobs AS (
            SELECT *
            FROM jobpush.dashboard_jobs
            WHERE priority_tier = ANY(%s)
              AND role_status = 'target'
              AND application_status = ANY(%s)
        ), closed_today AS (
            SELECT count(*) AS closed_jobs_today
            FROM jobpush.job_postings posting
            JOIN jobpush.crawl_targets target USING (consolidation_key)
            JOIN jobpush.job_title_labels label USING (normalized_title)
            CROSS JOIN chicago_day
            WHERE target.priority_tier = ANY(%s)
              AND label.classification_status = 'target'
              AND posting.closed_at >= chicago_day.start_at
        )
        SELECT
            count(*) AS open_target_jobs,
            count(DISTINCT consolidation_key) AS companies,
            count(*) FILTER (WHERE first_seen_at >= chicago_day.start_at) AS new_target_jobs_today,
            (SELECT closed_jobs_today FROM closed_today) AS closed_jobs_today,
            count(*) FILTER (
                WHERE COALESCE(location, '') ILIKE '%%chicago%%'
                   OR COALESCE(location, '') ILIKE '%%illinois%%'
                   OR COALESCE(location, '') ~* '(^|[,/ -])IL($|[,/ -])'
            ) AS chicago_or_il_jobs,
            count(*) FILTER (
                WHERE canonical_role = 'candidate_profile_track: product'
                   OR normalized_title LIKE '%%product%%manager%%'
            ) AS product_manager_jobs
        FROM open_jobs
        CROSS JOIN chicago_day
        """,
        (list(tiers), list(OPEN_APPLICATION_STATUSES), list(tiers)),
    )


@st.cache_data(ttl=60)
def application_status_summary(tiers: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        WITH counts AS (
            SELECT application_status, count(*) AS jobs
            FROM jobpush.dashboard_jobs
            WHERE priority_tier = ANY(%s)
              AND role_status = 'target'
            GROUP BY application_status
        )
        SELECT application_status,
               jobs,
               ROUND(100.0 * jobs / NULLIF(SUM(jobs) OVER (), 0), 1) AS pct
        FROM counts
        ORDER BY CASE application_status
            WHEN 'new' THEN 0
            WHEN 'apply_next' THEN 1
            WHEN 'referred' THEN 2
            WHEN 'applied' THEN 3
            WHEN 'dismissed' THEN 4
            WHEN 'saved' THEN 5
            ELSE 6
        END
        """,
        (list(tiers),),
    )


@st.cache_data(ttl=60)
def target_job_mix_summary(tiers: tuple[str, ...], app_statuses: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        WITH chicago_day AS (
            SELECT ((NOW() AT TIME ZONE 'America/Chicago')::date AT TIME ZONE 'America/Chicago') AS start_at
        ), base AS (
            SELECT canonical_role, normalized_title, first_seen_at
            FROM jobpush.dashboard_jobs
            WHERE priority_tier = ANY(%s)
              AND role_status = 'target'
              AND application_status = ANY(%s)
        ), classified AS (
            SELECT
                first_seen_at,
                CASE
                    WHEN canonical_role IN ('candidate_profile_track: product', 'candidate_profile_track: analyst/bi')
                         OR normalized_title LIKE '%%product%%manager%%'
                         OR normalized_title LIKE '%%business%%analyst%%'
                         OR normalized_title LIKE '%%data%%analyst%%'
                         OR normalized_title LIKE '%%strategy%%analyst%%'
                         OR normalized_title LIKE '%%operations%%analyst%%'
                         OR normalized_title LIKE '%%program%%manager%%'
                         OR normalized_title LIKE '%%project%%manager%%'
                         OR normalized_title LIKE '%%implementation%%'
                         OR normalized_title LIKE '%%consultant%%'
                         OR normalized_title LIKE '%%consulting%%'
                         OR normalized_title LIKE '%%coordinator%%'
                         OR canonical_role ILIKE '%%financial%%analyst%%'
                         OR canonical_role ILIKE '%%financial and investment%%'
                         OR canonical_role ILIKE '%%market research%%'
                    THEN 'stack_1_business_product_data'
                    WHEN canonical_role IN ('candidate_profile_track: solutions/systems', 'candidate_profile_track: applied_ai')
                         OR (canonical_role = 'candidate_profile_track: software/data'
                             AND (normalized_title LIKE '%%data%%engineer%%'
                                  OR normalized_title LIKE '%%analytics%%engineer%%'
                                  OR normalized_title LIKE '%%data%%architect%%'
                                  OR normalized_title LIKE '%%database%%administrator%%'
                                  OR normalized_title LIKE '%%database%%admin%%'))
                         OR normalized_title LIKE '%%systems%%analyst%%'
                         OR normalized_title LIKE '%%information%%system%%'
                    THEN 'stack_2_ai_solutions_systems_data'
                    WHEN canonical_role = 'candidate_profile_track: software/data'
                         OR normalized_title LIKE '%%software%%'
                         OR normalized_title LIKE '%%quality%%assurance%%'
                         OR normalized_title LIKE '%% qa %%'
                         OR normalized_title LIKE '%%test engineer%%'
                         OR normalized_title LIKE '%%tester%%'
                         OR normalized_title LIKE '%%devops%%'
                         OR normalized_title LIKE '%%cloud%%'
                         OR normalized_title LIKE '%%site reliability%%'
                         OR normalized_title LIKE '%%sre%%'
                         OR normalized_title LIKE '%%security%%'
                         OR normalized_title LIKE '%%cyber%%'
                         OR canonical_role ILIKE '%%network%%'
                         OR canonical_role ILIKE '%%systems administrator%%'
                    THEN 'stack_4_sde'
                    WHEN canonical_role = 'candidate_profile_track: customer_success'
                         OR normalized_title LIKE '%%customer%%success%%'
                         OR normalized_title LIKE '%%technical%%account%%'
                         OR normalized_title LIKE '%%relationship%%manager%%'
                         OR normalized_title LIKE '%%support%%'
                         OR normalized_title LIKE '%%specialist%%'
                         OR normalized_title LIKE '%%administrator%%'
                         OR normalized_title LIKE '%%admin%%'
                    THEN 'stack_3_customer_success'
                    WHEN canonical_role = 'candidate_profile_track: marketing automation'
                         OR normalized_title LIKE '%%sales%%'
                         OR normalized_title LIKE '%%marketing%%'
                         OR normalized_title LIKE '%%business%%development%%'
                    THEN 'stack_3_gtm'
                    ELSE 'stack_5_possible_target'
                END AS role_stack,
                CASE
                    WHEN canonical_role = 'candidate_profile_track: product' THEN 'product_manager'
                    WHEN canonical_role = 'candidate_profile_track: analyst/bi' THEN 'data_analytics_bi'
                    WHEN canonical_role = 'candidate_profile_track: solutions/systems' THEN 'systems_engineering'
                    WHEN canonical_role = 'candidate_profile_track: applied_ai' THEN 'applied_ai'
                    WHEN canonical_role = 'candidate_profile_track: customer_success' THEN 'customer_success'
                    WHEN canonical_role = 'candidate_profile_track: marketing automation' THEN 'marketing'
                    WHEN canonical_role = 'candidate_profile_track: software/data'
                         AND (normalized_title LIKE '%%data%%engineer%%'
                              OR normalized_title LIKE '%%analytics%%engineer%%'
                              OR normalized_title LIKE '%%data%%architect%%') THEN 'data_engineering'
                    WHEN canonical_role = 'candidate_profile_track: software/data' THEN 'software_engineering'
                    WHEN normalized_title LIKE '%%intern%%'
                         OR normalized_title LIKE '%%internship%%'
                         OR normalized_title LIKE '%%co op%%'
                         OR normalized_title LIKE '%%co-op%%' THEN 'internship'
                    WHEN normalized_title LIKE '%%forward deployed engineer%%'
                         OR normalized_title LIKE '%%forward-deployed engineer%%' THEN 'forward_deployed_engineer'
                    WHEN normalized_title LIKE '%%ai full stack%%'
                         OR normalized_title LIKE '%%ai engineer%%'
                         OR normalized_title LIKE '%%gtm engineer%%' THEN 'applied_ai'
                    WHEN normalized_title LIKE '%%product%%manager%%' THEN 'product_manager'
                    WHEN normalized_title LIKE '%%program%%manager%%' THEN 'program_manager'
                    WHEN normalized_title LIKE '%%project%%manager%%' THEN 'project_manager'
                    WHEN normalized_title LIKE '%%system%%engineer%%'
                         OR normalized_title LIKE '%%systems%%engineer%%'
                         OR normalized_title LIKE '%%systems%%analyst%%'
                         OR normalized_title LIKE '%%information%%system%%' THEN 'systems_engineering'
                    WHEN normalized_title LIKE '%%software%%engineer%%'
                         OR normalized_title LIKE '%%software%%developer%%'
                         OR normalized_title LIKE '%%fullstack%%'
                         OR normalized_title LIKE '%%full stack%%' THEN 'software_engineering'
                    WHEN normalized_title LIKE '%%data%%scientist%%'
                         OR normalized_title LIKE '%%machine%%learning%%'
                         OR normalized_title LIKE '%%ml engineer%%' THEN 'data_science_ml'
                    WHEN normalized_title LIKE '%%data%%engineer%%'
                         OR normalized_title LIKE '%%analytics%%engineer%%'
                         OR normalized_title LIKE '%%data%%architect%%'
                         OR normalized_title LIKE '%%database%%administrator%%'
                         OR normalized_title LIKE '%%database%%admin%%' THEN 'data_engineering'
                    WHEN normalized_title LIKE '%%data%%analyst%%'
                         OR normalized_title LIKE '%%business intelligence%%'
                         OR normalized_title LIKE '%%bi analyst%%' THEN 'data_analytics_bi'
                    WHEN normalized_title LIKE '%%business%%analyst%%' THEN 'business_analyst'
                    WHEN normalized_title LIKE '%%operations%%analyst%%'
                         OR normalized_title LIKE '%%strategy%%analyst%%' THEN 'strategy_operations'
                    WHEN normalized_title LIKE '%%customer%%success%%'
                         OR normalized_title LIKE '%%technical%%account%%'
                         OR normalized_title LIKE '%%relationship%%manager%%' THEN 'customer_success'
                    WHEN normalized_title LIKE '%%quality%%assurance%%'
                         OR normalized_title LIKE '%% qa %%'
                         OR normalized_title LIKE '%%test engineer%%'
                         OR normalized_title LIKE '%%tester%%' THEN 'qa_testing'
                    WHEN normalized_title LIKE '%%devops%%'
                         OR normalized_title LIKE '%%cloud%%'
                         OR normalized_title LIKE '%%site reliability%%'
                         OR normalized_title LIKE '%%sre%%' THEN 'cloud_devops'
                    WHEN normalized_title LIKE '%%security%%'
                         OR normalized_title LIKE '%%cyber%%' THEN 'security'
                    WHEN normalized_title LIKE '%%implementation%%'
                         OR normalized_title LIKE '%%consultant%%'
                         OR normalized_title LIKE '%%consulting%%' THEN 'implementation_consulting'
                    WHEN normalized_title LIKE '%%support%%'
                         OR normalized_title LIKE '%%specialist%%'
                         OR normalized_title LIKE '%%administrator%%'
                         OR normalized_title LIKE '%%admin%%' THEN 'it_support_admin'
                    WHEN normalized_title LIKE '%%operations%%'
                         OR normalized_title LIKE '%%coordinator%%' THEN 'business_operations'
                    WHEN normalized_title LIKE '%%marketing%%' THEN 'marketing'
                    WHEN normalized_title LIKE '%%sales%%' THEN 'sales'
                    WHEN canonical_role ILIKE '%%market research%%' THEN 'marketing'
                    WHEN canonical_role ILIKE '%%financial%%analyst%%'
                         OR canonical_role ILIKE '%%financial and investment%%' THEN 'financial_analyst'
                    WHEN canonical_role ILIKE '%%statistic%%' THEN 'data_analytics_bi'
                    WHEN canonical_role ILIKE '%%information technology project manager%%' THEN 'project_manager'
                    WHEN canonical_role ILIKE '%%network%%'
                         OR canonical_role ILIKE '%%systems administrator%%' THEN 'systems_engineering'
                    WHEN canonical_role ILIKE '%%software developer%%' THEN 'software_engineering'
                    ELSE CONCAT('title:', COALESCE(NULLIF(normalized_title, ''), NULLIF(canonical_role, ''), 'unclassified target title'))
                END AS role_family
            FROM base
        ), segments AS (
            SELECT 'track' AS dimension,
                   CASE
                       WHEN role_stack = 'stack_5_possible_target' THEN CONCAT('track_family:', role_family)
                       ELSE role_stack
                   END AS segment_key,
                   first_seen_at
            FROM classified
            UNION ALL
            SELECT 'role_family' AS dimension, role_family AS segment_key, first_seen_at FROM classified
        ), counts AS (
            SELECT
                dimension,
                segment_key,
                count(*) AS current_open_jobs,
                count(*) FILTER (WHERE first_seen_at >= chicago_day.start_at) AS new_today_jobs
            FROM segments
            CROSS JOIN chicago_day
            GROUP BY dimension, segment_key
        )
        SELECT
            dimension,
            segment_key,
            current_open_jobs,
            ROUND(100.0 * current_open_jobs / NULLIF(SUM(current_open_jobs) OVER (PARTITION BY dimension), 0), 1) AS current_pct,
            new_today_jobs,
            ROUND(100.0 * new_today_jobs / NULLIF(SUM(new_today_jobs) OVER (PARTITION BY dimension), 0), 1) AS today_pct
        FROM counts
        ORDER BY dimension, current_open_jobs DESC, segment_key
        """,
        (list(tiers), list(app_statuses)),
    )


@st.cache_data(ttl=300)
def candidate_profile_yaml() -> tuple[str, str]:
    paths = [
        os.environ.get("JOBPUSH_PROFILE_YAML_PATH"),
        str(Path(__file__).resolve().parents[2] / "joblens/evals/golden_set/candidate_profile.yaml"),
    ]
    for path in paths:
        if path and Path(path).exists():
            return path, Path(path).read_text(encoding="utf-8")
    with urlopen(PROFILE_YAML_URL, timeout=5) as response:
        return PROFILE_YAML_URL, response.read().decode("utf-8")


@st.cache_data(ttl=60)
def daily_activity(tiers: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        WITH days AS (
            SELECT generate_series(
                ((NOW() AT TIME ZONE 'America/Chicago')::date - 29)::timestamp,
                (NOW() AT TIME ZONE 'America/Chicago')::date::timestamp,
                interval '1 day'
            )::date AS activity_date
        ), jobs AS (
            SELECT
                (job.first_seen_at AT TIME ZONE 'America/Chicago')::date AS activity_date,
                count(*) AS new_jobs,
                count(*) FILTER (WHERE job.role_status = 'target') AS new_target_jobs,
                count(*) FILTER (WHERE job.role_status = 'review') AS new_review_jobs
            FROM jobpush.dashboard_jobs job
            WHERE job.priority_tier = ANY(%s)
            GROUP BY 1
        ), closed AS (
            SELECT
                (posting.closed_at AT TIME ZONE 'America/Chicago')::date AS activity_date,
                count(*) AS closed_jobs
            FROM jobpush.job_postings posting
            JOIN jobpush.crawl_targets target USING (consolidation_key)
            JOIN jobpush.job_title_labels label USING (normalized_title)
            WHERE posting.closed_at IS NOT NULL
              AND target.priority_tier = ANY(%s)
              AND label.classification_status = 'target'
            GROUP BY 1
        ), runs AS (
            SELECT
                (run.started_at AT TIME ZONE 'America/Chicago')::date AS activity_date,
                count(*) AS crawl_runs,
                count(*) FILTER (WHERE run.status = 'succeeded') AS successful_runs,
                count(*) FILTER (WHERE run.status = 'failed') AS failed_runs,
                COALESCE(sum(run.requests_count), 0) AS requests,
                COALESCE(sum(run.new_job_count), 0) AS run_reported_new_jobs
            FROM jobpush.crawl_runs run
            JOIN jobpush.career_sites site USING (site_id)
            JOIN jobpush.crawl_targets target USING (consolidation_key)
            WHERE target.priority_tier = ANY(%s)
            GROUP BY 1
        )
        SELECT days.activity_date,
               COALESCE(jobs.new_jobs, 0) AS new_jobs,
               COALESCE(jobs.new_target_jobs, 0) AS new_target_jobs,
               COALESCE(jobs.new_review_jobs, 0) AS new_review_jobs,
               COALESCE(closed.closed_jobs, 0) AS closed_jobs,
               COALESCE(runs.crawl_runs, 0) AS crawl_runs,
               COALESCE(runs.successful_runs, 0) AS successful_runs,
               COALESCE(runs.failed_runs, 0) AS failed_runs,
               COALESCE(runs.requests, 0) AS requests,
               COALESCE(runs.run_reported_new_jobs, 0) AS run_reported_new_jobs
        FROM days
        LEFT JOIN jobs USING (activity_date)
        LEFT JOIN closed USING (activity_date)
        LEFT JOIN runs USING (activity_date)
        ORDER BY days.activity_date DESC
        """,
        (list(tiers), list(tiers), list(tiers)),
    )


@st.cache_data(ttl=60)
def crawl_funnel() -> pd.DataFrame:
    return query("SELECT * FROM jobpush.dashboard_crawl_funnel")


@st.cache_data(ttl=60)
def coverage_by_tier() -> pd.DataFrame:
    return query(
        """
        WITH target_counts AS (
            SELECT priority_tier, COUNT(*) AS companies
            FROM jobpush.crawl_targets
            WHERE enabled AND priority_tier IN ('P0','P1','P2','P3')
            GROUP BY priority_tier
        ), candidate_counts AS (
            SELECT target.priority_tier,
                   COUNT(DISTINCT site.consolidation_key) FILTER (WHERE site.verification_status='unverified') AS companies_with_candidates,
                   COUNT(DISTINCT site.consolidation_key) FILTER (WHERE site.verification_status='verified') AS companies_with_verified_site,
                   COUNT(DISTINCT site.consolidation_key) FILTER (
                       WHERE site.verification_status='verified' AND COALESCE(site.reviewed_by, '') NOT LIKE 'system:%%'
                   ) AS human_verified_companies,
                   COUNT(DISTINCT site.consolidation_key) FILTER (
                       WHERE site.verification_status='verified' AND site.reviewed_by LIKE 'system:%%'
                   ) AS auto_trusted_companies,
                   COUNT(*) FILTER (WHERE site.verification_status='verified' AND site.crawl_enabled) AS verified_enabled_sites
            FROM jobpush.career_sites site
            JOIN jobpush.crawl_targets target USING (consolidation_key)
            WHERE target.enabled AND target.priority_tier IN ('P0','P1','P2','P3')
            GROUP BY target.priority_tier
        ), schedule_counts AS (
            SELECT priority_tier,
                   COUNT(*) AS schedulable_sites,
                   COUNT(*) FILTER (WHERE is_due) AS due_now,
                   COUNT(*) FILTER (WHERE last_crawled_at IS NULL) AS never_crawled
            FROM jobpush.crawl_schedule_queue
            GROUP BY priority_tier
        )
        SELECT target_counts.priority_tier,
               target_counts.companies,
               COALESCE(candidate_counts.companies_with_candidates, 0) AS companies_with_candidates,
               COALESCE(candidate_counts.companies_with_verified_site, 0) AS companies_with_verified_site,
               COALESCE(candidate_counts.human_verified_companies, 0) AS human_verified_companies,
               COALESCE(candidate_counts.auto_trusted_companies, 0) AS auto_trusted_companies,
               COALESCE(candidate_counts.verified_enabled_sites, 0) AS verified_enabled_sites,
               COALESCE(schedule_counts.schedulable_sites, 0) AS schedulable_sites,
               COALESCE(schedule_counts.due_now, 0) AS due_now,
               COALESCE(schedule_counts.never_crawled, 0) AS never_crawled,
               ROUND(COALESCE(candidate_counts.companies_with_verified_site, 0)::numeric / NULLIF(target_counts.companies, 0), 4) AS verified_company_rate
        FROM target_counts
        LEFT JOIN candidate_counts USING (priority_tier)
        LEFT JOIN schedule_counts USING (priority_tier)
        ORDER BY CASE target_counts.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 ELSE 3 END
        """
    )


@st.cache_data(ttl=60)
def review_workbench_summary(tiers: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        WITH target AS (
            SELECT consolidation_key, priority_tier, priority_score, canonical_name
            FROM jobpush.crawl_targets
            WHERE enabled AND priority_tier = ANY(%s)
        ), site_rollup AS (
            SELECT consolidation_key,
                   BOOL_OR(verification_status = 'verified') AS has_verified_site,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled) AS has_enabled_site,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_crawled_at IS NOT NULL) AS has_attempt,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_success_at IS NOT NULL) AS has_success,
                   COUNT(*) FILTER (WHERE verification_status = 'unverified') AS unverified_candidates,
                   COUNT(*) FILTER (WHERE verification_status = 'rejected') AS rejected_candidates
            FROM jobpush.career_sites
            GROUP BY consolidation_key
        )
        SELECT target.priority_tier,
               COUNT(*) AS companies,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_verified_site, FALSE)) AS site_reviewed_verified,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.unverified_candidates, 0) > 0) AS waiting_site_review,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_enabled_site, FALSE)) AS can_crawl,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_attempt, FALSE)) AS crawled_at_least_once,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_success, FALSE)) AS crawled_successfully,
               COUNT(*) FILTER (
                   WHERE NOT COALESCE(site_rollup.has_verified_site, FALSE)
                     AND COALESCE(site_rollup.unverified_candidates, 0) = 0
               ) AS no_site_candidate_yet,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.rejected_candidates, 0) > 0) AS has_rejected_candidates,
               ROUND(100.0 * COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_verified_site, FALSE)) / NULLIF(COUNT(*), 0), 2) AS verified_pct,
               ROUND(100.0 * COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_success, FALSE)) / NULLIF(COUNT(*), 0), 2) AS success_pct
        FROM target
        LEFT JOIN site_rollup USING (consolidation_key)
        GROUP BY target.priority_tier
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END
        """,
        (list(tiers),),
    )


@st.cache_data(ttl=60)
def crawl_rank_coverage() -> pd.DataFrame:
    return query(
        """
        WITH ranked AS (
            SELECT target.*,
                   ROW_NUMBER() OVER (
                       ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 ELSE 3 END,
                                priority_score DESC NULLS LAST,
                                canonical_name
                   ) AS overall_rank
            FROM jobpush.crawl_targets target
            WHERE target.enabled AND target.priority_tier IN ('P0','P1','P2','P3')
        ), site_rollup AS (
            SELECT consolidation_key,
                   BOOL_OR(verification_status = 'verified') AS has_verified_site,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled) AS has_enabled_site,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_crawled_at IS NOT NULL) AS has_attempt,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_success_at IS NOT NULL) AS has_success
            FROM jobpush.career_sites
            GROUP BY consolidation_key
        ), buckets AS (
            SELECT 'Top 500 overall' AS bucket, 500 AS max_rank
            UNION ALL SELECT 'Top 1000 overall', 1000
            UNION ALL SELECT 'All active P0/P1/P2/P3', 999999
        )
        SELECT buckets.bucket,
               COUNT(*) AS companies,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_verified_site, FALSE)) AS verified_site_companies,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_enabled_site, FALSE)) AS can_crawl,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_attempt, FALSE)) AS crawled_at_least_once,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_success, FALSE)) AS crawled_successfully,
               ROUND(100.0 * COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_success, FALSE)) / NULLIF(COUNT(*), 0), 2) AS success_pct
        FROM buckets
        JOIN ranked ON ranked.overall_rank <= buckets.max_rank
        LEFT JOIN site_rollup USING (consolidation_key)
        GROUP BY buckets.bucket, buckets.max_rank
        ORDER BY buckets.max_rank
        """
    )


@st.cache_data(ttl=60)
def crawl_rollout_by_tier() -> pd.DataFrame:
    return query(
        """
        WITH site_rollup AS (
            SELECT consolidation_key,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled) AS has_enabled_site,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_crawled_at IS NOT NULL) AS has_attempt,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_success_at IS NOT NULL) AS has_success,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND crawl_status = 'failed') AS has_failed,
                   COUNT(*) FILTER (WHERE verification_status = 'unverified') AS unverified_candidates,
                   COUNT(*) FILTER (WHERE verification_status = 'unverified' AND source_type = 'generic_html') AS generic_candidates,
                   COUNT(*) FILTER (WHERE verification_status = 'unverified' AND source_type <> 'generic_html') AS structured_candidates
            FROM jobpush.career_sites
            GROUP BY consolidation_key
        ), due AS (
            SELECT consolidation_key,
                   COUNT(*) FILTER (WHERE is_due) AS due_sites
            FROM jobpush.crawl_schedule_queue
            GROUP BY consolidation_key
        )
        SELECT target.priority_tier,
               COUNT(*) AS companies,
               COUNT(*) FILTER (WHERE COALESCE(site.has_enabled_site, FALSE)) AS enabled_site_companies,
               COUNT(*) FILTER (WHERE COALESCE(site.has_attempt, FALSE)) AS attempted_companies,
               COUNT(*) FILTER (WHERE COALESCE(site.has_success, FALSE)) AS succeeded_companies,
               COUNT(*) FILTER (WHERE COALESCE(site.has_failed, FALSE)) AS failed_companies,
               COUNT(*) FILTER (WHERE COALESCE(due.due_sites, 0) > 0) AS due_now_companies,
               COUNT(*) FILTER (
                   WHERE COALESCE(site.structured_candidates, 0) > 0
                     AND NOT COALESCE(site.has_enabled_site, FALSE)
               ) AS structured_candidate_not_enabled,
               COUNT(*) FILTER (
                   WHERE COALESCE(site.generic_candidates, 0) > 0
                     AND NOT COALESCE(site.has_enabled_site, FALSE)
               ) AS generic_html_needs_resolution,
               COUNT(*) FILTER (
                   WHERE target.discovery_status = 'pending'
                     AND NOT COALESCE(site.has_enabled_site, FALSE)
                     AND COALESCE(site.unverified_candidates, 0) = 0
               ) AS not_searched_yet,
               ROUND(100.0 * COUNT(*) FILTER (WHERE COALESCE(site.has_success, FALSE)) / NULLIF(COUNT(*), 0), 2) AS success_pct,
               ROUND(100.0 * COUNT(*) FILTER (WHERE COALESCE(site.has_attempt, FALSE)) / NULLIF(COUNT(*), 0), 2) AS attempted_pct
        FROM jobpush.crawl_targets target
        LEFT JOIN site_rollup site USING (consolidation_key)
        LEFT JOIN due USING (consolidation_key)
        WHERE target.enabled AND target.priority_tier IN ('P0','P1','P2','P3')
        GROUP BY target.priority_tier
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 ELSE 3 END
        """
    )


@st.cache_data(ttl=60)
def today_crawl_progress(tiers: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        WITH chicago_day AS (
            SELECT ((NOW() AT TIME ZONE 'America/Chicago')::date AT TIME ZONE 'America/Chicago') AS start_at
        )
        SELECT target.priority_tier,
               COUNT(*) AS site_attempts_today,
               COUNT(DISTINCT target.consolidation_key) AS companies_attempted_today,
               COUNT(DISTINCT target.consolidation_key) FILTER (WHERE run.status = 'succeeded') AS companies_succeeded_today,
               COUNT(*) FILTER (WHERE run.status = 'failed') AS failed_site_attempts_today,
               COALESCE(SUM(run.parsed_job_count), 0) AS parsed_jobs_today,
               COALESCE(SUM(run.new_job_count), 0) AS new_jobs_today,
               COALESCE(SUM(run.closed_job_count), 0) AS closed_jobs_today,
               COALESCE(SUM(run.target_job_count), 0) AS target_jobs_today,
               COALESCE(SUM(run.review_job_count), 0) AS review_jobs_today
        FROM jobpush.crawl_runs run
        JOIN jobpush.career_sites site USING (site_id)
        JOIN jobpush.crawl_targets target USING (consolidation_key)
        CROSS JOIN chicago_day
        WHERE run.started_at >= chicago_day.start_at
          AND target.priority_tier = ANY(%s)
        GROUP BY target.priority_tier
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END
        """,
        (list(tiers),),
    )


@st.cache_data(ttl=60)
def recent_crawl_runs(tiers: tuple[str, ...], limit: int = 20) -> pd.DataFrame:
    return query(
        """
        SELECT run.started_at AT TIME ZONE 'America/Chicago' AS started_ct,
               run.finished_at AT TIME ZONE 'America/Chicago' AS finished_ct,
               target.priority_tier, target.canonical_name, site.source_type,
               run.status, run.parsed_job_count, run.new_job_count,
               run.closed_job_count, run.target_job_count, run.review_job_count,
               run.error_code, LEFT(run.error_message, 220) AS error_message
        FROM jobpush.crawl_runs run
        JOIN jobpush.career_sites site USING (site_id)
        JOIN jobpush.crawl_targets target USING (consolidation_key)
        WHERE target.priority_tier = ANY(%s)
        ORDER BY run.started_at DESC
        LIMIT %s
        """,
        (list(tiers), int(limit)),
    )


@st.cache_data(ttl=60)
def crawl_completion_summary(tiers: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        WITH target AS (
            SELECT consolidation_key, priority_tier, priority_score
            FROM jobpush.crawl_targets
            WHERE enabled AND priority_tier = ANY(%s)
        ), site_rollup AS (
            SELECT consolidation_key,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled) AS has_enabled_site,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_success_at IS NOT NULL) AS has_success,
                   COUNT(*) FILTER (WHERE verification_status = 'verified' AND crawl_enabled) AS enabled_sites
            FROM jobpush.career_sites
            GROUP BY consolidation_key
        ), schedule AS (
            SELECT consolidation_key,
                   COUNT(*) AS schedulable_sites,
                   COUNT(*) FILTER (WHERE is_due) AS due_sites
            FROM jobpush.crawl_schedule_queue
            GROUP BY consolidation_key
        ), chicago_day AS (
            SELECT ((NOW() AT TIME ZONE 'America/Chicago')::date AT TIME ZONE 'America/Chicago') AS start_at
        ), today_runs AS (
            SELECT target.priority_tier,
                   COUNT(*) AS site_attempts_today,
                   COUNT(DISTINCT target.consolidation_key) AS companies_attempted_today,
                   COUNT(DISTINCT target.consolidation_key) FILTER (WHERE run.status = 'succeeded') AS companies_succeeded_today,
                   COUNT(*) FILTER (WHERE run.status = 'failed') AS failed_site_attempts_today,
                   MAX(run.started_at) AS latest_started_at,
                   MAX(run.finished_at) AS latest_finished_at
            FROM jobpush.crawl_runs run
            JOIN jobpush.career_sites site USING (site_id)
            JOIN target USING (consolidation_key)
            CROSS JOIN chicago_day
            WHERE run.started_at >= chicago_day.start_at
            GROUP BY target.priority_tier
        )
        SELECT target.priority_tier,
               COUNT(*) AS companies,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_enabled_site, FALSE)) AS companies_with_enabled_site,
               COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_success, FALSE)) AS companies_succeeded_ever,
               COALESCE(SUM(schedule.schedulable_sites), 0) AS schedulable_sites,
               COALESCE(SUM(schedule.due_sites), 0) AS due_sites,
               COALESCE(today_runs.site_attempts_today, 0) AS site_attempts_today,
               COALESCE(today_runs.companies_attempted_today, 0) AS companies_attempted_today,
               COALESCE(today_runs.companies_succeeded_today, 0) AS companies_succeeded_today,
               COALESCE(today_runs.failed_site_attempts_today, 0) AS failed_site_attempts_today,
               today_runs.latest_started_at,
               today_runs.latest_finished_at,
               ROUND(100.0 * COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_enabled_site, FALSE)) / NULLIF(COUNT(*), 0), 2) AS enabled_company_pct,
               ROUND(100.0 * COALESCE(today_runs.companies_attempted_today, 0) / NULLIF(COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_enabled_site, FALSE)), 0), 2) AS today_attempted_pct_of_enabled,
               ROUND(100.0 * COALESCE(today_runs.companies_succeeded_today, 0) / NULLIF(COUNT(*) FILTER (WHERE COALESCE(site_rollup.has_enabled_site, FALSE)), 0), 2) AS today_succeeded_pct_of_enabled
        FROM target
        LEFT JOIN site_rollup USING (consolidation_key)
        LEFT JOIN schedule USING (consolidation_key)
        LEFT JOIN today_runs USING (priority_tier)
        GROUP BY target.priority_tier,
                 today_runs.site_attempts_today, today_runs.companies_attempted_today,
                 today_runs.companies_succeeded_today, today_runs.failed_site_attempts_today,
                 today_runs.latest_started_at, today_runs.latest_finished_at
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END
        """,
        (list(tiers),),
    )


@st.cache_data(ttl=60)
def p1_blocker_distribution() -> pd.DataFrame:
    return query(
        """
        WITH site_rollup AS (
            SELECT consolidation_key,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled) AS has_enabled_site,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_crawled_at IS NOT NULL) AS has_attempt,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_success_at IS NOT NULL) AS has_success,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND crawl_status = 'failed') AS has_failed,
                   COUNT(*) FILTER (WHERE verification_status = 'unverified' AND source_type = 'generic_html') AS generic_candidates,
                   COUNT(*) FILTER (WHERE verification_status = 'unverified' AND source_type <> 'generic_html') AS structured_candidates,
                   COUNT(*) FILTER (WHERE verification_status = 'unverified') AS unverified_candidates
            FROM jobpush.career_sites
            GROUP BY consolidation_key
        ), due AS (
            SELECT consolidation_key, COUNT(*) FILTER (WHERE is_due) AS due_sites
            FROM jobpush.crawl_schedule_queue
            GROUP BY consolidation_key
        ), classified AS (
            SELECT target.consolidation_key,
                   CASE
                       WHEN COALESCE(site.has_success, FALSE) THEN 'successfully_crawled'
                       WHEN COALESCE(site.has_failed, FALSE) THEN 'adapter_or_site_failed'
                       WHEN COALESCE(due.due_sites, 0) > 0 THEN 'enabled_waiting_for_scheduler'
                       WHEN COALESCE(site.has_enabled_site, FALSE) THEN 'enabled_not_due_yet'
                       WHEN COALESCE(site.structured_candidates, 0) > 0 THEN 'structured_candidate_not_enabled'
                       WHEN COALESCE(site.generic_candidates, 0) > 0 THEN 'generic_html_needs_resolution'
                       WHEN target.discovery_status = 'pending' THEN 'not_searched_yet'
                       ELSE 'searched_no_usable_candidate'
                   END AS crawl_state
            FROM jobpush.crawl_targets target
            LEFT JOIN site_rollup site USING (consolidation_key)
            LEFT JOIN due USING (consolidation_key)
            WHERE target.enabled AND target.priority_tier = 'P1'
        )
        SELECT crawl_state,
               COUNT(*) AS companies,
               ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS pct
        FROM classified
        GROUP BY crawl_state
        ORDER BY companies DESC, crawl_state
        """
    )


@st.cache_data(ttl=60)
def crawl_state_by_tier(tiers: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        WITH site_rollup AS (
            SELECT consolidation_key,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled) AS has_enabled_site,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_crawled_at IS NOT NULL) AS has_attempt,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_success_at IS NOT NULL) AS has_success,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND crawl_status = 'failed') AS has_failed,
                   COUNT(*) FILTER (WHERE verification_status = 'unverified' AND source_type = 'generic_html') AS generic_candidates,
                   COUNT(*) FILTER (WHERE verification_status = 'unverified' AND source_type <> 'generic_html') AS structured_candidates,
                   COUNT(*) FILTER (WHERE verification_status = 'unverified') AS unverified_candidates
            FROM jobpush.career_sites
            GROUP BY consolidation_key
        ), due AS (
            SELECT consolidation_key, COUNT(*) FILTER (WHERE is_due) AS due_sites
            FROM jobpush.crawl_schedule_queue
            GROUP BY consolidation_key
        ), classified AS (
            SELECT target.priority_tier,
                   CASE
                       WHEN COALESCE(site.has_success, FALSE) THEN '01 successfully crawled'
                       WHEN COALESCE(site.has_failed, FALSE) THEN '02 adapter/site failed'
                       WHEN COALESCE(due.due_sites, 0) > 0 THEN '03 enabled and due'
                       WHEN COALESCE(site.has_enabled_site, FALSE) THEN '04 enabled not due'
                       WHEN COALESCE(site.structured_candidates, 0) > 0 THEN '05 structured candidate not enabled'
                       WHEN COALESCE(site.generic_candidates, 0) > 0 THEN '06 generic HTML needs resolution'
                       WHEN target.discovery_status = 'pending' THEN '07 not searched yet'
                       ELSE '08 searched no usable candidate'
                   END AS crawl_state
            FROM jobpush.crawl_targets target
            LEFT JOIN site_rollup site USING (consolidation_key)
            LEFT JOIN due USING (consolidation_key)
            WHERE target.enabled AND target.priority_tier = ANY(%s)
        )
        SELECT priority_tier,
               crawl_state,
               COUNT(*) AS companies,
               ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY priority_tier), 0), 2) AS pct_within_tier
        FROM classified
        GROUP BY priority_tier, crawl_state
        ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
                 crawl_state
        """,
        (list(tiers),),
    )


@st.cache_data(ttl=60)
def generic_blocker_template_summary(tiers: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        WITH site_rollup AS (
            SELECT consolidation_key,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled) AS has_enabled_site,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_success_at IS NOT NULL) AS has_success
            FROM jobpush.career_sites
            GROUP BY consolidation_key
        ), generic_sites AS (
            SELECT target.priority_tier,
                   target.consolidation_key,
                   lower(regexp_replace(coalesce(site.normalized_domain, split_part(regexp_replace(site.site_url, '^https?://', ''), '/', 1)), '^www\\.', '')) AS host,
                   lower(regexp_replace(regexp_replace(site.site_url, '^https?://[^/]+', ''), '[?#].*$', '')) AS path
            FROM jobpush.career_sites site
            JOIN jobpush.crawl_targets target USING (consolidation_key)
            LEFT JOIN site_rollup rollup USING (consolidation_key)
            WHERE target.enabled
              AND target.priority_tier = ANY(%s)
              AND site.source_type = 'generic_html'
              AND site.verification_status = 'unverified'
              AND site.crawl_enabled = FALSE
              AND NOT COALESCE(rollup.has_enabled_site, FALSE)
              AND NOT COALESCE(rollup.has_success, FALSE)
        ), classified AS (
            SELECT *,
                   CASE
                       WHEN host LIKE '%%myworkdayjobs.com' THEN 'workday domain missed'
                       WHEN host LIKE '%%greenhouse.io' THEN 'greenhouse domain missed'
                       WHEN host LIKE '%%lever.co' THEN 'lever domain missed'
                       WHEN host LIKE '%%ashbyhq.com' THEN 'ashby domain missed'
                       WHEN host LIKE '%%smartrecruiters.com' THEN 'smartrecruiters domain missed'
                       WHEN host LIKE '%%icims.com' THEN 'icims domain missed'
                       WHEN host LIKE '%%successfactors.%%' OR host LIKE '%%successfactors.com' THEN 'successfactors domain missed'
                       WHEN host LIKE '%%oraclecloud.com' THEN 'oracle cloud domain missed'
                       WHEN path ~ '(career|careers|job|jobs|openings|opportunities)' THEN 'corporate careers page'
                       ELSE 'generic/corporate page'
                   END AS template_family
            FROM generic_sites
        )
        SELECT priority_tier,
               template_family,
               COUNT(DISTINCT consolidation_key) AS companies,
               COUNT(*) AS site_rows,
               ROUND(100.0 * COUNT(DISTINCT consolidation_key) / NULLIF(SUM(COUNT(DISTINCT consolidation_key)) OVER (PARTITION BY priority_tier), 0), 2) AS pct_within_tier
        FROM classified
        GROUP BY priority_tier, template_family
        ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
                 companies DESC, template_family
        """,
        (list(tiers),),
    )


@st.cache_data(ttl=60)
def p1_rank_coverage() -> pd.DataFrame:
    return query(
        """
        WITH ranked AS (
            SELECT target.*,
                   ROW_NUMBER() OVER (
                       ORDER BY priority_score DESC NULLS LAST, canonical_name
                   ) AS priority_rank
            FROM jobpush.crawl_targets target
            WHERE target.enabled AND target.priority_tier = 'P1'
        ), site_rollup AS (
            SELECT consolidation_key,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled) AS has_enabled_site,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_crawled_at IS NOT NULL) AS has_attempt,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_success_at IS NOT NULL) AS has_success,
                   BOOL_OR(verification_status = 'verified' AND crawl_enabled AND crawl_status = 'failed') AS has_failed
            FROM jobpush.career_sites
            GROUP BY consolidation_key
        ), cohorts AS (
            SELECT 'P1 top 500' AS cohort, * FROM ranked WHERE priority_rank <= 500
            UNION ALL
            SELECT 'P1 top 1000' AS cohort, * FROM ranked WHERE priority_rank <= 1000
            UNION ALL
            SELECT 'All P1' AS cohort, * FROM ranked
        )
        SELECT cohort,
               COUNT(*) AS companies,
               COUNT(*) FILTER (WHERE COALESCE(site.has_enabled_site, FALSE)) AS enabled_site_companies,
               COUNT(*) FILTER (WHERE COALESCE(site.has_attempt, FALSE)) AS attempted_companies,
               COUNT(*) FILTER (WHERE COALESCE(site.has_success, FALSE)) AS succeeded_companies,
               COUNT(*) FILTER (WHERE COALESCE(site.has_failed, FALSE)) AS failed_companies,
               ROUND(100.0 * COUNT(*) FILTER (WHERE COALESCE(site.has_success, FALSE)) / NULLIF(COUNT(*), 0), 2) AS success_pct,
               ROUND(100.0 * COUNT(*) FILTER (WHERE COALESCE(site.has_attempt, FALSE)) / NULLIF(COUNT(*), 0), 2) AS attempted_pct
        FROM cohorts
        LEFT JOIN site_rollup site USING (consolidation_key)
        GROUP BY cohort
        ORDER BY CASE cohort WHEN 'P1 top 500' THEN 0 WHEN 'P1 top 1000' THEN 1 ELSE 2 END
        """
    )


@st.cache_data(ttl=60)
def current_failure_reasons() -> pd.DataFrame:
    return query(
        """
        WITH failed AS (
            SELECT target.priority_tier,
                   target.canonical_name,
                   site.source_type,
                   site.site_url,
                   site.last_error,
                   CASE
                       WHEN site.last_error ILIKE '%%404%%' THEN 'wrong_or_stale_ats_url'
                       WHEN site.last_error ILIKE '%%422%%' OR site.last_error ILIKE '%%workday%%' THEN 'adapter_payload_or_endpoint'
                       WHEN site.last_error ILIKE '%%empty title%%' OR site.last_error ILIKE '%%missing title%%' THEN 'empty_or_bad_payload'
                       WHEN site.last_error IS NULL OR site.last_error = '' THEN 'unknown_failed_state'
                       ELSE 'other_adapter_or_site_error'
                   END AS failure_reason,
                   CASE
                       WHEN site.last_error ILIKE '%%404%%' THEN 'Rediscover career URL / ATS slug'
                       WHEN site.last_error ILIKE '%%422%%' OR site.last_error ILIKE '%%workday%%' THEN 'Patch adapter request or endpoint handling'
                       WHEN site.last_error ILIKE '%%empty title%%' OR site.last_error ILIKE '%%missing title%%' THEN 'Skip malformed jobs and retry'
                       ELSE 'Inspect recent run log and group with similar failures'
                   END AS next_action
            FROM jobpush.career_sites site
            JOIN jobpush.crawl_targets target USING (consolidation_key)
            WHERE site.verification_status = 'verified'
              AND site.crawl_enabled
              AND site.crawl_status = 'failed'
              AND target.priority_tier IN ('P0','P1','P2','P3')
        )
        SELECT failure_reason,
               priority_tier,
               source_type,
               next_action,
               COUNT(*) AS sites,
               STRING_AGG(canonical_name, ', ' ORDER BY canonical_name) AS example_companies
        FROM failed
        GROUP BY failure_reason, priority_tier, source_type, next_action
        ORDER BY sites DESC, priority_tier, source_type, failure_reason
        """
    )


@st.cache_data(ttl=60)
def ml_status() -> tuple[pd.DataFrame, pd.DataFrame]:
    title_labels = query(
        """
        SELECT classification_status, COALESCE(rule_version, 'manual_or_unknown') AS rule_version, COUNT(*) AS titles
        FROM jobpush.job_title_labels
        GROUP BY classification_status, COALESCE(rule_version, 'manual_or_unknown')
        ORDER BY titles DESC
        """
    )
    ml_runs = query(
        """
        SELECT model_version, classification_status AS predicted_status, applied,
               COUNT(*) AS titles,
               ROUND(AVG(confidence)::numeric, 3) AS avg_confidence
        FROM jobpush.job_title_ml_classifications
        GROUP BY model_version, classification_status, applied
        ORDER BY model_version DESC, applied DESC, titles DESC
        LIMIT 20
        """
    )
    return title_labels, ml_runs


@st.cache_data(ttl=60)
def p1_score_distribution() -> pd.DataFrame:
    return query(
        """
        SELECT priority_score, COUNT(*) AS companies
        FROM jobpush.crawl_targets
        WHERE enabled AND priority_tier = 'P1'
        GROUP BY priority_score
        ORDER BY priority_score DESC
        """
    )


@st.cache_data(ttl=60)
def company_targets(tiers: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        WITH ranked_targets AS (
            SELECT target.*,
                   ROW_NUMBER() OVER (
                       PARTITION BY target.priority_tier
                       ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name
                   ) AS priority_rank_in_tier
            FROM jobpush.crawl_targets target
            WHERE target.enabled
        )
        SELECT target.consolidation_key, target.canonical_name,
               target.priority_tier, target.priority_score,
               target.priority_rank_in_tier,
               target.priority_source, target.discovery_status,
               consolidated.lca_count, consolidated.target_role_lca_count,
               consolidated.target_role_score, consolidated.lca_count_score,
               consolidated.chicago_score, consolidated.product_role_score,
               consolidated.product_manager_score, consolidated.salary_score,
               consolidated.linkedin_top_employer_score,
               consolidated.employer_city, consolidated.employer_state
        FROM ranked_targets target
        JOIN jobpush.company_targets_consolidated consolidated USING (consolidation_key)
        WHERE target.priority_tier = ANY(%s)
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
                 target.priority_rank_in_tier
        """,
        (list(tiers),),
    )


@st.cache_data(ttl=60)
def site_review_queue(
    limit: int = 500,
    tiers: tuple[str, ...] = ("P0", "P1"),
    statuses: tuple[str, ...] = ("REVIEW_CANDIDATES", "VERIFIED"),
    company_search: str = "",
) -> pd.DataFrame:
    company_search = normalize_search_query(company_search)
    return query(
        """
        SELECT review.review_rank, review.consolidation_key, review.priority_tier, review.priority_score,
               row_number() OVER (
                   PARTITION BY review.priority_tier
                   ORDER BY review.priority_score DESC NULLS LAST, review.canonical_name
               ) AS priority_rank_in_tier,
               review.canonical_name, review.action_status, review.potential_p0_signal,
               review.candidate_count,
               review.candidate_1_site_id, review.candidate_1_source, review.candidate_1_url,
               review.candidate_2_site_id, review.candidate_2_source, review.candidate_2_url,
               review.candidate_3_site_id, review.candidate_3_source, review.candidate_3_url,
               review.verified_site_id, review.verified_source, review.verified_url,
               review.discovery_status, review.employer_city, review.employer_state,
               review.lca_count, review.target_role_lca_count
        FROM jobpush.career_site_review_workbench review
        LEFT JOIN jobpush.company_identity_search identity USING (consolidation_key)
        WHERE review.priority_tier = ANY(%s)
          AND review.action_status = ANY(%s)
          AND (
              %s = ''
              OR concat_ws(' ', review.canonical_name, review.consolidation_key, review.priority_tier,
                           review.action_status, review.discovery_status, review.employer_city, review.employer_state,
                           review.candidate_1_url, review.candidate_2_url, review.candidate_3_url, review.verified_url,
                           identity.search_text)
                 ILIKE ALL (ARRAY(
                     SELECT '%%' || term || '%%'
                     FROM regexp_split_to_table(%s, '\\s+') AS term
                     WHERE term <> ''
                 ))
          )
        ORDER BY CASE review.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
                 CASE review.action_status WHEN 'REVIEW_CANDIDATES' THEN 0 WHEN 'VERIFIED' THEN 1 ELSE 2 END,
                 review.priority_score DESC NULLS LAST,
                 review.review_rank
        LIMIT %s
        """,
        (list(tiers), list(statuses), company_search, company_search, limit),
    )


@st.cache_data(ttl=60)
def title_review_queue(limit: int = 2000) -> pd.DataFrame:
    frame = query(
        """
        WITH latest_ml AS (
            SELECT DISTINCT ON (normalized_title)
                   normalized_title,
                   confidence AS ml_confidence,
                   classification_status AS ml_suggestion
            FROM jobpush.job_title_ml_classifications
            ORDER BY normalized_title, created_at DESC, ml_classification_id DESC
        )
        SELECT queue.normalized_title, queue.example_title, example_posting.job_url AS example_job_url,
               queue.active_posting_count,
               queue.company_count, queue.suggestion_reason, queue.matched_soc_codes,
               queue.matched_soc_titles,
               latest_ml.ml_suggestion,
               latest_ml.ml_confidence,
               ROUND((1 - COALESCE(latest_ml.ml_confidence, 0.5))::numeric, 5) AS ml_uncertainty,
               (
                   queue.active_posting_count
                   + queue.company_count * 3
                   + CASE WHEN latest_ml.ml_confidence IS NULL THEN 25
                          ELSE ROUND((1 - latest_ml.ml_confidence) * 50)::integer
                     END
               ) AS learning_priority_score
        FROM jobpush.job_title_review_queue queue
        LEFT JOIN latest_ml USING (normalized_title)
        LEFT JOIN LATERAL (
            SELECT posting.job_url
            FROM jobpush.job_postings_us posting
            WHERE posting.normalized_title = queue.normalized_title
              AND posting.active
              AND posting.job_url IS NOT NULL
            ORDER BY posting.last_seen_at DESC, posting.first_seen_at DESC
            LIMIT 1
        ) example_posting ON TRUE
        ORDER BY learning_priority_score DESC,
                 queue.active_posting_count DESC,
                 queue.company_count DESC,
                 queue.normalized_title
        LIMIT %s
        """,
        (limit,),
    )
    frame["人工判断（请填写）"] = ""
    frame["标准岗位（可选）"] = ""
    frame["判断原因/备注（可选）"] = ""
    return frame


def csv_bytes(frame: pd.DataFrame) -> bytes:
    return frame.to_csv(index=False).encode("utf-8-sig")


def normalize_company_query(value: str) -> str:
    return " ".join((value or "").strip().split())


def normalize_search_query(value: str) -> str:
    return " ".join((value or "").strip().split())


def linkedin_company_search_url(company_name: str) -> str:
    return f"https://www.linkedin.com/search/results/companies/?keywords={quote_plus(company_name)}"


def classify_career_url(raw_url: str) -> dict[str, str | None]:
    raw_url = (raw_url or "").strip()
    if raw_url and not raw_url.startswith(("http://", "https://")):
        raw_url = f"https://{raw_url}"
    parsed = urlparse(raw_url)
    host = parsed.netloc.casefold().split(":", 1)[0].removeprefix("www.")
    netloc = parsed.netloc
    path_parts = [part for part in parsed.path.split("/") if part]
    source_type = "generic_html"
    source_key = None
    site_kind = "careers"
    canonical_path = parsed.path.rstrip("/") or "/"

    if host in {"boards.greenhouse.io", "job-boards.greenhouse.io"} and path_parts:
        source_key = (parse_qs(parsed.query).get("for") or [None])[0] if path_parts[0] == "embed" else path_parts[0]
        if source_key:
            source_type, site_kind = "greenhouse", "ats_feed"
            canonical_path = f"/{source_key}"
    elif host in {"jobs.lever.co", "jobs.eu.lever.co"} and path_parts:
        source_type, source_key, site_kind = "lever", path_parts[0], "ats_feed"
        canonical_path = f"/{source_key}"
    elif host == "jobs.ashbyhq.com" and path_parts:
        source_type, source_key, site_kind = "ashby", path_parts[0], "ats_feed"
        canonical_path = f"/{source_key}"
    elif host == "careers.smartrecruiters.com" and path_parts:
        source_type, source_key, site_kind = "smartrecruiters", path_parts[0], "ats_feed"
        canonical_path = f"/{source_key}"
    elif host == "api.smartrecruiters.com" and len(path_parts) >= 3 and path_parts[:2] == ["v1", "companies"]:
        source_type, source_key, site_kind = "smartrecruiters", path_parts[2], "ats_feed"
        host = "careers.smartrecruiters.com"
        netloc = host
        canonical_path = f"/{source_key}"
    elif host == "jobs.jobvite.com" and path_parts:
        source_type = "jobvite"
        source_key = path_parts[1] if path_parts[0] == "careers" and len(path_parts) >= 2 else path_parts[0]
        site_kind = "ats_feed"
        canonical_path = f"/{source_key}/jobs"
    elif host in {"apply.workable.com", "jobs.workable.com"} and path_parts:
        source_type, source_key, site_kind = "workable", path_parts[0], "ats_feed"
        canonical_path = f"/{source_key}"
    elif host == "recruiting.paylocity.com" and len(path_parts) >= 3:
        source_type, source_key, site_kind = "paylocity", "/".join(path_parts[:3]), "ats_feed"
        canonical_path = "/" + source_key
    elif host == "ats.rippling.com" and path_parts:
        source_type, source_key, site_kind = "rippling", path_parts[0], "ats_feed"
        canonical_path = f"/{source_key}/jobs"
    elif host.endswith("myworkdayjobs.com"):
        source_type, source_key, site_kind = "workday", host, "ats_feed"
    elif host.endswith("icims.com"):
        source_type, source_key, site_kind = "icims", host, "ats_feed"
    elif host.endswith("successfactors.com"):
        source_type, source_key, site_kind = "successfactors", host, "ats_feed"
    elif host.endswith("phenompeople.com") or host.endswith("phenom.com"):
        source_type, source_key, site_kind = "phenom", host, "ats_feed"
    elif host.endswith("talentbrew.com"):
        source_type, source_key, site_kind = "talentbrew", host, "ats_feed"
    elif host == "sjobs.brassring.com" or host.endswith(".brassring.com"):
        source_type, source_key, site_kind = "brassring", host, "ats_feed"
    elif host.endswith("oraclecloud.com") and "CandidateExperience" in parsed.path and "/sites/" in parsed.path:
        site_index = path_parts.index("sites") if "sites" in path_parts else -1
        source_key = path_parts[site_index + 1] if site_index >= 0 and site_index + 1 < len(path_parts) else host
        source_type, site_kind = "oracle_cloud", "ats_feed"
        locale = "/".join(path_parts[:site_index]) if site_index > 0 else "hcmUI/CandidateExperience/en"
        canonical_path = f"/{locale}/sites/{source_key}/jobs"
    elif host == "amazon.jobs" and any(term in parsed.path.casefold() for term in CAREER_TERMS):
        source_type, source_key, site_kind = "amazon_jobs", host, "ats_feed"
    elif host == "www.google.com" and "/about/careers/applications/jobs/results" in parsed.path:
        source_type, source_key, site_kind = "google_jobs", host, "ats_feed"
    elif host == "careers.cognizant.com" and "/jobs" in parsed.path:
        source_type, source_key, site_kind = "cognizant_jobs", host, "ats_feed"
    elif host == "jobs.uber.com" and "/jobs" in parsed.path:
        source_type, source_key, site_kind = "uber_jobs", host, "ats_feed"
    elif host.endswith("eightfold.ai") or host in {"portal.careers.hsbc.com", "jobs.ericsson.com"}:
        source_type, source_key, site_kind = "eightfold", host, "ats_feed"
    elif not any(term in parsed.path.casefold() for term in CAREER_TERMS):
        site_kind = "corporate"

    canonical_query = parsed.query if source_type in {"generic_html", "uber_jobs"} else ""
    canonical_url = urlunparse((parsed.scheme or "https", netloc, canonical_path, "", canonical_query, ""))
    scope_method = "local_filter" if source_type in LOCAL_FILTER_SOURCE_TYPES | {"uber_jobs"} else "unknown"
    if source_type in {"amazon_jobs", "apple_jobs", "cognizant_jobs", "eightfold", "google_jobs", "oracle_cloud"}:
        scope_method = "server_filter"
    return {
        "site_url": canonical_url,
        "normalized_domain": host[:500],
        "site_kind": site_kind,
        "source_type": source_type,
        "source_key": source_key,
        "target_country_code": "US" if source_type in SUPPORTED_SOURCE_TYPES else None,
        "scope_method": scope_method,
    }


def clear_dashboard_caches() -> None:
    for cached_fn in [
        apply_job_summary,
        daily_activity,
        crawl_funnel,
        coverage_by_tier,
        review_workbench_summary,
        crawl_rank_coverage,
        crawl_rollout_by_tier,
        today_crawl_progress,
        recent_crawl_runs,
        crawl_completion_summary,
        p1_blocker_distribution,
        p1_rank_coverage,
        current_failure_reasons,
        ml_status,
        p1_score_distribution,
        company_targets,
        site_review_queue,
        title_review_queue,
        jobs,
        company_jobs,
        company_lca_roles,
        company_lca_roles_by_key,
        company_lookup_options,
        lca_soc_review_table,
        lca_raw_job_review_sample,
        recent_failures,
    ]:
        try:
            cached_fn.clear()
        except Exception:
            pass


def apply_title_review(normalized_title: str, status: str, canonical_role: str, reason: str) -> None:
    execute(
        "SELECT jobpush.apply_manual_job_title_label(%s, %s, %s, %s, 'nicole')",
        (normalized_title, status, canonical_role, reason),
    )


def set_manual_crawl_priority(consolidation_key: str, tier: str, reason: str) -> None:
    execute(
        "SELECT jobpush.set_manual_crawl_priority(%s, %s, %s, 'nicole')",
        (consolidation_key, tier, reason),
    )


def update_site_scope_and_due(site_id: int, source_type: str, notes: str | None = None) -> None:
    scope_method = "local_filter" if source_type in LOCAL_FILTER_SOURCE_TYPES | {"uber_jobs"} else "unknown"
    if source_type in {"amazon_jobs", "apple_jobs", "cognizant_jobs", "eightfold", "google_jobs", "oracle_cloud"}:
        scope_method = "server_filter"
    execute(
        """
        UPDATE jobpush.career_sites site
        SET target_country_code = CASE WHEN %s = ANY(%s) THEN 'US' ELSE target_country_code END,
            scope_method = %s,
            crawl_status = 'pending',
            next_crawl_at = now(),
            review_notes = COALESCE(NULLIF(%s, ''), review_notes),
            updated_at = now()
        WHERE site_id = %s
        """,
        (source_type, list(SUPPORTED_SOURCE_TYPES), scope_method, notes, int(site_id)),
    )


def review_existing_career_site(site_id: int, decision: str, source_type: str, notes: str) -> None:
    execute(
        "SELECT jobpush.review_career_site(%s, %s, 'nicole', %s)",
        (int(site_id), decision, notes),
    )
    if decision == "verified":
        update_site_scope_and_due(site_id, source_type, notes)


def import_manual_career_site(consolidation_key: str, raw_url: str, notes: str) -> dict[str, str | int | None]:
    classified = classify_career_url(raw_url)
    execute(
        """
        INSERT INTO jobpush.career_sites (
            consolidation_key, site_url, normalized_domain, site_kind,
            source_type, source_key, discovery_source, verification_status,
            crawl_enabled, crawl_status, target_country_code, scope_method,
            next_crawl_at, reviewed_at, reviewed_by, review_notes, updated_at
        ) VALUES (
            %s, %s, %s, %s,
            %s, NULLIF(%s, ''), 'manual_dashboard', 'verified',
            TRUE, 'pending', %s, %s,
            now(), now(), 'nicole', NULLIF(%s, ''), now()
        )
        ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
            normalized_domain = EXCLUDED.normalized_domain,
            site_kind = EXCLUDED.site_kind,
            source_type = EXCLUDED.source_type,
            source_key = EXCLUDED.source_key,
            discovery_source = EXCLUDED.discovery_source,
            verification_status = 'verified',
            crawl_enabled = TRUE,
            crawl_status = 'pending',
            target_country_code = EXCLUDED.target_country_code,
            scope_method = EXCLUDED.scope_method,
            next_crawl_at = now(),
            reviewed_at = now(),
            reviewed_by = 'nicole',
            review_notes = EXCLUDED.review_notes,
            updated_at = now()
        """,
        (
            consolidation_key,
            classified["site_url"],
            classified["normalized_domain"],
            classified["site_kind"],
            classified["source_type"],
            classified["source_key"] or "",
            classified["target_country_code"],
            classified["scope_method"],
            notes,
        ),
    )
    execute(
        """
        UPDATE jobpush.crawl_targets
        SET discovery_status = 'found', next_discovery_at = NULL, updated_at = now()
        WHERE consolidation_key = %s
        """,
        (consolidation_key,),
    )
    site = query(
        """
        SELECT site_id
        FROM jobpush.career_sites
        WHERE consolidation_key = %s
          AND site_url = %s
        ORDER BY site_id DESC
        LIMIT 1
        """,
        (consolidation_key, classified["site_url"]),
    )
    classified["site_id"] = int(site.iloc[0]["site_id"]) if not site.empty else None
    return classified


def trigger_inline_due_crawl(limit: int = 1) -> tuple[bool, str]:
    if os.environ.get("JOBPUSH_ENABLE_INLINE_CRAWL") != "1":
        return False, "Inline crawl is disabled; site was marked due now and the scheduler/GitHub Action will pick it up."
    try:
        result = subprocess.run(
            ["bash", "db/run_due_crawl_batch.sh", str(limit)],
            cwd=os.environ.get("JOBPUSH_REPO_DIR", os.getcwd()),
            check=False,
            capture_output=True,
            text=True,
            timeout=300,
        )
    except Exception as exc:
        return False, f"Could not trigger inline crawl: {exc}"
    output = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part)
    return result.returncode == 0, output[-4000:]


def trigger_inline_site_crawl(site_id: int | None) -> tuple[bool, str]:
    if not site_id:
        return trigger_inline_due_crawl(1)
    if os.environ.get("JOBPUSH_ENABLE_INLINE_CRAWL") != "1":
        return False, "Inline crawl is disabled; site was marked due now and the scheduler/GitHub Action will pick it up."
    env = os.environ.copy()
    env["SITE_ID_FILTER"] = str(int(site_id))
    try:
        result = subprocess.run(
            ["bash", "db/run_due_crawl_batch.sh", "1"],
            cwd=os.environ.get("JOBPUSH_REPO_DIR", os.getcwd()),
            env=env,
            check=False,
            capture_output=True,
            text=True,
            timeout=300,
        )
    except Exception as exc:
        return False, f"Could not trigger inline crawl for site_id={site_id}: {exc}"
    output = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part)
    return result.returncode == 0, output[-4000:]


@st.cache_data(ttl=60)
def jobs(
    start_date,
    end_date,
    search: str,
    tiers: tuple[str, ...],
    role_statuses: tuple[str, ...],
    app_statuses: tuple[str, ...],
    row_limit: int,
) -> pd.DataFrame:
    search = normalize_search_query(search)
    return query(
        """
        WITH ranked_targets AS (
            SELECT consolidation_key, priority_score,
                   ROW_NUMBER() OVER (
                       PARTITION BY priority_tier
                       ORDER BY priority_score DESC NULLS LAST, canonical_name
                   ) AS priority_rank_in_tier
            FROM jobpush.crawl_targets
            WHERE enabled
        )
        SELECT job.site_id, job.external_job_id, job.canonical_name, job.priority_tier,
               ranked.priority_score, ranked.priority_rank_in_tier, job.title,
               location, category, employment_type, role_status, canonical_role,
               CASE
                   WHEN role_status = 'target' AND canonical_role = 'candidate_profile_track: product' THEN 'stack_1_business_product_data'
                   WHEN role_status = 'target' AND canonical_role = 'candidate_profile_track: analyst/bi' THEN 'stack_1_business_product_data'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%%product%%manager%%'
                       OR normalized_title LIKE '%%business%%analyst%%'
                       OR normalized_title LIKE '%%data%%analyst%%'
                       OR normalized_title LIKE '%%strategy%%analyst%%'
                       OR normalized_title LIKE '%%operations%%analyst%%'
                       OR normalized_title LIKE '%%program%%manager%%'
                       OR normalized_title LIKE '%%project%%manager%%'
                       OR normalized_title LIKE '%%implementation%%'
                       OR normalized_title LIKE '%%consultant%%'
                       OR normalized_title LIKE '%%consulting%%'
                       OR normalized_title LIKE '%%coordinator%%'
                       OR canonical_role ILIKE '%%financial%%analyst%%'
                       OR canonical_role ILIKE '%%financial and investment%%'
                       OR canonical_role ILIKE '%%market research%%'
                   ) THEN 'stack_1_business_product_data'
                   WHEN role_status = 'target' AND canonical_role IN (
                       'candidate_profile_track: solutions/systems',
                       'candidate_profile_track: applied_ai'
                   ) THEN 'stack_2_ai_solutions_systems_data'
                   WHEN role_status = 'target'
                        AND canonical_role = 'candidate_profile_track: software/data'
                        AND (normalized_title LIKE '%%data%%engineer%%'
                             OR normalized_title LIKE '%%analytics%%engineer%%'
                             OR normalized_title LIKE '%%data%%architect%%'
                             OR normalized_title LIKE '%%database%%administrator%%'
                             OR normalized_title LIKE '%%database%%admin%%') THEN 'stack_2_ai_solutions_systems_data'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%%systems%%analyst%%'
                       OR normalized_title LIKE '%%information%%system%%'
                   ) THEN 'stack_2_ai_solutions_systems_data'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%%software%%'
                       OR normalized_title LIKE '%%quality%%assurance%%'
                       OR normalized_title LIKE '%% qa %%'
                       OR normalized_title LIKE '%%test engineer%%'
                       OR normalized_title LIKE '%%tester%%'
                       OR normalized_title LIKE '%%devops%%'
                       OR normalized_title LIKE '%%cloud%%'
                       OR normalized_title LIKE '%%site reliability%%'
                       OR normalized_title LIKE '%%sre%%'
                       OR normalized_title LIKE '%%security%%'
                       OR normalized_title LIKE '%%cyber%%'
                       OR canonical_role ILIKE '%%network%%'
                       OR canonical_role ILIKE '%%systems administrator%%'
                       OR canonical_role = 'candidate_profile_track: software/data'
                   ) THEN 'stack_4_sde'
                   WHEN role_status = 'target' AND canonical_role = 'candidate_profile_track: customer_success' THEN 'stack_3_customer_success'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%%customer%%success%%'
                       OR normalized_title LIKE '%%technical%%account%%'
                       OR normalized_title LIKE '%%relationship%%manager%%'
                       OR normalized_title LIKE '%%support%%'
                       OR normalized_title LIKE '%%specialist%%'
                       OR normalized_title LIKE '%%administrator%%'
                       OR normalized_title LIKE '%%admin%%'
                   ) THEN 'stack_3_customer_success'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%%sales%%'
                       OR normalized_title LIKE '%%marketing%%'
                       OR normalized_title LIKE '%%business%%development%%'
                       OR canonical_role = 'candidate_profile_track: marketing automation'
                   ) THEN 'stack_3_gtm'
                   WHEN role_status = 'target' THEN 'stack_5_possible_target'
                   WHEN role_status = 'review' THEN 'needs_review'
                   ELSE 'excluded_non_target'
               END AS role_stack,
               CASE
                   WHEN role_status = 'non_target' THEN 'excluded_non_target'
                   WHEN role_status = 'review' THEN 'needs_review'
                   WHEN canonical_role = 'candidate_profile_track: product' THEN 'product_manager'
                   WHEN canonical_role = 'candidate_profile_track: analyst/bi' THEN 'data_analytics_bi'
                   WHEN canonical_role = 'candidate_profile_track: solutions/systems' THEN 'systems_engineering'
                   WHEN canonical_role = 'candidate_profile_track: applied_ai' THEN 'applied_ai'
                   WHEN canonical_role = 'candidate_profile_track: customer_success' THEN 'customer_success'
                   WHEN canonical_role = 'candidate_profile_track: marketing automation' THEN 'marketing'
                   WHEN canonical_role = 'candidate_profile_track: software/data'
                        AND (normalized_title LIKE '%%data%%engineer%%'
                             OR normalized_title LIKE '%%analytics%%engineer%%'
                             OR normalized_title LIKE '%%data%%architect%%') THEN 'data_engineering'
                   WHEN canonical_role = 'candidate_profile_track: software/data' THEN 'software_engineering'
                   WHEN normalized_title LIKE '%%intern%%'
                        OR normalized_title LIKE '%%internship%%'
                        OR normalized_title LIKE '%%co op%%'
                        OR normalized_title LIKE '%%co-op%%' THEN 'internship'
                   WHEN normalized_title LIKE '%%forward deployed engineer%%'
                        OR normalized_title LIKE '%%forward-deployed engineer%%' THEN 'forward_deployed_engineer'
                   WHEN normalized_title LIKE '%%ai full stack%%'
                        OR normalized_title LIKE '%%ai engineer%%'
                        OR normalized_title LIKE '%%gtm engineer%%' THEN 'applied_ai'
                   WHEN normalized_title LIKE '%%product%%manager%%' THEN 'product_manager'
                   WHEN normalized_title LIKE '%%program%%manager%%' THEN 'program_manager'
                   WHEN normalized_title LIKE '%%project%%manager%%' THEN 'project_manager'
                   WHEN normalized_title LIKE '%%system%%engineer%%'
                        OR normalized_title LIKE '%%systems%%engineer%%'
                        OR normalized_title LIKE '%%systems%%analyst%%'
                        OR normalized_title LIKE '%%information%%system%%' THEN 'systems_engineering'
                   WHEN normalized_title LIKE '%%software%%engineer%%'
                        OR normalized_title LIKE '%%software%%developer%%'
                        OR normalized_title LIKE '%%fullstack%%'
                        OR normalized_title LIKE '%%full stack%%' THEN 'software_engineering'
                   WHEN normalized_title LIKE '%%data%%scientist%%'
                        OR normalized_title LIKE '%%machine%%learning%%'
                        OR normalized_title LIKE '%%ml engineer%%' THEN 'data_science_ml'
                   WHEN normalized_title LIKE '%%data%%engineer%%'
                        OR normalized_title LIKE '%%analytics%%engineer%%'
                        OR normalized_title LIKE '%%data%%architect%%'
                        OR normalized_title LIKE '%%database%%administrator%%'
                        OR normalized_title LIKE '%%database%%admin%%' THEN 'data_engineering'
                   WHEN normalized_title LIKE '%%data%%analyst%%'
                        OR normalized_title LIKE '%%business intelligence%%'
                        OR normalized_title LIKE '%%bi analyst%%' THEN 'data_analytics_bi'
                   WHEN normalized_title LIKE '%%business%%analyst%%' THEN 'business_analyst'
                   WHEN normalized_title LIKE '%%operations%%analyst%%'
                        OR normalized_title LIKE '%%strategy%%analyst%%' THEN 'strategy_operations'
                   WHEN normalized_title LIKE '%%customer%%success%%'
                        OR normalized_title LIKE '%%technical%%account%%'
                        OR normalized_title LIKE '%%relationship%%manager%%' THEN 'customer_success'
                   WHEN normalized_title LIKE '%%technical%%support%%'
                        OR normalized_title LIKE '%%technical%%specialist%%'
                        OR normalized_title LIKE '%%technical%%expert%%' THEN 'technical_support'
                   WHEN normalized_title LIKE '%%marketing%%' THEN 'marketing'
                   WHEN normalized_title LIKE '%%sales%%' THEN 'sales'
                   WHEN canonical_role ILIKE '%%market research%%' THEN 'marketing'
                   WHEN canonical_role ILIKE '%%financial%%analyst%%'
                        OR canonical_role ILIKE '%%financial and investment%%' THEN 'financial_analyst'
                   WHEN canonical_role ILIKE '%%statistic%%' THEN 'data_analytics_bi'
                   WHEN canonical_role ILIKE '%%information technology project manager%%' THEN 'project_manager'
                   WHEN canonical_role ILIKE '%%network%%'
                        OR canonical_role ILIKE '%%systems administrator%%' THEN 'systems_engineering'
                   WHEN canonical_role ILIKE '%%software developer%%' THEN 'software_engineering'
                   ELSE CONCAT('title:', COALESCE(NULLIF(normalized_title, ''), NULLIF(canonical_role, ''), 'unclassified target title'))
               END AS role_family,
               CASE
                   WHEN normalized_title LIKE '%%intern%%'
                        OR normalized_title LIKE '%%internship%%'
                        OR normalized_title LIKE '%%co op%%'
                        OR normalized_title LIKE '%%co-op%%' THEN 'internship'
                   WHEN normalized_title LIKE '%%new grad%%'
                        OR normalized_title LIKE '%%university grad%%'
                        OR normalized_title LIKE '%%entry level%%'
                        OR normalized_title LIKE '%%early career%%' THEN 'entry_level'
                   WHEN normalized_title LIKE '%%senior%%'
                        OR normalized_title LIKE '%%sr %%'
                        OR normalized_title LIKE '%%staff%%'
                        OR normalized_title LIKE '%%principal%%'
                        OR normalized_title LIKE '%%lead%%'
                        OR normalized_title LIKE '%%director%%'
                        OR normalized_title LIKE '%%vice president%%'
                        OR normalized_title LIKE '%%vp%%' THEN 'senior_or_leadership'
                   ELSE 'regular_full_time'
               END AS seniority_bucket,
               CASE
                   WHEN normalized_title LIKE '%%intern%%'
                        OR normalized_title LIKE '%%internship%%'
                        OR normalized_title LIKE '%%co op%%'
                        OR normalized_title LIKE '%%co-op%%' THEN 'internship'
                   WHEN COALESCE(employment_type, '') ILIKE '%%contract%%'
                        OR normalized_title LIKE '%%contract%%' THEN 'contract'
                   WHEN COALESCE(employment_type, '') ILIKE '%%part%%time%%'
                        OR normalized_title LIKE '%%part time%%' THEN 'part_time'
                   WHEN COALESCE(employment_type, '') ILIKE '%%full%%time%%' THEN 'full_time'
                   ELSE 'full_time_or_unknown'
               END AS employment_bucket,
               CASE
                   WHEN COALESCE(location, '') ILIKE '%%chicago%%'
                        OR COALESCE(location, '') ILIKE '%%illinois%%'
                        OR COALESCE(location, '') ~* '(^|[,/ -])IL($|[,/ -])' THEN 'chicago_or_illinois'
                   WHEN COALESCE(location, '') ILIKE '%%remote%%' THEN 'remote'
                   WHEN COALESCE(location, '') = '' THEN 'location_not_listed'
                   ELSE 'other_us'
               END AS location_bucket,
               application_status,
               first_seen_at, last_seen_at, job_url
        FROM jobpush.dashboard_jobs job
        LEFT JOIN ranked_targets ranked USING (consolidation_key)
        LEFT JOIN jobpush.company_identity_search identity USING (consolidation_key)
        WHERE job.first_seen_at >= (%s::date AT TIME ZONE 'America/Chicago')
          AND job.first_seen_at < ((%s::date + 1) AT TIME ZONE 'America/Chicago')
          AND (
              %s = ''
              OR concat_ws(' ', job.canonical_name, job.title, job.canonical_role,
                           job.location, job.category, job.employment_type,
                           job.priority_tier, job.job_url, identity.search_text)
                 ILIKE ALL (ARRAY(
                     SELECT '%%' || term || '%%'
                     FROM regexp_split_to_table(%s, '\\s+') AS term
                     WHERE term <> ''
                 ))
          )
          AND job.priority_tier = ANY(%s)
          AND job.role_status = ANY(%s)
          AND job.application_status = ANY(%s)
        ORDER BY job.first_seen_at DESC, job.canonical_name, job.title
        LIMIT %s
        """,
        (
            start_date,
            end_date,
            search,
            search,
            list(tiers),
            list(role_statuses),
            list(app_statuses),
            int(row_limit),
        ),
    )


@st.cache_data(ttl=60)
def company_jobs(company: str) -> pd.DataFrame:
    company = normalize_search_query(company)
    return query(
        """
        WITH ranked_targets AS (
            SELECT consolidation_key, priority_score,
                   ROW_NUMBER() OVER (
                       PARTITION BY priority_tier
                       ORDER BY priority_score DESC NULLS LAST, canonical_name
                   ) AS priority_rank_in_tier
            FROM jobpush.crawl_targets
            WHERE enabled
        )
        SELECT job.canonical_name, job.priority_tier,
               ranked.priority_score, ranked.priority_rank_in_tier,
               job.title, job.location,
               job.role_status, job.canonical_role, job.application_status,
               job.first_seen_at, job.last_seen_at, job.job_url
        FROM jobpush.dashboard_jobs job
        LEFT JOIN ranked_targets ranked USING (consolidation_key)
        LEFT JOIN jobpush.company_identity_search identity USING (consolidation_key)
        WHERE %s <> ''
          AND concat_ws(' ', job.canonical_name, job.title, job.canonical_role,
                        job.location, job.priority_tier, job.job_url, identity.search_text)
              ILIKE ALL (ARRAY(
                  SELECT '%%' || term || '%%'
                  FROM regexp_split_to_table(%s, '\\s+') AS term
                  WHERE term <> ''
              ))
        ORDER BY CASE role_status WHEN 'target' THEN 0 WHEN 'review' THEN 1 ELSE 2 END,
                 first_seen_at DESC, title
        LIMIT 1000
        """,
        (company, company),
    )


@st.cache_data(ttl=60)
def company_lookup_options(company: str, limit: int = 25) -> pd.DataFrame:
    company = normalize_search_query(company)
    if not company:
        return pd.DataFrame()
    return query(
        """
        SELECT target.consolidation_key, target.canonical_name,
               target.priority_tier, target.priority_score,
               consolidated.lca_count, consolidated.target_role_lca_count,
               consolidated.employer_city, consolidated.employer_state
        FROM jobpush.crawl_targets target
        JOIN jobpush.company_targets_consolidated consolidated USING (consolidation_key)
        LEFT JOIN jobpush.company_identity_search identity USING (consolidation_key)
        WHERE concat_ws(' ', target.canonical_name, target.consolidation_key,
                        target.priority_tier, consolidated.employer_city,
                        consolidated.employer_state, identity.search_text)
              ILIKE ALL (ARRAY(
                  SELECT '%%' || term || '%%'
                  FROM regexp_split_to_table(%s, '\\s+') AS term
                  WHERE term <> ''
              ))
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 ELSE 3 END,
                 target.priority_score DESC NULLS LAST,
                 target.canonical_name
        LIMIT %s
        """,
        (company, limit),
    )


@st.cache_data(ttl=60)
def company_lca_roles(company: str) -> pd.DataFrame:
    company = normalize_company_query(company)
    if not company:
        return pd.DataFrame()
    return query(
        """
        WITH matched_companies AS (
            SELECT consolidated.consolidation_key, consolidated.canonical_name, consolidated.member_feins
            FROM jobpush.company_targets_consolidated consolidated
            LEFT JOIN jobpush.company_identity_search identity USING (consolidation_key)
            WHERE identity.search_text ILIKE '%%' || %s || '%%'
               OR consolidated.canonical_name ILIKE '%%' || %s || '%%'
            ORDER BY consolidated.priority_score DESC NULLS LAST, consolidated.canonical_name
            LIMIT 20
        ), member_feins AS (
            SELECT matched.consolidation_key, matched.canonical_name,
                   unnest(matched.member_feins) AS employer_fein
            FROM matched_companies matched
        ), lca AS (
            SELECT member.consolidation_key, member.canonical_name,
                   jobpush.normalize_soc_code(case_row.soc_code) AS normalized_soc_code,
                   COALESCE(NULLIF(case_row.soc_title, ''), '(missing SOC title)') AS soc_title,
                   COALESCE(NULLIF(case_row.job_title, ''), '(missing raw title)') AS raw_job_title,
                   case_row.case_status, case_row.decision_date,
                   case_row.wage_rate_of_pay_from, case_row.wage_unit_of_pay
            FROM member_feins member
            JOIN public.lca_cases case_row
              ON case_row.employer_fein = member.employer_fein
        )
        SELECT lca.canonical_name,
               lca.normalized_soc_code,
               lca.soc_title,
               lca.raw_job_title,
               CASE WHEN target.normalized_soc_code IS NOT NULL THEN TRUE ELSE FALSE END AS current_target_soc,
               COUNT(*) AS lca_count,
               COUNT(*) FILTER (WHERE lca.case_status = 'Certified') AS certified_count,
               MIN(lca.decision_date) AS first_decision_date,
               MAX(lca.decision_date) AS last_decision_date,
               MIN(lca.wage_rate_of_pay_from) FILTER (WHERE lca.wage_unit_of_pay = 'Year') AS min_yearly_wage_from,
               MAX(lca.wage_rate_of_pay_from) FILTER (WHERE lca.wage_unit_of_pay = 'Year') AS max_yearly_wage_from
        FROM lca
        LEFT JOIN jobpush.target_soc_roles target
          ON target.normalized_soc_code = lca.normalized_soc_code
         AND target.active
        GROUP BY lca.canonical_name, lca.normalized_soc_code, lca.soc_title,
                 lca.raw_job_title, target.normalized_soc_code
        ORDER BY current_target_soc DESC, lca_count DESC, lca.canonical_name, raw_job_title
        LIMIT 1000
        """,
        (company, company),
    )


@st.cache_data(ttl=60)
def company_lca_roles_by_key(consolidation_key: str) -> pd.DataFrame:
    if not consolidation_key:
        return pd.DataFrame()
    return query(
        """
        WITH selected_company AS (
            SELECT consolidation_key, canonical_name, member_feins
            FROM jobpush.company_targets_consolidated
            WHERE consolidation_key = %s
        ), member_feins AS (
            SELECT selected.consolidation_key, selected.canonical_name,
                   unnest(selected.member_feins) AS employer_fein
            FROM selected_company selected
        ), lca AS (
            SELECT member.consolidation_key, member.canonical_name,
                   jobpush.normalize_soc_code(case_row.soc_code) AS normalized_soc_code,
                   COALESCE(NULLIF(case_row.soc_title, ''), '(missing SOC title)') AS soc_title,
                   COALESCE(NULLIF(case_row.job_title, ''), '(missing raw title)') AS raw_job_title,
                   case_row.case_status, case_row.decision_date,
                   case_row.wage_rate_of_pay_from, case_row.wage_unit_of_pay
            FROM member_feins member
            JOIN public.lca_cases case_row
              ON case_row.employer_fein = member.employer_fein
        )
        SELECT lca.normalized_soc_code,
               lca.soc_title,
               lca.raw_job_title,
               CASE WHEN target.normalized_soc_code IS NOT NULL THEN TRUE ELSE FALSE END AS current_target_soc,
               COUNT(*) AS lca_count,
               COUNT(*) FILTER (WHERE lca.case_status = 'Certified') AS certified_count,
               MIN(lca.decision_date) AS first_decision_date,
               MAX(lca.decision_date) AS last_decision_date,
               MIN(lca.wage_rate_of_pay_from) FILTER (WHERE lca.wage_unit_of_pay = 'Year') AS min_yearly_wage_from,
               MAX(lca.wage_rate_of_pay_from) FILTER (WHERE lca.wage_unit_of_pay = 'Year') AS max_yearly_wage_from
        FROM lca
        LEFT JOIN jobpush.target_soc_roles target
          ON target.normalized_soc_code = lca.normalized_soc_code
         AND target.active
        GROUP BY lca.normalized_soc_code, lca.soc_title,
                 lca.raw_job_title, target.normalized_soc_code
        ORDER BY current_target_soc DESC, lca_count DESC, raw_job_title
        LIMIT 500
        """,
        (consolidation_key,),
    )


@st.cache_data(ttl=300)
def lca_soc_review_table(statuses: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        SELECT normalized_soc_code, soc_title, review_status, previous_target,
               lca_count, company_count, certified_count, raw_title_count,
               first_decision_date, last_decision_date,
               min_yearly_wage_from, median_yearly_wage_from, max_yearly_wage_from,
               source_file, reviewed_by, reviewed_at
        FROM jobpush.lca_soc_role_review_current
        WHERE review_status = ANY(%s)
        ORDER BY CASE review_status WHEN 'target' THEN 0 WHEN 'review' THEN 1 WHEN 'non_target' THEN 2 ELSE 3 END,
                 lca_count DESC, normalized_soc_code, soc_title
        """,
        (list(statuses),),
    )


@st.cache_data(ttl=300)
def lca_raw_job_review_sample(statuses: tuple[str, ...], search: str, limit: int) -> pd.DataFrame:
    search = normalize_company_query(search)
    if not search:
        return pd.DataFrame()
    return query(
        """
        WITH lca AS (
            SELECT jobpush.normalize_soc_code(case_row.soc_code) AS normalized_soc_code,
                   COALESCE(NULLIF(case_row.soc_title, ''), '(missing SOC title)') AS soc_title,
                   COALESCE(NULLIF(case_row.job_title, ''), '(missing raw title)') AS raw_job_title,
                   case_row.employer_fein,
                   case_row.employer_name,
                   case_row.case_status,
                   case_row.decision_date,
                   case_row.wage_rate_of_pay_from,
                   case_row.wage_unit_of_pay
            FROM public.lca_cases case_row
            WHERE case_row.job_title ILIKE '%%' || %s || '%%'
               OR case_row.soc_title ILIKE '%%' || %s || '%%'
        )
        SELECT lca.normalized_soc_code,
               lca.soc_title,
               lca.raw_job_title,
               COALESCE(review.review_status, '') AS soc_review_status,
               COUNT(*) AS lca_count,
               COUNT(DISTINCT lca.employer_fein) AS company_count,
               COUNT(*) FILTER (WHERE lca.case_status = 'Certified') AS certified_count,
               LEFT(
                   STRING_AGG(DISTINCT lca.employer_name, ' | ' ORDER BY lca.employer_name)
                       FILTER (WHERE lca.employer_name IS NOT NULL),
                   1000
               ) AS example_employers,
               MIN(lca.decision_date) AS first_decision_date,
               MAX(lca.decision_date) AS last_decision_date,
               MIN(lca.wage_rate_of_pay_from) FILTER (WHERE lca.wage_unit_of_pay = 'Year') AS min_yearly_wage_from,
               PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY lca.wage_rate_of_pay_from)
                   FILTER (WHERE lca.wage_unit_of_pay = 'Year') AS median_yearly_wage_from,
               MAX(lca.wage_rate_of_pay_from) FILTER (WHERE lca.wage_unit_of_pay = 'Year') AS max_yearly_wage_from
        FROM lca
        LEFT JOIN jobpush.lca_soc_role_review_current review
          ON review.normalized_soc_code = lca.normalized_soc_code
        WHERE COALESCE(review.review_status, '') = ANY(%s)
        GROUP BY lca.normalized_soc_code, lca.soc_title, lca.raw_job_title,
                 COALESCE(review.review_status, '')
        ORDER BY lca_count DESC, company_count DESC, lca.raw_job_title
        LIMIT %s
        """,
        (search, search, list(statuses), int(limit)),
    )


@st.cache_data(ttl=60)
def recent_failures() -> pd.DataFrame:
    return query(
        """
        SELECT run.started_at, target.priority_tier, target.canonical_name,
               site.source_type, run.status, run.requests_count, run.pages_fetched,
               run.parsed_job_count, run.new_job_count, run.closed_job_count,
               run.latency_ms, run.error_code, run.error_message, site.site_url
        FROM jobpush.crawl_runs run
        JOIN jobpush.career_sites site USING (site_id)
        JOIN jobpush.crawl_targets target USING (consolidation_key)
        WHERE run.status = 'failed'
        ORDER BY run.started_at DESC
        LIMIT 200
        """
    )


def dataframe(frame: pd.DataFrame, *, height: int = 520) -> None:
    visible = frame.drop(columns=["site_id", "external_job_id"], errors="ignore")
    st.dataframe(
        visible,
        hide_index=True,
        use_container_width=True,
        height=height,
        column_config={
            "job_url": st.column_config.LinkColumn("Open job", display_text="Open ↗"),
            "first_seen_at": st.column_config.DatetimeColumn("First seen", format="MMM D, h:mm a"),
            "last_seen_at": st.column_config.DatetimeColumn("Last seen", format="MMM D, h:mm a"),
        },
    )


TRACK_LABELS = {
    "stack_1_business_product_data": "Track 1 · Business / Product / Data",
    "stack_2_ai_solutions_systems_data": "Track 2 · AI / Solutions / Systems / Data",
    "stack_2_software_systems": "Track 2 · AI / Solutions / Systems / Data",
    "stack_3_customer_success": "Track 3 · Customer Success / Technical Account",
    "stack_3_gtm": "Track 3 · GTM / Sales / Marketing",
    "stack_4_sde": "Track 4 · SDE / Software Engineering",
    "stack_5_possible_target": "Track 5 · Possible Target / Unclassified",
    "stack_3_additional_targets": "Track 5 · Possible Target / Unclassified",
    "stack_3_target_roles": "Track 5 · Possible Target / Unclassified",
    "needs_review": "Needs review",
    "excluded_non_target": "Excluded / non-target",
    "review": "Needs review",
    "non_target": "Excluded / non-target",
    "unlabeled": "Unlabeled",
}

ROLE_FAMILY_LABELS = {
    "internship": "Internship",
    "forward_deployed_engineer": "Forward Deployed Engineer",
    "product_manager": "Product Manager",
    "program_manager": "Program Manager",
    "project_manager": "Project Manager",
    "systems_engineering": "Systems Engineering",
    "software_engineering": "Software Engineering",
    "data_science_ml": "Data Science / ML",
    "data_engineering": "Data Engineering / Architecture",
    "data_analytics_bi": "Data Analytics / BI",
    "business_analyst": "Business Analyst",
    "strategy_operations": "Strategy / Operations",
    "marketing": "Marketing",
    "sales": "Sales",
    "customer_success": "Customer Success / Technical Account",
    "technical_support": "Technical Support / Specialist",
    "applied_ai": "Applied AI / GTM Engineering",
    "financial_analyst": "Financial Analyst",
    "qa_testing": "QA / Testing",
    "cloud_devops": "Cloud / DevOps / SRE",
    "security": "Security / Cybersecurity",
    "implementation_consulting": "Implementation / Consulting",
    "it_support_admin": "IT Support / Admin",
    "business_operations": "Business Operations / Coordinator",
    "needs_review": "Needs review",
    "excluded_non_target": "Excluded / non-target",
    "other": "Unclassified target title",
}

TRACK_OPTIONS = [
    "Track 1 · Business / Product / Data",
    "Track 2 · AI / Solutions / Systems / Data",
    "Track 3 · Customer Success / Technical Account",
    "Track 3 · GTM / Sales / Marketing",
    "Track 4 · SDE / Software Engineering",
    "Track 5 · Possible Target / Unclassified",
    "Needs review",
    "Excluded / non-target",
]

TRACK_VALUE_TO_LABEL = {
    "stack_1_business_product_data": "Track 1 · Business / Product / Data",
    "stack_2_ai_solutions_systems_data": "Track 2 · AI / Solutions / Systems / Data",
    "stack_2_software_systems": "Track 2 · AI / Solutions / Systems / Data",
    "stack_3_customer_success": "Track 3 · Customer Success / Technical Account",
    "stack_3_gtm": "Track 3 · GTM / Sales / Marketing",
    "stack_4_sde": "Track 4 · SDE / Software Engineering",
    "stack_5_possible_target": "Track 5 · Possible Target / Unclassified",
    "stack_3_additional_targets": "Track 5 · Possible Target / Unclassified",
    "stack_3_target_roles": "Track 5 · Possible Target / Unclassified",
    "needs_review": "Needs review",
    "excluded_non_target": "Excluded / non-target",
}
TRACK_LABEL_TO_VALUE = {label: value for value, label in TRACK_VALUE_TO_LABEL.items()}
TRACK_LABEL_TO_VALUE["Track 5 · Possible Target / Unclassified"] = "stack_5_possible_target"


def role_family_label(value: str | None) -> str:
    if not value:
        return "Unclassified target title"
    if value.startswith("title:"):
        return value.removeprefix("title:").replace("_", " ").strip().title()
    return ROLE_FAMILY_LABELS.get(value, value)


def track_label(value: str | None) -> str:
    if not value:
        return "Unclassified target title"
    if value.startswith("track_family:"):
        return f"Track 5 · {role_family_label(value.removeprefix('track_family:'))}"
    return TRACK_LABELS.get(value, value)


def track_sort_rank(label: str | None) -> int:
    if not label:
        return 99
    if label.startswith("Track 1"):
        return 1
    if label.startswith("Track 2"):
        return 2
    if label.startswith("Track 3"):
        return 3
    if label.startswith("Track 4"):
        return 4
    if label.startswith("Track 5"):
        return 5
    return 90


ROLE_FAMILY_OPTIONS = [
    "Internship",
    "Forward Deployed Engineer",
    "Product Manager",
    "Program Manager",
    "Project Manager",
    "Systems Engineering",
    "Software Engineering",
    "Data Science / ML",
    "Data Engineering / Architecture",
    "Data Analytics / BI",
    "Business Analyst",
    "Strategy / Operations",
    "Marketing",
    "Sales",
    "Customer Success / Technical Account",
    "Technical Support / Specialist",
    "Applied AI / GTM Engineering",
    "Financial Analyst",
    "Needs review",
    "Excluded / non-target",
    "Unclassified target title",
]

EMPLOYMENT_BUCKET_OPTIONS = ["internship", "entry_level", "full_time_or_unknown", "full_time", "part_time", "contract"]
LOCATION_BUCKET_OPTIONS = ["chicago_or_illinois", "remote", "other_us", "location_not_listed"]
SENIORITY_BUCKET_OPTIONS = ["internship", "entry_level", "regular_full_time", "senior_or_leadership"]

SEGMENT_DIMENSIONS = {
    "Track 1/2/3": "track_label",
    "Role family": "role_family_label",
    "Employment type": "employment_bucket",
    "Seniority": "seniority_bucket",
    "Location": "location_bucket",
    "Priority tier": "priority_tier",
}


st.markdown(
    """
    <div class="hero">
      <h1>JobPush Ops</h1>
      <div class="quiet">Career-site crawl operations, job discovery, and application review · timestamps in America/Chicago</div>
    </div>
    """,
    unsafe_allow_html=True,
)

chicago_today = datetime.now(ZoneInfo("America/Chicago")).date()

st.sidebar.header("Global view")
st.sidebar.caption("Global date range, tier filter, and fuzzy search.")
with st.sidebar.form("global_view_form"):
    global_search = st.text_input(
        "Global search",
        placeholder="Company, title, role, location, tier, URL...",
    )
    date_window = st.date_input(
        "First seen date range",
        value=(chicago_today - timedelta(days=6), chicago_today),
        min_value=chicago_today - timedelta(days=90),
        max_value=chicago_today,
    )
    priority_choice = st.selectbox(
        "Priority tier",
        ["All P tiers", "P0 only", "P1 only", "P2 only", "P3 only", "P0 + P1"],
    )
    row_limit = st.selectbox("Rows to load", [300, 1000, 2000, 5000], index=0)
    st.form_submit_button("Apply global view", use_container_width=True)
company = normalize_search_query(global_search)
title = ""
location = ""
role_choice = "target only"
app_choice = "open items"
if isinstance(date_window, tuple):
    start_date = date_window[0]
    end_date = date_window[1] if len(date_window) > 1 else date_window[0]
else:
    start_date = date_window
    end_date = date_window
if start_date > end_date:
    st.sidebar.error("Start date must be before end date.")
    st.stop()
tiers = {
    "P0 + P1": ("P0", "P1"),
    "P0 only": ("P0",),
    "P1 only": ("P1",),
    "P2 only": ("P2",),
    "P3 only": ("P3",),
    "All P tiers": ("P0", "P1", "P2", "P3"),
}[priority_choice]
role_statuses = {
    "target only": ("target",),
    "target + needs review": ("target", "review"),
    "needs review only": ("review",),
    "all decisions": ("target", "review", "non_target"),
}[role_choice]
app_statuses = {
    "open items": OPEN_APPLICATION_STATUSES,
    "new only": ("new",),
    "saved/apply next": ("saved", "apply_next", "referred"),
    "all statuses": ("new", "saved", "apply_next", "referred", "applied", "dismissed"),
}[app_choice]
if not tiers or not role_statuses or not app_statuses:
    st.warning("Select at least one priority tier, role decision, and application status.")
    st.stop()

selected_tier_label = priority_choice.replace(" only", "").replace("All P tiers", "P0+P1+P2+P3")

PAGE_LABELS = [
    "Pulse",
    "Jobs to apply",
    "Crawl monitor",
    "Title review",
    "Site review",
    "Companies",
    "Scoring rules",
]
selected_page = st.radio(
    "Dashboard page",
    PAGE_LABELS,
    horizontal=True,
    key="dashboard_page",
)

def load_current_jobs() -> pd.DataFrame:
    return jobs(start_date, end_date, company.strip(), tiers, role_statuses, app_statuses, row_limit)

if selected_page == "Pulse":
    summary = apply_job_summary(tiers)
    summary_row = summary.iloc[0] if not summary.empty else pd.Series(dtype="int64")
    metric_columns = st.columns(5)
    metric_columns[0].metric(f"Open target jobs · {selected_tier_label}", f"{int(summary_row.get('open_target_jobs', 0)):,}")
    metric_columns[1].metric("Newly discovered today", f"{int(summary_row.get('new_target_jobs_today', 0)):,}")
    metric_columns[2].metric("Closed today", f"{int(summary_row.get('closed_jobs_today', 0)):,}")
    metric_columns[3].metric("Product Manager", f"{int(summary_row.get('product_manager_jobs', 0)):,}")
    metric_columns[4].metric("Companies", f"{int(summary_row.get('companies', 0)):,}")
    st.caption("Home counts active US target jobs that are still open for application. “Newly discovered” means JobPush first saw the posting today, not necessarily the employer posted it today.")

    status_summary = application_status_summary(tiers)
    if not status_summary.empty:
        st.subheader("Application status mix")
        status_labels = {
            "new": "New",
            "apply_next": "Apply Next",
            "referred": "Referred",
            "applied": "Applied",
            "dismissed": "Dismiss",
            "saved": "Saved legacy",
        }
        status_cards = st.columns(min(6, len(status_summary)))
        for column, row in zip(status_cards, status_summary.itertuples()):
            label = status_labels.get(row.application_status, row.application_status)
            column.metric(label, f"{int(row.jobs):,}", f"{float(row.pct or 0):.1f}%")

    mix_summary = target_job_mix_summary(tiers, OPEN_APPLICATION_STATUSES)
    if not mix_summary.empty:
        st.subheader("Target job mix")
        st.caption("Current open target jobs and jobs first seen today, grouped by your track and role family.")
        mix_summary = mix_summary.copy()
        mix_summary["label"] = mix_summary.apply(
            lambda row: track_label(row["segment_key"]) if row["dimension"] == "track" else role_family_label(row["segment_key"]),
            axis=1,
        )
        mix_summary["Current"] = mix_summary.apply(
            lambda row: f"{int(row['current_open_jobs']):,} ({float(row['current_pct'] or 0):.1f}%)",
            axis=1,
        )
        mix_summary["New today"] = mix_summary.apply(
            lambda row: f"{int(row['new_today_jobs']):,} ({float(row['today_pct'] or 0):.1f}%)",
            axis=1,
        )
        mix_summary["track_sort"] = mix_summary["label"].apply(track_sort_rank)
        track_mix = mix_summary[mix_summary["dimension"] == "track"].sort_values(["track_sort", "current_open_jobs"], ascending=[True, False])
        role_mix = mix_summary[mix_summary["dimension"] == "role_family"].sort_values("current_open_jobs", ascending=False).head(15)
        track_col, role_col = st.columns(2)
        with track_col:
            st.markdown("##### Track distribution")
            st.dataframe(
                track_mix[["label", "Current", "New today"]].rename(columns={"label": "Track"}),
                hide_index=True,
                use_container_width=True,
                height=220,
            )
            if track_mix["current_open_jobs"].sum() > 0:
                st.bar_chart(track_mix.set_index("label")["current_open_jobs"], height=220)
        with role_col:
            st.markdown("##### Role family distribution")
            st.caption("Unclassified rows are expanded by normalized title instead of being grouped into one fallback bucket.")
            st.dataframe(
                role_mix[["label", "Current", "New today"]].rename(columns={"label": "Role family"}),
                hide_index=True,
                use_container_width=True,
                height=220,
            )
            if role_mix["current_open_jobs"].sum() > 0:
                st.bar_chart(role_mix.set_index("label")["current_open_jobs"], height=220)

    activity = daily_activity(tiers)
    st.subheader("30-day target job discovery")
    chart = activity.sort_values("activity_date").set_index("activity_date")
    st.line_chart(chart[["new_target_jobs", "closed_jobs"]], height=330)

    st.subheader("Crawl rollout by priority tier")
    rollout = crawl_rollout_by_tier()
    if not rollout.empty:
        st.caption("Company coverage by priority tier")
        coverage_cards = st.columns(4)
        for column, tier in zip(coverage_cards, ["P0", "P1", "P2", "P3"]):
            tier_rows = rollout[rollout["priority_tier"] == tier]
            if tier_rows.empty:
                column.metric(tier, "0 / 0", "0.0% succeeded")
                continue
            tier_row = tier_rows.iloc[0]
            total = int(tier_row.get("companies", 0))
            enabled = int(tier_row.get("enabled_site_companies", 0))
            succeeded = int(tier_row.get("succeeded_companies", 0))
            pct = 100 * succeeded / total if total else 0
            column.metric(
                f"{tier} coverage",
                f"{succeeded:,} / {total:,}",
                f"{pct:.1f}% succeeded · {enabled:,} enabled",
            )
    st.dataframe(rollout, hide_index=True, use_container_width=True, height=240)

if selected_page == "Crawl monitor":
    st.subheader("P0 / P1 / P2 / P3 company crawl rollout")
    st.caption(
        "这个 tab 回答三个问题：总共有多少公司、今天/目前跑了多少、没跑成功主要卡在哪里。"
    )
    rollout = crawl_rollout_by_tier()
    selected_rollout = rollout[rollout["priority_tier"].isin(tiers)]
    selected_total = int(selected_rollout["companies"].sum()) if not selected_rollout.empty else 0
    selected_success = int(selected_rollout["succeeded_companies"].sum()) if not selected_rollout.empty else 0
    selected_attempted = int(selected_rollout["attempted_companies"].sum()) if not selected_rollout.empty else 0
    selected_waiting = int(selected_rollout["due_now_companies"].sum()) if not selected_rollout.empty else 0
    rollout_cols = st.columns(4)
    rollout_cols[0].metric(f"{selected_tier_label} companies", f"{selected_total:,}", " ")
    rollout_cols[1].metric("Succeeded", f"{selected_success:,}", f"{(100 * selected_success / selected_total):.1f}%" if selected_total else " ")
    rollout_cols[2].metric("Attempted", f"{selected_attempted:,}", f"{(100 * selected_attempted / selected_total):.1f}%" if selected_total else " ")
    rollout_cols[3].metric("Due / waiting", f"{selected_waiting:,}", " ")

    st.dataframe(rollout, hide_index=True, use_container_width=True)
    with st.expander("这些状态是什么意思？"):
        st.markdown(
            "- **Successfully crawled**：这个公司至少有一个已启用官网成功抓到过职位。\n"
            "- **Attempted at least once**：已经请求过网站，可能成功也可能失败。\n"
            "- **Due / waiting now**：已有可爬网站，也到了应跑时间；主要是调度队列还没消费完。\n"
            "- **Structured candidate not enabled**：找到了 Workday/Greenhouse/Lever/Ashby/iCIMS 等结构化候选，但还没被自动信任/启用。\n"
            "- **generic_html_needs_resolution**：只有普通公司招聘页，不是标准 ATS API；需要泛化解析或重新定位到真正 ATS 页面。\n"
            "- **not_searched_yet**：还没有走官网搜索，通常等 Tavily credits 或分批策略。"
        )
    with st.expander("SQL behind crawl completion / rollout"):
        st.code(
            """
WITH site_rollup AS (
    SELECT consolidation_key,
           BOOL_OR(verification_status = 'verified' AND crawl_enabled) AS has_enabled_site,
           BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_success_at IS NOT NULL) AS has_success,
           BOOL_OR(verification_status = 'verified' AND crawl_enabled AND crawl_status = 'failed') AS has_failed
    FROM jobpush.career_sites
    GROUP BY consolidation_key
)
SELECT target.priority_tier,
       COUNT(*) AS companies,
       COUNT(*) FILTER (WHERE site_rollup.has_enabled_site) AS enabled_site_companies,
       COUNT(*) FILTER (WHERE site_rollup.has_success) AS succeeded_companies,
       COUNT(*) FILTER (WHERE site_rollup.has_failed) AS failed_companies
FROM jobpush.crawl_targets target
LEFT JOIN site_rollup USING (consolidation_key)
WHERE target.enabled AND target.priority_tier IN ('P0','P1','P2','P3')
GROUP BY target.priority_tier
ORDER BY target.priority_tier;
            """.strip(),
            language="sql",
        )

    st.subheader("Crawlable vs blocked distribution")
    state_frame = crawl_state_by_tier(tiers)
    if state_frame.empty:
        st.info("No companies found for the selected priority tiers.")
    else:
        chart_frame = state_frame.pivot(index="crawl_state", columns="priority_tier", values="companies").fillna(0)
        st.bar_chart(chart_frame, height=330)
        st.dataframe(state_frame, hide_index=True, use_container_width=True, height=300)

    st.subheader("Generic HTML blocker template families")
    template_frame = generic_blocker_template_summary(tiers)
    if template_frame.empty:
        st.success("No unresolved generic HTML blockers in the selected tiers.")
    else:
        st.caption("This separates true corporate careers pages from missed structured ATS domains. Missed structured domains are the cheapest parser/classifier wins.")
        st.dataframe(template_frame, hide_index=True, use_container_width=True, height=260)

    left, right = st.columns([1, 1])
    with left:
        st.subheader("P1 blockers")
        blockers = p1_blocker_distribution()
        if blockers.empty:
            st.info("No P1 companies found.")
        else:
            st.bar_chart(blockers.set_index("crawl_state")["companies"], height=330)
            st.dataframe(blockers, hide_index=True, use_container_width=True)
    with right:
        st.subheader("P1 top-rank coverage")
        rank_coverage = p1_rank_coverage()
        st.dataframe(rank_coverage, hide_index=True, use_container_width=True, height=260)
        st.caption("Top 500 / Top 1000 是按 priority_score 从高到低排序，用来判断最值得先跑的一批推进到哪里了。")

    st.subheader("Current crawl failure reasons")
    failure_reasons = current_failure_reasons()
    if failure_reasons.empty:
        st.success("No currently failed enabled sites.")
    else:
        st.dataframe(failure_reasons, hide_index=True, use_container_width=True, height=320)

    st.subheader("Local ML / title-classification status")
    label_status, classifier_status = ml_status()
    ml_left, ml_right = st.columns(2)
    with ml_left:
        st.caption("Rules + manual labels currently stored")
        st.dataframe(label_status, hide_index=True, use_container_width=True, height=260)
    with ml_right:
        st.caption("Local supervised model predictions and whether they were auto-applied")
        if classifier_status.empty:
            st.info("No ML classification records found yet.")
        else:
            st.dataframe(classifier_status, hide_index=True, use_container_width=True, height=260)

if selected_page == "Jobs to apply":
    st.subheader("Application queue")
    st.caption(
        "Review target jobs, update application status, and open application links from one page."
    )
    filter_cols = st.columns(4)
    job_search_filter = filter_cols[0].text_input("Search this page", value=global_search, key="jobs-global-search")
    effective_job_search = job_search_filter.strip() or global_search.strip()
    track_choice = filter_cols[1].multiselect(
        "Track",
        TRACK_OPTIONS,
        default=TRACK_OPTIONS,
    )
    role_family_choice = filter_cols[2].selectbox("Role family", ["All"] + ROLE_FAMILY_OPTIONS)
    employment_choice = filter_cols[3].selectbox("Type", ["All"] + EMPLOYMENT_BUCKET_OPTIONS)
    selected_status_labels = st.multiselect(
        "Application status",
        list(APPLICATION_STATUS_OPTIONS.keys()),
        default=["New", "Apply Next", "Referred", "Saved (legacy)"],
    )
    job_app_statuses = tuple(APPLICATION_STATUS_OPTIONS[label] for label in selected_status_labels) or OPEN_APPLICATION_STATUSES

    job_frame = jobs(
        start_date,
        end_date,
        effective_job_search,
        tiers,
        role_statuses,
        job_app_statuses,
        row_limit,
    )
    if job_frame.empty:
        st.info("No jobs match the current filters.")
    else:
        job_frame = job_frame.copy()
        job_frame["first_seen_ct"] = pd.to_datetime(job_frame["first_seen_at"], utc=True).dt.tz_convert("America/Chicago").dt.strftime("%Y-%m-%d %I:%M %p")
        job_frame["role_family_label"] = job_frame["role_family"].apply(role_family_label)
        job_frame["track_label"] = job_frame.apply(
            lambda row: f"Track 5 · {row['role_family_label']}" if row["role_stack"] == "stack_5_possible_target" else track_label(row["role_stack"]),
            axis=1,
        )
        job_frame["track_sort"] = job_frame["track_label"].apply(track_sort_rank)

        selected_tracks = TRACK_OPTIONS if effective_job_search else (track_choice or TRACK_OPTIONS)
        if role_family_choice != "All":
            job_frame = job_frame[job_frame["role_family_label"] == role_family_choice]
        if employment_choice != "All":
            job_frame = job_frame[job_frame["employment_bucket"] == employment_choice]
        fallback_selected = "Track 5 · Possible Target / Unclassified" in selected_tracks
        track_mask = job_frame["track_label"].isin(selected_tracks)
        if fallback_selected:
            track_mask = track_mask | (job_frame["role_stack"] == "stack_5_possible_target")
        job_frame = job_frame[track_mask].sort_values(["track_sort", "first_seen_at"], ascending=[True, False])

        display_columns = [
            "first_seen_ct", "canonical_name", "priority_tier", "priority_score",
            "priority_rank_in_tier", "title", "location",
            "role_family_label", "track_label", "employment_bucket", "seniority_bucket",
            "application_status", "job_url",
        ]
        st.caption("Select one row in the table, then update its application status below.")
        table_event = st.dataframe(
            job_frame[display_columns],
            hide_index=True,
            use_container_width=True,
            height=620,
            column_config={"job_url": st.column_config.LinkColumn("Apply link", display_text="Open ↗")},
            on_select="rerun",
            selection_mode="single-row",
            key="jobs-to-apply-table",
        )
        selected_rows = table_event.selection.rows if table_event and table_event.selection else []
        if selected_rows:
            selected_job = job_frame.iloc[int(selected_rows[0])]
            st.markdown("#### Update selected job")
            st.caption(
                f"{selected_job['canonical_name']} · {selected_job['title']} · "
                f"Current status: `{selected_job['application_status']}` · "
                f"[Open application link]({selected_job['job_url']})"
            )
            status_note = st.text_input(
                "Optional note",
                placeholder="Referral contact, resume tweak, deadline, why dismissed…",
                key=f"job-status-note-{selected_job['site_id']}-{selected_job['external_job_id']}",
            )
            action_columns = st.columns(4)
            for column, (button_label, status) in zip(
                action_columns,
                [
                    ("Apply Next", "apply_next"),
                    ("Referred", "referred"),
                    ("Applied", "applied"),
                    ("Dismiss", "dismissed"),
                ],
            ):
                if column.button(button_label, use_container_width=True, key=f"job-{status}-{selected_job['site_id']}-{selected_job['external_job_id']}"):
                    execute(
                        "SELECT jobpush.set_job_application_action(%s, %s, %s, %s, 'nicole')",
                        (int(selected_job["site_id"]), str(selected_job["external_job_id"]), status, status_note),
                    )
                    jobs.clear()
                    apply_job_summary.clear()
                    application_status_summary.clear()
                    st.success(f"Saved as {status}.")
                    st.rerun()
        st.download_button(
            "Download current job table (CSV)",
            csv_bytes(job_frame),
            file_name=f"jobpush_jobs_to_apply_{chicago_today}.csv",
            mime="text/csv",
        )

if selected_page == "Title review":
    st.subheader("Title samples for improving the classifier")
    st.caption(
        "这里只是抽样训练/修正规则用，不是每天申请流程。已被人工标注、YAML/profile hard rules、"
        "local ML 高置信度处理过的 title 会从这里移除。你可以直接在页面里填人工判断并提交到数据库。"
    )
    review_limit = st.select_slider("Review batch size", options=[100, 250, 500, 1000, 2000], value=500)
    review_frame = title_review_queue(review_limit)
    st.download_button(
        "Download title review batch (CSV)", csv_bytes(review_frame),
        file_name=f"jobpush_title_review_{chicago_today}_{review_limit}.csv", mime="text/csv",
    )
    if review_frame.empty:
        st.success("No titles are currently waiting for manual review.")
    else:
        st.subheader("Select one or more titles from the table")
        title_selection = st.dataframe(
            review_frame.drop(columns=["人工判断（请填写）", "标准岗位（可选）", "判断原因/备注（可选）"], errors="ignore"),
            hide_index=True,
            use_container_width=True,
            height=420,
            column_config={
                "example_job_url": st.column_config.LinkColumn("Example job", display_text="Open ↗"),
            },
            on_select="rerun",
            selection_mode="multi-row",
            key="title_review_table",
        )
        selected_title_rows = getattr(getattr(title_selection, "selection", None), "rows", []) or []
        selected_title_indices = [int(index) for index in selected_title_rows] if selected_title_rows else [0]
        selected_title_rows_frame = review_frame.iloc[selected_title_indices]
        selected_title_row = selected_title_rows_frame.iloc[0]
        selected_count = len(selected_title_rows_frame)
        if selected_count > 1:
            st.info(
                f"{selected_count:,} titles selected. The decision and notes below will be submitted "
                "for every selected title."
            )
        st.subheader("Submit selected title label(s)")
        with st.form("title_review_form", clear_on_submit=True):
            st.caption(
                f"Selected: **{selected_title_row['normalized_title']}** · "
                f"{selected_count:,} selected · "
                f"{int(selected_title_row['active_posting_count']):,} active postings · "
                f"{int(selected_title_row['company_count']):,} companies"
            )
            st.caption(
                f"Example: {selected_title_row['example_title']} | "
                f"Suggested by: {selected_title_row['suggestion_reason']}"
            )
            example_url = str(selected_title_row.get("example_job_url") or "")
            if example_url and example_url.lower() != "nan":
                st.caption(f"[Open example job posting]({example_url})")
            title_status = st.selectbox("Decision for all selected titles", ["target", "non_target", "review"])
            default_role = str(selected_title_row.get("matched_soc_titles") or "")[:180] if selected_count == 1 else ""
            canonical_role_override = st.text_input(
                "Standard role / role family override",
                value=default_role,
                help=(
                    "For multiple selected titles, leave this blank to use each row's own suggested SOC/role. "
                    "Fill it only when every selected title should share the same role label."
                ),
            )
            title_reason = st.text_input(
                "Reason / notes",
                value="dashboard title review",
            )
            title_submit = st.form_submit_button(
                f"Submit {selected_count:,} selected title label(s)",
                use_container_width=True,
            )
        if title_submit:
            for _, title_row in selected_title_rows_frame.iterrows():
                row_suggested_role = str(title_row.get("matched_soc_titles") or "")[:180]
                apply_title_review(
                    str(title_row["normalized_title"]),
                    title_status,
                    canonical_role_override.strip() or row_suggested_role,
                    title_reason,
                )
            clear_dashboard_caches()
            st.success(f"Submitted {selected_count:,} title label(s) → {title_status}.")

    st.divider()
    with st.expander("Optional batch editor"):
        st.caption("备用批量入口；主流程优先用上面的表格选中一行再提交。")
        edited_titles = st.data_editor(
            review_frame,
            hide_index=True,
            use_container_width=True,
            height=520,
            disabled=[
                "normalized_title",
                "example_title",
                "active_posting_count",
                "company_count",
                "suggestion_reason",
                "matched_soc_codes",
                "matched_soc_titles",
            ],
            column_config={
                "人工判断（请填写）": st.column_config.SelectboxColumn(
                    "人工判断",
                    options=["", "target", "non_target", "review"],
                    help="提交后写入 jobpush.job_title_labels，并保留 history。",
                ),
                "标准岗位（可选）": st.column_config.TextColumn("标准岗位 / role family"),
                "判断原因/备注（可选）": st.column_config.TextColumn("判断原因/备注"),
            },
            key="title_review_editor",
        )
        filled_titles = edited_titles[
            edited_titles["人工判断（请填写）"].isin(["target", "non_target", "review"])
        ].copy()
        title_submit_col, title_info_col = st.columns([1, 3])
        if title_submit_col.button(
            f"Submit {len(filled_titles):,} title labels",
            disabled=filled_titles.empty,
            use_container_width=True,
        ):
            for _, row in filled_titles.iterrows():
                apply_title_review(
                    str(row["normalized_title"]),
                    str(row["人工判断（请填写）"]),
                    str(row.get("标准岗位（可选）") or ""),
                    str(row.get("判断原因/备注（可选）") or "dashboard title review"),
                )
            clear_dashboard_caches()
            st.success(f"Submitted {len(filled_titles):,} title labels to the database.")
        title_info_col.caption(
            "提交后会立即影响新的 dashboard job 分类；规则代码不会被网页静默改写，"
            "重复模式会在后续 migration / YAML 规则里固化。"
        )

if selected_page == "Site review":
    st.subheader("Career-site samples for improving website selection")
    st.caption(
        "这里是人工 override surface，不只是系统待审核队列；已 verified / auto-trusted 的站点也可以展示并被重新判断。"
        "一行是一家公司；所有 discovery source（包括 direct ATS guessing）最多展示前三个候选；"
        "你也可以直接输入真实官网 URL。"
    )
    site_col1, site_col2, site_col3, site_col4 = st.columns([1, 1, 1, 1.3])
    site_limit = site_col1.select_slider("Site review batch size", options=[100, 250, 500, 1000], value=500)
    site_tiers = tuple(site_col2.multiselect("Site review tiers", ["P0", "P1", "P2", "P3"], default=["P0", "P1", "P2", "P3"]))
    site_statuses = tuple(site_col3.multiselect(
        "Site statuses",
        ["REVIEW_CANDIDATES", "VERIFIED"],
        default=["REVIEW_CANDIDATES", "VERIFIED"],
    ))
    site_company_search = site_col4.text_input(
        "Search site review",
        value=global_search,
        placeholder="Uber, Google, Pfizer...",
    )
    if site_tiers:
        st.markdown("#### Review and crawl coverage")
        site_summary = review_workbench_summary(site_tiers)
        if not site_summary.empty:
            totals = site_summary.drop(columns=["priority_tier"], errors="ignore").sum(numeric_only=True)
            stat_cols = st.columns(6)
            stat_cols[0].metric("Companies", f"{int(totals.get('companies', 0)):,}")
            stat_cols[1].metric("Verified sites", f"{int(totals.get('site_reviewed_verified', 0)):,}")
            stat_cols[2].metric("Waiting review", f"{int(totals.get('waiting_site_review', 0)):,}")
            stat_cols[3].metric("Can crawl", f"{int(totals.get('can_crawl', 0)):,}")
            stat_cols[4].metric("Crawled once", f"{int(totals.get('crawled_at_least_once', 0)):,}")
            stat_cols[5].metric("Succeeded", f"{int(totals.get('crawled_successfully', 0)):,}")
            st.dataframe(site_summary, hide_index=True, use_container_width=True, height=170)

        site_frame = site_review_queue(
            site_limit,
            site_tiers,
            site_statuses or ("REVIEW_CANDIDATES", "VERIFIED"),
            site_company_search,
        )
        st.download_button(
            "Download site review batch (CSV)", csv_bytes(site_frame),
            file_name=f"jobpush_site_review_{'_'.join(site_tiers)}_{chicago_today}_{site_limit}.csv",
            mime="text/csv",
        )
        site_selection = st.dataframe(
            site_frame,
            hide_index=True,
            use_container_width=True,
            height=440,
            on_select="rerun",
            selection_mode="multi-row",
            key="site_review_table",
            column_config={
                "candidate_1_url": st.column_config.LinkColumn("Candidate 1", display_text="Open ↗"),
                "candidate_2_url": st.column_config.LinkColumn("Candidate 2", display_text="Open ↗"),
                "candidate_3_url": st.column_config.LinkColumn("Candidate 3", display_text="Open ↗"),
                "verified_url": st.column_config.LinkColumn("Verified", display_text="Open ↗"),
            },
        )
        if not site_frame.empty:
            selected_site_rows = getattr(getattr(site_selection, "selection", None), "rows", []) or []
            selected_site_index = selected_site_rows[0] if selected_site_rows else 0
            selected_row = site_frame.iloc[int(selected_site_index)]
            if len(selected_site_rows) > 1:
                st.info(f"{len(selected_site_rows):,} companies selected. The action panels below use the first selected company; batch site actions can be added next.")
            st.subheader("Review selected company")
            st.caption("在上面的表格点一行；下面所有候选判断、P 档调整、手动官网导入都会默认作用于这家公司。")
            st.markdown("#### Selected company context")
            context_cols = st.columns(6)
            context_cols[0].metric("Tier", str(selected_row["priority_tier"]))
            context_cols[1].metric("Tier rank", f"{int(selected_row['priority_rank_in_tier']):,}")
            context_cols[2].metric("Priority score", f"{float(selected_row['priority_score']):.2f}")
            context_cols[3].metric("LCA rows", f"{int(selected_row['lca_count']):,}")
            context_cols[4].metric("Target LCA rows", f"{int(selected_row['target_role_lca_count']):,}")
            context_cols[5].metric("Candidates", f"{int(selected_row['candidate_count']):,}")
            st.caption(
                f"Company: **{selected_row['canonical_name']}** · "
                f"Key: `{selected_row['consolidation_key']}` · "
                f"Location: {selected_row.get('employer_city') or '(missing)'}, "
                f"{selected_row.get('employer_state') or '(missing)'} · "
                f"Signal: {selected_row.get('potential_p0_signal') or '(none)'}"
            )

            priority_col, lca_col = st.columns([1, 2])
            with priority_col:
                st.markdown("##### Priority override")
                new_tier = st.selectbox(
                    "Change this company to",
                    ["Keep current", "P0", "P1", "P2", "P3", "Use computed / remove override"],
                    key=f"site-priority-tier-{selected_row['consolidation_key']}",
                )
                priority_reason = st.text_input(
                    "Reason",
                    value="dashboard site review priority adjustment",
                    key=f"site-priority-reason-{selected_row['consolidation_key']}",
                )
                if st.button(
                    "Save priority override",
                    disabled=new_tier == "Keep current",
                    use_container_width=True,
                    key=f"site-priority-save-{selected_row['consolidation_key']}",
                ):
                    tier_value = "AUTO" if new_tier == "Use computed / remove override" else new_tier
                    set_manual_crawl_priority(
                        str(selected_row["consolidation_key"]),
                        tier_value,
                        priority_reason,
                    )
                    clear_dashboard_caches()
                    st.success(
                        f"Updated {selected_row['canonical_name']} to {new_tier}."
                    )
            with lca_col:
                st.markdown("##### LCA sponsorship roles")
                selected_lca_roles = company_lca_roles_by_key(str(selected_row["consolidation_key"]))
                if selected_lca_roles.empty:
                    st.info("No LCA sponsorship roles found for this company key.")
                else:
                    st.download_button(
                        "Download selected company LCA roles (CSV)",
                        csv_bytes(selected_lca_roles),
                        file_name=(
                            f"jobpush_lca_roles_"
                            f"{str(selected_row['consolidation_key']).replace('/', '_')}_{chicago_today}.csv"
                        ),
                        mime="text/csv",
                        key=f"site-lca-download-{selected_row['consolidation_key']}",
                    )
                    st.dataframe(
                        selected_lca_roles,
                        hide_index=True,
                        use_container_width=True,
                        height=300,
                    )

            st.divider()
            candidate_options: dict[str, tuple[int | None, str | None, str | None]] = {
                "Verified site": (
                    selected_row.get("verified_site_id"),
                    selected_row.get("verified_source"),
                    selected_row.get("verified_url"),
                ),
                "Candidate 1": (
                    selected_row.get("candidate_1_site_id"),
                    selected_row.get("candidate_1_source"),
                    selected_row.get("candidate_1_url"),
                ),
                "Candidate 2": (
                    selected_row.get("candidate_2_site_id"),
                    selected_row.get("candidate_2_source"),
                    selected_row.get("candidate_2_url"),
                ),
                "Candidate 3": (
                    selected_row.get("candidate_3_site_id"),
                    selected_row.get("candidate_3_source"),
                    selected_row.get("candidate_3_url"),
                ),
            }
            available_candidates = {
                f"{label} · {source or 'unknown'} · {url}": value
                for label, value in candidate_options.items()
                for site_id, source, url in [value]
                if pd.notna(site_id) and url
            }
            if available_candidates:
                selected_candidate = st.radio("Candidate decision", list(available_candidates.keys()))
                decision_notes = st.text_input(
                    "Site review notes",
                    value="dashboard site review",
                    key="site-review-notes",
                )
                verify_col, reject_col, crawl_col = st.columns([1, 1, 2])
                selected_site_id, selected_source, selected_url = available_candidates[selected_candidate]
                if verify_col.button("Verify selected site", use_container_width=True):
                    review_existing_career_site(int(selected_site_id), "verified", str(selected_source), decision_notes)
                    ok, output = trigger_inline_site_crawl(int(selected_site_id))
                    clear_dashboard_caches()
                    st.success(f"Verified {selected_url}. {output}")
                if reject_col.button("Reject selected site", use_container_width=True):
                    review_existing_career_site(int(selected_site_id), "rejected", str(selected_source), decision_notes)
                    clear_dashboard_caches()
                    st.success(f"Rejected {selected_url}.")
                crawl_col.caption("Verify 会把该站点设为 due now；Reject 可覆盖已 verified/auto-trusted 的系统选择。")
            else:
                st.info("This row has no usable candidate URL.")

            st.divider()
            st.subheader("Import a real official career site for selected company")
            st.caption(
                f"当前默认导入给：{selected_row['canonical_name']}。不需要再复制 company name。"
            )
            manual_url = st.text_input(
                "Official career URL",
                placeholder="https://jobs.example.com/...",
                key=f"manual-site-url-{selected_row['consolidation_key']}",
            )
            manual_notes = st.text_input(
                "Notes",
                value="Manually confirmed official career site from dashboard",
                key=f"manual-site-notes-{selected_row['consolidation_key']}",
            )
            if manual_url:
                classified_preview = classify_career_url(manual_url)
                st.caption(
                    f"Detected: source_type={classified_preview['source_type']}, "
                    f"source_key={classified_preview['source_key'] or '(none)'}, "
                    f"scope={classified_preview['scope_method']}, canonical_url={classified_preview['site_url']}"
                )
            if st.button(
                "Import verified site and crawl now",
                disabled=not manual_url,
                use_container_width=True,
                key=f"manual-site-import-{selected_row['consolidation_key']}",
            ):
                classified = import_manual_career_site(str(selected_row["consolidation_key"]), manual_url, manual_notes)
                ok, output = trigger_inline_site_crawl(classified.get("site_id"))
                clear_dashboard_caches()
                st.success(
                    f"Imported {classified['site_url']} for {selected_row['canonical_name']} "
                    f"as {classified['source_type']}. {output}"
                )
    else:
        st.info("Select at least one tier for site review export.")

if selected_page == "Companies":
    st.subheader("Company lookup")
    lookup = st.text_input("Search company / jobs", value=global_search, placeholder="e.g. Pfizer Chicago product")
    if lookup.strip():
        st.link_button("Open LinkedIn company search", linkedin_company_search_url(lookup.strip()))
    company_frame = company_jobs(lookup.strip()) if lookup.strip() else pd.DataFrame()
    if lookup.strip() and company_frame.empty:
        st.info("No active US jobs found for that company name.")
    elif not lookup.strip():
        st.caption("Type a company name to see active US jobs, LCA sponsorship roles, and LinkedIn search.")
    else:
        st.subheader("Active US official-site jobs")
        st.caption(f"{len(company_frame):,} active US jobs matched.")
        st.download_button(
            "Download this company job list (CSV)", csv_bytes(company_frame),
            file_name=f"jobpush_company_jobs_{chicago_today}.csv", mime="text/csv",
        )
        dataframe(company_frame, height=620)
    if lookup.strip():
        st.divider()
        st.subheader("LCA sponsorship roles")
        lca_role_frame = company_lca_roles(lookup.strip())
        if lca_role_frame.empty:
            st.info("No LCA sponsorship rows matched that company name.")
        else:
            st.caption(
                "这是历史 LCA 里的 SOC + raw job title 聚合，用来判断这家公司过去赞助过什么岗位。"
            )
            st.download_button(
                "Download company LCA roles (CSV)",
                csv_bytes(lca_role_frame),
                file_name=f"jobpush_company_lca_roles_{chicago_today}.csv",
                mime="text/csv",
            )
            st.dataframe(lca_role_frame, hide_index=True, use_container_width=True, height=460)

if selected_page == "Companies":
    st.subheader("Company priority tables")
    st.caption("Company-level scoring table with tier rank. Default includes P0/P1/P2/P3; use tiers to narrow.")
    target_tiers = tuple(st.multiselect("Company tiers", ["P0", "P1", "P2", "P3"], default=["P0", "P1", "P2", "P3"], key="company-target-tiers"))
    if not target_tiers:
        st.info("Select at least one P tier.")
    else:
        target_frame = company_targets(target_tiers)
        tier_summary = target_frame.groupby("priority_tier", as_index=False).agg(
            companies=("consolidation_key", "count"),
            average_score=("priority_score", "mean"),
            median_lca=("lca_count", "median"),
        )
        st.dataframe(tier_summary, hide_index=True, use_container_width=True)
        st.download_button(
            "Download company tier table (CSV)", csv_bytes(target_frame),
            file_name=f"jobpush_company_tiers_{'_'.join(target_tiers)}_{chicago_today}.csv", mime="text/csv",
        )
        st.dataframe(target_frame, hide_index=True, use_container_width=True, height=600)

if selected_page == "Scoring rules":
    st.subheader("Company priority and role-labeling rules")
    st.caption("这个区域展示公司 P 档从哪里来，以及 LCA/SOC 初始职业标注如何影响 target_role_score。")
    try:
        profile_source, profile_yaml = candidate_profile_yaml()
        st.subheader("Current candidate profile YAML")
        st.caption(f"Source: `{profile_source}`")
        st.code(profile_yaml, language="yaml")
    except Exception as exc:
        st.warning(f"Could not load candidate profile YAML: {exc}")
    st.markdown(
        """
### P 档定义

| Tier | 定义 | 用途 |
|---|---|---|
| P0 | 人工 override | Nicole 明确指定最高优先级公司 |
| P1 | `priority_score > 3` | 自动高优先级，优先找官网和爬取 |
| P2 | `priority_score = 3.0` 或 `2.5` | 自动中优先级，排在 P1 后 |
| P3 | `priority_score > 1` 且未达到 P2/P1 | 有额外信号但低优先级；展示和审核，默认不进日常 crawl schedule |
| NULL | `priority_score <= 1` 或 high-executive-only exclusion | 暂不进入优先级池；只有一条目标 SOC LCA 的薄证据公司也在这里 |

### `priority_score`

```text
priority_score =
    target_role_score
  + lca_count_score
  + chicago_score
  + product_role_score
  + product_manager_score
  + salary_score
  + linkedin_top_employer_score
```

`target_role_score` 来自你人工确认的目标 SOC code：只要公司至少一条 LCA 的
`soc_code` 命中 `jobpush.target_soc_roles`，就是 1，否则是 0。大部分后续加分都以它为前提。

| Score item | Points | Meaning |
|---|---:|---|
| `target_role_score` | +1 | At least one LCA SOC code is in the target SOC list |
| `lca_count_score` | +1 | Has target-role evidence and more than one LCA |
| `chicago_score` | +0.5 | Has target-role evidence and employer city is in Chicago metro |
| `product_role_score` | +1 | Has target-role evidence and LCA raw title matches product-class rules |
| `product_manager_score` | +0.25 | Has target-role evidence and LCA raw title is Product Manager / Technical Product Manager |
| `salary_score` | +1 | Has target-role evidence and valid minimum target-role salary is at least $90k |
| `linkedin_top_employer_score` | +1 | Has target-role evidence and matches LinkedIn Top Companies 2026 |

### 初始职业标注层

- 来源：LCA 原始数据里的 `soc_code` / `soc_title` / `job_title`
- 目标 SOC 表：`jobpush.target_soc_roles`
- 详细官网 title 表：`jobpush.job_title_labels`
- 人工 title 审核：写入 `jobpush.apply_manual_job_title_label(...)`
- Senior/Sr、Lead、Principal、硬件、医护、律师、教师、技工等 hard exclusion 会覆盖泛化匹配
        """
    )
    score_bands_all = query(
        """
        SELECT COALESCE(crawl_priority_tier, 'NULL') AS effective_tier,
               priority_score,
               COUNT(*) AS companies
        FROM jobpush.company_targets_consolidated
        GROUP BY 1, 2
        ORDER BY CASE COALESCE(crawl_priority_tier, 'NULL')
                   WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
                 priority_score DESC
        """
    )
    st.dataframe(score_bands_all, hide_index=True, use_container_width=True, height=360)
    st.download_button(
        "Download priority score bands (CSV)",
        csv_bytes(score_bands_all),
        file_name=f"jobpush_priority_rules_score_bands_{chicago_today}.csv",
        mime="text/csv",
    )
    st.divider()
    st.subheader("LCA / SOC role review table")
    st.caption(
        "这是当前生效的 SOC 大类复审表。改这张表会影响 target_role_score，进而影响公司 P 档。"
    )
    soc_status_options = st.multiselect(
        "SOC review status",
        ["target", "non_target", "review", ""],
        default=["target", "non_target"],
        format_func=lambda value: value or "(blank)",
        key="soc-review-status-filter",
    )
    if soc_status_options:
        soc_review = lca_soc_review_table(tuple(soc_status_options))
        soc_counts = soc_review.groupby("review_status", dropna=False).size().reset_index(name="rows")
        st.dataframe(soc_counts, hide_index=True, use_container_width=True)
        st.download_button(
            "Download SOC review table (CSV)",
            csv_bytes(soc_review),
            file_name=f"jobpush_lca_soc_review_current_{chicago_today}.csv",
            mime="text/csv",
        )
        soc_selection = st.dataframe(
            soc_review,
            hide_index=True,
            use_container_width=True,
            height=520,
            on_select="rerun",
            selection_mode="multi-row",
            key="soc_review_table",
        )
        selected_soc_rows = getattr(getattr(soc_selection, "selection", None), "rows", []) or []
        if selected_soc_rows:
            selected_soc = soc_review.iloc[[int(index) for index in selected_soc_rows]]
            st.caption(f"{len(selected_soc):,} SOC role row(s) selected.")
            st.download_button(
                "Download selected SOC rows (CSV)",
                csv_bytes(selected_soc),
                file_name=f"jobpush_lca_soc_review_selected_{chicago_today}.csv",
                mime="text/csv",
            )
    else:
        st.info("Select at least one SOC review status.")

    st.subheader("Raw LCA job-title aggregate search")
    st.caption(
        "Raw job title 很长尾；这里用于抽查和复审 SOC 下面的具体 title，不建议把每个 raw title 都变成长期规则。"
    )
    raw_col1, raw_col2, raw_col3 = st.columns([1.3, 1, 1])
    raw_search = raw_col1.text_input("Search raw title / SOC title", placeholder="e.g. Product, Customer, Chief")
    raw_statuses = tuple(raw_col2.multiselect(
        "SOC status for raw titles",
        ["target", "non_target", "review", ""],
        default=["target"],
        format_func=lambda value: value or "(blank)",
        key="raw-soc-status-filter",
    ))
    raw_limit = raw_col3.selectbox("Rows", [100, 250, 500, 1000], index=1)
    if raw_statuses and raw_search.strip():
        raw_review = lca_raw_job_review_sample(raw_statuses, raw_search.strip(), raw_limit)
        st.download_button(
            "Download raw job aggregate sample (CSV)",
            csv_bytes(raw_review),
            file_name=f"jobpush_lca_raw_job_review_sample_{chicago_today}.csv",
            mime="text/csv",
        )
        raw_selection = st.dataframe(
            raw_review,
            hide_index=True,
            use_container_width=True,
            height=520,
            on_select="rerun",
            selection_mode="multi-row",
            key="raw_lca_title_review_table",
        )
        selected_raw_rows = getattr(getattr(raw_selection, "selection", None), "rows", []) or []
        if selected_raw_rows:
            selected_raw = raw_review.iloc[[int(index) for index in selected_raw_rows]]
            st.caption(f"{len(selected_raw):,} raw role row(s) selected.")
            st.download_button(
                "Download selected raw role rows (CSV)",
                csv_bytes(selected_raw),
                file_name=f"jobpush_lca_raw_role_selected_{chicago_today}.csv",
                mime="text/csv",
            )
    elif not raw_search.strip():
        st.info("Enter a keyword before searching raw LCA titles. This avoids scanning the full LCA table from the dashboard.")
    else:
        st.info("Select at least one SOC status for raw job search.")

if selected_page == "Crawl monitor":
    st.divider()
    st.subheader("System logs")
    adapter_health = query("SELECT * FROM jobpush.crawl_adapter_health ORDER BY source_type")
    st.subheader("Adapter health · trailing 7 days")
    st.dataframe(adapter_health, hide_index=True, use_container_width=True)
    st.subheader("Recent runs")
    recent_runs = query(
        """
        SELECT run.started_at, target.canonical_name, site.source_type,
               run.status, run.requests_count, run.pages_fetched,
               run.parsed_job_count, run.new_job_count, run.closed_job_count,
               run.latency_ms, run.error_code, run.error_message
        FROM jobpush.crawl_runs run
        JOIN jobpush.career_sites site USING (site_id)
        JOIN jobpush.crawl_targets target USING (consolidation_key)
        ORDER BY run.started_at DESC
        LIMIT 100
        """
    )
    st.dataframe(recent_runs, hide_index=True, use_container_width=True, height=420)
    st.subheader("Recent failures")
    failures = recent_failures()
    if failures.empty:
        st.success("No failed crawl runs recorded.")
    else:
        st.dataframe(
            failures,
            hide_index=True,
            use_container_width=True,
            height=360,
            column_config={"site_url": st.column_config.LinkColumn("Site", display_text="Open ↗")},
        )

if selected_page == "Scoring rules":
    st.divider()
    st.subheader("Coverage")
    funnel = crawl_funnel().iloc[0]
    st.subheader("Company → scheduled crawl funnel")
    funnel_columns = st.columns(4)
    funnel_columns[0].metric("All companies", f"{int(funnel.all_companies):,}")
    p_tier_total = int(funnel.p0_companies + funnel.p1_companies + funnel.p2_companies + funnel.p3_companies)
    funnel_columns[1].metric("P0 / P1 / P2 / P3", f"{p_tier_total:,}")
    funnel_columns[2].metric("Verified sites", f"{int(funnel.companies_with_verified_site):,}")
    funnel_columns[3].metric("Schedulable sites", f"{int(funnel.schedulable_sites):,}")
    coverage = pd.DataFrame(
        {
            "stage": ["All companies", "Target SOC", "P-tier (P0-P3)", "Has candidates", "Verified", "US-ready", "Schedulable", "Due now"],
            "companies_or_sites": [
                funnel.all_companies,
                funnel.target_soc_companies,
                p_tier_total,
                funnel.companies_with_candidates,
                funnel.companies_with_verified_site,
                funnel.us_ready_sites,
                funnel.schedulable_sites,
                funnel.due_sites,
            ],
        }
    )
    st.dataframe(coverage, hide_index=True, use_container_width=True)
    st.caption("A verified site remains excluded until its adapter and safe US scope are known.")
    st.markdown("**Tier thresholds:** P1 `> 3`; P2 `= 3.0 or 2.5`; P3 `> 1 and below P2`; NULL `<= 1`.")
    st.subheader("Coverage by priority tier")
    st.dataframe(coverage_by_tier(), hide_index=True, use_container_width=True)
    st.subheader("All priority score bands")
    score_bands = query(
        """
        SELECT COALESCE(crawl_priority_tier, 'NULL') AS priority_tier,
               priority_score,
               count(*) AS companies,
               round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_of_all_companies,
               round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY COALESCE(crawl_priority_tier, 'NULL')), 2) AS pct_within_tier
        FROM jobpush.company_targets_consolidated
        GROUP BY 1, 2
        ORDER BY CASE COALESCE(crawl_priority_tier, 'NULL') WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
                 priority_score DESC
        """
    )
    st.download_button(
        "Download score distribution (CSV)", csv_bytes(score_bands),
        file_name=f"jobpush_priority_score_distribution_{chicago_today}.csv", mime="text/csv",
    )
    st.dataframe(score_bands, hide_index=True, use_container_width=True, height=360)
    st.subheader("P1 score distribution")
    p1_scores = p1_score_distribution()
    left, right = st.columns([1.1, 1])
    with left:
        st.bar_chart(p1_scores.set_index("priority_score"), height=300)
    with right:
        st.dataframe(p1_scores, hide_index=True, use_container_width=True, height=300)
