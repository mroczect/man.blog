SHELL := /bin/bash
.DEFAULT_GOAL := all

# --- Config ---------------------------------------------------------------
PUBLIC      := public
POSTS       := posts
ASSETS      := assets
PORT        := 8000
PYTHON      := python3
BUILD       := build.sh
CSS         := man.css
SITE_URL    ?=
DEBUG       ?= 0

POST_FILES  := $(shell find $(POSTS) -type f -name '*.1' 2>/dev/null)
ASSET_FILES := $(shell find $(ASSETS) -type f 2>/dev/null)
BUILD_DEPS  := $(BUILD) $(CSS) Makefile $(POST_FILES) $(ASSET_FILES)

STAMP := $(PUBLIC)/.build-stamp

.PHONY: all force serve open watch feed no-feed clean \
        check check-syntax lint verify debug stats help \
        check-watch require-mandoc require-python

all: $(STAMP)

$(STAMP): $(BUILD_DEPS)
	@mkdir -p $(PUBLIC)
	@$(MAKE) --no-print-directory _build
	@touch $@

_build:
	@[ -x $(BUILD) ] || chmod +x $(BUILD)
	@DEBUG=$(DEBUG) ./$(BUILD)

force:
	@rm -f $(STAMP)
	@$(MAKE) --no-print-directory all

feed: $(BUILD_DEPS)
	@[ -x $(BUILD) ] || chmod +x $(BUILD)
	@ENABLE_FEED=true  DEBUG=$(DEBUG) ./$(BUILD)
	@touch $(STAMP)

no-feed: $(BUILD_DEPS)
	@[ -x $(BUILD) ] || chmod +x $(BUILD)
	@ENABLE_FEED=false DEBUG=$(DEBUG) ./$(BUILD)
	@touch $(STAMP)

debug:
	@$(MAKE) --no-print-directory DEBUG=1 force

serve: all require-python
	@printf '\n  http://localhost:%s/\n\n' "$(PORT)"
	@cd $(PUBLIC) && $(PYTHON) -m http.server $(PORT)

open: all require-python
	@printf '\n  http://localhost:%s/\n\n' "$(PORT)"
	@( sleep 0.5 && { command -v xdg-open >/dev/null 2>&1 && xdg-open "http://localhost:$(PORT)/" >/dev/null 2>&1 & } ) || true
	@cd $(PUBLIC) && $(PYTHON) -m http.server $(PORT)

watch: check-watch
	@printf 'watch mode. Ctrl+C buat stop.\n'
	@$(MAKE) --no-print-directory all
	@while true; do \
		inotifywait -q -r -e modify,create,delete,move \
			$(POSTS) $(ASSETS) $(CSS) $(BUILD) >/dev/null 2>&1 || true; \
		printf '\n  change terdeteksi, rebuild...\n'; \
		$(MAKE) --no-print-directory force || true; \
	done

check-watch:
	@command -v inotifywait >/dev/null 2>&1 || { \
		printf 'error: butuh inotifywait. install:\n'; \
		printf '  sudo dnf install inotify-tools   # Fedora/RHEL\n'; \
		printf '  sudo apt install inotify-tools   # Debian/Ubuntu\n'; \
		exit 1; \
	}

clean:
	@rm -rf $(PUBLIC)
	@printf 'public/ dihapus.\n'

distclean: clean
	@rm -f $(BUILD).bak
	@printf 'distclean selesai.\n'

check: check-syntax
	@printf '\ndependencies:\n'
	@missing=0; \
	for cmd in mandoc awk sed sort find mktemp date sha512sum shasum shellcheck $(PYTHON); do \
		if command -v $$cmd >/dev/null 2>&1; then \
			printf '  [ok]      %s\n' "$$cmd"; \
		else \
			printf '  [missing] %s\n' "$$cmd"; \
			missing=$$((missing+1)); \
		fi; \
	done; \
	printf '\n'; \
	if [ "$$missing" -gt 0 ]; then \
		printf 'warning: %d dependency missing\n' "$$missing"; \
	else \
		printf 'semua dependency siap.\n'; \
	fi

check-syntax:
	@printf 'syntax check (%s):\n' "$(BUILD)"
	@[ -f $(BUILD) ] || { printf '  [FAIL] %s tidak ada\n' "$(BUILD)"; exit 1; }
	@bash -n $(BUILD) && printf '  [ok] bash -n\n'
	@bash -u -o pipefail -n $(BUILD) && printf '  [ok] bash -u -o pipefail -n\n'

lint: check-syntax
	@printf 'lint (%s):\n' "$(BUILD)"
	@command -v shellcheck >/dev/null 2>&1 || { \
		printf '  [skip] shellcheck belum diinstall\n'; exit 0; }
	@shellcheck -S style -o all -x $(BUILD) \
		&& printf '  [ok] shellcheck clean\n' \
		|| { printf '  [FAIL] shellcheck ada temuan\n'; exit 1; }

verify: check-syntax lint
	@[ -x ./check.sh ] || { \
		printf 'check.sh tidak ada / tidak executable. skip.\n'; exit 0; }
	@./check.sh

stats:
	@printf 'post per folder:\n'
	@if [ -d $(POSTS) ]; then \
		find $(POSTS) -mindepth 1 -maxdepth 1 -type d | sort | while read -r d; do \
			n=$$(find "$$d" -type f -name '*.1' | wc -l); \
			printf '  %-20s %s\n' "$$(basename $$d)" "$$n"; \
		done; \
		n=$$(find $(POSTS) -maxdepth 1 -type f -name '*.1' | wc -l); \
		[ "$$n" -gt 0 ] && printf '  %-20s %s\n' "(root)" "$$n"; \
		total=$$(find $(POSTS) -type f -name '*.1' | wc -l); \
		printf '\n  total: %s post\n' "$$total"; \
	else \
		printf '  posts/ nggak ada.\n'; \
	fi

require-python:
	@command -v $(PYTHON) >/dev/null 2>&1 || { \
		printf 'error: butuh %s\n' "$(PYTHON)"; exit 1; }

require-mandoc:
	@command -v mandoc >/dev/null 2>&1 || { \
		printf 'error: butuh mandoc. install: dnf/apt install mandoc\n'; exit 1; }

help:
	@printf 'targets:\n'
	@printf '\n'
	@printf '  build:\n'
	@printf '    all       build semua (default)\n'
	@printf '    force     force rebuild tanpa peduli timestamp\n'
	@printf '    feed      build dengan RSS\n'
	@printf '    no-feed   build tanpa RSS\n'
	@printf '    debug     build dengan DEBUG=1 (verbose)\n'
	@printf '\n'
	@printf '  serve:\n'
	@printf '    serve     build + serve di localhost:%s\n' "$(PORT)"
	@printf '    open      serve + auto-open browser\n'
	@printf '    watch     auto-rebuild saat file berubah\n'
	@printf '\n'
	@printf '  housekeeping:\n'
	@printf '    clean     hapus public/\n'
	@printf '    distclean clean + hapus backup\n'
	@printf '\n'
	@printf '  cek:\n'
	@printf '    check     cek dependency + syntax\n'
	@printf '    lint      shellcheck build.sh\n'
	@printf '    verify    check + lint + check.sh\n'
	@printf '    stats     jumlah post per folder\n'
	@printf '    help      pesan ini\n'
	@printf '\n'
	@printf '  variabel yang bisa di-override:\n'
	@printf '    PORT=%s\n' "$(PORT)"
	@printf '    SITE_URL=%s\n' "$(SITE_URL)"
	@printf '    DEBUG=%s\n' "$(DEBUG)"
