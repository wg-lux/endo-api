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
# CSRF Trusted Origins (comma-separated). Defaults to https://<HOST>
CSRF_ORIGINS  ?= https://$(HOST)

ENGINE        ?= $(shell command -v podman >/dev/null 2>&1 && echo podman || (command -v docker >/dev/null 2>&1 && echo docker))
CTR_NS        ?= k8s.io
IMAGE_TAR     ?= $(IMAGE_NAME)-$(VERSION).tar

# External registry configuration (no auto-detection)
# Provide the Docker registry as host[:port], e.g. moose1.xulutions.net or moose1.xulutions.net:5000
# Scheme controls validation requests (does not affect image reference). Use https for TLS-enabled registries.
REGISTRY          ?= moose1.xulutions.net
REGISTRY_SCHEME   ?= https
# (Optional) If REGISTRY is empty, images will not be pushed and a local containerd import workflow is used.

# Fully qualified image (priority: explicit registry -> docker hub library)
IMAGE_FQN := $(if $(strip $(REGISTRY)),$(REGISTRY)/$(IMAGE_NAME):$(VERSION),docker.io/library/$(IMAGE_NAME):$(VERSION))
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
	@echo ""
	@echo "Registry Management:"
	@echo "  validate-registry       - Validate that REGISTRY is a reachable Docker Registry (expects HTTP 200 or 401 on /v2/)"
	@echo "  debug-registry          - Show registry configuration and run validation"
	@echo "  configure-docker-registry - Configure Docker for insecure HTTP registry (only needed if REGISTRY_SCHEME=http)"
	@echo "  registry-login          - Login to registry (requires credentials)"
	@echo "  registry-test           - Test registry connectivity and authentication"

.PHONY: build
build:
	@if [ -z "$(ENGINE)" ]; then echo "No container engine (podman|docker) found"; exit 1; fi
	@echo "Building image $(IMG) (base tag) with $(ENGINE) (DOCKER_BUILDKIT=$(DOCKER_BUILDKIT))"
	DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) $(ENGINE) build $(BUILD_ARGS) -t $(IMG) -f container/Dockerfile.prod .
	@if [ -n "$(strip $(REGISTRY))" ]; then \
	  $(MAKE) validate-registry; \
	  echo "Tagging & pushing to registry: $(IMAGE_FQN)"; \
	  $(ENGINE) tag $(IMG) $(IMAGE_FQN); \
	  if [ "$(REGISTRY_SCHEME)" = "http" ]; then \
	    echo "Note: For HTTP registries you may need to configure Docker's insecure registries"; \
	  fi; \
	  $(ENGINE) push $(IMAGE_FQN); \
	else \
	  echo "No registry configured (REGISTRY is empty). Using local import workflow."; \
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
	  --from-literal=DJANGO_SETTINGS_MODULE="config.settings.prod" \
	  --from-literal=DJANGO_ALLOWED_HOSTS="$(HOST),localhost,127.0.0.1,endo-api,endo-api.endo-api.svc,endo-api.endo-api.svc.cluster.local" \
	  --from-literal=DJANGO_DEBUG=false \
	  --from-literal=DJANGO_HOST=0.0.0.0 \
	  --from-literal=DJANGO_PORT=8118 \
	  --from-literal=TIME_ZONE=Europe/Berlin \
	  --from-literal=STATIC_URL=/static/ \
	  --from-literal=MEDIA_URL=/media/ \
	  --from-literal=RUN_VIDEO_TESTS=false \
	  --from-literal=SKIP_EXPENSIVE_TESTS=true \
	  --from-literal=STORAGE_DIR=/app/data \
	  --from-literal=ASSET_DIR=tests/assets \
	  --from-literal=DJANGO_CSRF_TRUSTED_ORIGINS="$(CSRF_ORIGINS)" \
	  --from-literal=DJANGO_SECURE_SSL_REDIRECT="true" \
	  --from-literal=DJANGO_SESSION_COOKIE_SECURE="true" \
	  --from-literal=DJANGO_CSRF_COOKIE_SECURE="true" \
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
	@if [ -z "$(strip $(REGISTRY))" ]; then \
		echo "[assert-image] No registry configured (using local import workflow)."; \
		echo "[assert-image] Verifying image present in containerd namespace $(CTR_NS): $(IMAGE_FQN)"; \
		if ! sudo ctr -n $(CTR_NS) images ls | awk '{print $$1}' | grep -qx '$(IMAGE_FQN)'; then \
			echo "[assert-image] MISSING image $(IMAGE_FQN). Run: make save VERSION=$(VERSION) && sudo make load VERSION=$(VERSION)"; \
			exit 1; \
		fi; \
		echo "[assert-image] Image found."; \
	else \
		echo "[assert-image] Registry configured ($(REGISTRY)); cluster will pull image."; \
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
	 echo "Registry: $(REGISTRY)"; \
	 echo "Registry scheme: $(REGISTRY_SCHEME)"; \
	 echo "Image FQN: $(IMAGE_FQN)";

# Validate registry
.PHONY: validate-registry
validate-registry:
	@if [ -z "$(strip $(REGISTRY))" ]; then echo "REGISTRY is empty; nothing to validate"; exit 1; fi
	@echo "Validating registry endpoint: $(REGISTRY_SCHEME)://$(REGISTRY)/v2/"
	@code=$$(curl -s -o /dev/null -w '%{http_code}' "$(REGISTRY_SCHEME)://$(REGISTRY)/v2/" || echo 000); \
	 if [ "$$code" = "200" ] || [ "$$code" = "401" ]; then \
	   echo "✓ Registry reachable (HTTP $$code)"; \
	 else \
	   echo "✗ Registry check failed (HTTP $$code)"; exit 1; \
	 fi

# Debug registry configuration
.PHONY: debug-registry
debug-registry:
	@echo "=== Registry Configuration Debug ==="
	@echo "REGISTRY: $(REGISTRY)"
	@echo "REGISTRY_SCHEME: $(REGISTRY_SCHEME)"
	@echo "IMAGE_FQN: $(IMAGE_FQN)"
	@echo "Container engine: $(ENGINE)"
	@$(MAKE) -s validate-registry || true

# Configure Docker for insecure registry (HTTP)
.PHONY: configure-docker-registry
configure-docker-registry:
	@echo "Configuring Docker for insecure registry $(REGISTRY) (scheme=$(REGISTRY_SCHEME))"
	@if [ "$(REGISTRY_SCHEME)" != "http" ]; then echo "Registry scheme is $(REGISTRY_SCHEME) - insecure Docker configuration is typically NOT required."; fi
	@if [ -z "$(REGISTRY)" ]; then echo "No registry configured"; exit 1; fi
	@echo "Creating/updating /etc/docker/daemon.json..."
	@sudo mkdir -p /etc/docker
	@if [ -f /etc/docker/daemon.json ]; then \
		echo "Backing up existing daemon.json..."; \
		sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$$(date +%Y%m%d_%H%M%S); \
	fi
	@echo '{"insecure-registries": ["$(REGISTRY)"]}' | sudo tee /etc/docker/daemon.json
	@echo "Restarting Docker daemon..."
	@sudo systemctl restart docker
	@echo "Docker configured for insecure registry: $(REGISTRY)"

# Login to registry (if authentication required)
.PHONY: registry-login
registry-login:
	@echo "Logging into registry $(REGISTRY)"
	@if [ -z "$(REGISTRY)" ]; then echo "No registry configured"; exit 1; fi
	@$(ENGINE) login $(REGISTRY)

# Check registry connectivity and authentication
.PHONY: registry-test
registry-test:
	@echo "Testing registry connectivity to $(REGISTRY)"
	@if [ -z "$(REGISTRY)" ]; then echo "No registry configured"; exit 1; fi
	@echo "Testing HTTP connectivity..."
	@curl -fsS $(REGISTRY_SCHEME)://$(REGISTRY)/v2/ >/dev/null 2>&1 && echo "✓ Registry accessible" || echo "Note: /v2/ returned non-2xx (this can be OK if it returns 401)."
	@code=$$(curl -s -o /dev/null -w '%{http_code}' "$(REGISTRY_SCHEME)://$(REGISTRY)/v2/" || echo 000); echo "HTTP $$code"
	@echo "Testing image push (hello-world) ..."
	@$(ENGINE) pull hello-world:latest >/dev/null 2>&1 || true
	@$(ENGINE) tag hello-world:latest $(REGISTRY)/hello-world:test 2>/dev/null || true
	@if $(ENGINE) push $(REGISTRY)/hello-world:test >/dev/null 2>&1; then \
		echo "✓ Can push to registry"; \
		$(ENGINE) rmi $(REGISTRY)/hello-world:test >/dev/null 2>&1 || true; \
	else \
		echo "✗ Cannot push to registry - may need authentication"; \
	fi
