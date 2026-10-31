#!/usr/bin/env bash
# Test end-to-end: invia un voto alla Vote App e verifica che arrivi nel database.
# Percorso verificato: vote -> redis -> worker -> postgres.
set -euo pipefail

CTX="${KCTX_NAME:-kind-voting-cluster}"
NS="${NAMESPACE:-voting-app}"
VOTE_URL="${VOTE_URL:-http://localhost:30000}"
TIMEOUT="${TIMEOUT:-30}"

# Numero di voti presenti nel DB. Se la tabella non esiste ancora (il worker la crea
# alla prima connessione) il risultato e' 0.
count_votes() {
  kubectl --context "$CTX" exec -n "$NS" deploy/db -- \
    sh -c 'psql -U "$POSTGRES_USER" -t -A -c "select count(*) from votes;"' 2>/dev/null \
    | tr -d '[:space:]' || true
}

before="$(count_votes)"
before="${before:-0}"
echo "Voti nel database prima del test: ${before}"

# curl senza cookie: l'app genera un nuovo voter_id, quindi viene registrato un voto nuovo.
curl -s -f -o /dev/null -X POST -d "vote=a" "${VOTE_URL}/"
echo "Voto inviato a ${VOTE_URL}"

deadline=$((SECONDS + TIMEOUT))
while [ "$SECONDS" -lt "$deadline" ]; do
  after="$(count_votes)"
  after="${after:-0}"
  if [ "$after" -gt "$before" ]; then
    echo "OK: il voto e' arrivato nel database (${before} -> ${after})"
    exit 0
  fi
  sleep 2
done

echo "ERRORE: dopo ${TIMEOUT}s il voto non risulta nel database." >&2
echo "Controllare: make logs APP=worker  |  make logs APP=vote  |  make verify" >&2
exit 1