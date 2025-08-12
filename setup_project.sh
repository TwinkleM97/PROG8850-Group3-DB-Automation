#!/usr/bin/env bash
set -euo pipefail

# ===== FLAGS =====
FORCE_CONFIG=0
AUTO=0
SKIP_VENV=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-config) FORCE_CONFIG=1; shift ;;
    --auto)         AUTO=1;         shift ;;
    --skip-venv)    SKIP_VENV=1;    shift ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# ===== SETTINGS =====
REPO_NAME="PROG8850-Group3-DB-Automation"
SIG_NOZ_DIR="monitoring/signoz"

# ===== HELPERS =====
ensure_mysql_logging_files() {
  mkdir -p monitoring/mysql
  if [[ $FORCE_CONFIG -eq 1 || ! -f monitoring/mysql/my.cnf ]]; then
    cat > monitoring/mysql/my.cnf <<'EOF'
[mysqld]
log_output=FILE
general_log=1
general_log_file=/var/lib/mysql/mysql-general.log
slow_query_log=1
slow_query_log_file=/var/lib/mysql/mysql-slow.log
long_query_time=0.2
log_queries_not_using_indexes=1
EOF
    echo "[CFG] Wrote monitoring/mysql/my.cnf"
    docker compose -f monitoring/mysql/docker-compose.mysql.yaml restart automated-mysql-server
  else
    echo "[CFG] Using existing monitoring/mysql/my.cnf (no overwrite)."
  fi
}

ensure_mysql_logging_runtime() {
  echo "[LOG] Applying runtime MySQL logging switches…"
  mysql -h 127.0.0.1 -P 3307 -u root -pSecret5555 -e "
    SET GLOBAL log_output='FILE';
    SET GLOBAL general_log=ON;
    SET GLOBAL general_log_file='/var/lib/mysql/mysql-general.log';
    SET GLOBAL slow_query_log=ON;
    SET GLOBAL slow_query_log_file='/var/lib/mysql/mysql-slow.log';
    SET GLOBAL long_query_time=0.2;
    SET GLOBAL log_queries_not_using_indexes=ON;
    FLUSH LOGS;
  "
}

ensure_otel_mysql_logs_config() {
  mkdir -p monitoring/otel
  if [[ $FORCE_CONFIG -eq 1 || ! -f monitoring/otel/otel-collector-config.yaml ]]; then
    cat > monitoring/otel/otel-collector-config.yaml <<'EOF'
receivers:
  filelog:
    include:
      - /var/lib/mysql/mysql-general.log
      - /var/lib/mysql/mysql-slow.log
    start_at: beginning

processors:
  resource:
    attributes:
      - key: service.name
        action: upsert
        value: automated-mysql-server
  batch:

exporters:
  otlp:
    endpoint: signoz-otel-collector:4317
    tls:
      insecure: true
  logging:
    verbosity: detailed

service:
  pipelines:
    logs:
      receivers: [filelog]
      processors: [resource, batch]
      exporters: [logging, otlp]
EOF
    echo "[CFG] Wrote monitoring/otel/otel-collector-config.yaml"
  else
    echo "[CFG] Using existing monitoring/otel/otel-collector-config.yaml (no overwrite)."
  fi
}

# NEW: docker metrics collector config (docker_stats -> SigNoz)
ensure_docker_metrics_config() {
  mkdir -p monitoring/otel
  if [[ $FORCE_CONFIG -eq 1 || ! -f monitoring/otel/docker-metrics-collector.yaml ]]; then
    cat > monitoring/otel/docker-metrics-collector.yaml <<'EOF'
receivers:
  docker_stats:
    endpoint: unix:///var/run/docker.sock
    collection_interval: 10s

processors:
  batch:

exporters:
  otlp:
    endpoint: signoz-otel-collector:4317
    tls:
      insecure: true

service:
  pipelines:
    metrics:
      receivers: [docker_stats]
      processors: [batch]
      exporters: [otlp]
EOF
    echo "[CFG] Wrote monitoring/otel/docker-metrics-collector.yaml"
  else
    echo "[CFG] Using existing monitoring/otel/docker-metrics-collector.yaml (no overwrite)."
  fi
}

detect_signoz_network() {
  docker network ls --format '{{.Name}}' | grep -i signoz | head -n1 || true
}

start_signoz() {
  echo "=== [S1] Starting SigNoz backend ==="
  if [[ ! -d "$SIG_NOZ_DIR" ]]; then
    mkdir -p monitoring
    command -v git >/dev/null 2>&1 || { sudo apt-get update && sudo apt-get install -y git; }
    git clone https://github.com/SigNoz/signoz.git "$SIG_NOZ_DIR"
  fi
  pushd "$SIG_NOZ_DIR/deploy/docker" >/dev/null
  docker compose up -d
  popd >/dev/null
  echo "SigNoz UI: port 3301 (in Codespaces this may appear as 8080)."
}

start_mysql_log_collector() {
  echo "=== [S2] Starting OTEL collector (MySQL logs -> SigNoz) ==="
  ensure_otel_mysql_logs_config

  local VOL
  VOL=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/mysql"}}{{.Name}}{{end}}{{end}}' automated-mysql-server || true)
  [[ -z "$VOL" ]] && { echo "Cannot find MySQL volume"; exit 1; }
  echo "[INFO] MySQL volume: $VOL"

  local NET
  NET=$(detect_signoz_network)
  [[ -z "$NET" ]] && { echo "Cannot detect SigNoz docker network. Start SigNoz first."; exit 1; }
  echo "[INFO] Using SigNoz network: $NET"

  docker exec -it automated-mysql-server sh -lc 'chmod 644 /var/lib/mysql/mysql-*.log || true' >/dev/null 2>&1 || true

  docker rm -f otelcol-mysql-logs >/dev/null 2>&1 || true
  docker run -d --name otelcol-mysql-logs \
    --user 0:0 \
    --network "$NET" \
    -v "$VOL":/var/lib/mysql:ro \
    -v "$(pwd)/monitoring/otel/otel-collector-config.yaml":/etc/otelcol/config.yaml:ro \
    --restart unless-stopped \
    otel/opentelemetry-collector-contrib:0.108.0 \
    --config=/etc/otelcol/config.yaml

  echo "[OK] MySQL logs collector started. Tail with: docker logs --tail=80 otelcol-mysql-logs"
}

# NEW: start docker metrics collector (runs as root to access /var/run/docker.sock)
start_docker_metrics_collector() {
  echo "=== [S3] Starting OTEL collector (Docker metrics -> SigNoz) ==="
  ensure_docker_metrics_config

  local NET
  NET=$(detect_signoz_network)
  [[ -z "$NET" ]] && { echo "Cannot detect SigNoz docker network. Start SigNoz first."; exit 1; }
  echo "[INFO] Using SigNoz network: $NET"

  docker rm -f otelcol-docker-metrics >/dev/null 2>&1 || true
  docker run -d --name otelcol-docker-metrics \
    --user 0:0 \
    --network "$NET" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)/monitoring/otel/docker-metrics-collector.yaml":/etc/otelcol/config.yaml:ro \
    --restart unless-stopped \
    otel/opentelemetry-collector-contrib:0.108.0 \
    --config=/etc/otelcol/config.yaml

  echo "[OK] Docker metrics collector started. Tail with: docker logs --tail=80 otelcol-docker-metrics"
}

ask_or_auto() {
  local prompt=$1 fn=$2
  if [[ $AUTO -eq 1 ]]; then
    $fn
  else
    read -p "$prompt (y/n): " ans
    [[ "$ans" =~ ^[Yy]$ ]] && $fn || echo "Skipped."
  fi
}

# ===== MAIN =====
echo "=== [1] Repo root ==="
cd "/workspaces/$REPO_NAME"

if [[ $SKIP_VENV -eq 1 ]]; then
  echo "=== [2] Skipping venv recreation (flag --skip-venv) ==="
else
  echo "=== [2] Python venv ==="
  deactivate 2>/dev/null || true
  rm -rf .venv
  python3 -m venv .venv
  source .venv/bin/activate
  python -m pip install --upgrade pip setuptools wheel
  pip install -r requirements.txt
fi

echo "=== [3] MySQL client ==="
command -v mysql >/dev/null 2>&1 || { sudo apt-get update && sudo apt-get install -y mysql-client; }

echo "=== [4] MySQL container ==="
docker compose -f monitoring/mysql/docker-compose.mysql.yaml up -d

echo "=== [5] Wait for MySQL ==="
for i in {1..40}; do
  if mysql -h 127.0.0.1 -P 3307 -u root -pSecret5555 -e "SELECT 1" >/dev/null 2>&1; then
    echo "MySQL ready."
    break
  fi
  echo "…waiting ($i)"; sleep 2
done

echo "=== [6] Ensure logging ==="
ensure_mysql_logging_files
ensure_mysql_logging_runtime

echo "=== [7] Schema & seed ==="
mysql -h 127.0.0.1 -P 3307 -u root -pSecret5555 < sql/01_create_climatedata.sql
mysql -h 127.0.0.1 -P 3307 -u root -pSecret5555 < sql/02_add_humidity.sql
mysql -h 127.0.0.1 -P 3307 -u root -pSecret5555 < sql/03_seed_data.sql

echo "=== [8] Workload (concurrent queries) ==="
python scripts/multi_thread_queries.py

echo "=== [9] Validate ==="
mysql -h 127.0.0.1 -P 3307 -u root -pSecret5555 < sql/99_validate.sql

# Optional stack pieces
ask_or_auto "Start SigNoz backend locally now?" start_signoz
ask_or_auto "Start OTEL collector to ship MySQL logs to SigNoz?" start_mysql_log_collector
ask_or_auto "Start OTEL collector to ship Docker metrics to SigNoz?" start_docker_metrics_collector

# act (optional)
if [[ $AUTO -eq 1 ]]; then
  RUN_ACT="n"
else
  read -p "Run local CI with act? (y/n): " RUN_ACT
fi
if [[ "$RUN_ACT" =~ ^[Yy]$ ]]; then
  command -v act >/dev/null 2>&1 || {
    sudo apt-get update && sudo apt-get install -y curl tar
    ARCH=$(uname -m); [[ "$ARCH" = x86_64 ]] && REL="Linux_x86_64" || REL="Linux_arm64"
    curl -L "https://github.com/nektos/act/releases/latest/download/act_${REL}.tar.gz" -o act.tgz
    tar -xzf act.tgz && sudo mv act /usr/local/bin/ && rm -f act.tgz
  }
  echo "If port clash on 3307: docker stop automated-mysql-server"
  act -W .github/workflows/ci_cd_pipeline.yml --secret-file .secrets -P ubuntu-latest=catthehacker/ubuntu:act-latest
fi

echo "=== DONE ==="
echo "SigNoz UI → Logs: filter service.name = automated-mysql-server"
echo "SigNoz UI → Dashboards: use metric 'container_cpu_usage_total' and label 'container_name'."
