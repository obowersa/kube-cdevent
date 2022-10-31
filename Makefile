# Base go config
GOCMD 	= go
GOTEST	= $(GOCMD) test
GOVET 	= $(GOCMD) vet

DATE 	?= $(shell date +%FT%T%z)
VERSION ?= $(shell git describe --tags --always --dirty --match=v* 2> /dev/null || \
           		   cat $(CURDIR)/.version 2> /dev/null || echo v0)

SERVICE_PORT 	?= 3000
DOCKER_REGISTRY ?= # if set it should finished by /

# Test configuration
EXPORT_RESULT ?= false # for CI please set EXPORT_RESULT to true

# Build configuration
MODULE 		= $(shell env GO111MODULE=on $(GOCMD) list -m)
BINARY_NAME = $(basename $(MODULE))
BIN			= $(CURDIR)/bin
BUILD_ENTRY = $(CURDIR)/main.go

# Build targets
TARGET_WINDOWS_EXTENSION	= exe
TARGET_WINDOWS_AMD64 		= GOOS=windows GOARCH=amd64
TARGET_LINUX_AMD64 			= GOOS=linux GOARCH=amd64
TARGET_DARWIN_AMD64 		= GOOS=darwin GOARCH=amd64

# Shell formatting. Pretty colours. Ooooh..Aaaahh
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

.PHONY: all test build vendor

all: help

## End to End
run-all: clean vendor format lint test  build-all ## End to End format, lint, test and build

## Build:
build-all: build-windows build-linux build-darwin ## Build your project and output binaries to $(BIN)

build-windows: ## Create windows amd64 binary
	mkdir -p $(BIN)
	$(TARGET_WINDOWS_AMD64) GO111MODULE=on $(GOCMD) build -mod vendor -ldflags '-X main.Version=$(VERSION) -X main.BuildDate=$(DATE)' -o $(BIN)/$(BINARY_NAME).$(TARGET_WINDOWS_EXTENSION) $(BUILD_ENTRY)

build-linux: ## Create linux amd64 binary
	mkdir -p $(BIN)
	$(TARGET_LINUX_AMD64) GO111MODULE=on $(GOCMD) build -mod vendor -ldflags '-X main.Version=$(VERSION) -X main.BuildDate=$(DATE)' -o $(BIN)/$(BINARY_NAME)_linux_amd64 $(BUILD_ENTRY)

build-darwin: ## Create darwin amd64 binary
	$(TARGET_DARWIN_AMD64) GO111MODULE=on $(GOCMD) build -mod vendor -ldflags '-X main.Version=$(VERSION) -X main.BuildDate=$(DATE)' -o $(BIN)/$(BINARY_NAME)_darwin_amd64 $(BUILD_ENTRY)

clean: ## Remove build related file
	rm -fr $(BIN)
	rm -f ./junit-report.xml checkstyle-report.xml ./coverage.xml ./profile.cov yamllint-checkstyle.xml

vendor: ## Copy of all packages needed to support builds and tests in the vendor directory
	$(GOCMD) mod vendor

watch: ## Run the code with cosmtrek/air to have automatic reload on changes
	$(eval PACKAGE_NAME=$(shell head -n 1 go.mod | cut -d ' ' -f2))
	docker run -it --rm -w /go/src/$(PACKAGE_NAME) -v $(shell pwd):/go/src/$(PACKAGE_NAME) -p $(SERVICE_PORT):$(SERVICE_PORT) cosmtrek/air

## Test:
test: ## Run the tests of the project
ifeq ($(EXPORT_RESULT), true)
	GO111MODULE=off go get -u github.com/jstemmer/go-junit-report
	$(eval OUTPUT_OPTIONS = | tee /dev/tty | go-junit-report -set-exit-code > junit-report.xml)
endif
	$(GOTEST) -v -race ./... $(OUTPUT_OPTIONS)

coverage: ## Run the tests of the project and export the coverage
	$(GOTEST) -cover -covermode=count -coverprofile=profile.cov ./...
	$(GOCMD) tool cover -func profile.cov
ifeq ($(EXPORT_RESULT), true)
	GO111MODULE=off go get -u github.com/AlekSi/gocov-xml
	GO111MODULE=off go get -u github.com/axw/gocov/gocov
	gocov convert profile.cov | gocov-xml > coverage.xml
endif

## Format:
format: imports-go fmt-go ## Cleans up imports and formats files

fmt-go: ## Run go fmt ./...
	go fmt ./...

imports-go: ## Clean up imports using go imports -w ./
	GO111MODULE=off go get -u golang.org/x/tools/cmd/goimports
	goimports -w ./

## Lint:
lint: lint-go lint-dockerfile lint-yaml ## Run all available linters

lint-dockerfile: ## Lint your Dockerfile
# If dockerfile is present we lint it.
ifeq ($(shell test -e ./Dockerfile && echo -n yes),yes)
	$(eval CONFIG_OPTION = $(shell [ -e $(shell pwd)/.hadolint.yaml ] && echo "-v $(shell pwd)/.hadolint.yaml:/root/.config/hadolint.yaml" || echo "" ))
	$(eval OUTPUT_OPTIONS = $(shell [ "${EXPORT_RESULT}" == "true" ] && echo "--format checkstyle" || echo "" ))
	$(eval OUTPUT_FILE = $(shell [ "${EXPORT_RESULT}" == "true" ] && echo "| tee /dev/tty > checkstyle-report.xml" || echo "" ))
	docker run --rm -i $(CONFIG_OPTION) hadolint/hadolint hadolint $(OUTPUT_OPTIONS) - < ./Dockerfile $(OUTPUT_FILE)
endif

lint-go: ## Use golintci-lint on your project
	$(eval OUTPUT_OPTIONS = $(shell [ "${EXPORT_RESULT}" == "true" ] && echo "--out-format checkstyle ./... | tee /dev/tty > checkstyle-report.xml" || echo "" ))
	docker run --rm -v $(shell pwd):/app -w /app golangci/golangci-lint:latest-alpine golangci-lint run --deadline=65s $(OUTPUT_OPTIONS)

lint-yaml: ## Use yamllint on the yaml file of your projects
ifeq ($(EXPORT_RESULT), true)
	GO111MODULE=off go get -u github.com/thomaspoignant/yamllint-checkstyle
	$(eval OUTPUT_OPTIONS = | tee /dev/tty | yamllint-checkstyle > yamllint-checkstyle.xml)
endif
	docker run --rm -it -v $(shell pwd):/data cytopia/yamllint -f parsable $(shell git ls-files '*.yml' '*.yaml') $(OUTPUT_OPTIONS)

## Docker:
docker-build: ## Use the dockerfile to build the container
	docker build --rm --tag $(BINARY_NAME) .

docker-release: ## Release the container with tag latest and version
	docker tag $(BINARY_NAME) $(DOCKER_REGISTRY)$(BINARY_NAME):latest
	docker tag $(BINARY_NAME) $(DOCKER_REGISTRY)$(BINARY_NAME):$(VERSION)
	# Push the docker images
	docker push $(DOCKER_REGISTRY)$(BINARY_NAME):latest
	docker push $(DOCKER_REGISTRY)$(BINARY_NAME):$(VERSION)

## Help:
help: ## Show this help.
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} { \
		if (/^[a-zA-Z_-]+:.*?##.*$$/) {printf "    ${YELLOW}%-20s${GREEN}%s${RESET}\n", $$1, $$2} \
		else if (/^## .*$$/) {printf "  ${CYAN}%s${RESET}\n", substr($$1,4)} \
		}' $(MAKEFILE_LIST)

version:
	@echo $(VERSION)