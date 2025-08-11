#!/usr/bin/env bash
# github_bootstrap.sh — tailored to your repo
# Repo: https://github.com/TwinkleM97/PROG8850-Group3-DB-Automation.git
# Local path: /workspaces/PROG8850-Group3-DB-Automation
# Creates/ensures: /sql, /scripts, /.github/workflows, required SQL/Python files, and CI workflow.

set -euo pipefail

REPO_DIR="/workspaces/PROG8850-Group3-DB-Automation"
GITHUB_URL="https://github.com/TwinkleM97/PROG8850-Group3-DB-Automation.git"
MYSQL_PASS="Secret5555" # keep consistent with MySQL service in Actions

mkdir -p "$REPO_DIR"/{sql,scripts,.github/workflows}

write_if_missing () {
  local target="$1"
  local content="$2"
  if [ -f "$target" ]; then
    echo "[SKIP] $target exists"
  else
    echo "$content" > "$target"
    echo "[WRITE] $target"
  fi
}

append_line_once () {
  local target="$1"
  local line="$2"
  touch "$target"
  grep -qxF "$line" "$target" || echo "$line" >> "$target"
}

# -------- requirements.txt --------
write_if_missing "$REPO_DIR/requirements.txt" "$(cat <<'EOF'
mysql-connector-python==9.0.0
EOF
)"

# -------- .gitignore (ensure .secrets ignored) --------
append_line_once "$REPO_DIR/.gitignore" ".venv/"
append_line_once "$REPO_DIR/.gitignore" "__pycache__/"
append_line_once "$REPO_DIR/.gitignore" ".secrets"

# -------- .secrets (for local `act` only; DO NOT COMMIT) --------
write_if_missing "$REPO_DIR/.secrets" "$(cat <<EOF
# Used ONLY for local \`act\` runs. Do NOT commit this file.
MYSQL_PASSWORD=$MYSQL_PASS
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3307
MYSQL_USER=root
MYSQL_DB=project_db
EOF
)"

# -------- SQL: 01_create (no humidity yet) --------
write_if_missing "$REPO_DIR/sql/01_create_climatedata.sql" "$(cat <<'EOF'
CREATE DATABASE IF NOT EXISTS project_db;
USE project_db;

DROP TABLE IF EXISTS ClimateData;
CREATE TABLE ClimateData (
  record_id INT PRIMARY KEY AUTO_INCREMENT,
  location VARCHAR(100) NOT NULL,
  record_date DATE NOT NULL,
  temperature FLOAT NOT NULL,
  precipitation FLOAT NOT NULL
);
EOF
)"

# -------- SQL: 02_add_humidity --------
write_if_missing "$REPO_DIR/sql/02_add_humidity.sql" "$(cat <<'EOF'
USE project_db;
ALTER TABLE ClimateData
  ADD COLUMN humidity FLOAT NOT NULL DEFAULT 0.0;
EOF
)"

# -------- SQL: 03_seed_data --------
write_if_missing "$REPO_DIR/sql/03_seed_data.sql" "$(cat <<'EOF'
USE project_db;
INSERT INTO ClimateData (location, record_date, temperature, precipitation, humidity) VALUES
('Ottawa',       '2025-07-01', 28.4,  3.2,  65.0),
('Ottawa',       '2025-07-02', 29.1,  0.0,  58.0),
('Toronto',      '2025-07-01', 30.2,  1.0,  62.0),
('Toronto',      '2025-07-02', 27.9,  6.1,  70.0),
('Montreal',     '2025-07-01', 26.3,  4.5,  68.0),
('Montreal',     '2025-07-02', 25.0,  0.0,  55.0),
('Vancouver',    '2025-07-01', 22.1,  7.4,  78.0),
('Vancouver',    '2025-07-02', 23.0,  2.2,  74.0),
('Calgary',      '2025-07-01', 24.5,  0.0,  40.0),
('Calgary',      '2025-07-02', 25.1,  0.0,  35.0);
EOF
)"

# -------- SQL: 99_validate --------
write_if_missing "$REPO_DIR/sql/99_validate.sql" "$(cat <<'EOF'
USE project_db;

-- 1) Structure check
SHOW COLUMNS FROM ClimateData;

-- 2) Humidity column presence
SELECT COLUMN_NAME, IS_NULLABLE, COLUMN_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA='project_db' AND TABLE_NAME='ClimateData' AND COLUMN_NAME='humidity';

-- 3) Seed data exists
SELECT COUNT(*) AS total_rows FROM ClimateData;

-- 4) Evidence of concurrent ops
SELECT COUNT(*) AS hot_days_over_20 FROM ClimateData WHERE temperature > 20;
SELECT location, MIN(humidity) AS min_h, MAX(humidity) AS max_h
FROM ClimateData
WHERE location IN ('Ottawa','Toronto')
GROUP BY location;
EOF
)"

# -------- Python: concurrent queries --------
write_if_missing "$REPO_DIR/scripts/multi_thread_queries.py" "$(cat <<'EOF'
import os, random, time
from concurrent.futures import ThreadPoolExecutor, as_completed
import mysql.connector

DB = {
    "host": os.getenv("MYSQL_HOST", "127.0.0.1"),
    "port": int(os.getenv("MYSQL_PORT", "3307")),
    "user": os.getenv("MYSQL_USER", "root"),
    "password": os.getenv("MYSQL_PASSWORD", "Secret5555"),
    "database": os.getenv("MYSQL_DB", "project_db"),
}

def conn():
    return mysql.connector.connect(**DB)

def insert_row(i):
    c=conn()
    try:
        cur=c.cursor()
        cur.execute("""
            INSERT INTO ClimateData (location, record_date, temperature, precipitation, humidity)
            VALUES (%s,%s,%s,%s,%s)
        """, (
            random.choice(["Ottawa","Toronto","Montreal","Vancouver","Calgary","Halifax","Winnipeg"]),
            f"2025-07-{random.randint(10,28):02d}",
            round(random.uniform(15,35),1),
            round(random.uniform(0,15),1),
            round(random.uniform(25,95),1),
        ))
        c.commit()
        return f"INSERT id={cur.lastrowid}"
    finally:
        c.close()

def select_hot():
    c=conn()
    try:
        cur=c.cursor()
        cur.execute("SELECT COUNT(*) FROM ClimateData WHERE temperature > 20")
        (n,)=cur.fetchone()
        return f"SELECT hot_days={n}"
    finally:
        c.close()

def update_humidity():
    c=conn()
    try:
        cur=c.cursor()
        cur.execute("""
            UPDATE ClimateData
            SET humidity = LEAST(humidity + 5.0, 100.0)
            WHERE location IN ('Ottawa','Toronto')
        """)
        c.commit()
        return f"UPDATE rows={cur.rowcount}"
    finally:
        c.close()

def main():
    time.sleep(1)
    tasks=[]
    with ThreadPoolExecutor(max_workers=8) as ex:
        for i in range(15):
            tasks.append(ex.submit(insert_row,i))
        tasks.append(ex.submit(select_hot))
        tasks.append(ex.submit(update_humidity))
        for f in as_completed(tasks):
            print(f.result())
    c=conn()
    try:
        cur=c.cursor()
        cur.execute("SELECT COUNT(*) FROM ClimateData")
        (total,)=cur.fetchone()
        print(f"FINAL COUNT rows={total}")
    finally:
        c.close()

if __name__=="__main__":
    main()
EOF
)"

# -------- GitHub Actions workflow --------
write_if_missing "$REPO_DIR/.github/workflows/ci_cd_pipeline.yml" "$(cat <<'EOF'
name: Database CI/CD Pipeline

on:
  push:
    branches: [ "main" ]
  workflow_dispatch: {}

jobs:
  db-pipeline:
    runs-on: ubuntu-latest

    services:
      mysql:
        image: mysql:8.0
        env:
          MYSQL_ROOT_PASSWORD: Secret5555
          MYSQL_DATABASE: project_db
        ports:
          - 3307:3306
        options: >-
          --health-cmd="mysqladmin ping -h 127.0.0.1 -u root -pSecret5555"
          --health-interval=5s
          --health-timeout=2s
          --health-retries=24

    env:
      MYSQL_HOST: 127.0.0.1
      MYSQL_PORT: 3307
      MYSQL_USER: root
      MYSQL_DB: project_db

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure MYSQL_PASSWORD from secret or default
        run: |
          if [ -z "${{ secrets.MYSQL_PASSWORD }}" ]; then
            echo "MYSQL_PASSWORD=Secret5555" >> $GITHUB_ENV
          else
            echo "MYSQL_PASSWORD=${{ secrets.MYSQL_PASSWORD }}" >> $GITHUB_ENV
          fi

      - name: Install MySQL client & Python deps
        run: |
          sudo apt-get update
          sudo apt-get install -y mysql-client
          python -m pip install --upgrade pip
          pip install -r requirements.txt

      - name: Wait for MySQL healthy
        run: |
          for i in {1..60}; do
            if mysql -h 127.0.0.1 -P 3307 -u root -p"$MYSQL_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
              echo "MySQL ready"; break
            fi
            echo "Waiting for MySQL... ($i)"; sleep 2
          done

      - name: Initial Schema Deployment
        run: |
          mysql -h 127.0.0.1 -P 3307 -u root -p"$MYSQL_PASSWORD" < sql/01_create_climatedata.sql

      - name: Schema Update (add humidity)
        run: |
          mysql -h 127.0.0.1 -P 3307 -u root -p"$MYSQL_PASSWORD" < sql/02_add_humidity.sql

      - name: Data Seeding
        run: |
          mysql -h 127.0.0.1 -P 3307 -u root -p"$MYSQL_PASSWORD" < sql/03_seed_data.sql

      - name: Concurrent Query Execution (Python)
        env:
          MYSQL_HOST: 127.0.0.1
          MYSQL_PORT: 3307
          MYSQL_USER: root
          MYSQL_PASSWORD: ${{ env.MYSQL_PASSWORD }}
          MYSQL_DB: project_db
        run: |
          python scripts/multi_thread_queries.py

      - name: Validation Step
        run: |
          mysql -h 127.0.0.1 -P 3307 -u root -p"$MYSQL_PASSWORD" < sql/99_validate.sql
EOF
)"

# -------- Git setup/push --------
cd "$REPO_DIR"

if [ ! -d .git ]; then
  git init
fi

git add -A
git commit -m "Scaffold: SQL, scripts, GitHub Actions CI/CD per requirements" || true

# Configure remote to your repo URL
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$GITHUB_URL"
else
  git remote add origin "$GITHUB_URL"
fi

# Ensure main exists and push
git branch -M main
git push -u origin main

echo "✅ Done. Repo synced to $GITHUB_URL"
echo "➜ Add repo secret in GitHub: Settings → Secrets and variables → Actions → New secret: MYSQL_PASSWORD"
