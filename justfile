set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# One-time: install bats-core test framework
bootstrap:
    bash script/install-bats.sh

# Assemble lib/ fragments into titan-setup.sh
build:
    bash script/build.sh

# Verify assembled titan-setup.sh matches lib/ source
build-check:
    bash script/build.sh --check

# Lint all shell scripts with shellcheck
lint:
    @# Fragments: error-level only (warnings are pre-existing in monolith); exclude cross-fragment false positives
    @if [ -d lib/ ] && [ -n "$(find lib/ -name '*.sh' 2>/dev/null)" ]; then \
      shellcheck -x --shell bash --severity=error \
        --exclude=SC2034,SC2154,SC1046,SC1047,SC1072,SC1073,SC1089,SC1009 \
        $(find lib/ -name '*.sh' | sort); \
    fi
    @# Assembled script: full check (authoritative), errors only (warnings are pre-existing)
    shellcheck -x --severity=error titan-setup.sh
    shellcheck -x --severity=error bin/agt agent-team-reset.sh agent-team-teardown.sh \
      $(find dot-claude/hooks/ -name '*.sh' 2>/dev/null | sort)

# Format all shell scripts
fmt:
    shfmt -w -i 2 -ci \
      $(find lib/ -name '*.sh' 2>/dev/null | sort) \
      bin/agt \
      agent-team-reset.sh agent-team-teardown.sh \
      $(find dot-claude/hooks/ -name '*.sh' 2>/dev/null | sort)

# Check formatting without writing
fmt-check:
    shfmt -d -i 2 -ci \
      $(find lib/ -name '*.sh' 2>/dev/null | sort) \
      bin/agt \
      agent-team-reset.sh agent-team-teardown.sh \
      $(find dot-claude/hooks/ -name '*.sh' 2>/dev/null | sort)

# Run bats unit + template tests
test:
    vendor/bats/bin/bats test/*.bats

# Run legacy test suite
test-legacy:
    bash test/run-tests.sh

# Docker integration test
test-docker:
    bash test/docker-test.sh

# Dry-run smoke test
smoke:
    bash titan-setup.sh --dry-run --mode desktop --name test

# Full CI check: lint + format + build + test + smoke
check: lint fmt-check build-check test smoke
