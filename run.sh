#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIG Padrão (pode editar) ----
MYSQL_ROOT_PASSWORD="minhasenha"
MYSQL_PORT="3307"
MYSQL_CONTAINER_NAME="mysql-grpc"
NETWORK_NAME="pd-net"

ORDER_PORT="3000"
PAYMENT_PORT="3001"

# DSNs (Go/GORM) para cada serviço
ORDER_DSN="root:${MYSQL_ROOT_PASSWORD}@tcp(127.0.0.1:${MYSQL_PORT})/order"
PAYMENT_DSN="root:${MYSQL_ROOT_PASSWORD}@tcp(127.0.0.1:${MYSQL_PORT})/payment"

PAYMENT_URL="localhost:${PAYMENT_PORT}"   # usado pelo Order para chamar Payment

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

  grpcurl -plaintext -d '{
    "customer_id": 456,
    "order_items": [{"product_code":"A2","unit_price":600,"quantity":4}],
    "total_price": 0
  }' localhost:${ORDER_PORT} Order/Create

  grpcurl -plaintext -d '{
    "customer_id": 123,
    "order_items": [{"product_code":"A1","unit_price":12,"quantity":60}],
    "total_price": 0
  }' localhost:${ORDER_PORT} Order/Create
}

function reset_db() {
  echo "Limpando tabelas do banco..."
  docker exec -i ${MYSQL_CONTAINER_NAME} mysql -uroot -p${MYSQL_ROOT_PASSWORD} <<SQL
USE \`order\`;
DELETE FROM order_items;
DELETE FROM orders;
ALTER TABLE order_items AUTO_INCREMENT = 1;
ALTER TABLE orders AUTO_INCREMENT = 1;

USE \`payment\`;
DELETE FROM payments;
ALTER TABLE payments AUTO_INCREMENT = 1;
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
  *)
    echo "Uso: bash run.sh {up|test|logs|down}"; exit 1;;
esac
