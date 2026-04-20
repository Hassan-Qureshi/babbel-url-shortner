.PHONY: install lint format clean zip apply deploy

ENV ?= dev

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
	poetry self add poetry-plugin-export
	cd lambda && poetry export --without-hashes -f requirements.txt -o requirements.txt
	pip install -t lambda/build -r lambda/requirements.txt
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
	aws lambda update-function-code --function-name url-shortener-shorten-$(ENV) --zip-file fileb://lambda/dist/shorten.zip --publish
	aws lambda update-function-code --function-name url-shortener-redirect-$(ENV) --zip-file fileb://lambda/dist/redirect.zip --publish
