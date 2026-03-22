# Titan Workstation User Guide

Welcome to your Claude Code workstation — 150+ CLI tools, 12 slash commands, 3 built-in agents, and smart safety hooks all configured and ready to use.

## Table of Contents

- [How This Works](#how-this-works)
- [Quick Start](#quick-start)
- [Slash Commands](#slash-commands)
- [Search & Navigation](#search--navigation)
- [Data Processing](#data-processing)
- [HTTP & APIs](#http--apis)
- [Git & Version Control](#git--version-control)
- [Security & Scanning](#security--scanning)
- [Network & DNS](#network--dns)
- [Process & System](#process--system)
- [Containers & Kubernetes](#containers--kubernetes)
- [Cloud & Infrastructure](#cloud--infrastructure)
- [Secrets & Certificates](#secrets--certificates)
- [Code Quality & Formatting](#code-quality--formatting)
- [DevOps & Automation](#devops--automation)
- [Databases](#databases)
- [Terminal UI & Utilities](#terminal-ui--utilities)
- [Documentation & Generation](#documentation--generation)
- [Claude Code Ecosystem](#claude-code-ecosystem)
- [Web & JavaScript](#web--javascript)
- [Shell Enhancement](#shell-enhancement)
- [Agents & Custom Agent Loading](#agents--custom-agent-loading)
- [Tips & Best Practices](#tips--best-practices)
- [Getting Help](#getting-help)

---

## How This Works

You don't memorize commands. You type **natural language prompts**, and Claude Code automatically:
1. Reads the tool's `--help` (never guesses flags)
2. Invokes the appropriate CLI tool
3. Returns the result

**Example workflow:**
> You: "Find all Python files that import requests"
> Claude: Runs `rg -l 'import requests' --type py` and shows results

This document is a **reference** — browse when you want to know what's available. Claude will discover and use tools on-demand based on your requests.

---

## Quick Start


After running `titan-setup.sh`, here's how to get started immediately:

```bash
# 1. Source your shell config
source ~/.bashrc

# 2. Authenticate Claude
claude auth login

# 3. Verify installation
claude --version && claude doctor

# 4. Start Claude in any project directory
cd ~/my-project
claude

# 5. Check what's available
/tools          # List all configured tools
/workspace-init # Auto-detect project type and set up workspace
```

**First things to try in Claude:**
- `"Show me the structure of this project"` — Claude uses `eza --tree` or `fd`
- `"Search for all TODO comments"` — Claude uses `rg 'TODO'`
- `"What's using the most disk space?"` — Claude uses `dust`
- `"Run a security scan on this project"` — or just type `/scan`

---

## Slash Commands

Titan installs 12 slash commands that automate common workflows. Type these directly in Claude Code:

| Command | What it does |
|---------|-------------|
| `/ship` | Full pre-push pipeline: lint → test → gitleaks scan → commit → push → optional PR |
| `/scan` | Security scan: gitleaks + trivy + osv-scanner + hadolint + tflint (as applicable) |
| `/review` | Code review of current branch vs. main using the reviewer agent |
| `/workspace-init` | Detect project type, generate `_workspace.json`, create `.envrc` with direnv |
| `/remember <thing>` | Save a fact, preference, or pattern to persistent memory |
| `/recall` | Surface memory + session handoff from previous sessions (0 startup cost) |
| `/catchup` | Resume work: reads git state, _handoff.md, _scratchpad.md, memory — asks what to work on |
| `/standup` | Generate standup from yesterday's git activity |
| `/handoff` | Create structured _handoff.md with task, decisions, blockers, checklist, next steps |
| `/context` | Show current context usage and compression status |
| `/tools` | List all configured CLI tools and their status |
| `/gh-action` | Set up a GitHub Actions workflow for the current project |

### Usage Examples

```
/ship                    # Push everything with full safety checks
/scan                    # Security audit the current project
/review                  # Review what you've changed vs. main
/remember "always use ruff not flake8 in this project"
/recall                  # What was I working on last session?
/standup                 # Generate my standup notes
/workspace-init          # Set up this new project
```

---

## Search & Navigation


#### rg (ripgrep)
Fast recursive text search across files. Replaces `grep` completely.

- Search for patterns with regex support
- Filter by file type (--type py, --type js, etc.)
- Show context around matches (-C flag)
- Count matches or just list matching files (-c, -l flags)

> **Example prompt:** "Search for all TODO comments in Python files and show context"

#### fd (fd-find)
Fast file finder with intuitive syntax. Replaces `find`.

- Find files by name pattern
- Filter by file type or extension
- Case-insensitive search
- Exclude directories

> **Example prompt:** "Find all .pyc files in the project and show how many there are"

#### sd (structural diff)
Find and replace with regex. Modern, intuitive sed replacement.

- Replace text patterns across files
- Regex and literal string support
- Preserve formatting
- Preview before replacing

> **Example prompt:** "Replace all occurrences of 'old_function' with 'new_function' in Python files"

#### eza
Modern `ls` with icons, colors, and git status. Shows file metadata beautifully.

- List files with icons and colors
- Show git status per file
- Tree view of directories
- File size and permission details

> **Example prompt:** "Show the contents of this directory in a tree view with git status"

#### bat
Cat with syntax highlighting, line numbers, and git diff markers.

- Display file contents with syntax highlighting
- Show line numbers
- Git modification indicators
- Integration with git diff

> **Example prompt:** "Show me the contents of config.json with line numbers"

#### dust
Visual disk usage analyzer. Shows which files/dirs consume space.

- Identify large files and directories
- Visual bar chart of space usage
- Sort by size
- Recursive depth analysis

> **Example prompt:** "What's consuming the most space in the home directory?"

#### ouch
Universal compression/decompression for zip, tar, gz, xz, 7z, bz2, and more.

- Compress files to any format
- Decompress automatically by extension
- Batch operations
- Parallel compression

> **Example prompt:** "Compress the logs directory into a gzipped tar archive"

#### trash-cli
Move files to trash instead of permanent deletion. Safer than `rm`.

- Delete files to trash (recoverable)
- Restore files from trash
- Empty trash when ready
- Detailed deletion logs

> **Example prompt:** "Move this debug file to trash instead of deleting it"

---

## Data Processing

#### jq
JSON processor and query engine. Transform, filter, and manipulate JSON.

- Query JSON with path expressions
- Transform and reshape data
- Filter arrays and objects
- Combine with other tools via pipes

> **Example prompt:** "Extract all user IDs from this JSON file and make a list"

#### yq
YAML/XML/JSON/TOML processor with jq-compatible syntax.

- Read and edit YAML files
- Convert between formats (YAML ↔ JSON)
- Query nested structures
- Batch updates across multiple files

> **Example prompt:** "Extract the version field from all YAML config files"

#### xsv
CSV statistics, filtering, slicing, and searching without loading into memory.

- Get stats on CSV files (column count, row count, etc.)
- Filter rows by criteria
- Search for patterns
- Join CSV files on columns

> **Example prompt:** "Find all rows in the CSV where status equals 'active'"

#### miller
CSV/JSON/TSV/XTAB multi-format data processor with SQL-like syntax.

- Query CSV/JSON with SQL-like syntax
- Format conversion
- Aggregation and grouping
- Streaming processing of large files

> **Example prompt:** "Group sales data by region and sum the totals"

#### duckdb
SQL on CSV, Parquet, and JSON files. No server required.

- Run SQL queries directly on files
- Join multiple data sources
- Complex aggregations and joins
- Export results to different formats

> **Example prompt:** "Query this CSV file to find customers who spent more than $1000"

#### gron
Flatten JSON into greppable lines. Convert nested structures to key-value pairs.

- Make JSON searchable with grep/rg
- Understand JSON structure at a glance
- Convert to and from JSON
- Filter large JSON documents

> **Example prompt:** "Flatten this JSON file so I can search for a specific value"

#### htmlq
Extract HTML elements using CSS selectors. Like jq for HTML.

- Select elements by CSS selector
- Extract attributes
- Get text content
- Chain selectors for complex queries

> **Example prompt:** "Extract all links from this HTML file"

#### choose
Friendly field selection tool. Like `cut` and `awk` but more intuitive.

- Select columns by number or range
- Split on custom delimiters
- Support for CSV and TSV
- Negative indexing (count from end)

> **Example prompt:** "Extract the third and fifth columns from this CSV file"

---

## HTTP & APIs

#### xh
HTTP client with syntax highlighting and colored output. Modern curl replacement.

- Make GET/POST/PUT/DELETE requests
- Send JSON payloads
- Add custom headers
- Pretty-print responses

> **Example prompt:** "Make a GET request to the API endpoint and show me the response"

#### hurl
Define HTTP test chains in plain text files. Like Postman but version-controllable.

- Write HTTP request sequences in plain text
- Use variables and assertions
- Run full test workflows
- Export results

> **Example prompt:** "Create a test that logs in and then fetches user data"

#### oha
HTTP load testing tool. Find performance bottlenecks.

- Simulate concurrent user load
- Measure response times
- Generate load test reports
- Benchmark different endpoints

> **Example prompt:** "Run a load test to see how many requests per second this API can handle"

#### websocat
WebSocket client for CLI. Interact with WebSocket servers.

- Connect to WebSocket servers
- Send and receive messages
- Inspect WebSocket traffic
- Test real-time applications

> **Example prompt:** "Connect to the WebSocket server and send a message"

#### mitmproxy
Intercept, inspect, and modify HTTP/HTTPS traffic in real-time.

- Man-in-the-middle proxy for debugging
- Inspect requests and responses
- Modify headers and bodies
- Record and replay traffic

> **Example prompt:** "Intercept API calls to see what my application is sending"

---

## Git & Version Control

#### delta (git-delta)
Beautiful diff pager for git. Syntax highlighting and side-by-side diffs.

- Compare changes with colored output
- Show full context
- Syntax highlighting for code
- Side-by-side diffs

> **Example prompt:** "Show me the diff of my recent changes with syntax highlighting"

#### git-absorb
Smart auto-fixup that rewrites commits to "absorb" staged changes.

- Automatically fix up previous commits
- Rebase and squash intelligently
- No need to manually git commit --fixup
- Resolve conflicts during rebase

> **Example prompt:** "Absorb these staged changes into the appropriate previous commits"

#### difftastic
Structural diff that understands code syntax instead of just lines.

- Syntax-aware diffs
- Detects moves and copies
- Function-level granularity
- Works with many languages

> **Example prompt:** "Show me a structural diff of the changes to this Python file"

#### gitleaks
Scan for secrets and credentials in git history.

- Find leaked API keys and passwords
- Scan git history
- Pre-commit hooks for prevention
- Integration with CI/CD

> **Example prompt:** "Scan the git history for any accidentally committed secrets"

#### act
Run GitHub Actions locally before pushing.

- Test workflows on your machine
- Debug Actions step-by-step
- Avoid failed CI runs
- Simulate different events

> **Example prompt:** "Run this GitHub Action locally to test it"

#### actionlint
Lint GitHub Actions workflow files for errors and best practices.

- Validate workflow syntax
- Check for deprecated actions
- Verify permissions and permissions
- Suggest improvements

> **Example prompt:** "Check this workflow file for any issues"

---

## Security & Scanning

#### trivy
Vulnerability scanner for containers, filesystems, and git repositories.

- Scan Docker images for CVEs
- Scan local filesystems
- Scan git repositories
- Generate SBOM and scan for vulnerabilities

> **Example prompt:** "Scan this Docker image for security vulnerabilities"

#### nuclei
Template-based vulnerability scanner. Discover security issues methodically.

- Run predefined security templates
- Custom template creation
- Multi-target scanning
- Detailed vulnerability reports

> **Example prompt:** "Run a comprehensive security scan on this web application"

#### nikto
Web server vulnerability scanner. Identifies misconfigurations and insecure settings.

- Scan web servers
- Check for outdated software
- Identify insecure headers
- Test for common vulnerabilities

> **Example prompt:** "Scan this web server for security issues"

#### lynis
System security auditing tool. Comprehensive Linux/Unix hardening checks.

- Audit system security configuration
- Check for vulnerabilities
- Generate hardening recommendations
- Track security posture over time

> **Example prompt:** "Audit the system for security issues and show recommendations"

#### sqlmap
Automated SQL injection detection and exploitation.

- Test parameters for SQL injection
- Enumerate database structure
- Extract data from vulnerable databases
- Automate exploitation workflows

> **Example prompt:** "Test this application for SQL injection vulnerabilities"

#### opengrep
Static analysis for security patterns, bugs, and code quality issues. Self-contained binary (LGPL 2.1 fork of semgrep, 100% rule compatible). No Python/pip dependency, no token needed.

- Find security vulnerabilities in code
- Enforce code patterns
- Custom rule creation
- Multi-language support
- Installed as a binary download from GitHub releases

> **Example prompt:** "Scan the codebase for security vulnerabilities with opengrep"
> **Direct usage:** `opengrep scan -f auto .`

#### osv-scanner
Google's open source vulnerability scanner. Checks dependencies against OSV database.

- Scan dependency files (package.json, requirements.txt, etc.)
- Detect vulnerable versions
- Generate detailed reports
- Integration with lockfiles

> **Example prompt:** "Scan my Python requirements.txt for vulnerable packages"

#### comby
Structural code search and replace. Regex-aware and syntax-aware. **amd64 only — skipped on ARM64.**

- Search across languages
- Pattern matching with holes
- Refactoring at scale
- Preserve code structure

> **Example prompt:** "Find all function calls with specific patterns and show them"

#### ast-grep
Structural code search using AST patterns. Understand code by its structure.

- Search by code pattern (not just regex)
- Language-aware matching
- Refactoring and replacement
- Rule-based scanning

> **Example prompt:** "Find all function definitions that are longer than 50 lines"

#### parry
Prompt injection scanner for AI applications. Detect adversarial inputs.

- Scan text for prompt injection attempts
- Test AI application inputs
- Generate test cases
- Vulnerability assessment

> **Example prompt:** "Check if this text contains prompt injection attempts"

#### recall
Spaced repetition flashcard system. Learn anything via CLI.

- Create and review flashcards
- Spaced repetition scheduling
- Terminal-based interface
- Progress tracking

> **Example prompt:** "Review my flashcards for today"

---

## Network & DNS

#### doggo
DNS client with colored output and advanced queries. Replaces `dig`.

- Query DNS records
- Support for all DNS record types
- Colored output
- Multiple nameserver queries

> **Example prompt:** "Look up the DNS records for this domain"

#### mtr
Network diagnostic combining ping and traceroute with real-time updates.

- Trace packet route to destination
- Real-time packet loss stats
- Show per-hop latency
- Identify network issues

> **Example prompt:** "Trace the network path to this server and show latency"

#### nmap
Network scanner and port mapper. Discover hosts and open ports.

- Scan for open ports
- Identify services and versions
- OS detection
- Vulnerability scripts

> **Example prompt:** "Scan this IP address to see what ports are open"

#### subfinder
Passive subdomain enumeration. Discover subdomains without active scanning.

- Find subdomains of a domain
- Use multiple data sources
- Passive reconnaissance
- Identify attack surface

> **Example prompt:** "Find all subdomains for this domain"

#### httpx
Fast HTTP prober for discovered hosts. Check which respond to HTTP/HTTPS.

- Probe multiple hosts
- Check for HTTP/HTTPS
- Title extraction
- Status code categorization

> **Example prompt:** "Check which of these hosts respond to HTTP requests"

#### dnsx
Fast DNS toolkit for bulk DNS queries and resolution.

- Bulk DNS resolution
- Subdomain enumeration
- DNS record querying
- Wildcard detection

> **Example prompt:** "Resolve a list of hostnames to IP addresses"

#### katana
Web crawler for discovering paths and attack surface.

- Crawl websites for links
- Discover API endpoints
- JavaScript analysis
- Parameter discovery

> **Example prompt:** "Crawl this website and show me all the unique paths found"

#### cloudflared
Cloudflare tunnel client. Create secure tunnels to internal services.

- Run a tunnel daemon
- Route traffic through Cloudflare
- Zero-trust access
- Internal service exposure

> **Example prompt:** "Create a Cloudflare tunnel to expose this internal service"

---

## Process & System

#### btop
Beautiful TUI system resource monitor for CPU, RAM, disk, and network.

- Monitor system resources
- Process list with resource usage
- Disk I/O stats
- Network utilization

> **Example prompt:** "Show me real-time system resource usage"

#### procs
Modern `ps` replacement with color and tree view of processes.

- List running processes
- Show process tree
- Filter by name or user
- Sort by resource usage

> **Example prompt:** "Show all Python processes running on the system"

#### hyperfine
Benchmark commands and compare performance.

- Time command execution
- Run multiple times for statistical significance
- Compare different implementations
- Generate HTML reports

> **Example prompt:** "Benchmark two different approaches and compare their speed"

#### pueue
Task queue manager for running commands sequentially or in parallel.

- Queue background tasks
- Run jobs in parallel
- Manage task dependencies
- Persistent job queue

> **Example prompt:** "Queue these long-running tasks and run them in the background"

#### watchexec-cli
Re-run commands automatically when files change.

- Watch files for changes
- Trigger commands on file modification
- Ignore specific paths
- Clear screen before each run

> **Example prompt:** "Re-run tests automatically whenever I save a Python file"

#### entr
Simple file watcher. Run commands when files change.

- Monitor file changes
- Execute commands on change
- Shell integration
- Minimal dependencies

> **Example prompt:** "Run my build command whenever I save a file"

#### inotify-tools
Watch filesystem events and execute commands on file changes.

- Monitor filesystem events
- Recursive directory watching
- Custom event handling
- Access specific events (create, modify, delete)

> **Example prompt:** "Monitor the logs directory and alert me when new files appear"

#### at
Schedule one-time commands to run at a specific time.

- Schedule task for later execution
- One-time execution (not recurring)
- Works even if you're logged out
- Simple time specification

> **Example prompt:** "Schedule a backup to run at 2 AM tonight"

---

## Containers & Kubernetes

#### docker
Container runtime and engine. Build, run, and manage containers.

- Build container images
- Run and manage containers
- Push to registries
- Compose multi-container apps

> **Example prompt:** "Build a Docker image from the Dockerfile"

#### dive
Explore Docker image layers interactively. See what's consuming space.

- Analyze image layers
- Identify large files
- Understand image composition
- Optimize images

> **Example prompt:** "Analyze this Docker image to see what's making it large"

#### stern
Tail logs from multiple Kubernetes pods simultaneously.

- Stream logs from multiple pods
- Filter by label
- Follow specific deployments
- Grep through logs in real-time

> **Example prompt:** "Show me logs from all pods in the default namespace"

#### kubectl
Kubernetes cluster management. Deploy, manage, and troubleshoot applications.

- Deploy applications
- Manage resources (pods, services, deployments)
- View logs and events
- Troubleshoot issues

> **Example prompt:** "Deploy this Kubernetes manifest to the cluster"

#### helm
Kubernetes package manager. Install and manage Helm charts.

- Install Helm charts
- Manage releases
- Create custom charts
- Template generation

> **Example prompt:** "Install Prometheus using a Helm chart"

#### ctop
Container resource usage top. Monitor container metrics in real-time.

- Show container resource usage
- CPU and memory stats
- Real-time monitoring
- Sort by resource consumption

> **Example prompt:** "Show me which containers are using the most CPU"

---

## Cloud & Infrastructure

#### gcloud
Google Cloud CLI. Manage GCP resources, deploy apps, manage databases.

- Authenticate with GCP
- Manage compute instances
- Deploy to App Engine
- Manage Cloud SQL databases

> **Example prompt:** "List all compute instances in my GCP project"

#### aws
AWS CLI. Manage all AWS resources from the command line.

- Manage EC2 instances
- S3 bucket operations
- Deploy to Elastic Beanstalk
- CloudFormation management

> **Example prompt:** "List all S3 buckets in my AWS account"

#### hcloud
Hetzner Cloud CLI. Manage servers and cloud resources on Hetzner.

- Create and manage servers
- Manage volumes and networks
- Manage firewalls
- SSH key management

> **Example prompt:** "List all servers in my Hetzner account"

#### terraform
Infrastructure as Code. Define and manage cloud infrastructure.

- Define infrastructure in HCL
- Plan changes before applying
- Manage state files
- Multi-cloud support

> **Example prompt:** "Review the Terraform plan before applying changes"

#### packer
Machine image builder. Create pre-configured VM images.

- Build custom VM images
- Multi-cloud image creation
- Automated configuration
- Image versioning

> **Example prompt:** "Build a machine image with this configuration"

#### tflint
Terraform linter. Check for errors and best practices in Terraform code.

- Validate Terraform syntax
- Check for best practices
- Warn about deprecated syntax
- Custom rule creation

> **Example prompt:** "Lint this Terraform configuration for issues"

#### infracost
Terraform cost estimation. Predict cloud costs before deploying.

- Estimate Terraform costs
- Compare infrastructure options
- Monthly cost breakdown
- Integration with CI/CD

> **Example prompt:** "Show me the estimated cost for this Terraform configuration"

#### mc (MinIO Client)
MinIO/S3-compatible object storage CLI. Manage object storage buckets.

- Upload and download objects
- Manage buckets
- Copy between S3 buckets
- Sync directories

> **Example prompt:** "Upload files to this S3 bucket"

---

## Secrets & Certificates

#### sops
Encrypted secrets file editor. Works with age, GPG, and KMS.

- Edit encrypted secrets files
- Multi-key encryption
- Git-friendly format
- CI/CD integration

> **Example prompt:** "Edit the encrypted secrets file"

#### age
Modern file encryption tool. Fast and simple.

- Encrypt files
- Decrypt files
- Key management
- Recipient-based encryption

> **Example prompt:** "Encrypt this file with my public key"

#### infisical
Secret management CLI. Store and retrieve secrets securely.

- Store application secrets
- Rotate secrets
- Team secret management
- Version control integration

> **Example prompt:** "Retrieve the database password from secret storage"

#### step (step-cli)
Certificate management, TLS debugging, and JWT inspection.

- Generate self-signed certificates
- Inspect certificates
- Decode and verify JWTs
- TLS debugging

> **Example prompt:** "Decode this JWT and show me the claims"

#### mkcert
Create locally-trusted development TLS certificates.

- Generate dev certificates
- Auto-trust in system store
- Support for SANs
- Works with localhost and 127.0.0.1

> **Example prompt:** "Create a self-signed certificate for development"

---

## Code Quality & Formatting

#### ruff
Python linter and formatter combined. Replaces flake8, black, and isort.

- Lint Python code
- Format code to black style
- Sort imports
- Fix issues automatically

> **Example prompt:** "Lint this Python file and fix formatting issues"

#### shellcheck
Shell script static analysis. Find bugs before running.

- Check shell script syntax
- Detect common mistakes
- Security warnings
- Performance tips

> **Example prompt:** "Check this shell script for errors"

#### shfmt
Shell script formatter. Consistent formatting for bash/sh/ksh.

- Format shell scripts
- Customizable indent
- Language-specific rules
- Idempotent formatting

> **Example prompt:** "Format this shell script"

#### hadolint
Dockerfile linter. Best practices and security checks.

- Validate Dockerfile syntax
- Check Dockerfile best practices
- Security recommendations
- Performance suggestions

> **Example prompt:** "Check this Dockerfile for issues"

#### typos-cli
Fast typo fixer for source code. Catches misspellings.

- Find typos in code
- Fix misspellings
- Custom dictionaries
- Exclude patterns

> **Example prompt:** "Find typos in the codebase"

#### prettier
Code formatter for JavaScript, TypeScript, JSON, YAML, Markdown, CSS.

- Format JavaScript/TypeScript
- Format YAML and JSON
- Consistent formatting
- IDE integration

> **Example prompt:** "Format this JSON file"

---

## DevOps & Automation

#### just
Command runner. Like make but with simpler syntax and better UX.

- Run project tasks
- Dependency management
- Cross-platform scripts
- Variable substitution

> **Example prompt:** "Show me available commands and run the build task"

#### task
Task runner with YAML syntax. Similar to make but more intuitive.

- Define and run tasks
- Task dependencies
- Variables and templates
- Parallel execution

> **Example prompt:** "Run the deployment task"

#### ansible-core
IT automation and configuration management for multi-machine setups.

- Configure multiple servers
- Deploy applications
- Configuration management
- Orchestration

> **Example prompt:** "Run an Ansible playbook to configure the servers"

#### ansible-lint
Linter for Ansible playbooks. Check for issues and best practices.

- Validate playbook syntax
- Check for best practices
- Security checks
- Custom rule creation

> **Example prompt:** "Check this Ansible playbook for issues"

#### direnv
Auto-load `.envrc` files when entering directories. Environment management.

- Load .env files automatically
- Per-directory environments
- Shell integration
- Security checks

> **Example prompt:** "Set up environment variables for this project"

#### asciinema
Record and share terminal sessions. Create terminal demos and tutorials.

- Record terminal session
- Create shareable asciicast files
- Playback recordings
- Embed in documentation

> **Example prompt:** "Record a terminal session showing how to use this tool"

#### cookiecutter
Scaffold new projects from templates. Quick project setup.

- Create projects from templates
- Template variables
- Interactive setup
- Version management

> **Example prompt:** "Create a new Python project from a template"

---

## Databases

#### pgcli
Postgres CLI with autocomplete and syntax highlighting.

- Connect to Postgres databases
- Execute SQL queries
- Autocomplete for tables and columns
- Syntax highlighting

> **Example prompt:** "Connect to the database and query the users table"

#### usql
Universal SQL client supporting Postgres, MySQL, SQLite, and many more.

- Connect to multiple database types
- Execute SQL queries
- Import/export data
- Multi-database support

> **Example prompt:** "Connect to the database and run a query"

#### redis-cli
Redis command line client. Interact with Redis databases.

- Get and set values
- Manage keys and data structures
- Monitor Redis activity
- Pipeline commands

> **Example prompt:** "Get the value of this Redis key"

---

## Terminal UI & Utilities

#### glow
Render markdown in the terminal. Beautiful TUI markdown viewer.

- Display markdown beautifully
- Syntax highlighting
- Pager integration
- Inline images

> **Example prompt:** "Show me this README formatted nicely in the terminal"

#### tmux
Terminal multiplexer. Sessions, panes, and windows for powerful terminal workflows.

- Create and manage sessions
- Split panes and windows
- Detach and reattach
- Powerful scripting

> **Example prompt:** "Create a new tmux session with multiple panes"

#### lnav
Log file navigator with SQL querying. Explore logs interactively.

- Navigate log files
- SQL queries on logs
- Pattern matching
- Real-time log monitoring

> **Example prompt:** "Open and explore these log files"

#### imagemagick
Image processing from command line. Convert, resize, and manipulate images.

- Convert image formats
- Resize and crop images
- Apply effects and filters
- Batch processing

> **Example prompt:** "Convert this PNG to JPEG and resize it"

#### chafa
Display images in terminal as colored characters or blocks.

- Show images in terminal
- ASCII and Unicode art
- Colored output
- Embedded images

> **Example prompt:** "Display this image in the terminal"

#### aria2
Multi-protocol download manager. Fast downloads with parallel connections.

- Download files
- Parallel connections
- Torrent support
- Resume interrupted downloads

> **Example prompt:** "Download this file using multiple connections"

#### scc
Count lines of code with complexity metrics. Code statistics.

- Count lines of code
- Show complexity metrics
- Language breakdown
- Exclude patterns

> **Example prompt:** "Show code statistics for this project"

#### universal-ctags
Code tag generation for navigation. Jump to definitions in editors.

- Generate tags for code navigation
- Multi-language support
- Editor integration
- Definition lookup

> **Example prompt:** "Generate tags for this codebase"

---

## Documentation & Generation

#### repomix
Pack entire repository into AI-friendly context. Prepare code for LLMs.

- Export repository as text
- Include/exclude patterns
- Output for AI models
- Code analysis ready format

> **Example prompt:** "Export this repository in a format I can send to Claude"

#### mermaid-cli
Render Mermaid diagrams to PNG/SVG. Create diagrams as code.

- Convert Mermaid to images
- Batch processing
- SVG and PNG output
- Include in documentation

> **Example prompt:** "Convert this Mermaid diagram to a PNG image"

#### pandoc
Convert between document formats. Markdown to PDF, DOCX, HTML, etc.

- Format conversion
- Template support
- Bibliography handling
- Batch processing

> **Example prompt:** "Convert this markdown to a PDF document"

---

## Claude Code Ecosystem

#### claude
Claude Code CLI — the AI assistant itself. Your main interface.

- Chat with Claude
- Ask questions
- Invoke tools
- Work with files

> **Example prompt:** Just use natural language — Claude understands context

#### ccusage
Track Claude Code token and cost usage. Monitor spending.

- View API usage
- Cost breakdown
- Token statistics
- Budget tracking

> **Example prompt:** "Show me my Claude Code usage and costs"

#### claude-lens
Quota pace tracking statusline for Claude Code. Shows how fast/slow you're consuming
quota relative to expected rate — zero configuration required.

- Quota delta: % faster/slower than expected pace
- 5-hour and 7-day remaining quota at a glance
- Reset timer countdown
- Model, effort level, context %, git branch
- Script location: `~/.claude/claude-lens.sh`

> **Example prompt:** "Show Claude Code quota usage in my terminal"

#### rtk (Rust Token Killer)
Command output compression proxy. Reduces tokens consumed by verbose CLI output.

- Auto-rewrites commands transparently via PreToolUse hook (`git status`, `ls`, `grep`, `docker ps`, test runners, etc.)
- 60-90% token reduction on verbose outputs
- `rtk gain` — show token savings; `rtk gain --graph` — view daily savings history
- Built from source (not crates.io) with Vertex AI null-fix patch — serialization panics on null fields no longer occur
- Installed from `github.com/rtk-ai/rtk` (NOT crates.io — name collision with Rust Type Kit)
- Hook appended to PreToolUse after settings.json is written — does not clobber existing safety hooks

> **Example prompt:** "Show token savings from rtk this week"

#### better-ccflare
Load balancer and proxy for multiple Claude accounts. Account switching.

- Route between Claude accounts
- Load balancing
- Account management
- `ANTHROPIC_BASE_URL` auto-set in settings.json env block post-install
- Built from source with NULL constraint patches applied

> **Example prompt:** "Switch to a different Claude account"

#### claude-squad
Manage multiple Claude Code instances in tmux. Parallel work.

- Launch multiple Claude sessions
- tmux integration
- Window management
- Session switching

> **Example prompt:** "Open multiple Claude sessions for parallel work"

#### claude-tmux
tmux integration for Claude Code. Enhanced multiplexing and SSH resilience.

- Integrate with tmux for session persistence
- Session management across terminal windows
- Enhanced window creation and switching
- SSH disconnect resilience: script runs inside named `titan-setup` session at startup
- Reconnect after SSH drop: `tmux attach -t titan-setup`
- Install log: `/tmp/titan-setup-<timestamp>.log`

> **Example prompt:** "Integrate Claude with my tmux setup"

#### cc-patch-thinking
Shows Claude Code thinking blocks inline in the transcript. Automatically patches the CC binary after updates.

- Auto-runs on SessionStart — detects CC version changes via SHA256 hash comparison
- Version-resilient: byte-level regex matches `case"thinking"` structure, not minified variable names
- Maintains binary integrity: pads replacements with no-op semicolons (exact byte length preserved)
- `cc-patch-thinking --check` — check if patch needed (exit 0=patched, 1=needs patch, 2=unknown version)
- `cc-patch-thinking --dry-run` — preview changes without modifying
- `cc-patch-thinking --restore` — restore from backup
- Backup saved at `<binary>.thinking-patch-backup`, hash tracked at `~/.claude/.cc-thinking-patch-hash`

> **Example prompt:** "Check if the thinking patch is applied" → runs `cc-patch-thinking --check`

---

## Claude Code Plugins (MCP)

Titan installs curated plugins where MCP is genuinely better than the CLI equivalent. All disabled-by-default plugins that can be replaced by CLI tools are excluded.

| Plugin | What It Does | Why MCP > CLI |
|--------|-------------|---------------|
| `hookify` | Visual hook configuration and management | GUI-based hook editing beats manual JSON |
| `code-review` | PR review subagent + structured review skill | Convenient subagent workflow |
| `skill-creator` | Create and edit skills interactively with guided flow | Skill authoring workflow |
| `playwright` | Microsoft's browser automation MCP — 22 tools for navigate, click, snapshot, fill, screenshot, etc. | Ref-based accessibility tree targeting is deterministic; deferred loading (~300 tokens startup) |
| `episodic-memory` | Semantic search over past Claude Code conversations | No CLI equivalent for cross-session memory |
| `claude-subconscious` | Letta-based background memory agent; updates silently between turns (requires Letta) | No CLI equivalent for ambient persistent memory |

### Plugin notes

- `playwright` MCP plugin provides AI-driven browser automation (navigate, click, fill, snapshot); the playwright CLI (installed via bun) provides E2E testing (`playwright test`, codegen, traces) — both are installed, serving different purposes
- `claude-subconscious` requires the Letta server to be running — skip with `--letta-skip`
- `superpowers` and `context7` are **not** installed as plugins — superpowers skills are installed directly into `~/.claude/skills/`

---

## LettaCtrl GUI

LettaCtrl is a web dashboard for managing Letta agents and memory blocks. It runs as a Bun-powered HTTP server on port 8284.

### Accessing LettaCtrl

- **Local:** `http://localhost:8284`
- **VPS (via Tailscale):** `https://<hostname>:8284`

### What you can do

- View and manage Letta agents
- Inspect and edit memory blocks
- Monitor agent activity
- Create new agents with custom configurations

### Service management

```bash
# Check status
systemctl --user status letta-ctrl

# Restart
systemctl --user restart letta-ctrl

# Logs
journalctl --user -u letta-ctrl -f
```

Authentication uses the Letta API key from `~/.config/letta/credentials`.

## Claude Code UI

Web/mobile interface for Claude Code sessions. Access your Claude Code projects,
file explorer, git, and terminal from any device on your tailnet.

- Zero configuration — auto-discovers sessions from `~/.claude/`
- Default port: 3001 (configurable via `--claudecodeui-port`)
- Skip with `--claudecodeui-skip` or `--minimal`
- Requires Node.js v22+ (installed via mise)

```bash
# Check status
systemctl --user status claudecodeui

# Restart
systemctl --user restart claudecodeui

# Logs
journalctl --user -u claudecodeui -f
```

Access via browser: `http://localhost:3001` (desktop) or `https://<hostname>:3001` (VPS via Tailscale).

---

## Web & JavaScript

#### gemini-cli (`gemini`)
Google Gemini CLI. Access Gemini AI from terminal. **Binary is `gemini`**, not `gemini-cli`.

- Chat with Gemini
- Ask questions
- Code assistance
- API integration

> **Example prompt:** "Ask Gemini about a coding problem"

#### notebooklm-mcp-cli (`nlm`)
Google NotebookLM from terminal — full API access. **Binary is `nlm`**. Install: `uv tool install notebooklm-mcp-cli`.

- Create notebooks
- Add sources
- Generate insights
- Export notes

> **Example prompt:** "Create a notebook and upload a document"

#### huggingface_hub (`hf`)
Hugging Face Hub CLI — download models, datasets, and spaces; manage repos and tokens. Install: `uv tool install huggingface_hub`.

- Download model weights and dataset files: `hf download <repo-id>`
- Upload files to the Hub: `hf upload <repo-id> <file>`
- Manage cache: `hf cache scan` / `hf cache delete`
- Authenticate: `hf auth login`

> **Example prompt:** "Download the config.json from mistralai/Mistral-7B-v0.1"

#### cozempic
Context bloat cleaner for Claude Code sessions. Diagnoses exact token consumption in session JSONL files and surgically removes noise (progress ticks, repeated thinking blocks, stale reads). Install: `uv tool install cozempic`.

- Diagnose current session bloat: `cozempic diagnose`
- Remove bloat interactively: `cozempic treat`
- Wire hooks and slash command: `cozempic init` (run once after setup)
- In-session treatment via MCP: `/cozempic treat`
- Guard daemon auto-starts on SessionStart with `--system-overhead-tokens 35000` (accounts for plugins, skills, and hooks overhead)
- Guard modes: `cozempic guard --daemon` (background), `cozempic guard` (foreground)
- Checkpoints fire on PreCompact, Stop, and PostToolUse (Task events)

> **Example prompt:** "Diagnose how much token bloat is in my current session, then treat it"
#### kilocode
Kilo Code CLI. Code generation assistant.

- Generate code snippets
- Templates and patterns
- Language support
- Integration ready

> **Example prompt:** "Generate a function that does X"

#### vercel
Deploy to Vercel from CLI. Serverless functions and static sites.

- Deploy projects
- Manage deployments
- Configure environment
- Domain management

> **Example prompt:** "Deploy this project to Vercel"

#### playwright
Browser automation and E2E testing framework. Installed **two ways**: bun CLI tool (E2E testing) + MCP plugin (AI-driven automation).

- **MCP plugin** (`@playwright/mcp`): 22 deferred tools — `browser_navigate`, `browser_click`, `browser_snapshot`, `browser_fill_form`, `browser_take_screenshot`, etc. Claude calls these directly as native tools (no bash needed). Uses ref-based accessibility tree for deterministic element targeting.
- **CLI** (`bun install -g playwright`): `playwright test`, `playwright codegen`, `playwright show-trace` for traditional E2E testing
- Navigate pages and interact with elements
- Fill forms, click buttons, handle dialogs
- Take screenshots, PDFs, and accessibility snapshots
- Chromium binaries installed at `~/.cache/ms-playwright/`

> **Example prompt:** "Navigate to example.com, take a snapshot, and click the login button"

#### tldr
Simplified community man pages. Quick command help.

- Get command examples
- Practical use cases
- Common options
- Faster than man pages

> **Example prompt:** "Show me examples of how to use this command"

---

## Shell Enhancement

#### nushell
Structured data shell. Work with pipelines as structured data.

- Structured pipelines
- JSON-like data handling
- SQL-like operations
- Batteries included

> **Example prompt:** "Use nushell to query and transform data"

---

## Spotify (Desktop Only)

#### spotify_player
Spotify TUI client with full keyboard control and playlists.

- Control Spotify playback
- Browse playlists
- Queue management
- Keyboard shortcuts

> **Example prompt:** "Play music using Spotify from the terminal"

---

## Agents & Custom Agent Loading

### Built-in Agents (Always Available)

Claude Code comes with three built-in agents ready to use immediately:

#### **researcher** (Haiku — fast, cheap)
Read-only codebase explorer. Perfect for investigation and analysis tasks.
- Quickly search codebases
- Understand file relationships
- Analyze code patterns
- Cost-efficient for large projects

**How to invoke:** In your prompt, mention you want to use the researcher agent: "Use the researcher agent to find all database queries in the codebase"

#### **reviewer** (Sonnet — balanced)
Code review specialist. Identifies bugs, security issues, and style violations.
- Security vulnerability detection
- Performance problem identification
- Code style enforcement
- Best practice suggestions

**How to invoke:** "Have the reviewer agent check this code for issues"

#### **planner** (Opus — most capable)
Architecture and strategy planning. Handles complex design decisions.
- System architecture design
- Implementation strategy
- Complex problem solving
- Large refactoring planning

**How to invoke:** "Use the planner agent to design the architecture for this feature"

### On-Demand Agent Slots

You can load additional agents dynamically using the `agt` CLI command. Five slots are available:
- **Slots 1–3:** Haiku (fast, cheap, good for search and quick analysis)
- **Slot 4:** Sonnet (balanced capability and cost)
- **Slot 5:** Opus (most capable, slower, more expensive)

#### Agent Stash Library

30 ready-made agents are pre-staged at `~/.claude/agent-stash/`. Browse and load as needed.

#### Using the `agt` CLI

```bash
# Search for agents by name or description
agt search researcher

# Load an agent into a slot
agt load agent-name slot-1

# View available agents and loaded slots
agt status

# Get info about an agent
agt info agent-name

# Unload an agent from a slot
agt unload slot-1

# Refresh the agent index
agt refresh

# Build/update the agent index
agt build-index
```

#### Creating Custom Agents

Create your own agents and Claude Code will auto-discover them at **process startup**.

1. **Create agent file** at `~/.claude/agents/<your-agent-name>.md`

2. **Add YAML frontmatter** at the top:
   ```yaml
   ---
   name: Your Agent Name
   description: What this agent does and when to use it
   model: haiku  # or sonnet or opus
   tools:
     - rg
     - fd
     - git
   ---
   ```

3. **Add agent instructions** below the frontmatter:
   ```markdown
   You are a specialist in X. Your role is to...

   Always:
   - Check git history first
   - Search broadly before narrowing
   - Show full context in answers
   ```

4. **CRITICAL: Full Claude Code restart required**
   - Simply running `/clear` does NOT re-scan the agents directory
   - Exit Claude Code completely (Ctrl+D or exit command)
   - Relaunch Claude Code
   - New agent will be registered and available

#### How Claude Discovers Agents

- Claude Code **scans** `~/.claude/agents/` at **process startup only**
- Each `.md` file with YAML frontmatter becomes an available agent
- Invoke by name in prompts: "Use the security-specialist agent to..."
- Agents can be used alongside built-in agents

#### Example Custom Agent

Create `~/.claude/agents/database-expert.md`:

```yaml
---
name: Database Expert
description: Specialist in SQL optimization, schema design, and performance tuning
model: sonnet
tools:
  - usql
  - pgcli
  - duckdb
  - rg
---

You are a database specialist with 15 years of experience.

When analyzing databases:
1. Check the schema first (DESCRIBE or SHOW TABLES)
2. Look for indexes and constraints
3. Review query execution plans
4. Suggest optimization strategies

Always explain query performance implications and test changes before recommending.
```

Then restart Claude Code and invoke: "Have the database-expert agent review this SQL query"

#### Agent Best Practices

- **Narrow focus:** Agents work best with specific expertise areas
- **Model choice:** Use Haiku for search/analysis, Sonnet for coding, Opus for architecture
- **Tool selection:** List only tools the agent will actually use
- **Clear instructions:** Be specific about the agent's methodology and constraints
- **Test invocation:** Restart CC and verify the agent is listed and responds correctly

---

## Tips & Best Practices

### Tool Discovery Philosophy

- **Never memorize flags.** Claude reads `--help` every time, never guesses.
- **Type natural language prompts.** "Find all Python files that import X" → Claude figures out `rg -l 'import X' --type py`
- **Ask for examples.** If unsure how a tool works, ask Claude: "Show me examples of using jq to transform JSON"

### Combining Tools

Tools work best together:

- Find files with `fd` → Process with `rg` → Transform output with `jq`
- Scan codebase with `ast-grep` → Review with `difftastic` → Commit with `git`
- Query data with `duckdb` → Format with `jq` → Analyze with `miller`

### Common Workflows

**Code search and refactoring:**
```
"Use ast-grep to find all function calls to old_function,
then show me diffs, then use comby to replace them"
```

**Security scanning:**
```
"Scan the codebase with opengrep, then check git history
with gitleaks, and finally report vulnerabilities"
```

**Infrastructure planning:**
```
"Check the current Terraform configuration with tflint,
estimate costs with infracost, then create a deployment plan"
```

### Performance Tips

- Use `fd` instead of `find` (faster)
- Use `rg` instead of `grep` (faster, better regex)
- Use `duckdb` for complex data queries (no memory overhead)
- Use `dust` to identify large files quickly
- Use Haiku agents for search tasks (costs less)

### Security Reminders

- Always run `gitleaks detect` before pushing to remote
- Use `gitleaks` to scan git history for leaked secrets
- Run `trivy` on container images before deployment
- Use `sops` or `age` for encrypted secrets files
- Never commit `.env` files or credentials

---

## Getting Help

**For any tool, use:**
```bash
<toolname> --help           # Full help and flags
<toolname> -h               # Quick help
tldr <toolname>             # Community examples
```

**Claude can:**
- Explain what a tool does
- Show you real-world examples
- Build complex command chains
- Fix errors and explain why they happened

Just ask in natural language. Claude reads the help first, then figures out the right approach.

---

**Welcome to your fully-armed workstation. Build with confidence.**
