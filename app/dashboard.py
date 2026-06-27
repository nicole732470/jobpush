from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pandas as pd
import streamlit as st

from db import execute, query


st.set_page_config(page_title="JobPush Ops", page_icon="↗", layout="wide")
st.markdown(
    """
    <style>
      .stApp {background: linear-gradient(180deg,#fbfcff 0%,#f6f8fb 42%,#f7f7f4 100%);}
      .block-container {padding-top: 1.4rem; padding-bottom: 3rem; max-width: 1500px;}
      [data-testid="stMetric"] {background:rgba(255,255,255,.88);border:1px solid #e4e7ec;
        border-radius:18px;padding:15px 17px;box-shadow:0 8px 24px rgba(16,24,40,.045); min-height:116px;}
      h1 {letter-spacing:-0.045em; margin-bottom:.15rem;}
      h2, h3 {letter-spacing:-0.025em;}
      .quiet {color:#667085;font-size:.92rem;}
      .hero {padding:18px 22px;border-radius:24px;background:linear-gradient(135deg,#111827 0%,#25314a 58%,#43506b 100%);
        color:#fff;margin-bottom:18px;box-shadow:0 16px 38px rgba(17,24,39,.16);}
      .hero .quiet {color:#d0d5dd;}
      .section-card {background:rgba(255,255,255,.8);border:1px solid #eaecf0;border-radius:18px;padding:14px 16px;}
      div[data-testid="stDataFrame"] {border-radius:16px; overflow:hidden;}
    </style>
    """,
    unsafe_allow_html=True,
)


@st.cache_data(ttl=60)
def daily_activity() -> pd.DataFrame:
    return query("SELECT * FROM jobpush.dashboard_daily_activity ORDER BY activity_date DESC")


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
            WHERE enabled AND priority_tier IN ('P0','P1','P2')
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
            WHERE target.enabled AND target.priority_tier IN ('P0','P1','P2')
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
        ORDER BY CASE target_counts.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END
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
        WHERE target.enabled AND target.priority_tier IN ('P0','P1','P2')
        GROUP BY target.priority_tier
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END
        """
    )


@st.cache_data(ttl=60)
def today_crawl_progress() -> pd.DataFrame:
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
          AND target.priority_tier IN ('P0','P1','P2')
        GROUP BY target.priority_tier
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END
        """
    )


@st.cache_data(ttl=60)
def crawl_completion_summary() -> pd.DataFrame:
    return query(
        """
        WITH target AS (
            SELECT consolidation_key, priority_tier, priority_score
            FROM jobpush.crawl_targets
            WHERE enabled AND priority_tier IN ('P0','P1','P2')
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
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END
        """
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
              AND target.priority_tier IN ('P0','P1','P2')
        )
        SELECT failure_reason,
               next_action,
               COUNT(*) AS sites,
               STRING_AGG(canonical_name, ', ' ORDER BY canonical_name) AS example_companies
        FROM failed
        GROUP BY failure_reason, next_action
        ORDER BY sites DESC, failure_reason
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
        SELECT target.consolidation_key, target.canonical_name,
               target.priority_tier, target.priority_score,
               target.priority_source, target.discovery_status,
               consolidated.lca_count, consolidated.target_role_lca_count,
               consolidated.target_role_score, consolidated.lca_count_score,
               consolidated.chicago_score, consolidated.product_role_score,
               consolidated.product_manager_score, consolidated.salary_score,
               consolidated.linkedin_top_employer_score,
               consolidated.employer_city, consolidated.employer_state
        FROM jobpush.crawl_targets target
        JOIN jobpush.company_targets_consolidated consolidated USING (consolidation_key)
        WHERE target.enabled AND target.priority_tier = ANY(%s)
        ORDER BY CASE target.priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
                 target.priority_score DESC, target.canonical_name
        """,
        (list(tiers),),
    )


@st.cache_data(ttl=60)
def title_review_queue(limit: int = 2000) -> pd.DataFrame:
    frame = query(
        """
        SELECT normalized_title, example_title, active_posting_count,
               company_count, suggestion_reason, matched_soc_codes,
               matched_soc_titles
        FROM jobpush.job_title_review_queue
        ORDER BY active_posting_count DESC, company_count DESC, normalized_title
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


@st.cache_data(ttl=60)
def jobs(
    days: int,
    company: str,
    title: str,
    location: str,
    tiers: tuple[str, ...],
    role_statuses: tuple[str, ...],
    app_statuses: tuple[str, ...],
) -> pd.DataFrame:
    return query(
        """
        SELECT site_id, external_job_id, canonical_name, priority_tier, title,
               location, category, employment_type, role_status, canonical_role,
               CASE
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%%product%%manager%%'
                       OR normalized_title LIKE '%%business%%analyst%%'
                       OR normalized_title LIKE '%%data%%analyst%%'
                       OR normalized_title LIKE '%%strategy%%analyst%%'
                       OR normalized_title LIKE '%%operations%%analyst%%'
                   ) THEN 'stack_1_business_product_data'
                   WHEN role_status = 'target' AND (
                       normalized_title LIKE '%%software%%'
                       OR normalized_title LIKE '%%systems%%analyst%%'
                       OR normalized_title LIKE '%%information%%system%%'
                   ) THEN 'stack_2_software_systems'
                   WHEN role_status = 'target' THEN 'stack_3_other_target'
                   WHEN role_status = 'review' THEN 'needs_review'
                   ELSE 'excluded_non_target'
               END AS role_stack,
               CASE
                   WHEN role_status = 'non_target' THEN 'excluded_non_target'
                   WHEN role_status = 'review' THEN 'needs_review'
                   WHEN normalized_title LIKE '%%intern%%'
                        OR normalized_title LIKE '%%internship%%'
                        OR normalized_title LIKE '%%co op%%'
                        OR normalized_title LIKE '%%co-op%%' THEN 'internship'
                   WHEN normalized_title LIKE '%%forward deployed engineer%%'
                        OR normalized_title LIKE '%%forward-deployed engineer%%' THEN 'forward_deployed_engineer'
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
                   WHEN normalized_title LIKE '%%data%%analyst%%'
                        OR normalized_title LIKE '%%business intelligence%%'
                        OR normalized_title LIKE '%%bi analyst%%' THEN 'data_analytics_bi'
                   WHEN normalized_title LIKE '%%business%%analyst%%' THEN 'business_analyst'
                   WHEN normalized_title LIKE '%%operations%%analyst%%'
                        OR normalized_title LIKE '%%strategy%%analyst%%' THEN 'strategy_operations'
                   WHEN normalized_title LIKE '%%marketing%%' THEN 'marketing'
                   WHEN normalized_title LIKE '%%sales%%' THEN 'sales'
                   ELSE COALESCE(NULLIF(canonical_role, ''), 'other')
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
        FROM jobpush.dashboard_jobs
        WHERE first_seen_at >= now() - make_interval(days => %s)
          AND (%s = '' OR canonical_name ILIKE '%%' || %s || '%%')
          AND (%s = '' OR title ILIKE '%%' || %s || '%%' OR canonical_role ILIKE '%%' || %s || '%%')
          AND (%s = '' OR location ILIKE '%%' || %s || '%%')
          AND priority_tier = ANY(%s)
          AND role_status = ANY(%s)
          AND application_status = ANY(%s)
        ORDER BY first_seen_at DESC, canonical_name, title
        LIMIT 5000
        """,
        (
            days,
            company,
            company,
            title,
            title,
            title,
            location,
            location,
            list(tiers),
            list(role_statuses),
            list(app_statuses),
        ),
    )


@st.cache_data(ttl=60)
def company_jobs(company: str) -> pd.DataFrame:
    return query(
        """
        SELECT canonical_name, priority_tier, title, location,
               role_status, canonical_role, application_status,
               first_seen_at, last_seen_at, job_url
        FROM jobpush.dashboard_jobs
        WHERE %s <> '' AND canonical_name ILIKE '%%' || %s || '%%'
        ORDER BY CASE role_status WHEN 'target' THEN 0 WHEN 'review' THEN 1 ELSE 2 END,
                 first_seen_at DESC, title
        LIMIT 1000
        """,
        (company, company),
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
    "stack_2_software_systems": "Track 2 · Software / Systems",
    "stack_3_other_target": "Track 3 · Other target",
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
    "data_analytics_bi": "Data Analytics / BI",
    "business_analyst": "Business Analyst",
    "strategy_operations": "Strategy / Operations",
    "marketing": "Marketing",
    "sales": "Sales",
    "needs_review": "Needs review",
    "excluded_non_target": "Excluded / non-target",
    "other": "Other",
}

TRACK_OPTIONS = [
    "Track 1 · Business / Product / Data",
    "Track 2 · Software / Systems",
    "Track 3 · Other target",
    "Needs review",
    "Excluded / non-target",
]

TRACK_VALUE_TO_LABEL = {
    "stack_1_business_product_data": "Track 1 · Business / Product / Data",
    "stack_2_software_systems": "Track 2 · Software / Systems",
    "stack_3_other_target": "Track 3 · Other target",
    "needs_review": "Needs review",
    "excluded_non_target": "Excluded / non-target",
}
TRACK_LABEL_TO_VALUE = {label: value for value, label in TRACK_VALUE_TO_LABEL.items()}

ROLE_FAMILY_OPTIONS = [
    "Internship",
    "Forward Deployed Engineer",
    "Product Manager",
    "Program Manager",
    "Project Manager",
    "Systems Engineering",
    "Software Engineering",
    "Data Science / ML",
    "Data Analytics / BI",
    "Business Analyst",
    "Strategy / Operations",
    "Marketing",
    "Sales",
    "Needs review",
    "Excluded / non-target",
    "Other",
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
      <div class="quiet">P0/P1 career-site monitoring · all companies · dates shown in America/Chicago</div>
    </div>
    """,
    unsafe_allow_html=True,
)

activity = daily_activity()
completion = crawl_completion_summary()
chicago_today = datetime.now(ZoneInfo("America/Chicago")).date()
today_row = activity[activity["activity_date"] == chicago_today]
today = today_row.iloc[0] if not today_row.empty else pd.Series(dtype="int64")

metric_columns = st.columns(6)
metrics = [
    ("New jobs today", int(today.get("new_jobs", 0))),
    ("Target jobs today", int(today.get("new_target_jobs", 0))),
    ("Review titles today", int(today.get("new_review_jobs", 0))),
    ("Closed jobs today", int(today.get("closed_jobs", 0))),
    ("Site crawl attempts", int(today.get("crawl_runs", 0))),
    ("Failed site attempts", int(today.get("failed_runs", 0))),
]
for column, (label, value) in zip(metric_columns, metrics):
    column.metric(label, f"{value:,}")
st.caption(
    "Site crawl attempts = 今天请求过的网站次数；New jobs = 第一次进入数据库的职位数；"
    "Closed jobs = 之前见过、这次快照里消失的职位。所以这些数字不会一一相等。"
)
if not completion.empty:
    p0p1_completion = completion[completion["priority_tier"].isin(["P0", "P1"])]
    p0p1_companies = int(p0p1_completion["companies"].sum())
    p0p1_enabled = int(p0p1_completion["companies_with_enabled_site"].sum())
    p0p1_succeeded = int(p0p1_completion["companies_succeeded_ever"].sum())
    p0p1_due = int(p0p1_completion["due_sites"].sum())
    p0p1_attempted_today = int(p0p1_completion["companies_attempted_today"].sum())
    latest_started = p0p1_completion["latest_started_at"].dropna().max()
    completion_columns = st.columns(5)
    completion_columns[0].metric("P0+P1 companies", f"{p0p1_companies:,}")
    completion_columns[1].metric("Can crawl now", f"{p0p1_enabled:,}", f"{(100 * p0p1_enabled / p0p1_companies):.1f}%" if p0p1_companies else None)
    completion_columns[2].metric("Ever succeeded", f"{p0p1_succeeded:,}", f"{(100 * p0p1_succeeded / p0p1_companies):.1f}%" if p0p1_companies else None)
    completion_columns[3].metric("Due / unfinished now", f"{p0p1_due:,}")
    completion_columns[4].metric("Attempted today", f"{p0p1_attempted_today:,}")
    if pd.notna(latest_started):
        st.caption(f"Latest P0/P1 crawl started at {pd.to_datetime(latest_started, utc=True).tz_convert('America/Chicago'):%Y-%m-%d %I:%M %p CT}.")

st.sidebar.header("Job filters")
st.sidebar.caption(
    "只控制“Jobs to apply / Company lookup”。爬虫覆盖率、失败原因、系统日志这些运营 tab 使用自己的统计口径。"
)
date_window = st.sidebar.date_input(
    "First seen date range",
    value=(chicago_today - timedelta(days=6), chicago_today),
    min_value=chicago_today - timedelta(days=90),
    max_value=chicago_today,
)
if isinstance(date_window, tuple):
    start_date = date_window[0]
    end_date = date_window[1] if len(date_window) > 1 else date_window[0]
else:
    start_date = date_window
    end_date = date_window
if start_date > end_date:
    st.sidebar.error("Start date must be before end date.")
    st.stop()
days = max(1, min(90, (chicago_today - start_date).days + 1))
company = st.sidebar.text_input("Company contains")
title = st.sidebar.text_input("Title / role contains")
location = st.sidebar.text_input("Location contains")
priority_choice = st.sidebar.selectbox("Priority tier", ["P0 + P1", "P0 only", "P1 only", "P2 only", "All P tiers"])
role_choice = st.sidebar.selectbox(
    "Role decision",
    ["target only", "target + needs review", "needs review only", "all decisions"],
    help="target = 推荐申请；needs review = 规则/模型还不够确定，用来抽样优化；excluded/non-target = 不推荐申请。",
)
app_choice = st.sidebar.selectbox(
    "My application status",
    ["open items", "new only", "saved/apply next", "all statuses"],
    help="这是你的个人投递状态，不是职位分类。new=还没处理，saved=收藏，apply_next=下一批投，applied=已投，dismissed=不投。",
)
tiers = {
    "P0 + P1": ("P0", "P1"),
    "P0 only": ("P0",),
    "P1 only": ("P1",),
    "P2 only": ("P2",),
    "All P tiers": ("P0", "P1", "P2"),
}[priority_choice]
role_statuses = {
    "target only": ("target",),
    "target + needs review": ("target", "review"),
    "needs review only": ("review",),
    "all decisions": ("target", "review", "non_target"),
}[role_choice]
app_statuses = {
    "open items": ("new", "saved", "apply_next"),
    "new only": ("new",),
    "saved/apply next": ("saved", "apply_next"),
    "all statuses": ("new", "saved", "apply_next", "applied", "dismissed"),
}[app_choice]
if not tiers or not role_statuses or not app_statuses:
    st.warning("Select at least one priority tier, role decision, and application status.")
    st.stop()

job_frame = jobs(days, company.strip(), title.strip(), location.strip(), tiers, role_statuses, app_statuses)
if not job_frame.empty:
    first_seen_dates = pd.to_datetime(job_frame["first_seen_at"], utc=True).dt.tz_convert("America/Chicago").dt.date
    job_frame = job_frame[(first_seen_dates >= start_date) & (first_seen_dates <= end_date)].copy()
overview_tab, jobs_tab, rollout_tab, review_tab, company_tab, target_tab, apply_tab, health_tab, coverage_tab = st.tabs(
    [
        "Home",
        "Jobs to apply",
        "Crawl monitor",
        "Title review",
        "Company lookup",
        "Company priority",
        "Application status",
        "System logs",
        "Coverage",
    ]
)

with overview_tab:
    left, right = st.columns([1.35, 1])
    with left:
        st.subheader("30-day job discovery")
        chart = activity.sort_values("activity_date").set_index("activity_date")
        st.line_chart(chart[["new_target_jobs", "new_review_jobs", "closed_jobs"]], height=330)
    with right:
        st.subheader("What needs attention")
        alerts = query(
            """
            SELECT priority_tier, canonical_name, source_type, alert_type,
                   consecutive_failures, last_crawled_at
            FROM jobpush.crawl_site_alerts
            ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
                     canonical_name
            LIMIT 30
            """
        )
        if alerts.empty:
            st.success("No active crawler alerts.")
        else:
            st.dataframe(alerts, hide_index=True, use_container_width=True, height=330)
    st.subheader("Today’s crawl progress by tier")
    progress_today = today_crawl_progress()
    if progress_today.empty:
        st.info("No crawl attempts have been recorded today yet.")
    else:
        st.dataframe(progress_today, hide_index=True, use_container_width=True)

with rollout_tab:
    st.subheader("P0 / P1 / P2 company crawl rollout")
    st.caption(
        "这个 tab 回答三个问题：总共有多少公司、今天/目前跑了多少、没跑成功主要卡在哪里。"
    )
    rollout = crawl_rollout_by_tier()
    p0p1 = rollout[rollout["priority_tier"].isin(["P0", "P1"])]
    p0p1_total = int(p0p1["companies"].sum()) if not p0p1.empty else 0
    p0p1_success = int(p0p1["succeeded_companies"].sum()) if not p0p1.empty else 0
    p0p1_attempted = int(p0p1["attempted_companies"].sum()) if not p0p1.empty else 0
    p0p1_waiting = int(p0p1["due_now_companies"].sum()) if not p0p1.empty else 0
    rollout_cols = st.columns(4)
    rollout_cols[0].metric("P0+P1 companies", f"{p0p1_total:,}")
    rollout_cols[1].metric("Successfully crawled", f"{p0p1_success:,}", f"{(100 * p0p1_success / p0p1_total):.1f}%" if p0p1_total else None)
    rollout_cols[2].metric("Attempted at least once", f"{p0p1_attempted:,}", f"{(100 * p0p1_attempted / p0p1_total):.1f}%" if p0p1_total else None)
    rollout_cols[3].metric("Due / waiting now", f"{p0p1_waiting:,}")

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
WHERE target.enabled AND target.priority_tier IN ('P0','P1','P2')
GROUP BY target.priority_tier
ORDER BY target.priority_tier;
            """.strip(),
            language="sql",
        )

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

with jobs_tab:
    st.subheader(f"{len(job_frame):,} active US jobs in this view")
    st.caption(
        "核心用途：看选定日期范围内新发现/仍 active 的岗位，然后点 apply link。默认只显示 target；"
        "只有在抽查分类器时才把 Needs review 加进来。"
    )
    if job_frame.empty:
        st.info("No jobs match the current filters.")
    else:
        segmented = job_frame.copy()
        segmented["first_seen_date"] = pd.to_datetime(segmented["first_seen_at"], utc=True).dt.tz_convert("America/Chicago").dt.date
        segmented["first_seen_ct"] = pd.to_datetime(segmented["first_seen_at"], utc=True).dt.tz_convert("America/Chicago").dt.strftime("%Y-%m-%d %I:%M %p")
        segmented["track_label"] = segmented["role_stack"].map(TRACK_LABELS).fillna(segmented["role_stack"].fillna("Unlabeled"))
        segmented["role_family_label"] = segmented["role_family"].map(ROLE_FAMILY_LABELS).fillna(segmented["role_family"].fillna("Other"))
        selected_period_segment = segmented[
            (segmented["first_seen_date"] >= start_date) & (segmented["first_seen_date"] <= end_date)
        ]
        period_label = f"{start_date:%Y-%m-%d} to {end_date:%Y-%m-%d}" if start_date != end_date else f"{start_date:%Y-%m-%d}"

        segment_metrics = st.columns(6)
        segment_metrics[0].metric("Jobs in view", f"{len(segmented):,}")
        segment_metrics[1].metric("Selected period", f"{len(selected_period_segment):,}")
        segment_metrics[2].metric("Internship", f"{int((segmented['employment_bucket'] == 'internship').sum()):,}")
        segment_metrics[3].metric("Chicago / IL", f"{int((segmented['location_bucket'] == 'chicago_or_illinois').sum()):,}")
        segment_metrics[4].metric("Product Manager", f"{int((segmented['role_family'] == 'product_manager').sum()):,}")
        segment_metrics[5].metric("Systems Eng.", f"{int((segmented['role_family'] == 'systems_engineering').sum()):,}")

        filter_left, filter_mid, filter_right = st.columns(3)
        track_choice = filter_left.selectbox(
            "Track",
            ["All tracks"] + TRACK_OPTIONS,
        )
        role_family_choice = filter_mid.selectbox(
            "Role family",
            ["All role families"] + ROLE_FAMILY_OPTIONS,
        )
        employment_choice = filter_right.selectbox(
            "Intern / full-time",
            ["All employment types"] + EMPLOYMENT_BUCKET_OPTIONS,
        )
        selected_tracks = TRACK_OPTIONS if track_choice == "All tracks" else [track_choice]
        selected_role_families = ROLE_FAMILY_OPTIONS if role_family_choice == "All role families" else [role_family_choice]
        selected_employment = EMPLOYMENT_BUCKET_OPTIONS if employment_choice == "All employment types" else [employment_choice]
        filtered_jobs = segmented[
            segmented["track_label"].isin(selected_tracks)
            & segmented["role_family_label"].isin(selected_role_families)
            & segmented["employment_bucket"].isin(selected_employment)
        ].sort_values("first_seen_at", ascending=False)

        segment_dimension_label = st.selectbox("Summary by", list(SEGMENT_DIMENSIONS.keys()), index=1)
        segment_dimension = SEGMENT_DIMENSIONS[segment_dimension_label]
        daily_summary = (
            filtered_jobs.groupby([segment_dimension, "first_seen_date"], dropna=False)
            .size()
            .reset_index(name="jobs")
            .pivot(index=segment_dimension, columns="first_seen_date", values="jobs")
            .fillna(0)
        )
        if daily_summary.empty:
            st.info("No jobs match the track / role / employment filters.")
        else:
            daily_summary["Total"] = daily_summary.sum(axis=1)
            daily_summary = daily_summary.sort_values("Total", ascending=False)
            ordered_columns = ["Total"] + [column for column in daily_summary.columns if column != "Total"]
            st.dataframe(
                daily_summary[ordered_columns].reset_index(),
                hide_index=True,
                use_container_width=True,
                height=min(520, 72 + 36 * len(daily_summary)),
            )

        left, right = st.columns(2)
        with left:
            st.subheader(f"{period_label} by track / role")
            period_roles = (
                selected_period_segment.groupby(["track_label", "role_family_label"], dropna=False)
                .size()
                .reset_index(name="jobs")
                .sort_values(["jobs", "track_label", "role_family_label"], ascending=[False, True, True])
            )
            st.dataframe(period_roles, hide_index=True, use_container_width=True, height=330)
        with right:
            st.subheader(f"{period_label} by location / employment")
            period_market = (
                selected_period_segment.groupby(["location_bucket", "employment_bucket", "seniority_bucket"], dropna=False)
                .size()
                .reset_index(name="jobs")
                .sort_values(["jobs", "location_bucket"], ascending=[False, True])
            )
            st.dataframe(period_market, hide_index=True, use_container_width=True, height=330)

        st.subheader(f"{period_label} Track 1/2/3 summary")
        period_track_summary = (
            selected_period_segment.groupby("track_label", dropna=False)
            .agg(
                jobs=("external_job_id", "count"),
                companies=("canonical_name", "nunique"),
                internships=("employment_bucket", lambda values: int((values == "internship").sum())),
                full_time_or_unknown=("employment_bucket", lambda values: int((values == "full_time_or_unknown").sum())),
                chicago_or_il=("location_bucket", lambda values: int((values == "chicago_or_illinois").sum())),
            )
            .reset_index()
            .sort_values("jobs", ascending=False)
        )
        st.dataframe(period_track_summary, hide_index=True, use_container_width=True, height=220)

        st.subheader("All matching jobs · track × role family summary")
        track_summary = (
            segmented.groupby(["track_label", "role_family_label"], dropna=False)
            .agg(
                jobs=("external_job_id", "count"),
                companies=("canonical_name", "nunique"),
                chicago_or_il=("location_bucket", lambda values: int((values == "chicago_or_illinois").sum())),
                internships=("employment_bucket", lambda values: int((values == "internship").sum())),
                full_time_or_unknown=("employment_bucket", lambda values: int((values == "full_time_or_unknown").sum())),
            )
            .reset_index()
            .sort_values(["track_label", "jobs"], ascending=[True, False])
        )
        st.dataframe(track_summary, hide_index=True, use_container_width=True, height=420)

        st.subheader("Filtered job list · newest first")
        display_columns = [
            "first_seen_ct", "canonical_name", "priority_tier", "title", "location",
            "track_label", "role_family_label", "employment_bucket", "seniority_bucket",
            "application_status", "job_url",
        ]
        st.download_button(
            "Download filtered jobs (CSV)",
            csv_bytes(filtered_jobs),
            file_name=f"jobpush_jobs_filtered_{chicago_today}.csv",
            mime="text/csv",
        )
        st.dataframe(
            filtered_jobs[display_columns],
            hide_index=True,
            use_container_width=True,
            height=620,
            column_config={"job_url": st.column_config.LinkColumn("Apply link", display_text="Open ↗")},
        )

        with st.expander("SQL behind this job view"):
            st.code(
                """
SELECT *
FROM jobpush.dashboard_jobs
WHERE first_seen_at >= now() - make_interval(days => :days)
  AND priority_tier = ANY(:tiers)
  AND role_status = ANY(:role_statuses)
  AND application_status = ANY(:app_statuses)
ORDER BY first_seen_at DESC, canonical_name, title
LIMIT 5000;
                """.strip(),
                language="sql",
            )
        st.download_button(
            "Download segmented jobs (CSV)",
            csv_bytes(segmented),
            file_name=f"jobpush_segmented_jobs_{chicago_today}.csv",
            mime="text/csv",
        )
        st.download_button(
            "Download track summary (CSV)",
            csv_bytes(track_summary),
            file_name=f"jobpush_track_summary_{chicago_today}.csv",
            mime="text/csv",
        )

with review_tab:
    st.subheader("Title samples for improving the classifier")
    st.caption(
        "这里只是抽样训练/修正规则用，不是每天申请流程。已被人工标注、YAML/profile hard rules、"
        "local ML 高置信度处理过的 title 会从这里移除。"
    )
    review_limit = st.select_slider("Review batch size", options=[100, 250, 500, 1000, 2000], value=500)
    review_frame = title_review_queue(review_limit)
    st.download_button(
        "Download title review batch (CSV)", csv_bytes(review_frame),
        file_name=f"jobpush_title_review_{chicago_today}_{review_limit}.csv", mime="text/csv",
    )
    dataframe(review_frame, height=610)

with company_tab:
    st.subheader("Company job list")
    lookup = st.text_input("Open one company", value=company.strip(), placeholder="e.g. Pfizer, Google, StackAdapt")
    company_frame = company_jobs(lookup.strip()) if lookup.strip() else pd.DataFrame()
    if lookup.strip() and company_frame.empty:
        st.info("No active US jobs found for that company name.")
    elif not lookup.strip():
        st.caption("Type a company name to see its active US jobs and links.")
    else:
        st.caption(f"{len(company_frame):,} active US jobs matched.")
        st.download_button(
            "Download this company job list (CSV)", csv_bytes(company_frame),
            file_name=f"jobpush_company_jobs_{chicago_today}.csv", mime="text/csv",
        )
        dataframe(company_frame, height=620)

with target_tab:
    st.subheader("Company priority tables")
    st.caption("This is where the 4,649 P0+P1 company universe lives. Select P tiers and download the company-level scoring table.")
    target_tiers = tuple(st.multiselect("Company tiers", ["P0", "P1", "P2"], default=["P0", "P1"], key="company-target-tiers"))
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

with apply_tab:
    actionable = job_frame[job_frame["role_status"] == "target"].copy()
    st.subheader("Target roles to review and apply")
    with st.expander("What do new / saved / apply_next / applied / dismissed mean?"):
        st.markdown(
            "- **new**: newly discovered; no decision yet.\n"
            "- **saved**: interesting, but not queued for immediate application.\n"
            "- **apply_next**: next application shortlist.\n"
            "- **applied**: application submitted.\n"
            "- **dismissed**: reviewed and intentionally skipped."
        )
    if actionable.empty:
        st.info("No target roles match the current filters.")
    else:
        labels = {
            f"{row.canonical_name} · {row.title} · {row.location or 'Location not listed'}": (row.site_id, row.external_job_id)
            for row in actionable.itertuples()
        }
        selected = st.selectbox("Choose a job", labels.keys())
        site_id, external_job_id = labels[selected]
        notes = st.text_input("Optional note", placeholder="Referral, deadline, contact, next step…")
        action_columns = st.columns(4)
        actions = [
            ("Save", "saved"),
            ("Apply next", "apply_next"),
            ("Applied", "applied"),
            ("Dismiss", "dismissed"),
        ]
        for column, (button_label, status) in zip(action_columns, actions):
            if column.button(button_label, use_container_width=True, key=f"{status}-{site_id}-{external_job_id}"):
                execute(
                    "SELECT jobpush.set_job_application_action(%s, %s, %s, %s, 'nicole')",
                    (int(site_id), str(external_job_id), status, notes),
                )
                jobs.clear()
                st.success(f"Saved as {status}.")
                st.rerun()
        dataframe(actionable, height=410)

with health_tab:
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

with coverage_tab:
    funnel = crawl_funnel().iloc[0]
    st.subheader("Company → scheduled crawl funnel")
    funnel_columns = st.columns(4)
    funnel_columns[0].metric("All companies", f"{int(funnel.all_companies):,}")
    funnel_columns[1].metric("P0 / P1 / P2", f"{int(funnel.p0_companies + funnel.p1_companies + funnel.p2_companies):,}")
    funnel_columns[2].metric("Verified sites", f"{int(funnel.companies_with_verified_site):,}")
    funnel_columns[3].metric("Schedulable sites", f"{int(funnel.schedulable_sites):,}")
    coverage = pd.DataFrame(
        {
            "stage": ["All companies", "Target SOC", "P-tier", "Has candidates", "Verified", "US-ready", "Schedulable", "Due now"],
            "companies_or_sites": [
                funnel.all_companies,
                funnel.target_soc_companies,
                funnel.p0_companies + funnel.p1_companies + funnel.p2_companies,
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
    st.subheader("Coverage by priority tier")
    st.dataframe(coverage_by_tier(), hide_index=True, use_container_width=True)
    st.subheader("All priority score bands")
    score_bands = query(
        """
        SELECT priority_tier, priority_score, count(*) AS companies,
               round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY priority_tier), 2) AS pct_within_tier
        FROM jobpush.crawl_targets
        WHERE enabled AND priority_tier IN ('P0','P1','P2')
        GROUP BY priority_tier, priority_score
        ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
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
