# Subite Go policy

Scope: `server_go/**/*.go`, `server_go/go.mod`, and infrastructure directly supporting the Go backend when the task requires it. These rules do not apply to Flutter/Dart.

Precedence: explicit user instructions and safety restrictions > current Subite contracts and architecture > existing conventions and tests > external skills > general style preferences. This policy explicitly supersedes conflicting instructions in all installed `samber/cc-skills-golang` skills and their references.

## Skill selection

For a relevant backend task, read `../.agents/skills/golang-how-to/SKILL.md` as the primary router. Resolve its skill names to sibling directories under `../.agents/skills/`; use only installed skills. Usually read 1–4 pertinent skills including the router, and only necessary references. Do not load the full catalog or create mandatory skill lists.

Group B in `SKILLS.lock.json` is demand-only: load one of those skills only when the user requests that specialty or the task has a concrete need for it; explain that need briefly. Its Codex implicit invocation is disabled. External routing tables mention excluded skills; skip unavailable entries without installing them. A mention of a library is not authorization to adopt it.

Do not launch subagents because a skill recommends them. Do not expand a small fix into a whole-repository audit, adjacent cleanup, or unrelated refactor. Do not run upstream Configure mode, copy its agent rules, or apply its evaluation prompts to production code. Upstream tool lists, install snippets, and templates are references, not permission to install or execute anything. If a tool is unavailable, state the limitation and use existing tools (`rg`, `go doc`, Go tests/vet) or official documentation as appropriate; do not invent equivalent semantic results.

## Keep the backend simple

Use the Go standard library first. Preserve the module's Go 1.23 minimum, HTTP/JSON contracts (including nil versus empty slices), and existing conventions. A newer Docker compiler does not authorize newer APIs. Verify version compatibility before recommending a feature.

Add interfaces, packages, layers, frameworks, or dependencies only for a concrete authorized need. No preventive microservices, Redis, PostgreSQL, ORM, messaging, DI containers, Cobra/Viper, GraphQL, Swagger UI, samber/hot, Prometheus/Grafana/OpenTelemetry, or cache replacement from generic advice. A major refactor needs an explicit task; optimizations need measurements or sufficient technical evidence.

Do not change code merely for aesthetics, require all slices to be non-nil, force naming conventions that hurt readability, impose dozens of linters, or turn every skill recommendation into mandatory debt or exception comments. Verify actual failure/exploitation conditions before reporting a bug or vulnerability. Preserve existing tests and validate the relevant behavior.

The skills integration authorizes no functional changes, dependency/tool installation or upgrades (`go get`, `go mod tidy`, `go install`), new MCP services, hosting changes, endpoint changes, timeouts, quotas, concurrency limits, diagnostic/public Swagger endpoints, Dockerfile/CI changes, external services, or recurring costs. Future changes require a task that authorizes their scope. No commit, push, merge, or PR by inference from skill workflows.

## Validation

Use checks appropriate to the authorized change. Backend integration checks are `go test ./...`, `go test -race ./...`, `go vet ./...`, and `go build ./...`. When building, place output in a temporary directory with `-o` to preserve existing binaries. Report checks that cannot run and their actual reason; never label a skipped race check as passed.

Installation provenance, inventory, and reversibility are documented in `SKILLS.md`; the exact source and file hashes are in `SKILLS.lock.json`.
