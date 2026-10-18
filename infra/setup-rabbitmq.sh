#!/bin/bash
# Cria a fila dedicada da Function e liga ao exchange do PaymentProcessedEvent.
# Idempotente (PUT de fila / POST de binding podem rodar varias vezes).
#
# Por que uma fila propria: o MassTransit publica o evento num exchange
# (pub/sub) e cada consumidor tem a sua fila ligada a ele. O catalog-api ja
# usa a fila "PaymentProcessed". Se a Function lesse dela, os dois
# competiriam pelas mesmas mensagens. Com uma fila dedicada, cada um recebe
# uma copia de cada evento.
#
# Rode DEPOIS que o catalog-api subiu pelo menos uma vez: e ele quem declara o
# exchange. Uso:
#   RABBITMQ_API=http://localhost:15672 bash infra/setup-rabbitmq.sh

set -e

RABBITMQ_API="${RABBITMQ_API:-http://localhost:15672}"
RABBITMQ_USER="${RABBITMQ_USER:-guest}"
RABBITMQ_PASS="${RABBITMQ_PASS:-guest}"
VHOST="%2F"                                   # vhost "/" url-encoded
QUEUE="${QUEUE:-notifications-payment-processed}"
EXCHANGE="${EXCHANGE:-FCG.Events:PaymentProcessedEvent}"

api() { curl -sf -u "$RABBITMQ_USER:$RABBITMQ_PASS" -H "content-type: application/json" "$@"; }

echo "[..] RabbitMQ em $RABBITMQ_API"
api "$RABBITMQ_API/api/overview" > /dev/null || { echo "[erro] Management API inacessivel"; exit 1; }

# O exchange precisa existir (declarado pelo MassTransit no catalog-api/payments-api)
EXCHANGE_ENC=$(printf '%s' "$EXCHANGE" | sed 's/:/%3A/g')
if ! api "$RABBITMQ_API/api/exchanges/$VHOST/$EXCHANGE_ENC" > /dev/null; then
  echo "[erro] exchange '$EXCHANGE' nao existe ainda."
  echo "       Suba o catalog-api/payments-api primeiro (eles declaram o exchange)."
  echo "       Exchanges atuais:"
  api "$RABBITMQ_API/api/exchanges/$VHOST" | grep -o '"name":"[^"]*"' | grep -v '"name":"amq\.' | grep -v '"name":""'
  exit 1
fi

api -X PUT "$RABBITMQ_API/api/queues/$VHOST/$QUEUE" \
  -d '{"durable":true,"auto_delete":false}' > /dev/null
echo "[ok] fila '$QUEUE' criada"

api -X POST "$RABBITMQ_API/api/bindings/$VHOST/e/$EXCHANGE_ENC/q/$QUEUE" \
  -d '{"routing_key":""}' > /dev/null
echo "[ok] binding '$EXCHANGE' -> '$QUEUE'"
