CLUSTER_NAME := voting-cluster
NAMESPACE := voting-app

.PHONY: doctor cluster-up cluster-down deploy wait-ready verify

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
	kubectl apply -k k8s/overlays/local

wait-ready:
	kubectl wait --for=condition=ready pod --all -n $(NAMESPACE) --timeout=120s

verify:
	kubectl get pods,svc,endpoints -n $(NAMESPACE)