# Common tasks. Run `make help` for the list.

.DEFAULT_GOAL := help
.PHONY: help build test package install reset clean version

help: ## Show this help
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  make %-9s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Build a release binary
	swift build -c release

test: ## Run the unit tests
	swift test

package: ## Build dist/Switchboard.zip
	scripts/make-app.sh --package

install: ## Build, then cleanly install into /Applications and launch
	scripts/make-app.sh

reset: ## Put every screen back to normal (reconnect, undim, wake)
	swift run Switchboard --reset

clean: ## Remove build products
	rm -rf .build dist

version: ## Print the version in VERSION
	@cat VERSION
