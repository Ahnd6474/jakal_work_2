import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def test_example_config_contains_required_contract_sections():
    config_path = REPO_ROOT / "config" / "experiment.example.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))

    assert config["schemaVersion"] == 1
    assert set(config) >= {"paths", "runtime", "prerequisites"}
    assert set(config["paths"]) >= {
        "localRoot",
        "upstreamCheckout",
        "workspaceRoot",
        "logsRoot",
        "profilesRoot",
        "fixturesRoot",
    }
    assert set(config["runtime"]) >= {
        "pythonCommand",
        "venvPath",
        "defaultProfile",
        "shell",
        "logLevel",
    }
    assert set(config["prerequisites"]) >= {"git", "python", "codex"}


def test_common_helper_exposes_frozen_entrypoints():
    common_path = REPO_ROOT / "scripts" / "common.ps1"
    common_text = common_path.read_text(encoding="utf-8")

    for function_name in [
        "Get-ExperimentRepoRoot",
        "Get-ExperimentConfigPath",
        "Read-ExperimentConfig",
        "Resolve-ExperimentPath",
        "Get-ExperimentPaths",
        "Get-ExperimentRuntimeDefaults",
        "Test-ExperimentPrerequisite",
        "Assert-ExperimentPrerequisites",
    ]:
        assert f"function {function_name}" in common_text


def test_gitignore_keeps_local_state_untracked():
    gitignore_path = REPO_ROOT / ".gitignore"
    gitignore_text = gitignore_path.read_text(encoding="utf-8")

    assert ".local/" in gitignore_text


def test_architecture_doc_describes_local_contract():
    architecture_path = REPO_ROOT / "docs" / "ARCHITECTURE.md"
    architecture_text = architecture_path.read_text(encoding="utf-8")

    assert "Local experiment harness contract" in architecture_text
    assert "config/experiment.example.json" in architecture_text
    assert "scripts/common.ps1" in architecture_text
