
SHELL := /bin/bash
.DEFAULT_GOAL := all

PUBLIC  := public
POSTS   := posts
PORT    := 8000
PYTHON  := python3

POST_FILES := $(shell find $(POSTS) -type f -name '*.1' 2>/dev/null)
BUILD_DEPS := build.sh man.css Makefile $(POST_FILES)

.PHONY: all serve open watch feed no-feed clean check stats help force


all: $(PUBLIC)/index.html

$(PUBLIC)/index.html: $(BUILD_DEPS)
	./build.sh

force:
	@rm -f $(PUBLIC)/index.html
	@$(MAKE) --no-print-directory all

feed: $(BUILD_DEPS)
	ENABLE_FEED=true ./build.sh

no-feed: $(BUILD_DEPS)
	ENABLE_FEED=false ./build.sh


serve: all
	@printf '\n  http://localhost:%s/\n\n' "$(PORT)"
	@cd $(PUBLIC) && $(PYTHON) -m http.server $(PORT)

open: all
	@printf '\n  http://localhost:%s/\n\n' "$(PORT)"
	@(sleep 0.5 && xdg-open "http://localhost:$(PORT)/" >/dev/null 2>&1 &) || true
	@cd $(PUBLIC) && $(PYTHON) -m http.server $(PORT)

watch: check-watch
	@printf 'watch mode. Ctrl+C buat stop.\n'
	@$(MAKE) --no-print-directory all
	@while true; do \
		inotifywait -q -r -e modify,create,delete \
			$(POSTS) man.css build.sh >/dev/null 2>&1; \
		printf '\n  change terdeteksi, rebuild...\n'; \
		$(MAKE) --no-print-directory all; \
	done

check-watch:
	@command -v inotifywait >/dev/null 2>&1 || { \
		printf 'error: butuh inotifywait. install:\n'; \
		printf '  sudo dnf install inotify-tools\n'; \
		exit 1; \
	}


clean:
	rm -rf $(PUBLIC)
	@printf 'public/ dihapus.\n'


check:
	@printf 'dependencies:\n'
	@for cmd in mandoc awk sed sort find mktemp python3; do \
		if command -v $$cmd >/dev/null 2>&1; then \
			printf '  [ok]      %s\n' "$$cmd"; \
		else \
			printf '  [missing] %s\n' "$$cmd"; \
		fi; \
	done

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

help:
	@printf 'targets:\n'
	@printf '  all       build semua (default)\n'
	@printf '  serve     build + serve di localhost:%s\n' "$(PORT)"
	@printf '  open      serve + auto-open browser\n'
	@printf '  watch     serve + auto-rebuild\n'
	@printf '  feed      build dengan RSS\n'
	@printf '  no-feed   build tanpa RSS\n'
	@printf '  clean     hapus public/\n'
	@printf '  force     force rebuild\n'
	@printf '  check     cek dependency\n'
	@printf '  stats     jumlah post per folder\n'
	@printf '  help      pesan ini\n'
