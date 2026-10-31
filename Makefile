CLUSTER_NAME := voting-cluster
NAMESPACE := voting-app
KCTX := --context kind-$(CLUSTER_NAME)
ENV_FILE := k8s/overlays/local/.env
DEPLOYMENTS := db redis vote result worker
APP ?= worker

.PHONY: help doctor init-env env-check cluster-up cluster-down deploy wait-ready verify events logs \
	smoke-test e2e-test incident-image recover-image incident-service recover-service \
	change-voting-options reset-voting-options scale-up scale-down reinstall

help:
	@echo "Setup:      doctor | init-env | cluster-up | deploy | wait-ready | reinstall | cluster-down"
	@echo "Verifica:   verify | events | logs APP=<nome> | smoke-test | e2e-test"
	@echo "Incidenti:  incident-image / recover-image | incident-service / recover-service"
	@echo "Demo:       change-voting-options / reset-voting-options | scale-up / scale-down"

doctor:
	@command -v docker >/dev/null 2>&1 || { echo >&2 "Docker mancante."; exit 1; }
	@command -v kind >/dev/null 2>&1 || { echo >&2 "Kind mancante."; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl mancante."; exit 1; }
	@docker info >/dev/null 2>&1 || { echo >&2 "Il daemon Docker non risponde (e' avviato?)."; exit 1; }
	@echo "Prerequisiti OK"
	@test -f $(ENV_FILE) && echo "File $(ENV_FILE) presente" || echo "Nota: manca $(ENV_FILE), eseguire 'make init-env'"

# Crea il file .env locale (non versionato) dal template, senza sovrascrivere uno esistente.
init-env:
	@test -f $(ENV_FILE) && echo "$(ENV_FILE) esiste gia', non lo sovrascrivo" || { cp $(ENV_FILE).example $(ENV_FILE) && echo "Creato $(ENV_FILE) dal template"; }

# Ferma i target che richiedono il .env con un messaggio chiaro (invece dell'errore di Kustomize).
env-check:
	@test -f $(ENV_FILE) || { echo >&2 "Manca $(ENV_FILE): eseguire 'make init-env'."; exit 1; }

cluster-up:
	kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml

cluster-down:
	kind delete cluster --name $(CLUSTER_NAME)

deploy: env-check
	kubectl $(KCTX) apply -k k8s/overlays/local

# Attende il completamento del rollout di ogni Deployment (fallisce con timeout se un rollout e' bloccato,
# ad esempio durante 'make incident-image').
wait-ready:
	@for d in $(DEPLOYMENTS); do \
		kubectl $(KCTX) rollout status deployment/$$d -n $(NAMESPACE) --timeout=120s || exit 1; \
	done

verify:
	kubectl $(KCTX) get pods,svc,endpoints -n $(NAMESPACE)

events:
	kubectl $(KCTX) get events -n $(NAMESPACE) --sort-by=.metadata.creationTimestamp

# Esempio: make logs APP=vote
logs:
	kubectl $(KCTX) logs deployment/$(APP) -n $(NAMESPACE) --tail=50

# Controlla solo che le due pagine rispondano (non verifica il percorso del voto).
smoke-test:
	@echo "Controllo che le interfacce esposte rispondano..."
	@curl -s -f -o /dev/null http://localhost:30000 && echo "OK Vote App risponde (HTTP < 400)" || (echo "ERRORE Vote App NON raggiungibile"; exit 1)
	@curl -s -f -o /dev/null http://localhost:30001 && echo "OK Result App risponde (HTTP < 400)" || (echo "ERRORE Result App NON raggiungibile"; exit 1)

# Invia un voto e verifica che arrivi in Postgres (vote -> redis -> worker -> db).
e2e-test:
	@KCTX_NAME=kind-$(CLUSTER_NAME) NAMESPACE=$(NAMESPACE) bash scripts/e2e-test.sh

incident-image: env-check
	kubectl $(KCTX) apply -k k8s/overlays/incident-image

recover-image: env-check
	kubectl $(KCTX) apply -k k8s/overlays/local

incident-service: env-check
	kubectl $(KCTX) apply -k k8s/overlays/incident-service

recover-service: env-check
	kubectl $(KCTX) apply -k k8s/overlays/local

change-voting-options: env-check
	kubectl $(KCTX) apply -k k8s/overlays/custom-options

reset-voting-options: env-check
	kubectl $(KCTX) apply -k k8s/overlays/local

scale-up:
	kubectl $(KCTX) scale deployment vote --replicas=3 -n $(NAMESPACE)
	kubectl $(KCTX) rollout status deployment/vote -n $(NAMESPACE) --timeout=120s
	kubectl $(KCTX) get pods -n $(NAMESPACE) -l app=vote

scale-down:
	kubectl $(KCTX) scale deployment vote --replicas=1 -n $(NAMESPACE)
	kubectl $(KCTX) get pods -n $(NAMESPACE) -l app=vote

# Reinstallazione completa da zero.
reinstall:
	$(MAKE) cluster-down
	$(MAKE) cluster-up
	$(MAKE) deploy
	$(MAKE) wait-ready