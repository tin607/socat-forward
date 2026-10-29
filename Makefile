PREFIX  ?= /usr/local
DESTDIR ?=
BINDIR  := $(DESTDIR)$(PREFIX)/bin
SCRIPT  := bin/socat-forward

.PHONY: all check check-version version bump-version tag install uninstall

all: check

check: check-version
	bash -n $(SCRIPT) scripts/version.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SCRIPT) scripts/version.sh; \
	else \
		echo "shellcheck 未安装，跳过静态检查"; \
	fi

check-version:
	@scripts/version.sh check

version:
	@scripts/version.sh get

bump-version:
	@if [ -z "$(VERSION)" ]; then \
		echo "用法: make bump-version VERSION=x.y.z" >&2; \
		exit 1; \
	fi
	@scripts/version.sh bump "$(VERSION)"

tag:
	@scripts/version.sh tag $(if $(filter 1 yes true,$(PUSH)),--push,)

install:
	install -D -m 0755 $(SCRIPT) $(BINDIR)/socat-forward

uninstall:
	rm -f $(BINDIR)/socat-forward
