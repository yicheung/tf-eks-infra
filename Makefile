.PHONY: help fmt validate test lint scan manifests check

TF_DIRS := terraform/bootstrap $(wildcard terraform/envs/*) $(wildcard terraform/modules/aws/*) terraform/modules/platform-bootstrap

help:
	@echo "fmt        terraform fmt -recursive"
	@echo "validate   terraform init -backend=false + validate in every root/module"
	@echo "test       terraform test (mocked providers) in every env with tests/"
	@echo "lint       tflint"
	@echo "scan       trivy + checkov IaC scans"
	@echo "manifests  render Helm/kustomize and validate with kubeconform"
	@echo "check      all of the above"

fmt:
	terraform fmt -recursive terraform

validate:
	@set -e; for d in $(TF_DIRS); do \
	  echo "==> $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null; \
	  terraform -chdir=$$d validate; \
	done

test:
	@set -e; for d in $(wildcard terraform/envs/*); do \
	  if [ -d $$d/tests ]; then \
	    echo "==> $$d"; \
	    terraform -chdir=$$d init -backend=false -input=false >/dev/null; \
	    terraform -chdir=$$d test; \
	  fi; \
	done

lint:
	tflint --init --config $(CURDIR)/.tflint.hcl
	tflint --recursive --config $(CURDIR)/.tflint.hcl --chdir terraform

scan:
	trivy config --severity HIGH,CRITICAL --exit-code 1 terraform
	checkov --directory terraform --framework terraform --quiet --compact --config-file .checkov.yaml

manifests:
	./scripts/validate-manifests.sh

check: validate test lint scan manifests
