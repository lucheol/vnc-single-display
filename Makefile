PREFIX ?= $(HOME)/.local
SWIFTC ?= swiftc

.PHONY: all build install uninstall status clean

all: build

build: build/vncdisplay

build/vncdisplay: src/vncdisplay.swift
	@mkdir -p build
	$(SWIFTC) -O -o $@ $<

install: build
	./install.sh

uninstall:
	./uninstall.sh

status: build
	./build/vncdisplay status

clean:
	rm -rf build
