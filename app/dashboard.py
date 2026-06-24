from __future__ import annotations

from datetime import date

import pandas as pd
import streamlit as st

from db import execute, query


st.set_page_config(page_title="JobPush Daily", page_icon="↗", layout="wide")
st.markdown(
    """
    <style>
      .block-container {padding-top: 1.6rem; padding-bottom: 3rem;}
      [data-testid="stMetric"] {background:#f7f8fa;border:1px solid #e7e9ee;
        border-radius:14px;padding:14px 16px;}
      h1 {letter-spacing:-0.04em;}
      .quiet {color:#667085;font-size:.92rem;}
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
def jobs(days: int, company: str, tiers: tuple[str, ...], role_statuses: tuple[str, ...]) -> pd.DataFrame:
    return query(
        """
        SELECT site_id, external_job_id, canonical_name, priority_tier, title,
               location, role_status, canonical_role, application_status,
               first_seen_at, last_seen_at, job_url
        FROM jobpush.dashboard_jobs
        WHERE first_seen_at >= now() - make_interval(days => %s)
          AND (%s = '' OR canonical_name ILIKE '%%' || %s || '%%')
          AND priority_tier = ANY(%s)
          AND role_status = ANY(%s)
        ORDER BY first_seen_at DESC, canonical_name, title
        LIMIT 3000
        """,
        (days, company, company, list(tiers), list(role_statuses)),
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


st.title("JobPush Daily")
st.markdown('<div class="quiet">US career-site monitoring · America/Chicago</div>', unsafe_allow_html=True)

activity = daily_activity()
today_row = activity[activity["activity_date"] == date.today()]
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
tiers = tuple(st.sidebar.multiselect("Priority tier", ["P0", "P1", "P2"], default=["P0", "P1", "P2"]))
role_statuses = tuple(st.sidebar.multiselect("Role decision", ["target", "review", "non_target"], default=["target", "review"]))
if not tiers or not role_statuses:
    st.warning("Select at least one priority tier and one role decision.")
    st.stop()

job_frame = jobs(days, company.strip(), tiers, role_statuses)
overview_tab, jobs_tab, apply_tab, health_tab, coverage_tab = st.tabs(
    ["Overview", "New jobs", "Application queue", "Crawl health", "Coverage"]
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
    st.caption("Target roles appear first when you select only target + review in the sidebar.")
    dataframe(job_frame)

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
