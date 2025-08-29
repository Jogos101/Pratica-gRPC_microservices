set -euo pipefail

MYSQL_ROOT_PASSWORD="minhasenha"
MYSQL_PORT="3307"
MYSQL_CONTAINER_NAME="mysql-grpc"
NETWORK_NAME="pd-net"

ORDER_PORT="3000"
PAYMENT_PORT="3001"

# DSNs (Go/GORM) para cada serviço
ORDER_DSN="root:${MYSQL_ROOT_PASSWORD}@tcp(127.0.0.1:${MYSQL_PORT})/order"
PAYMENT_DSN="root:${MYSQL_ROOT_PASSWORD}@tcp(127.0.0.1:${MYSQL_PORT})/payment"

# usado pelo Order para chamar Payment (coerente com GetPaymentServiceURL)
PAYMENT_URL="localhost:${PAYMENT_PORT}"

# Pastas (assumindo a estrutura pedida)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_SQL="${ROOT_DIR}/../init/init.sql"

if ! command -v grpcurl >/dev/null 2>&1; then
    echo "grpcurl não encontrado. Instalando..."
    go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
    export PATH="$(go env GOPATH)/bin:$PATH"
fi

function ensure_network() {
  if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
    docker network create "${NETWORK_NAME}" >/dev/null
  fi
}

function require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Erro: comando '$1' não encontrado."; exit 1; }
}
function netem_add_delay() {
  # Aplica delay na loopback (afeta Order->Payment, grpcurl->Order e acessos locais)
  local ms="${1:-3000}"
  echo "[netem] Adicionando delay de ${ms}ms na interface lo (sudo)..."
  sudo tc qdisc replace dev lo root netem delay "${ms}ms"
}
function netem_clear() {
  echo "[netem] Limpando regras netem (sudo)..."
  sudo tc qdisc del dev lo root || true
}
function block_payment_port() {
  # Bloqueia tráfego local para Payment (porta ${PAYMENT_PORT}) para simular Unavailable
  echo "[fw] Bloqueando porta ${PAYMENT_PORT} na loopback (sudo, iptables)..."
  sudo iptables -I OUTPUT -o lo -p tcp --dport "${PAYMENT_PORT}" -j REJECT || true
  sudo iptables -I INPUT  -i lo -p tcp --sport "${PAYMENT_PORT}" -j REJECT || true
}
function unblock_payment_port() {
  echo "[fw] Desbloqueando porta ${PAYMENT_PORT} (sudo, iptables)..."
  sudo iptables -D OUTPUT -o lo -p tcp --dport "${PAYMENT_PORT}" -j REJECT || true
  sudo iptables -D INPUT  -i lo -p tcp --sport "${PAYMENT_PORT}" -j REJECT || true
}

function up_db() {
  ensure_network
  # Montagem do init.sql; no WSL, use caminho Linux mesmo (pwd/…)
  docker run -d \
    --name "${MYSQL_CONTAINER_NAME}" \
    --network "${NETWORK_NAME}" \
    -p ${MYSQL_PORT}:3306 \
    -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
    -v "${INIT_SQL}:/docker-entrypoint-initdb.d/init.sql:ro" \
    mysql:8

  echo "Aguardando MySQL subir..."
  # espera simples
  for i in {1..30}; do
    if docker exec "${MYSQL_CONTAINER_NAME}" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
      echo "MySQL pronto."
      return
    fi
    sleep 1
  done
  echo "Falha ao conectar no MySQL."; exit 1
}

function kill_existing() {
  pkill -f "go run cmd/main.go" || true
}

function up_payment() {
  echo "-> Subindo Payment (porta ${PAYMENT_PORT})"
  pushd "${ROOT_DIR}/payment" >/dev/null
  DB_DRIVER=mysql \
  DATA_SOURCE_URL="${PAYMENT_DSN}" \
  APPLICATION_PORT="${PAYMENT_PORT}" \
  ENV=development \
  nohup go run cmd/main.go >/tmp/payment.log 2>&1 &
  popd >/dev/null
}

function up_order() {
  echo "-> Subindo Order (porta ${ORDER_PORT})"
  pushd "${ROOT_DIR}/order" >/dev/null
  DB_DRIVER=mysql \
  DATA_SOURCE_URL="${ORDER_DSN}" \
  APPLICATION_PORT="${ORDER_PORT}" \
  ENV=development \
  PAYMENT_SERVICE_URL="${PAYMENT_URL}" \
  nohup go run cmd/main.go >/tmp/order.log 2>&1 &
  popd >/dev/null
}

function down_all() {
  kill_existing
  docker rm -f "${MYSQL_CONTAINER_NAME}" >/dev/null 2>&1 || true
  echo "Processo finalizado."
}

function logs() {
  echo "== payment.log =="
  tail -n 100 /tmp/payment.log || true
  echo
  echo "== order.log =="
  tail -n 100 /tmp/order.log || true
}

function test_call() {
  echo "Executando teste via grpcurl no Order/Create ..."
  grpcurl -plaintext -d '{
    "customer_id": 123,
    "order_items": [{"product_code":"A1","unit_price":12,"quantity":4}],
    "total_price": 0
  }' localhost:${ORDER_PORT} Order/Create
SQL
  echo "Banco limpo com sucesso."
}

function db_shell() {
  echo "Abrindo cliente MySQL no container ${MYSQL_CONTAINER_NAME}..."
  echo "Use: SHOW DATABASES;  USE \`order\`;  SHOW TABLES;  SELECT * FROM orders;"
  docker exec -it ${MYSQL_CONTAINER_NAME} mysql -uroot -p${MYSQL_ROOT_PASSWORD}
}

function db_view() {
  echo "== Pedidos (order.orders) =="
  docker exec -i ${MYSQL_CONTAINER_NAME} mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e \
    "USE \`order\`; SELECT * FROM orders ORDER BY id DESC LIMIT 10;"

  echo
  echo "== Pagamentos (payment.payments) =="
  docker exec -i ${MYSQL_CONTAINER_NAME} mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e \
    "USE \`payment\`; SELECT id, order_id, total_price FROM payments ORDER BY id DESC LIMIT 10;"
}


function test_deadline() {
  # Provoca DeadlineExceeded (2s por tentativa) adicionando delay > 2000ms
  require_cmd tc
  local delay_ms="${1:-3000}"

  echo "[teste] DeadlineExceeded esperado (delay ${delay_ms}ms > 2000ms)"
  netem_add_delay "${delay_ms}"
  trap netem_clear EXIT

  set +e
  out="$(grpcurl -plaintext -d '{
    "customer_id": 123,
    "order_items": [{"product_code":"A1","unit_price":12,"quantity":4}],
    "total_price": 0
  }' localhost:${ORDER_PORT} Order/Create 2>&1)"
  rc=$?
  set -e

  echo "${out}"
  netem_clear
  trap - EXIT

  if echo "${out}" | grep -qi "DeadlineExceeded"; then
    echo "[OK] DeadlineExceeded detectado (Order->Payment excedeu o deadline por tentativa)."
  else
    echo "[WARN] Não detectei DeadlineExceeded no retorno. Verifique logs com: bash run.sh logs"
  fi
  return ${rc}
}

function test_retry() {
  # Provoca Unavailable para acionar retries (até 5) no interceptor
  require_cmd iptables

  echo "[teste] Unavailable esperado (bloqueando porta ${PAYMENT_PORT} na loopback)"
  block_payment_port
  trap unblock_payment_port EXIT

  set +e
  out="$(grpcurl -plaintext -d '{
    "customer_id": 123,
    "order_items": [{"product_code":"A1","unit_price":12,"quantity":4}],
    "total_price": 0
  }' localhost:${ORDER_PORT} Order/Create 2>&1)"
  rc=$?
  set -e

  echo "${out}"
  unblock_payment_port
  trap - EXIT

  if echo "${out}" | grep -qi "Unavailable"; then
    echo "[OK] Unavailable detectado (interceptor deve ter tentado novas tentativas com backoff)."
  else
    echo "[WARN] Não detectei Unavailable no retorno. Verifique logs com: bash run.sh logs"
  fi
  return ${rc}
}
# ------------------------------------------------

case "${1:-}" in
  up)
    down_all
    up_db
    up_payment
    up_order
    echo "Serviços no ar. Use: bash run.sh test  |  bash run.sh logs"
    ;;
  test)
    test_call
    ;;
  test-deadline)
    test_deadline "${2:-3000}"
    ;;
  test-retry)
    test_retry
    ;;
  logs)
    logs
    ;;
  down)
    down_all
    ;;
  reset-db)
    reset_db
    ;;
  db)
    db_shell
    ;;
  db-view)
    db_view
    ;;
  netem-clear)
    netem_clear
    ;;
  *)
    echo "Uso: bash run.sh {up|test|test-deadline [ms]|test-retry|logs|down|reset-db|db|db-view|netem-clear}"
    exit 1
    ;;
esac
