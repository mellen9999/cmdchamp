PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

install:
	mkdir -p $(DESTDIR)$(BINDIR)
	install -m 755 cmdchamp $(DESTDIR)$(BINDIR)/cmdchamp

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/cmdchamp

test:
	./cmdchamp test
	./test_cmdchamp.sh
	./test_terminals.sh

.PHONY: install uninstall test
