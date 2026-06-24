from __future__ import annotations

from datetime import datetime
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
        border-radius:18px;padding:15px 17px;box-shadow:0 8px 24px rgba(16,24,40,.045);}
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
               location, category, role_status, canonical_role,
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
                   ELSE role_status
               END AS role_stack,
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
chicago_today = datetime.now(ZoneInfo("America/Chicago")).date()
today_row = activity[activity["activity_date"] == chicago_today]
today = today_row.iloc[0] if not today_row.empty else pd.Series(dtype="int64")

metric_columns = st.columns(6)
metrics = [
    ("New today", int(today.get("new_jobs", 0))),
    ("Target today", int(today.get("new_target_jobs", 0))),
    ("Needs review", int(today.get("new_review_jobs", 0))),
    ("Closed today", int(today.get("closed_jobs", 0))),
    ("Crawl runs", int(today.get("crawl_runs", 0))),
    ("Failed runs", int(today.get("failed_runs", 0))),
]
for column, (label, value) in zip(metric_columns, metrics):
    column.metric(label, f"{value:,}")

st.sidebar.header("Job filters")
days = st.sidebar.select_slider("First seen within", options=[1, 3, 7, 14, 30, 90], value=7, format_func=lambda value: f"{value} days")
company = st.sidebar.text_input("Company contains")
title = st.sidebar.text_input("Title / role contains")
location = st.sidebar.text_input("Location contains")
tiers = tuple(st.sidebar.multiselect("Priority tier", ["P0", "P1", "P2"], default=["P0", "P1"]))
role_statuses = tuple(st.sidebar.multiselect("Role decision", ["target", "review", "non_target"], default=["target", "review"]))
app_statuses = tuple(st.sidebar.multiselect("Application status", ["new", "saved", "apply_next", "applied", "dismissed"], default=["new", "saved", "apply_next"]))
if not tiers or not role_statuses or not app_statuses:
    st.warning("Select at least one priority tier, role decision, and application status.")
    st.stop()

job_frame = jobs(days, company.strip(), title.strip(), location.strip(), tiers, role_statuses, app_statuses)
overview_tab, jobs_tab, breakdown_tab, company_tab, apply_tab, health_tab, coverage_tab = st.tabs(
    ["Overview", "New jobs", "Breakdowns", "Company view", "Application queue", "Crawl health", "Coverage"]
)

with overview_tab:
    left, right = st.columns([1.35, 1])
    with left:
        st.subheader("30-day activity")
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

with jobs_tab:
    st.subheader(f"{len(job_frame):,} active US jobs in this view")
    st.caption("Use the sidebar to filter by company, title/role, location, P-tier, role decision, and application status.")
    dataframe(job_frame)

with breakdown_tab:
    st.subheader("Role, company, and location breakdowns")
    if job_frame.empty:
        st.info("No jobs match the current filters.")
    else:
        left, right = st.columns(2)
        with left:
            st.caption("By role stack")
            st.bar_chart(job_frame.groupby("role_stack").size().sort_values(ascending=False), height=260)
            st.caption("By canonical role")
            role_counts = (
                job_frame.assign(canonical_role=job_frame["canonical_role"].fillna("Unlabeled"))
                .groupby("canonical_role")
                .size()
                .sort_values(ascending=False)
                .head(30)
            )
            st.dataframe(role_counts.reset_index(name="jobs"), hide_index=True, use_container_width=True, height=360)
        with right:
            st.caption("By company")
            company_counts = job_frame.groupby(["priority_tier", "canonical_name"]).size().reset_index(name="jobs")
            company_counts = company_counts.sort_values(["jobs", "canonical_name"], ascending=[False, True]).head(50)
            st.dataframe(company_counts, hide_index=True, use_container_width=True, height=300)
            st.caption("By location text")
            location_counts = (
                job_frame.assign(location=job_frame["location"].fillna("Location not listed"))
                .groupby("location")
                .size()
                .sort_values(ascending=False)
                .head(50)
            )
            st.dataframe(location_counts.reset_index(name="jobs"), hide_index=True, use_container_width=True, height=320)

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
        dataframe(company_frame, height=620)

with apply_tab:
    actionable = job_frame[job_frame["role_status"] == "target"].copy()
    st.subheader("Target roles to review and apply")
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
    st.subheader("P1 score distribution")
    p1_scores = p1_score_distribution()
    left, right = st.columns([1.1, 1])
    with left:
        st.bar_chart(p1_scores.set_index("priority_score"), height=300)
    with right:
        st.dataframe(p1_scores, hide_index=True, use_container_width=True, height=300)
