from __future__ import annotations

import os
from typing import Any

import pandas as pd
import psycopg2
import streamlit as st


@st.cache_resource
def connection():
    return psycopg2.connect(
        host=os.environ["JOBPUSH_DB_HOST"],
        port=int(os.environ.get("JOBPUSH_DB_PORT", "5432")),
        dbname=os.environ["JOBPUSH_DB_NAME"],
        user=os.environ["JOBPUSH_DB_USER"],
        password=os.environ["JOBPUSH_DB_PASSWORD"],
        sslmode=os.environ.get("JOBPUSH_DB_SSLMODE", "require"),
        connect_timeout=10,
    )


def discard_connection(conn) -> None:
    if not conn.closed:
        try:
            conn.rollback()
        except psycopg2.Error:
            pass
        conn.close()
    connection.clear()


def query(sql: str, params: tuple[Any, ...] = ()) -> pd.DataFrame:
    for attempt in range(2):
        conn = connection()
        try:
            with conn.cursor() as cursor:
                cursor.execute(sql, params)
                rows = cursor.fetchall()
                columns = [item.name for item in cursor.description]
            conn.commit()
            return pd.DataFrame(rows, columns=columns)
        except (psycopg2.InterfaceError, psycopg2.OperationalError):
            discard_connection(conn)
            if attempt:
                raise
        except Exception:
            discard_connection(conn)
            raise
    raise RuntimeError("database query retry exhausted")


def execute(sql: str, params: tuple[Any, ...]) -> None:
    conn = connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(sql, params)
        conn.commit()
    except Exception:
        discard_connection(conn)
        raise
