# Harness Architecture

Local experiment harness contract: tracked repository code only defines scripts,
profiles, fixtures, and docs. All generated state, upstream checkouts, and
managed workspaces live under `.local/`. Every entry script must load
`config/experiment.example.json` through `scripts/common.ps1` so CLI and desktop
flows share the same paths, runtime defaults, and prerequisite checks.

## Layout Contract

Tracked repository content:

- `config/`: checked-in configuration templates and schema examples.
- `docs/`: architecture notes and operator-facing documentation.
- `fixtures/`: tracked seed inputs for repeatable experiments.
- `profiles/`: tracked profile definitions referenced by runtime scripts.
- `scripts/`: entry scripts and shared PowerShell helpers.

Generated local state:

- `.local/upstream/`: cloned or refreshed upstream repositories.
- `.local/workspaces/`: mutable workspaces for managed runs and desktop flows.
- `.local/logs/`: command logs and diagnostic output.
- `.local/venv/`: repo-local Python environment used by harness scripts.

The repository must remain runnable when `.local/` is deleted and recreated.
Later steps may add more subdirectories under `.local/`, but they must not move
state outside `.local/` or rename the tracked top-level folders above without a
deliberate contract change.

## Shared Config Contract

`config/experiment.example.json` is the canonical checked-in example for all
entry scripts. It defines three top-level sections:

- `paths`: relative paths for tracked roots and generated local state.
- `runtime`: shared runtime defaults such as shell, profile, and Python command.
- `prerequisites`: named tool requirements consumed by helper checks.

Entry scripts must not hardcode local paths or prerequisite names outside
`scripts/common.ps1`. They should read the config and resolve absolute paths via
the helper functions described below.

## Helper Contract

`scripts/common.ps1` defines the shared PowerShell surface for downstream
scripts:

- `Get-ExperimentRepoRoot`: returns the repository root containing `scripts/`.
- `Get-ExperimentConfigPath`: resolves the example config path, with optional
  override support for later tasks.
- `Read-ExperimentConfig`: loads JSON and verifies the required top-level keys.
- `Get-ExperimentPaths`: resolves configured path values to absolute paths.
- `Get-ExperimentRuntimeDefaults`: returns the `runtime` block as a PowerShell
  object.
- `Test-ExperimentPrerequisite`: checks whether a configured command is
  available on the current machine.
- `Assert-ExperimentPrerequisites`: aggregates prerequisite failures and stops
  execution before scripts mutate local state.

Every future entry script should start with:

```powershell
. "$PSScriptRoot/common.ps1"
$config = Read-ExperimentConfig
$paths = Get-ExperimentPaths -Config $config
Assert-ExperimentPrerequisites -Config $config
```

That requirement keeps CLI and desktop flows aligned on path layout, runtime
defaults, and prerequisite checks.
