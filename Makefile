.PHONY: install lint format clean zip apply deploy deploy-shorten deploy-redirect

ENV ?= dev
AWS ?= aws
PYTHON ?= python3
LAMBDA_PLATFORM ?= manylinux2014_aarch64
LAMBDA_PYTHON_VERSION ?= 3.13

# ---------------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------------

install:
	cd lambda && poetry install

lint:
	cd lambda && poetry run ruff check .

format:
	cd lambda && poetry run ruff format .

# ---------------------------------------------------------------------------
# Lambda zip packaging
# ---------------------------------------------------------------------------

clean:
	rm -rf lambda/build lambda/dist

zip: clean
	mkdir -p lambda/build lambda/dist
	# install dependencies
	cd lambda && poetry export --without-hashes -f requirements.txt -o requirements.txt
	$(PYTHON) -m pip install \
		--upgrade \
		--only-binary=:all: \
		--platform $(LAMBDA_PLATFORM) \
		--implementation cp \
		--python-version $(LAMBDA_PYTHON_VERSION) \
		--target lambda/build \
		-r lambda/requirements.txt
	rm lambda/requirements.txt
	# cleanup unnecessary files from dependencies
	find lambda/build -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find lambda/build -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
	find lambda/build -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
	find lambda/build -type f -name "*.pyc" -delete 2>/dev/null || true
	find lambda/build -type f -name "*.pyo" -delete 2>/dev/null || true
	find lambda/build -type f -name "*.c" -delete 2>/dev/null || true
	find lambda/build -type f -name "*.h" -delete 2>/dev/null || true
	# shorten
	cp -r lambda/src/shorten lambda/shared lambda/build/
	cd lambda/build && zip -r ../dist/shorten.zip .
	rm -rf lambda/build/shorten lambda/build/shared
	# redirect
	cp -r lambda/src/redirect lambda/shared lambda/build/
	cd lambda/build && zip -r ../dist/redirect.zip .
	rm -rf lambda/build

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------

apply: zip
	terraform -chdir=terraform/environments/$(ENV) init -input=false
	terraform -chdir=terraform/environments/$(ENV) apply -auto-approve

# ---------------------------------------------------------------------------
# Deploy Lambda code
# ---------------------------------------------------------------------------

deploy: zip
	$(MAKE) deploy-shorten ENV=$(ENV)
	$(MAKE) deploy-redirect ENV=$(ENV)

deploy-shorten:
	@VERSION=`$(AWS) lambda update-function-code \
		--function-name url-shortener-shorten-$(ENV) \
		--zip-file fileb://lambda/dist/shorten.zip \
		--publish \
		--query Version \
		--output text`; \
	$(AWS) lambda update-alias \
		--function-name url-shortener-shorten-$(ENV) \
		--name live \
		--function-version $$VERSION; \
	echo "shorten deployed: version $$VERSION"

deploy-redirect:
	@VERSION=`$(AWS) lambda update-function-code \
		--function-name url-shortener-redirect-$(ENV) \
		--zip-file fileb://lambda/dist/redirect.zip \
		--publish \
		--query Version \
		--output text`; \
	$(AWS) lambda update-alias \
		--function-name url-shortener-redirect-$(ENV) \
		--name live \
		--function-version $$VERSION; \
	echo "redirect deployed: version $$VERSION"
