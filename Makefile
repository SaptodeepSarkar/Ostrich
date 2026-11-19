SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help deps validate lint compile test review check format smoke protect

help:
	@printf 'Ostrich development targets\n\n'
	@printf '  make check      Run all local checks (validate + lint + compile + test + review)\n'
	@printf '  make validate   Validate VERSION, CHANGELOG and required files\n'
	@printf '  make lint       qmllint + shellcheck (+ qmlformat if FORMAT_STRICT=1)\n'
	@printf '  make compile    Parse and type-check QML sources\n'
	@printf '  make test       Run Qt Quick Test suites (tests/**/tst_*.qml)\n'
	@printf '  make review     Repository hygiene and secret scan\n'
	@printf '  make format     Format QML sources in place\n'
	@printf '  make smoke      Launch the shell headless (needs qs)\n'
	@printf '  make deps       Install build dependencies with pacman\n'
	@printf '  make protect    Re-apply branch protection (needs gh auth)\n'

deps:
	sudo pacman -S --needed --noconfirm git base-devel qt6-declarative shellcheck

validate:
	@bash scripts/ci/validate.sh

lint:
	@bash scripts/ci/lint.sh

compile:
	@bash scripts/ci/compile.sh

test:
	@bash scripts/ci/test.sh

review:
	@bash scripts/ci/review.sh

check: validate lint compile test review
	@printf 'All local checks passed.\n'

format:
	@bash scripts/format.sh

smoke:
	@bash scripts/ci/smoke.sh

protect:
	@bash scripts/setup-branch-protection.sh
