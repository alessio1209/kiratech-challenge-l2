CLUSTER_NAME := voting-cluster
NAMESPACE := voting-app
KCTX := --context kind-$(CLUSTER_NAME)

.PHONY: doctor cluster-up cluster-down deploy wait-ready verify incident-image recover-image incident-service recover-service scale-up scale-down smoke-test

doctor:
	@command -v docker >/dev/null 2>&1 || { echo >&2 "Docker mancante."; exit 1; }
	@command -v kind >/dev/null 2>&1 || { echo >&2 "Kind mancante."; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl mancante."; exit 1; }
	@echo "Prerequisiti OK"

cluster-up:
	kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml

cluster-down:
	kind delete cluster --name $(CLUSTER_NAME)

deploy:
	kubectl $(KCTX) apply -k k8s/overlays/local

wait-ready:
	kubectl $(KCTX) wait --for=condition=ready pod --all -n$(NAMESPACE) --timeout=120s

verify:
	kubectl $(KCTX) get pods,svc,endpoints -n$(NAMESPACE)

incident-image:
	kubectl $(KCTX) apply -k k8s/overlays/incident-image

recover-image:
	kubectl $(KCTX) apply -k k8s/overlays/local

incident-service:
	kubectl $(KCTX) apply -k k8s/overlays/incident-service

recover-service:
	kubectl $(KCTX) apply -k k8s/overlays/local

scale-up:
	kubectl $(KCTX) scale deployment vote --replicas=3 -n$(NAMESPACE)
	kubectl $(KCTX) get pods -n$(NAMESPACE) -l app=vote -w

scale-down:
	kubectl $(KCTX) scale deployment vote --replicas=1 -n$(NAMESPACE)
	kubectl $(KCTX) get pods -n$(NAMESPACE) -l app=vote

smoke-test:
	@echo "Eseguo smoke test HTTP sulle interfacce esposte..."
	@curl -s -f -o /dev/null http://localhost:30000 && echo "✅ Vote App raggiungibile (HTTP 200 OK)" || (echo "❌ Vote App NON raggiungibile"; exit 1)
	@curl -s -f -o /dev/null http://localhost:30001 && echo "✅ Result App raggiungibile (HTTP 200 OK)" || (echo "❌ Result App NON raggiungibile"; exit 1)

change-voting-options:
	kubectl $(KCTX) apply -k k8s/overlays/custom-options

reset-voting-options:
	kubectl $(KCTX) apply -k k8s/overlays/local