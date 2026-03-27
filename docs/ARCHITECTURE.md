# Harness Architecture

Local experiment harness contract: tracked repository code only defines scripts,
profiles, fixtures, and docs. All generated state, upstream checkouts, and
managed workspaces live under `.local/`. Every entry script must load
`config/experiment.example.json` through `scripts/profile-common.ps1` so CLI and
desktop flows share the same paths, runtime defaults, profile normalization, and
prerequisite checks. `scripts/common.ps1` remains a compatibility loader for
existing scripts, but `scripts/profile-common.ps1` is the canonical helper
surface.

## Layout Contract

Tracked repository content:

- `config/`: checked-in configuration templates and schema examples.
- `config/profiles/`: tracked declarative experiment profiles for CLI and
  desktop launchers.
- `docs/`: architecture notes and operator-facing documentation.
- `fixtures/`: tracked seed inputs for repeatable experiments.
- `scripts/`: entry scripts and shared PowerShell helpers.

Generated local state:

- `.local/upstream/`: cloned or refreshed upstream repositories.
- `.local/targets/`: local target repositories materialized from tracked
  fixtures or remote sources.
- `.local/workspaces/`: mutable workspaces for managed runs and desktop flows.
- `.local/logs/`: command logs and diagnostic output.
- `.local/venv/`: repo-local Python environment used by harness scripts.

The repository must remain runnable when `.local/` is deleted and recreated.
Later steps may add more subdirectories under `.local/`, but they must not move
state outside `.local/` or rename the tracked top-level folders above without a
deliberate contract change.

## Shared Config Contract

`config/experiment.example.json` is the canonical checked-in example for all
entry scripts. It defines four top-level sections and fixes the default profile
decision:

- `paths`: relative paths for tracked roots and generated local state.
- `runtime`: shared runtime defaults such as shell, Python command, and the
  default profile id. The default profile is `jakal-flow-local`.
- `entryScripts`: fixed harness entrypoint names mapped to repository-relative
  script paths.
- `prerequisites`: named tool requirements consumed by helper checks.

Entry scripts must not hardcode local paths or prerequisite names outside
`scripts/profile-common.ps1`. They should read the config and resolve absolute
paths via the helper functions described below.

The fixed entry script names are:

- `checkPrereqs`
- `bootstrap`
- `cleanLocalState`
- `materializeTarget`
- `invokeVerification`

Later implementation steps may add the remaining scripts, but they must use
these names rather than introducing alternate entrypoints.

## Profile Contract

`config/profiles/jakal-flow-local.json` is the first real Jakal-flow remote
target profile. It freezes the declarative shape that downstream provisioning
and verification steps must consume:

- `source`: immutable source metadata including repository URL, default branch,
  and checkout path under `.local/upstream/`.
- `target`: mutable repository path under `.local/targets/`.
- `workspace`: mutable workspace path under `.local/workspaces/`.
- `environment`: required and optional environment variable names.
- `prerequisites.overlays`: profile-specific adjustments applied on top of the
  shared prerequisite catalog.
- `verification.phases`: ordered verification phases. Each phase is either a
  named `entryScript` reference or a direct command with explicit working
  directory and timeout.

The tracked `sample-local` fixture profile remains available for local fixture
smoke tests, but it is no longer the default contract for Jakal-flow work.

## Helper Contract

`scripts/profile-common.ps1` defines the shared PowerShell surface for
downstream scripts:

- `Get-ExperimentRepoRoot`: returns the repository root containing `scripts/`.
- `Get-ExperimentConfigPath`: resolves the example config path, with optional
  override support for later tasks.
- `Read-ExperimentConfig`: loads JSON and verifies the required top-level keys.
- `Get-ExperimentPaths`: resolves configured path values to absolute paths.
- `Get-ExperimentRuntimeDefaults`: returns the `runtime` block as a PowerShell
  object.
- `Get-ExperimentEntryScripts`: resolves the fixed harness entry script names to
  absolute paths.
- `Resolve-ExperimentProfilePath`: resolves either a profile id or explicit JSON
  path using the default profile when none is provided.
- `Read-ExperimentProfile`: loads a declarative profile and verifies the
  required sections for remote-target work.
- `Normalize-ExperimentProfile`: returns immutable metadata for source checkout,
  target repository path, workspace path, environment requirements,
  prerequisite overlays, and ordered verification phases.
- `Test-ExperimentPrerequisite`: checks whether a configured command is
  available on the current machine.
- `Assert-ExperimentPrerequisites`: aggregates prerequisite failures and stops
  execution before scripts mutate local state.

Every future entry script should start with:

```powershell
. "$PSScriptRoot/profile-common.ps1"
$config = Read-ExperimentConfig
$paths = Get-ExperimentPaths -Config $config
$profile = Normalize-ExperimentProfile -ConfigPath "config/experiment.example.json"
Assert-ExperimentPrerequisites -Config $config
```

That requirement keeps CLI and desktop flows aligned on path layout, runtime
defaults, entry script names, normalized profile metadata, and prerequisite
checks.
