# Makefile for Mole

.PHONY: all build clean check format test test-go verify release release-amd64 release-arm64 release-linux-amd64 release-linux-arm64 mod-download

# Output directory
BIN_DIR := bin

# Go toolchain
GO ?= go
GO_DOWNLOAD_RETRIES ?= 3

# Binaries
ANALYZE := analyze
STATUS := status
TRASH := trash

# Source directories
ANALYZE_SRC := ./cmd/analyze
STATUS_SRC := ./cmd/status
TRASH_SRC := ./cmd/trash

# Build flags
LDFLAGS := -s -w
RELEASE_GO_ENV := CGO_ENABLED=0

all: build

# Download modules with retries to mitigate transient proxy/network EOF errors.
mod-download:
	@attempt=1; \
	while [ $$attempt -le $(GO_DOWNLOAD_RETRIES) ]; do \
		echo "Downloading Go modules ($$attempt/$(GO_DOWNLOAD_RETRIES))..."; \
		if $(GO) mod download; then \
			exit 0; \
		fi; \
		sleep $$((attempt * 2)); \
		attempt=$$((attempt + 1)); \
	done; \
	echo "Go module download failed after $(GO_DOWNLOAD_RETRIES) attempts"; \
	exit 1

# Local build (current architecture)
build: mod-download
	@echo "Building for local architecture..."
	$(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(ANALYZE)-go $(ANALYZE_SRC)
	$(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(STATUS)-go $(STATUS_SRC)
	$(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(TRASH)-go $(TRASH_SRC)

check:
	./scripts/check.sh --no-format

format:
	./scripts/check.sh --format

test:
	MOLE_TEST_NO_AUTH=1 ./scripts/test.sh

test-go:
	$(GO) test ./...

verify: check test-go

# Release build targets. Keep these pure-Go so the macOS SDK on the
# release runner cannot raise the Mach-O minimum OS version via cgo.
release-amd64: mod-download
	@echo "Building release binaries (amd64)..."
	$(RELEASE_GO_ENV) GOOS=darwin GOARCH=amd64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(ANALYZE)-darwin-amd64 $(ANALYZE_SRC)
	$(RELEASE_GO_ENV) GOOS=darwin GOARCH=amd64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(STATUS)-darwin-amd64 $(STATUS_SRC)

release-arm64: mod-download
	@echo "Building release binaries (arm64)..."
	$(RELEASE_GO_ENV) GOOS=darwin GOARCH=arm64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(ANALYZE)-darwin-arm64 $(ANALYZE_SRC)
	$(RELEASE_GO_ENV) GOOS=darwin GOARCH=arm64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(STATUS)-darwin-arm64 $(STATUS_SRC)

release-linux-amd64: mod-download
	@echo "Building release binaries (linux-amd64)..."
	$(RELEASE_GO_ENV) GOOS=linux GOARCH=amd64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(ANALYZE)-linux-amd64 $(ANALYZE_SRC)
	$(RELEASE_GO_ENV) GOOS=linux GOARCH=amd64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(STATUS)-linux-amd64 $(STATUS_SRC)
	$(RELEASE_GO_ENV) GOOS=linux GOARCH=amd64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(TRASH)-linux-amd64 $(TRASH_SRC)

release-linux-arm64: mod-download
	@echo "Building release binaries (linux-arm64)..."
	$(RELEASE_GO_ENV) GOOS=linux GOARCH=arm64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(ANALYZE)-linux-arm64 $(ANALYZE_SRC)
	$(RELEASE_GO_ENV) GOOS=linux GOARCH=arm64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(STATUS)-linux-arm64 $(STATUS_SRC)
	$(RELEASE_GO_ENV) GOOS=linux GOARCH=arm64 $(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(TRASH)-linux-arm64 $(TRASH_SRC)

clean:
	@echo "Cleaning binaries..."
	rm -f $(BIN_DIR)/$(ANALYZE)-* $(BIN_DIR)/$(STATUS)-* $(BIN_DIR)/$(ANALYZE)-go $(BIN_DIR)/$(STATUS)-go $(BIN_DIR)/$(TRASH)-* $(BIN_DIR)/$(TRASH)-go
