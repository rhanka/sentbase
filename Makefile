SHELL := /bin/bash

# OpenDB workflow targets (sentropic harness, see rules/MASTER.md). Every target
# has a `## comment` consumed by `make help`. Run targets from the root of the
# checkout or of a `tmp/<slug>` worktree: `make <target>`.

WORKTREE := $(CURDIR)
ENV ?= test-harness-adopt
CARGO    := cargo
GIT      := git -C $(WORKTREE)
NPM      := npm
NODE_BIN := $(WORKTREE)/target/debug/opendb-node

# Resolved with docker buildx imagetools inspect; rust:bookworm tracks the
# stable channel in rust-toolchain.toml. Both official images use Bookworm.
RUST_IMAGE := rust:bookworm@sha256:e6f2cff35d0f309acf8433b4f05878ed77092602c5065cc81801177da0bb3a9c
NODE_IMAGE := node:24-bookworm@sha256:8fa96264f302f58bbb13aa7339c541547b56975766ce956c875da149452a3e40
MUSL_IMAGE := rust:alpine@sha256:44819b27be4c97b0e4d7203bd2e02c4820f97700211b6a37fb4c246a2de59383
ACTIONLINT_IMAGE := rhysd/actionlint:latest@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
export BUILDX_CONFIG := $(WORKTREE)/tmp/toolchain/buildx
TOOLCHAIN_IMAGE := sentbase-toolchain:v1-$(shell printf '%s' '$(RUST_IMAGE) $(NODE_IMAGE)' | sha256sum | cut -c1-16)
DOCKER_RUN = docker run --rm --init --user "$$(id -u):$$(id -g)" \
	-v "$(WORKTREE):/workspace" -w /workspace -e HOME=/tmp \
	-e CARGO_HOME=/workspace/tmp/toolchain/target/cargo \
	-e npm_config_cache=/workspace/tmp/toolchain/npm
TOOLCHAIN_RUN = $(DOCKER_RUN) $(TOOLCHAIN_IMAGE) \
	sh -ec 'export RUSTUP_TOOLCHAIN="$$(rustup default | cut -d" " -f1)"; exec "$$@"' --

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available targets
	@echo "OpenDB Makefile — drumbeat-friendly workflow targets"
	@echo ""
	@echo "  Quality:"
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /Quality/ {next} /Build|Test|Lint|Check/ {printf "    \033[32m%-22s\033[0m %s\n", $$1, $$2}'
	@echo "  Git workflow:"
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /Git|Commit|Push|Ship|Status/ {printf "    \033[32m%-22s\033[0m %s\n", $$1, $$2}'
	@echo "  POC / smoke:"
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /POC|Smoke|Probe|Bench/ {printf "    \033[32m%-22s\033[0m %s\n", $$1, $$2}'
	@echo "  DB workflow:"
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /DB|Query|opendb/ {printf "    \033[32m%-22s\033[0m %s\n", $$1, $$2}'
	@echo "  Audit:"
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; /Audit|sentropic|grep|cloc/ {printf "    \033[32m%-22s\033[0m %s\n", $$1, $$2}'

# ----- Build / Test / Lint / Check ------------------------------------------

.PHONY: toolchain npm-ci
toolchain: ## Build the pinned Rust + Node toolchain (Docker is the only host toolchain)
	@mkdir -p "$(WORKTREE)/tmp/toolchain/target/cargo" "$(WORKTREE)/tmp/toolchain/npm"
	@docker image inspect $(TOOLCHAIN_IMAGE) >/dev/null 2>&1 || \
	printf '%s\n' 'FROM $(NODE_IMAGE) AS node' 'FROM $(RUST_IMAGE)' \
	  'RUN rustup component add clippy rustfmt' \
	  'COPY --from=node /usr/local/bin/node /usr/local/bin/node' \
	  'COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules' \
	  'RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx' \
	  | docker build -t $(TOOLCHAIN_IMAGE) -

npm-ci: toolchain ## Install locked Node dependencies, including dev dependencies, in Docker
	$(TOOLCHAIN_RUN) $(NPM) ci --include=dev

.PHONY: build
build: toolchain ## Build the full Rust workspace
	$(TOOLCHAIN_RUN) $(CARGO) build --workspace --locked

.PHONY: build-release
build-release: toolchain ## Build the Rust workspace in release mode
	$(TOOLCHAIN_RUN) $(CARGO) build --workspace --release --locked

.PHONY: test
test: toolchain ## Run the full cargo test workspace
	$(TOOLCHAIN_RUN) $(CARGO) test --workspace --locked

.PHONY: test-storage
test-storage: toolchain ## Run cargo tests for opendb-storage only
	$(TOOLCHAIN_RUN) $(CARGO) test -p opendb-storage --locked

.PHONY: test-sql
test-sql: toolchain ## Run cargo tests for opendb-sql only
	$(TOOLCHAIN_RUN) $(CARGO) test -p opendb-sql --locked

.PHONY: test-node
test-node: toolchain ## Run cargo tests for opendb-node only
	$(TOOLCHAIN_RUN) $(CARGO) test -p opendb-node --locked

.PHONY: fmt
fmt: toolchain ## Apply rustfmt to the whole workspace
	$(TOOLCHAIN_RUN) $(CARGO) fmt --all

.PHONY: fmt-check
fmt-check: toolchain ## Verify rustfmt has nothing to change
	$(TOOLCHAIN_RUN) $(CARGO) fmt --all -- --check

.PHONY: clippy
clippy: toolchain ## Run cargo clippy with -D warnings on the workspace
	$(TOOLCHAIN_RUN) $(CARGO) clippy --workspace --all-targets --locked -- -D warnings

.PHONY: lint
lint: fmt-check clippy ## fmt-check + clippy

.PHONY: check-ci
check-ci: ## Check GitHub Actions syntax and expressions with pinned actionlint
	docker run --rm --user "$$(id -u):$$(id -g)" -v "$(WORKTREE):/workspace:ro" \
	  -w /workspace $(ACTIONLINT_IMAGE) -color .github/workflows/ci.yml

.PHONY: check-ts
check-ts: npm-ci ## TypeScript typecheck (npm run check:ts)
	$(TOOLCHAIN_RUN) $(NPM) run check:ts

.PHONY: check-no-python
check-no-python: npm-ci ## Verify no Python file leaked into the repo
	$(TOOLCHAIN_RUN) $(NPM) run check:no-python

.PHONY: check-manifests
check-manifests: npm-ci ## Validate Kubernetes manifests
	$(TOOLCHAIN_RUN) $(NPM) run check:manifests

.PHONY: vitest
vitest: npm-ci build ## Run all vitest suites (npm test), including SQL parity's Cargo subprocess
	$(TOOLCHAIN_RUN) $(NPM) test

.PHONY: test-image-receipt
test-image-receipt: toolchain ## Test image receipts against failed checks, stale SHAs and image substitution
	$(TOOLCHAIN_RUN) node --test tools/image-receipt.test.mjs

.PHONY: check
check: lint test check-ts check-no-python check-manifests vitest test-image-receipt test-attribution test-workflow check-license check-ci scope-check ## Full check pipeline

.PHONY: check-license
check-license: toolchain ## Check every workspace package and the npm manifest declare MIT
	@mkdir -p tmp/ci
	@$(TOOLCHAIN_RUN) cargo metadata --no-deps --locked --format-version 1 > tmp/ci/license-metadata.json
	@$(TOOLCHAIN_RUN) node -e 'const fs = require("node:fs"); const m = JSON.parse(fs.readFileSync("tmp/ci/license-metadata.json")); if (!m.packages.length || m.packages.some(p => p.license !== "MIT") || require("./package.json").license !== "MIT") process.exit(1); console.log("license: MIT (" + m.packages.length + " Cargo packages and npm)");'

# ----- Git workflow ---------------------------------------------------------

.PHONY: status
status: ## Show git status + recent log
	$(GIT) status --short
	@echo "---"
	$(GIT) log --oneline -10

.PHONY: hooks
hooks: ## Git: install the repo hooks (core.hooksPath=.githooks, attribution guard)
	@$(GIT) config core.hooksPath .githooks
	@echo "hooks: core.hooksPath=.githooks"

export ATTRIBUTION_RANGE ?= HEAD
.PHONY: check-attribution
check-attribution: ## Check: refuse AI/agent attribution in commits (ATTRIBUTION_RANGE=origin/main..HEAD)
	@sh tools/check-attribution.sh "$$ATTRIBUTION_RANGE"

.PHONY: test-attribution
test-attribution: toolchain ## Test attribution markers, identities and inspection errors
	$(TOOLCHAIN_RUN) node --test tools/check-attribution.test.mjs

.PHONY: ci-source
ci-source: ## Check: record the checked-out SHA after a successful CI gate
	@printf 'sha=%s\n' "$$($(GIT) rev-parse HEAD)" >> "$${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

.PHONY: harness-tool scope-check
harness-tool: toolchain ## Install the exact harness CLI/API in the isolated tooling cache
	@$(TOOLCHAIN_RUN) sh -ec 'node -e '\''if (require("./tmp/toolchain/harness/node_modules/@sentropic/harness/package.json").version !== "0.4.0") process.exit(1)'\'' 2>/dev/null || npm install --prefix tmp/toolchain/harness --no-package-lock --ignore-scripts --no-save @sentropic/harness@0.4.0'

export SCOPE_RANGE ?= main...HEAD
scope-check: harness-tool ## Check: branch range plus staged/unstaged/untracked against the project profile
	$(DOCKER_RUN) -v "$$($(GIT) rev-parse --path-format=absolute --git-common-dir):$$($(GIT) rev-parse --path-format=absolute --git-common-dir):ro" \
	  -e CI -e SCOPE_RANGE $(TOOLCHAIN_IMAGE) node tools/scope-check.mjs

# Preserve command-line dollars as data, including Make function syntax.
override export MSG := $(value MSG)
.PHONY: commit test-workflow
commit: $(if $(wildcard BRANCH.md),scope-check) ## Git: commit staged files with a literal single-line MSG
	@sh tools/commit.sh

test-workflow: harness-tool ## Test literal commit messages and scope failure handling
	$(TOOLCHAIN_RUN) node --test tools/workflow.test.mjs

.PHONY: check-push-attribution push
check-push-attribution: ## Check: scan the exact outgoing branch range before push
	@set -e; b="$$($(GIT) branch --show-current)"; \
	  if [ -z "$$b" ] || [ "$$b" = main ]; then echo 'Refusing detached HEAD or main'; exit 1; fi; \
	  ref="refs/remotes/origin/$$b"; \
	  if $(GIT) show-ref --verify --quiet "$$ref"; then base="$$ref"; \
	  else status=$$?; [ "$$status" -eq 1 ] || exit "$$status"; base=refs/remotes/origin/main; fi; \
	  sh tools/check-attribution.sh "$$base..HEAD"
push: check-push-attribution ## Git: push a scanned branch with an explicit refspec
	@set -e; b="$$($(GIT) branch --show-current)"; \
	  test -n "$$b" && test "$$b" != main; \
	  $(GIT) push -u origin "refs/heads/$$b:refs/heads/$$b"

.PHONY: diff
diff: ## Show uncommitted diff
	$(GIT) diff

# ----- POC smoke / benches --------------------------------------------------

.PHONY: smoke
smoke: ## Run the sentropic POC smoke (POC = end-to-end Drizzle probe matrix)
	cd $(WORKTREE) && $(NPM) run poc:sentropic:smoke

.PHONY: smoke-real
smoke-real: ## Sprint 15.E corrective: rejoue 8 vraies requêtes sentropic
	cd $(WORKTREE) && $(NPM) run poc:sentropic:real

.PHONY: poc-migrate
poc-migrate: ## Sprint 18.A: rejoue les 27 migrations Drizzle sentropic contre opendb-node
	cd $(WORKTREE) && $(NPM) run poc:sentropic:migrate

.PHONY: poc-seed
poc-seed: ## Sprint 18.B: migrations + seed minimal Drizzle (workspaces/orgs/folders/initiatives)
	cd $(WORKTREE) && $(NPM) run poc:sentropic:seed

.PHONY: poc-http
poc-http: ## Sprint 18.C: HTTP route /api/folders bout-en-bout sur opendb-node
	cd $(WORKTREE) && $(NPM) run poc:sentropic:http

IMAGE_TAG ?= opendb-node:$(ENV)
.PHONY: check-image-inputs
check-image-inputs: toolchain ## Check runtime and toolchain image pins without live package resolution
	$(TOOLCHAIN_RUN) node tools/check-image-inputs.mjs
.PHONY: image poc-image image-receipt verify-image-receipt
image: poc-image ## Build and smoke-test Dockerfile.alpine with a static musl binary
poc-image: poc-musl check-image-inputs ## Build the Alpine runtime using only its Dockerfile and binary as context
	@mkdir -p "$(WORKTREE)/tmp/ci"
	@set -o pipefail; tar -C "$(WORKTREE)" --sort=name --owner=0 --group=0 --numeric-owner \
	  --mtime='UTC 1970-01-01' -cf - Dockerfile.alpine target/x86_64-unknown-linux-musl/release/opendb-node | \
	  docker buildx build --load -t $(IMAGE_TAG) --metadata-file "$(WORKTREE)/tmp/ci/image-metadata.json" -f Dockerfile.alpine -
	@docker image inspect $(IMAGE_TAG) --format '{{.Id}}' > "$(WORKTREE)/tmp/ci/image-id"
	docker run --rm "$$(cat "$(WORKTREE)/tmp/ci/image-id")" --help

.PHONY: image-integration
image-integration: image npm-ci ## Test the exact image ID with SQL write/read and restart recovery
	@TOOLCHAIN_IMAGE=$(TOOLCHAIN_IMAGE) SOURCE_SHA="$$($(GIT) rev-parse HEAD)" bash tools/image-integration.sh

RECEIPT_RUN = $(DOCKER_RUN) -e GITHUB_REPOSITORY -e GITHUB_SHA -e GITHUB_WORKFLOW \
	-e GITHUB_RUN_ID -e GITHUB_RUN_ATTEMPT -e CI_NEEDS -e SOURCE_SHA="$$($(GIT) rev-parse HEAD)" \
	$(TOOLCHAIN_IMAGE) node tools/image-receipt.mjs
RECEIPT_FILES := tmp/ci/image-receipt.json tmp/ci/image-metadata.json tmp/ci/image-id
image-receipt: image ## Check successful same-SHA jobs and write the tested image receipt
	$(RECEIPT_RUN) write $(RECEIPT_FILES)
verify-image-receipt: toolchain ## Check the image receipt against this workflow run and build metadata
	$(RECEIPT_RUN) verify $(RECEIPT_FILES)

.PHONY: poc-bench
poc-bench: ## Sprint 20: side-by-side latency bench opendb-node vs postgres:16-alpine
	cd $(WORKTREE) && $(NPM) run poc:sentropic:bench

.PHONY: poc-bench-concurrent
poc-bench-concurrent: ## Phase B prep: multi-client concurrent INSERT+SELECT bench opendb vs PG
	cd $(WORKTREE) && $(NPM) run poc:sentropic:bench-concurrent

.PHONY: poc-musl
poc-musl: toolchain ## Build the static musl binary in a pinned Rust Alpine image
	$(DOCKER_RUN) $(MUSL_IMAGE) sh -ec \
	  'export RUSTUP_TOOLCHAIN="$$(rustup default | cut -d" " -f1)"; exec cargo build --release --target x86_64-unknown-linux-musl -p opendb-node --locked'

.PHONY: smoke-k3s
smoke-k3s: ## Run the k3s cluster smoke (non-destructive default)
	cd $(WORKTREE) && $(NPM) run smoke:k3s

.PHONY: bench-jsonb
bench-jsonb: ## JSONB throughput bench
	cd $(WORKTREE) && $(NPM) run bench:jsonb -- --rows $${ROWS:-100}

.PHONY: bench-alter
bench-alter: ## ALTER TABLE bench
	cd $(WORKTREE) && $(NPM) run bench:alter -- --rows $${ROWS:-50}

.PHONY: bench-fk
bench-fk: ## FK insert/delete bench
	cd $(WORKTREE) && $(NPM) run bench:fk -- --rows $${ROWS:-50}

# ----- DB workflow (local opendb-node for ad-hoc queries) -------------------

OPENDB_PGWIRE_PORT ?= 25432
OPENDB_HEALTH_PORT ?= 28080
OPENDB_DATA_DIR    ?= $(WORKTREE)/tmp/opendb-local

.PHONY: db-up
db-up: build ## Spawn a local opendb-node on $(OPENDB_PGWIRE_PORT) (background)
	@mkdir -p $(OPENDB_DATA_DIR)
	@pkill -f 'opendb-node.*--pgwire-addr=127.0.0.1:$(OPENDB_PGWIRE_PORT)' 2>/dev/null || true
	$(NODE_BIN) --node-id 1 \
	  --data-dir $(OPENDB_DATA_DIR) \
	  --pgwire-addr 127.0.0.1:$(OPENDB_PGWIRE_PORT) \
	  --health-addr 127.0.0.1:$(OPENDB_HEALTH_PORT) > $(WORKTREE)/tmp/opendb-local.log 2>&1 &
	@sleep 1
	@echo "opendb-node up on pgwire 127.0.0.1:$(OPENDB_PGWIRE_PORT) (logs: $(WORKTREE)/tmp/opendb-local.log)"

.PHONY: db-down
db-down: ## Stop the local opendb-node started by db-up
	@pkill -f 'opendb-node.*--pgwire-addr=127.0.0.1:$(OPENDB_PGWIRE_PORT)' 2>/dev/null && echo "stopped" || echo "no opendb-node running on $(OPENDB_PGWIRE_PORT)"

.PHONY: db-reset
db-reset: db-down ## Stop opendb-node and wipe its data dir
	@rm -rf $(OPENDB_DATA_DIR)
	@echo "data dir $(OPENDB_DATA_DIR) cleared"

.PHONY: db-query
db-query: ## Run a one-shot SQL query against the local opendb-node: SQL="SELECT * FROM t"
	@if [ -z "$(SQL)" ]; then echo "SQL is required: make db-query SQL=\"SELECT 1\""; exit 1; fi
	cd $(WORKTREE) && OPENDB_PGWIRE_HOST=127.0.0.1 OPENDB_PGWIRE_PORT=$(OPENDB_PGWIRE_PORT) tsx tools/pgwire-exec.ts "$(SQL)"

.PHONY: db-status
db-status: ## Check whether the local opendb-node is up
	@curl -fsS http://127.0.0.1:$(OPENDB_HEALTH_PORT)/healthz && echo "" && echo "opendb-node health OK on $(OPENDB_HEALTH_PORT)" || echo "opendb-node not reachable on $(OPENDB_HEALTH_PORT)"

# ----- Audit (cross-repo grep helpers) --------------------------------------

SENTROPIC_ROOT ?= /home/antoinefa/src/sentropic/api

.PHONY: audit-sentropic-tables
audit-sentropic-tables: ## Count Drizzle pgTable() declarations in sentropic
	@grep -cE "pgTable\(" $(SENTROPIC_ROOT)/src/db/schema.ts

.PHONY: audit-sentropic-types
audit-sentropic-types: ## Histogram of column types declared in sentropic migrations
	@grep -ohE '\b(text|timestamp|jsonb|boolean|integer|bigint|uuid|varchar|numeric|serial|date|interval|bytea)\b' $(SENTROPIC_ROOT)/drizzle/*.sql | sort | uniq -c | sort -rn

.PHONY: audit-sentropic-verbs
audit-sentropic-verbs: ## Drizzle verb usage histogram in sentropic src/
	@printf "%-20s %5d\n" ".select(" "$$(grep -rE '\.select\(' $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | wc -l)"
	@printf "%-20s %5d\n" ".update(" "$$(grep -rE '\.update\(' $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | wc -l)"
	@printf "%-20s %5d\n" ".delete(" "$$(grep -rE '\.delete\(' $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | wc -l)"
	@printf "%-20s %5d\n" ".insert(" "$$(grep -rE '\.insert\(' $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | wc -l)"
	@printf "%-20s %5d\n" ".where(and(" "$$(grep -rE '\.where\(and\(' $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | wc -l)"
	@printf "%-20s %5d\n" ".where(or(" "$$(grep -rE '\.where\(or\(' $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | wc -l)"
	@printf "%-20s %5d\n" ".where(eq(" "$$(grep -rE '\.where\(eq\(' $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | wc -l)"
	@printf "%-20s %5d\n" ".returning(" "$$(grep -rE '\.returning\(' $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | wc -l)"
	@printf "%-20s %5d\n" "db.transaction(" "$$(grep -rE 'db\.transaction\(' $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | wc -l)"
	@printf "%-20s %5d\n" "groupBy/agg" "$$(grep -rE '\.groupBy\(|\.having\(|count\(|sum\(|max\(|min\(|avg\(' $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | wc -l)"

.PHONY: audit-sentropic-grep
audit-sentropic-grep: ## Generic grep over sentropic src: PATTERN="..."
	@if [ -z "$(PATTERN)" ]; then echo "PATTERN is required: make audit-sentropic-grep PATTERN='SELECT'"; exit 1; fi
	@grep -rE "$(PATTERN)" $(SENTROPIC_ROOT)/src --include='*.ts' 2>/dev/null | head -50

.PHONY: cloc
cloc: ## Count lines of code in the opendb workspace
	@cd $(WORKTREE) && cloc --vcs=git crates tools tests docs 2>/dev/null || echo "cloc not installed"
