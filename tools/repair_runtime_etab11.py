#!/usr/bin/env python3
"""Idempotent runtime repair for etablissement 11 in MySQL.

This script only adds/fixes missing records (non-destructive):
- 10 students per class for classes 35..43
- 8 target subjects per class
- 9 teachers (csob_teacher_01..09)
- director account ouali_csob_directeur bound to etab 11
"""

from __future__ import annotations

from datetime import date, datetime

import pymysql


HOST = "127.0.0.1"
PORT = 3306
USER = "gestion_user"
PASSWORD = "gestion_password"
DATABASE = "gestion_school"
ETAB_ID = 11


def connect():
    return pymysql.connect(
        host=HOST,
        port=PORT,
        user=USER,
        password=PASSWORD,
        database=DATABASE,
        charset="utf8mb4",
        autocommit=False,
    )


def ensure_students(cur, now: str, today: str, password_hash: str) -> None:
    for cid in range(35, 44):
        for i in range(1, 11):
            username = f"stu_e11_c{cid}_{i:03d}"
            first = f"Eleve{i:02d}"
            last = f"CSOB-C{cid}"
            email = f"{username}@local.school"

            cur.execute("SELECT id FROM users WHERE username=%s LIMIT 1", (username,))
            r = cur.fetchone()
            if r:
                uid = int(r[0])
            else:
                cur.execute(
                    """
                    INSERT INTO users (
                        password,last_login,is_superuser,username,first_name,last_name,email,
                        is_staff,is_active,date_joined,role,phone,profile_photo,etablissement_id
                    ) VALUES (%s,NULL,0,%s,%s,%s,%s,0,1,%s,'student','',NULL,%s)
                    """,
                    (password_hash, username, first, last, email, now, ETAB_ID),
                )
                uid = int(cur.lastrowid)

            cur.execute("SELECT id FROM school_student WHERE user_id=%s LIMIT 1", (uid,))
            s = cur.fetchone()
            if s:
                cur.execute(
                    """
                    UPDATE school_student
                    SET etablissement_id=%s,classroom_id=%s,is_archived=0,updated_at=%s
                    WHERE id=%s
                    """,
                    (ETAB_ID, cid, now, int(s[0])),
                )
            else:
                matricule = f"GS-2026-11{cid}{i}"
                cur.execute(
                    """
                    INSERT INTO school_student (
                        created_at,updated_at,matricule,birth_date,photo,enrollment_date,
                        is_archived,classroom_id,parent_id,user_id,etablissement_id,conduite
                    ) VALUES (%s,%s,%s,NULL,NULL,%s,0,%s,NULL,%s,%s,10.00)
                    """,
                    (now, now, matricule, today, cid, uid, ETAB_ID),
                )


def ensure_subjects(cur, now: str) -> None:
    subjects = [
        "Français",
        "Mathématiques",
        "Histoire",
        "Géographie",
        "Sciences d'obsevation",
        "Éducation civique et morale (ECM)",
        "Éducation physique et sportive (EPS)",
        "Dessin / Arts",
    ]

    for cid in range(35, 44):
        for idx, name in enumerate(subjects, start=1):
            cur.execute(
                "SELECT id FROM school_subject WHERE classroom_id=%s AND name=%s LIMIT 1",
                (cid, name),
            )
            if cur.fetchone():
                continue

            base = f"CS{cid}_{idx:02d}"
            candidate = base
            n = 1
            while True:
                cur.execute("SELECT id FROM school_subject WHERE code=%s LIMIT 1", (candidate,))
                if not cur.fetchone():
                    break
                n += 1
                candidate = f"{base}_x{n}"

            cur.execute(
                """
                INSERT INTO school_subject (created_at,updated_at,name,code,coefficient,classroom_id)
                VALUES (%s,%s,%s,%s,1.00,%s)
                """,
                (now, now, name, candidate, cid),
            )


def ensure_teachers(cur, now: str, today: str, password_hash: str) -> None:
    for i in range(1, 10):
        ii = f"{i:02d}"
        username = f"csob_teacher_{ii}"

        cur.execute("SELECT id FROM users WHERE username=%s LIMIT 1", (username,))
        r = cur.fetchone()
        if r:
            uid = int(r[0])
        else:
            cur.execute(
                """
                INSERT INTO users (
                    password,last_login,is_superuser,username,first_name,last_name,email,
                    is_staff,is_active,date_joined,role,phone,profile_photo,etablissement_id
                ) VALUES (%s,NULL,0,%s,'Prof',%s,%s,0,1,%s,'teacher','',NULL,%s)
                """,
                (password_hash, username, f"CSOB {ii}", f"{username}@local.school", now, ETAB_ID),
            )
            uid = int(cur.lastrowid)

        cur.execute("UPDATE users SET etablissement_id=%s, role='teacher' WHERE id=%s", (ETAB_ID, uid))

        cur.execute("SELECT id FROM school_teacher WHERE user_id=%s LIMIT 1", (uid,))
        t = cur.fetchone()
        if t:
            cur.execute(
                "UPDATE school_teacher SET etablissement_id=%s, updated_at=%s WHERE id=%s",
                (ETAB_ID, now, int(t[0])),
            )
        else:
            cur.execute(
                """
                INSERT INTO school_teacher (
                    created_at,updated_at,employee_code,hire_date,salary_base,user_id,etablissement_id,hourly_rate
                ) VALUES (%s,%s,%s,%s,0.00,%s,%s,0.00)
                """,
                (now, now, f"CSOB-T-{ii}", today, uid, ETAB_ID),
            )


def ensure_director(cur, now: str, password_hash: str) -> None:
    cur.execute("SELECT id FROM users WHERE username='ouali_csob_directeur' LIMIT 1")
    if cur.fetchone():
        cur.execute(
            "UPDATE users SET role='director', etablissement_id=%s WHERE username='ouali_csob_directeur'",
            (ETAB_ID,),
        )
        return

    cur.execute(
        """
        INSERT INTO users (
            password,last_login,is_superuser,username,first_name,last_name,email,
            is_staff,is_active,date_joined,role,phone,profile_photo,etablissement_id
        ) VALUES (%s,NULL,0,'ouali_csob_directeur','OUALI','SISSOKO','',0,1,%s,'director','',NULL,%s)
        """,
        (password_hash, now, ETAB_ID),
    )


def main() -> int:
    conn = connect()
    cur = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    today = date.today().isoformat()

    cur.execute("SELECT password FROM users WHERE username='ouali' LIMIT 1")
    row = cur.fetchone()
    if not row:
        cur.execute("SELECT password FROM users WHERE role='student' LIMIT 1")
        row = cur.fetchone()
    password_hash = row[0] if row else "pbkdf2_sha256$720000$seed$seed"

    try:
        ensure_students(cur, now, today, password_hash)
        ensure_subjects(cur, now)
        ensure_teachers(cur, now, today, password_hash)
        ensure_director(cur, now, password_hash)
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()

    print("[repair] completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
