# ALIASES
SWIFTFORMAT     = $(MISEFILE) exec -- swiftformat
MISEFILE        := $(HOME)/.local/bin/mise

PHONY: format
format: validate-xcstrings ensure-tools
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat --config ./.swiftformat . ; \
	elif $(MISEFILE) which swiftformat >/dev/null 2>&1; then \
		$(SWIFTFORMAT) --config ./.swiftformat . ; \
	else \
		echo "swiftformat is not available; skipping format target." ; \
	fi

PHONY: validate-xcstrings
validate-xcstrings:
	@Scripts/validate-xcstrings.sh

PHONY: ensure-tools
ensure-tools:
ifndef CI
ifeq ($(wildcard $(MISEFILE)),)
	@bash Scripts/setup-mise.sh
endif
	@$(MISEFILE) install
endif
