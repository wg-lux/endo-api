# Simple build/load/deploy workflow for RKE2
# Requirements on the target node:
# - Podman or Docker
# - containerd (ctr) available (RKE2)
# - kubectl configured (export KUBECONFIG=/etc/rancher/rke2/rke2.yaml)

# Force bash (dash lacks -o pipefail) to avoid /bin/sh errors
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

VERSION       ?= 1.0.0
IMAGE_NAME    ?= endo-api
IMG           ?= $(IMAGE_NAME):$(VERSION)
NAMESPACE     ?= endo-api
HOST          ?= endo-api.xulutions.net

ENGINE        ?= $(shell command -v podman >/dev/null 2>&1 && echo podman || (command -v docker >/dev/null 2>&1 && echo docker))
NAMESPACE	  ?= endo-api
CTR_NS        ?= k8s.io
IMAGE_TAR     ?= $(IMAGE_NAME)-$(VERSION).tar

# Optional local/regional registry support
# Set REGISTRY (host:port) explicitly or auto-detect a Service named 'registry' or 'docker-registry'
REGISTRY       ?=
REGISTRY_PORT  ?= 5000
#TODO Document how we deteckt docker-registry
REGISTRY_DETECTED := $(shell kubectl get svc -A -o jsonpath='{range .items[?(@.metadata.name=="registry" || @.metadata.name=="docker-registry")]}{.metadata.name}.{.metadata.namespace}.svc.cluster.local:{(index .spec.ports 0).port}{"\n"}{end}' 2>/dev/null | head -1)
REGISTRY_EFFECTIVE := $(if $(strip $(REGISTRY)),$(REGISTRY),$(REGISTRY_DETECTED))
# Fully qualified image (priority: detected/explicit registry -> docker hub library)
IMAGE_FQN := $(if $(strip $(REGISTRY_EFFECTIVE)),$(REGISTRY_EFFECTIVE)/$(IMAGE_NAME):$(VERSION),docker.io/library/$(IMAGE_NAME):$(VERSION))
BUILD_TS    := $(shell date -u +%Y%m%d%H%M%S)

# Build configuration
DOCKER_BUILDKIT ?= 0          # Default off (was causing stack smash); override with DOCKER_BUILDKIT=1 make build
BUILD_ARGS      ?=            # Extra args e.g. BUILD_ARGS="--no-cache"

.PHONY: help
help:
	@echo "Targets:"
	@echo "  build           - Build production image ($(IMG))"
	@echo "                   (ENGINE=$(ENGINE) DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) BUILD_ARGS='$(BUILD_ARGS)')"
	@echo "  save            - Save image to tar ($(IMAGE_TAR))"
	@echo "  load            - Load image into containerd (sudo ctr -n $(CTR_NS) images import)"
	@echo "  assert-image    - Ensure image is present locally when no registry is used"
	@echo "  k8s-namespace   - Create namespace ($(NAMESPACE))"
	@echo "  k8s-config      - Create/Update ConfigMap (non-secrets)"
	@echo "  k8s-secrets     - Create/Update Secret from env (DJANGO_SECRET_KEY, DATABASE_URL or DB_*)"
	@echo "  deploy          - Apply PVC, Deployment, Service, Ingress (verifies image present if no registry)"
	@echo "  undeploy        - Delete resources (keeps namespace)"
	@echo "  logs            - Tail logs"
	@echo "  status          - Show objects/status"

.PHONY: build
build:
	@if [ -z "$(ENGINE)" ]; then echo "No container engine (podman|docker) found"; exit 1; fi
	@echo "Building image $(IMG) (base tag) with $(ENGINE) (DOCKER_BUILDKIT=$(DOCKER_BUILDKIT))"
	DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) $(ENGINE) build $(BUILD_ARGS) -t $(IMG) -f container/Dockerfile.prod .
	@if [ -n "$(strip $(REGISTRY_EFFECTIVE))" ]; then \
	  echo "Tagging & pushing to registry: $(IMAGE_FQN)"; \
	  $(ENGINE) tag $(IMG) $(IMAGE_FQN); \
	  $(ENGINE) push $(IMAGE_FQN); \
	else \
	  echo "No registry detected (REGISTRY/Service 'registry'). Using local import workflow."; \
	fi

.PHONY: save
save:
	@if [ -z "$(ENGINE)" ]; then echo "No container engine (podman|docker) found"; exit 1; fi
	$(ENGINE) save -o $(IMAGE_TAR) $(IMG)
	@ls -lh $(IMAGE_TAR)

.PHONY: load
load:
	@echo "Importing $(IMAGE_TAR) into containerd namespace $(CTR_NS) (requires sudo)..."
	sudo ctr -n $(CTR_NS) images import $(IMAGE_TAR)
	sudo ctr -n $(CTR_NS) images ls | grep $(IMAGE_NAME) || true

.PHONY: k8s-namespace
k8s-namespace:
	kubectl apply -f k8s/namespace.yaml

.PHONY: k8s-config
k8s-config: k8s-namespace
	@echo "Applying ConfigMap endo-api-config in $(NAMESPACE)"
	kubectl -n $(NAMESPACE) create configmap endo-api-config \
	  --from-literal=DJANGO_ENV=production \
	  --from-literal=DJANGO_DEBUG=false \
	  --from-literal=DJANGO_ALLOWED_HOSTS="$(HOST),localhost,127.0.0.1,endo-api,endo-api.endo-api.svc,endo-api.endo-api.svc.cluster.local" \
	  --from-literal=DJANGO_SETTINGS_MODULE="endo_api.settings_prod" \
	  --dry-run=client -o yaml | kubectl apply -f -

.PHONY: k8s-secrets
k8s-secrets: k8s-namespace
	@if [ -z "$$DJANGO_SECRET_KEY" ]; then echo "DJANGO_SECRET_KEY env is required"; exit 1; fi
	@if [ -n "$$DATABASE_URL" ]; then \
	  kubectl -n $(NAMESPACE) create secret generic endo-api-secrets \
	    --from-literal=DJANGO_SECRET_KEY="$$DJANGO_SECRET_KEY" \
	    --from-literal=DATABASE_URL="$$DATABASE_URL" \
	    --dry-run=client -o yaml | kubectl apply -f - ; \
	else \
	  if [ -z "$$DB_ENGINE" ] || [ -z "$$DB_NAME" ] || [ -z "$$DB_USER" ] || [ -z "$$DB_PASSWORD" ] || [ -z "$$DB_HOST" ] || [ -z "$$DB_PORT" ]; then \
	    echo "Either set DATABASE_URL or all of DB_ENGINE,DB_NAME,DB_USER,DB_PASSWORD,DB_HOST,DB_PORT"; exit 1; \
	  fi; \
	  kubectl -n $(NAMESPACE) create secret generic endo-api-secrets \
	    --from-literal=DJANGO_SECRET_KEY="$$DJANGO_SECRET_KEY" \
	    --from-literal=DB_ENGINE="$$DB_ENGINE" \
	    --from-literal=DB_NAME="$$DB_NAME" \
	    --from-literal=DB_USER="$$DB_USER" \
	    --from-literal=DB_PASSWORD="$$DB_PASSWORD" \
	    --from-literal=DB_HOST="$$DB_HOST" \
	    --from-literal=DB_PORT="$$DB_PORT" \
	    --dry-run=client -o yaml | kubectl apply -f - ; \
	fi

.PHONY: assert-image
assert-image:
	@if [ -z "$(strip $(REGISTRY_EFFECTIVE))" ]; then \
		echo "[assert-image] No registry detected (using local import workflow)."; \
		echo "[assert-image] Verifying image present in containerd namespace $(CTR_NS): $(IMAGE_FQN)"; \
		if ! sudo ctr -n $(CTR_NS) images ls | awk '{print $$1}' | grep -qx '$(IMAGE_FQN)'; then \
			echo "[assert-image] MISSING image $(IMAGE_FQN). Run: make save VERSION=$(VERSION) && sudo make load VERSION=$(VERSION)"; \
			exit 1; \
		fi; \
		echo "[assert-image] Image found."; \
	else \
		echo "[assert-image] Registry detected ($(REGISTRY_EFFECTIVE)); cluster will pull image."; \
	fi

.PHONY: deploy
deploy: k8s-namespace k8s-config k8s-secrets assert-image
	kubectl apply -f k8s/pvc.yaml
	@echo "Applying Deployment (preferred image=$(IMAGE_FQN))"
	@BUILD_TS="$(BUILD_TS)" IMAGE="$(IMAGE_FQN)" envsubst '$${BUILD_TS} $${IMAGE}' < k8s/deployment.tmpl.yaml | kubectl -n $(NAMESPACE) apply -f -
	kubectl apply -f k8s/service.yaml
	@echo "Applying Ingress (host=$(HOST))"
	@HOST="$(HOST)" envsubst '$${HOST}' < k8s/ingress.tmpl.yaml | kubectl -n $(NAMESPACE) apply -f -
	kubectl -n $(NAMESPACE) rollout status deploy/endo-api

.PHONY: undeploy
undeploy:
	@HOST="$(HOST)" envsubst '$${HOST}' < k8s/ingress.tmpl.yaml | kubectl -n $(NAMESPACE) delete -f - --ignore-not-found
	kubectl -n $(NAMESPACE) delete -f k8s/service.yaml --ignore-not-found
	kubectl -n $(NAMESPACE) delete deploy/endo-api --ignore-not-found
	kubectl -n $(NAMESPACE) delete pvc/endo-api-data --ignore-not-found
	kubectl -n $(NAMESPACE) delete secret/endo-api-secrets --ignore-not-found
	kubectl -n $(NAMESPACE) delete configmap/endo-api-config --ignore-not-found

.PHONY: logs
logs:
	kubectl -n $(NAMESPACE) logs -f deploy/endo-api

.PHONY: status
status:
	kubectl -n $(NAMESPACE) get all
	kubectl -n $(NAMESPACE) get ingress

# Helper: show resolved image refs
.PHONY: image-info
image-info:
	@echo "Base tag: $(IMG)"; \
	 echo "Registry effective: $(REGISTRY_EFFECTIVE)"; \
	 echo "Image FQN: $(IMAGE_FQN)";

# Debug registry detection
.PHONY: debug-registry
debug-registry:
	@echo "=== Registry Detection Debug ==="
	@echo "REGISTRY (manual): $(REGISTRY)"
	@echo "REGISTRY_DETECTED raw command:"
	@echo "kubectl get svc -A -o jsonpath='{range .items[?(@.metadata.name==\"registry\" || @.metadata.name==\"docker-registry\")]}{.metadata.name}.{.metadata.namespace}.svc.cluster.local:{(index .spec.ports 0).port}{\"\\n\"}{end}'"
	@echo "REGISTRY_DETECTED result: $(REGISTRY_DETECTED)"
	@echo "REGISTRY_EFFECTIVE: $(REGISTRY_EFFECTIVE)"
	@echo ""
	@echo "=== All registry-related services ==="
	@kubectl get svc -A | grep -i registry || echo "No registry services found"
	@echo ""
	@echo "=== Testing alternative detection methods ==="
	@kubectl get svc docker-registry -n registry -o jsonpath='{.metadata.name}.{.metadata.namespace}.svc.cluster.local:{(index .spec.ports 0).port}' 2>/dev/null || echo "Direct service lookup failed"
