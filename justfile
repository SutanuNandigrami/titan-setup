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
    shellcheck -x \
      $(find lib/ -name '*.sh' 2>/dev/null | sort) \
      bin/agt \
      agent-team-reset.sh agent-team-teardown.sh \
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
