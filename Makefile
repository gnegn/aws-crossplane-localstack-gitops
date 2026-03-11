.PHONY: help setup setup-cluster setup-argocd setup-crossplane setup-localstack status destroy \
        argocd-ui sync logs check-buckets check-queues

CLUSTER_NAME ?= crossplane-localstack
ARGOCD_NAMESPACE ?= argocd
ARGOCD_PORT ?= 8080

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ============================================================
# SETUP
# ============================================================

setup: setup-cluster setup-localstack setup-argocd setup-crossplane ## Full cluster setup from scratch
	@echo "\n\033[32m✔ Setup complete! Run 'make status' to check everything.\033[0m"

setup-cluster: ## Create kind cluster
	@echo "\033[34m▶ Creating kind cluster...\033[0m"
	kind create cluster --name $(CLUSTER_NAME) --config k8s-cluster/kind-config.yaml
	@echo "\033[32m✔ Cluster created.\033[0m"

setup-localstack: ## Deploy localstack into the cluster
	@echo "\033[34m▶ Deploying localstack...\033[0m"
	kubectl apply -f infrastructure/localstack/namespace.yaml
	kubectl apply -f infrastructure/localstack/deployment.yaml
	kubectl apply -f infrastructure/localstack/service.yaml
	kubectl rollout status deployment/localstack -n localstack --timeout=300s
	@echo "\033[32m✔ Localstack is ready.\033[0m"

setup-argocd: ## Install ArgoCD and deploy the main Application
	@echo "\033[34m▶ Installing ArgoCD...\033[0m"
	kubectl create namespace $(ARGOCD_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n $(ARGOCD_NAMESPACE) -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl rollout status deployment/argocd-server -n $(ARGOCD_NAMESPACE) --timeout=180s
	@echo "\033[34m▶ Applying ArgoCD Application...\033[0m"
	kubectl apply -f infrastructure/argocd/infra-app.yaml
	@echo "\033[32m✔ ArgoCD is ready.\033[0m"

setup-crossplane: ## Install Crossplane via Helm
	@echo "\033[34m▶ Installing Crossplane...\033[0m"
	helm repo add crossplane-stable https://charts.crossplane.io/stable
	helm repo update
	helm upgrade --install crossplane crossplane-stable/crossplane \
		--namespace crossplane-system \
		--create-namespace \
		--wait
	@echo "\033[32m✔ Crossplane is ready.\033[0m"

# ============================================================
# STATUS
# ============================================================

status: ## Show status of all components
	@echo "\n\033[34m=== Cluster ===\033[0m"
	kubectl cluster-info
	@echo "\n\033[34m=== Localstack ===\033[0m"
	kubectl get pods -n localstack
	@echo "\n\033[34m=== Crossplane ===\033[0m"
	kubectl get pods -n crossplane-system
	kubectl get providers
	kubectl get functions
	@echo "\n\033[34m=== ArgoCD Apps ===\033[0m"
	kubectl get applications -n $(ARGOCD_NAMESPACE)
	@echo "\n\033[34m=== Crossplane Resources ===\033[0m"
	kubectl get xrd
	kubectl get composition
	kubectl get storage -A
	kubectl get buckets -A
	kubectl get queues -A

check-buckets: ## List S3 buckets in localstack
	@echo "\033[34m▶ S3 Buckets in localstack:\033[0m"
	kubectl exec -n localstack deployment/localstack -- awslocal s3 ls

check-queues: ## List SQS queues in localstack
	@echo "\033[34m▶ SQS Queues in localstack:\033[0m"
	kubectl exec -n localstack deployment/localstack -- awslocal sqs list-queues

# ============================================================
# ARGOCD
# ============================================================

argocd-ui: ## Port-forward ArgoCD UI to localhost:8080
	@echo "\033[34m▶ ArgoCD UI: http://localhost:$(ARGOCD_PORT)\033[0m"
	@echo "\033[34m▶ Username: admin\033[0m"
	@echo "\033[34m▶ Password: $$(kubectl -n $(ARGOCD_NAMESPACE) get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)\033[0m"
	kubectl port-forward svc/argocd-server -n $(ARGOCD_NAMESPACE) $(ARGOCD_PORT):443

sync: ## Force ArgoCD sync
	argocd app sync crossplane-resources --hard-refresh

# ============================================================
# LOGS
# ============================================================

logs: ## Show logs for all key components
	@echo "\n\033[34m=== Crossplane logs ===\033[0m"
	kubectl logs -n crossplane-system deployment/crossplane --tail=30
	@echo "\n\033[34m=== Localstack logs ===\033[0m"
	kubectl logs -n localstack deployment/localstack --tail=30

# ============================================================
# DESTROY
# ============================================================

destroy: ## Delete the kind cluster completely
	@echo "\033[31m▶ Destroying cluster $(CLUSTER_NAME)...\033[0m"
	kind delete cluster --name $(CLUSTER_NAME)
	@echo "\033[32m✔ Cluster destroyed.\033[0m"	