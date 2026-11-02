SHELL := /usr/bin/env bash

.PHONY: check lint test smoke build clean

check: lint test

lint:
	tests/lint.sh

test:
	tests/run.sh

smoke:
	tests/install-smoke.sh

build:
	./build.sh

clean:
	rm -rf dist
