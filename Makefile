CLUSTER_NAME := voting-cluster
NAMESPACE := voting-app
KCTX := --context kind-$(CLUSTER_NAME)
KC := kubectl $(KCTX)
ENV_FILE := k8s/overlays/local/.env
DEPLOYMENTS := db redis vote result worker
APP ?= worker

.PHONY: help doctor init-env env-check cluster-up cluster-down deploy wait-ready verify events logs \
	smoke-test e2e-test incident-image recover-image incident-service recover-service \
	change-voting-options reset-voting-options scale-up scale-down reinstall \
	diagnose evidence

help:
	@echo "Setup:      doctor | init-env | cluster-up | deploy | wait-ready | reinstall | cluster-down"
	@echo "Verifica:   verify | events | logs APP=<nome> | smoke-test | e2e-test"
	@echo "Incidenti:  incident-image / recover-image | incident-service / recover-service"
	@echo "Demo:       change-voting-options / reset-voting-options | scale-up / scale-down"
	@echo "Escalation: diagnose | evidence [LABEL=<nome>]"

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

# Raccoglie le evidenze da allegare a un'escalation: stato, Service/EndpointSlice, label, eventi,
# describe dei Pod non pronti, log di ogni Pod. Sola lettura: non modifica nulla nel cluster.
diagnose:
	@echo "### DATA: $$(date '+%Y-%m-%d %H:%M:%S %z')   CONTESTO: kind-$(CLUSTER_NAME)   NAMESPACE: $(NAMESPACE)"
	@echo; echo "### DEPLOYMENT E POD"; $(KC) get deployments,pods -o wide -n $(NAMESPACE)
	@echo; echo "### SERVICE (colonna SELECTOR) ED ENDPOINTSLICE"; $(KC) get svc,endpointslices -o wide -n $(NAMESPACE)
	@echo; echo "### LABEL DEI POD (da confrontare con i selector dei Service)"; $(KC) get pods -n $(NAMESPACE) --show-labels
	@echo; echo "### EVENTI DI TIPO WARNING"; $(KC) get events -n $(NAMESPACE) --field-selector type=Warning --sort-by=.metadata.creationTimestamp
	@echo; echo "### ULTIMI EVENTI (25)"; $(KC) get events -n $(NAMESPACE) --sort-by=.metadata.creationTimestamp | tail -n 25
	@echo; echo "### POD NON PRONTI (describe, ultime 25 righe)"; \
	for p in $$($(KC) get pods -n $(NAMESPACE) --no-headers | awk '{split($$2,a,"/"); if (a[1]!=a[2]) print $$1}'); do \
		echo "--- $$p"; $(KC) describe pod $$p -n $(NAMESPACE) | tail -n 25; \
	done
	@echo; echo "### LOG DI OGNI POD (ultime 30 righe; [previous] = container precedente al riavvio)"; \
	for p in $$($(KC) get pods -n $(NAMESPACE) -o name); do \
		echo "--- $$p"; \
		$(KC) logs $$p -n $(NAMESPACE) --tail=30 2>&1 || true; \
		$(KC) logs $$p -n $(NAMESPACE) --previous --tail=30 2>/dev/null | sed 's/^/[previous] /' || true; \
	done

# Salva l'output di diagnose in docs/evidence/ con data e ora.
# Esempio: make evidence LABEL=incident-image   ->   docs/evidence/diagnose-incident-image-<data>.txt
LABEL ?=
evidence:
	@mkdir -p docs/evidence
	@f=docs/evidence/diagnose$(if $(LABEL),-$(LABEL))-$$(date +%Y%m%d-%H%M%S).txt; \
	$(MAKE) --no-print-directory diagnose > $$f 2>&1; echo "Evidenze salvate in $$f"

# Reinstallazione completa da zero.
reinstall:
	$(MAKE) cluster-down
	$(MAKE) cluster-up
	$(MAKE) deploy
	$(MAKE) wait-ready