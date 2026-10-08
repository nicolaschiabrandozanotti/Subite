# Go skills for Subite

Installed on 2026-10-08 for Codex only. This is agent documentation; it is not part of the application or an approval to change dependencies or architecture. Backend policy has one owner: [AGENTS.md](AGENTS.md).

## Provenance and installation

- Source: [samber/cc-skills-golang](https://github.com/samber/cc-skills-golang/tree/8e899e20ff0cd4dc524af3993e4c62d8ee8c5717).
- Pinned commit: `8e899e20ff0cd4dc524af3993e4c62d8ee8c5717`.
- Exactly 31 selected skills, one canonical copy each in `../.agents/skills/`. None of the 15 excluded skills was installed.
- Installer: the bundled official Codex `skill-installer/scripts/install-skill-from-github.py`, with explicit `--repo samber/cc-skills-golang`, `--ref <commit>`, `--method download`, `--dest <repository>/.agents/skills`, and `--path` followed by the 31 selected `skills/<name>` paths.
- Its source/options were reviewed before execution. No global destination, other agent destination, plugin, dependency, or auxiliary tool installation was used. The CLI `skills` 1.7.1 options and Codex destination were also inspected; the official helper was chosen to avoid its shared user-level lock bookkeeping. The helper has no telemetry implementation. The temporary `npx --help` invocation did not install project dependencies.
- All 222 selected upstream files (31 SKILL.md and 191 auxiliary files) were inventoried/read by the precheck and screened for commands, tool installation, newer Go APIs, routing, configuration templates, and conflicting directives. JSON evaluation files parsed successfully. No auxiliary scripts or templates were executed or activated. This review does not certify every technical recommendation as correct.
- Before adaptation, all 222 installed files matched the pinned Git blobs after line-ending normalization. Source and installed SHA-256 hashes, groups, and adaptations are recorded in [SKILLS.lock.json](SKILLS.lock.json). The upstream MIT notice is retained at `../.agents/skills/LICENSE.samber-cc-skills-golang`.

Local adaptations only shorten/scope descriptions, scope upstream Go path hints, prepend a policy pointer, and add `agents/openai.yaml` invocation policies. Upstream instruction bodies, references, examples, and evaluation data are retained. Evaluation expectations are upstream test fixtures, not Subite requirements. They include incompatible or unapproved recommendations; the backend policy takes precedence.

## Discovery, selection, and limits

Codex discovers repository `.agents/skills` from its working directory up to the Git root. It initially loads skill names/descriptions/paths; full instructions and references are read when selected. See [official skill documentation](https://learn.chatgpt.com/docs/build-skills).

Group A has 16 contextual skills; group B has 15 demand-only skills with `policy.allow_implicit_invocation: false`. Group membership lives in the lock file, without a second mandatory skill list. `golang-how-to` routes through installed sibling directories; absent upstream cross-references are skipped. Normal backend tasks select 1–4 skills including the router. For example, cancellation uses how-to + context + concurrency; naming uses how-to + naming (style only if necessary); a specific panic uses how-to + troubleshooting + safety. A measured performance task may select how-to + benchmark + performance. These routes resolve to installed files without adopting upstream optional libraries.

The root `AGENTS.md` is a short backend-policy pointer. `server_go/AGENTS.md` owns the scoped rules. This pointer matters when Codex starts at the repository root: nested AGENTS files are not automatically in its startup instruction chain. When started inside `server_go`, Codex also discovers the nested policy directly. See [official AGENTS discovery documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

The installed desktop's `codex.exe` (0.162.0-alpha.2) was checked through a read-only `app-server` `skills/list` request with `forceReload: true`; no thread or agent run was created. All 31 skills were returned as enabled repository skills, with no loader errors, from root, backend, and Flutter working directories. Their names and paths resolve correctly. The executable recognizes `allow_implicit_invocation`, and the policy files follow the documented format; this API response does not expose invocation policy values. Autonomous model selection was not exercised by launching another agent.

Repository skill visibility is broader than backend activation: root skills also appear in Flutter's catalog. Codex does not provide a verified file-glob activation barrier here; upstream `paths` hints are not treated as such. Scoped descriptions, the root pointer, and the backend policy prevent applying Go guidance to Flutter. The group B policy prevents automatic description matching, while explicit invocation and justified manual reference reads remain available. These are agent instructions, not a sandbox preventing a human from explicitly requesting something else.

Codex detects installed skills automatically; they should be available on the next turn. If the current host still shows an old catalog, restart Codex. No claim is made that this turn's already supplied skill list refreshed. Some optional gopls/godig/swag/benchstat workflows need tools that this integration did not install; use the policy's existing-tool fallback and report reduced capability.

## Integrity and checks

Precheck: Git repository `friendly-salk`, branch `feat/support-subite`, no staged changes, existing Flutter/documentation edits and untracked files. A SHA-256 baseline covered 136 existing tracked/untracked paths, including existing deletions. Those contents, deletions, index, branch, and HEAD were preserved. No pre-existing project file was overwritten.

Created: root `AGENTS.md`, backend `AGENTS.md`, this report, `SKILLS.lock.json`, 31 skill directories (253 files including Codex policy adapters), and one shared license. Modified pre-existing project files: zero. Go dependencies added: zero. Flutter, functional Go code, Go 1.23 declaration, Dockerfile, deployment, and CI are unchanged by this integration. Prior dirty changes remain uncommitted; installation files are new/untracked. No commit, push, merge, or PR.

Executed from `server_go/`:

| Check | Result |
| --- | --- |
| `go test ./...` | PASS (cached) |
| `go vet ./...` | PASS |
| `go build -o <temporary executable> ./...` | PASS; output outside repository |
| `go test -race ./...` | Could not run: CGO disabled |
| Process-local `CGO_ENABLED=1 go test -race ./...` | Could not build: `gcc` absent from PATH |
| `git diff --check` | PASS for the existing tracked diff; existing LF/CRLF warnings only |
| Skills inventory, hashes, metadata/discovery, policy and routing checks | PASS |

Validation is PARTIAL because race coverage could not execute in this Windows environment; no compiler was installed to bypass that constraint. Other checks passed on the existing Go 1.27 compiler; this integration did not execute Go 1.23 separately or change its minimum contract. Loader discovery and static routes are verified; future model behavior still depends on following project instructions.

## Reversibility and Flutter

To undo this integration, remove only its newly created root/backend instruction and report/lock files, the 31 directories enumerated by this lock, and the shared license. First compare installed hashes with the lock so subsequent edits are preserved. Do not remove whole `.agents` trees or overwrite global skills/configuration. No application or dependency rollback is needed.

Flutter needs a separate future selection covering architecture, map performance, state management, GPS/lifecycle, offline persistence, testing, and Android performance. No Flutter skills were installed and `bondi_app/` was not modified in this task.
