# ─── Repo files (static content loaded from git repo) ────────────────────────
# Cloned early so tools like RTK can use patches from the repo during Phase 3.
REPO_FILES="${TITAN_REPO_FILES:-}"
if [[ -z "$REPO_FILES" ]]; then
  _REPO_TMPDIR=$(mktemp -d -t titan-files-XXXXXX)
  ok "Fetching repo files..."
  git clone --depth=1 --quiet \
    https://github.com/SutanuNandigrami/claude-titan-setup.git \
    "$_REPO_TMPDIR" 2>&1 | tee -a "$LOG_FILE"
  REPO_FILES="$_REPO_TMPDIR"
  _CLEANUP_DIRS+=("$_REPO_TMPDIR")
fi
