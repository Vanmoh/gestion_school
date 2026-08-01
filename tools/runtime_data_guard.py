#!/usr/bin/env python3
"""Runtime data guard for the API MySQL database.

Purpose:
- Detect data drift between expected runtime dataset and actual runtime DB.
- Fail fast before launching UI workflows that depend on seeded data.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass

import pymysql


@dataclass
class Counts:
    classes: int
    students_active: int
    subjects: int
    teachers: int


def _connect(host: str, port: int, user: str, password: str, database: str):
    return pymysql.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        database=database,
        charset="utf8mb4",
        autocommit=True,
    )


def _fetch_counts(conn, etab_id: int) -> Counts:
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM school_classroom WHERE etablissement_id=%s", (etab_id,))
        classes = int(cur.fetchone()[0])

        cur.execute(
            "SELECT COUNT(*) FROM school_student WHERE etablissement_id=%s AND is_archived=0",
            (etab_id,),
        )
        students_active = int(cur.fetchone()[0])

        cur.execute(
            """
            SELECT COUNT(*)
            FROM school_subject s
            JOIN school_classroom c ON c.id=s.classroom_id
            WHERE c.etablissement_id=%s
            """,
            (etab_id,),
        )
        subjects = int(cur.fetchone()[0])

        cur.execute("SELECT COUNT(*) FROM school_teacher WHERE etablissement_id=%s", (etab_id,))
        teachers = int(cur.fetchone()[0])

    return Counts(classes=classes, students_active=students_active, subjects=subjects, teachers=teachers)


def _check_director_scope(conn, username: str, etab_id: int) -> tuple[bool, str]:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT username, role, etablissement_id FROM users WHERE username=%s LIMIT 1",
            (username,),
        )
        row = cur.fetchone()

    if not row:
        return False, f"Compte introuvable: {username}"

    got_user, role, got_etab = row
    if role != "director":
        return False, f"Compte {got_user}: role={role} (attendu: director)"
    if int(got_etab or 0) != etab_id:
        return False, f"Compte {got_user}: etablissement_id={got_etab} (attendu: {etab_id})"
    return True, "OK"


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify runtime MySQL data consistency for an etablissement.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3306)
    parser.add_argument("--user", default="gestion_user")
    parser.add_argument("--password", default="gestion_password")
    parser.add_argument("--database", default="gestion_school")
    parser.add_argument("--etab-id", type=int, default=11)
    parser.add_argument("--min-classes", type=int, default=9)
    parser.add_argument("--min-students", type=int, default=90)
    parser.add_argument("--min-subjects", type=int, default=72)
    parser.add_argument("--min-teachers", type=int, default=9)
    parser.add_argument("--director-username", default="ouali_csob_directeur")
    args = parser.parse_args()

    try:
        conn = _connect(args.host, args.port, args.user, args.password, args.database)
    except Exception as exc:  # pragma: no cover
        print(f"[guard] KO: connection MySQL impossible: {exc}")
        return 2

    try:
        counts = _fetch_counts(conn, args.etab_id)
        ok_scope, scope_msg = _check_director_scope(conn, args.director_username, args.etab_id)
    finally:
        conn.close()

    print(
        "[guard] counts "
        f"classes={counts.classes} students_active={counts.students_active} "
        f"subjects={counts.subjects} teachers={counts.teachers}"
    )

    failures: list[str] = []
    if counts.classes < args.min_classes:
        failures.append(f"classes<{args.min_classes}")
    if counts.students_active < args.min_students:
        failures.append(f"students_active<{args.min_students}")
    if counts.subjects < args.min_subjects:
        failures.append(f"subjects<{args.min_subjects}")
    if counts.teachers < args.min_teachers:
        failures.append(f"teachers<{args.min_teachers}")
    if not ok_scope:
        failures.append(f"scope:{scope_msg}")

    if failures:
        print("[guard] KO:", "; ".join(failures))
        return 1

    print(f"[guard] director_scope={scope_msg}")
    print("[guard] OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
