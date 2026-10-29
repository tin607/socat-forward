PREFIX  ?= /usr/local
DESTDIR ?=
BINDIR  := $(DESTDIR)$(PREFIX)/bin
SCRIPT  := bin/socat-forward

.PHONY: all check install uninstall

all: check

check:
	bash -n $(SCRIPT)
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SCRIPT); \
	else \
		echo "shellcheck 未安装，跳过静态检查"; \
	fi

install:
	install -D -m 0755 $(SCRIPT) $(BINDIR)/socat-forward

uninstall:
	rm -f $(BINDIR)/socat-forward
