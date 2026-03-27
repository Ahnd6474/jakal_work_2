import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def normalize_path(path: str) -> str:
    return path.replace("\\", "/")


def test_example_config_contains_required_contract_sections():
    config_path = REPO_ROOT / "config" / "experiment.example.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))

    assert config["schemaVersion"] == 1
    assert set(config) >= {"paths", "runtime", "entryScripts", "prerequisites"}
    assert set(config["paths"]) >= {
        "localRoot",
        "upstreamRoot",
        "upstreamCheckout",
        "targetsRoot",
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
    assert set(config["entryScripts"]) >= {
        "checkPrereqs",
        "bootstrap",
        "cleanLocalState",
        "materializeTarget",
        "invokeVerification",
    }
    assert set(config["prerequisites"]) >= {"git", "python", "codex"}


def test_profile_helper_exposes_frozen_entrypoints():
    helper_path = REPO_ROOT / "scripts" / "profile-common.ps1"
    helper_text = helper_path.read_text(encoding="utf-8")

    for function_name in [
        "Get-ExperimentRepoRoot",
        "Get-ExperimentConfigPath",
        "Read-ExperimentConfig",
        "Resolve-ExperimentPath",
        "Get-ExperimentPaths",
        "Get-ExperimentRuntimeDefaults",
        "Get-ExperimentEntryScripts",
        "Resolve-ExperimentProfilePath",
        "Read-ExperimentProfile",
        "Normalize-ExperimentProfile",
        "Test-ExperimentPrerequisite",
        "Assert-ExperimentPrerequisites",
    ]:
        assert f"function {function_name}" in helper_text

    assert '"""Normalize a declarative experiment profile' in helper_text


def test_common_helper_remains_a_compatibility_loader():
    common_path = REPO_ROOT / "scripts" / "common.ps1"
    common_text = common_path.read_text(encoding="utf-8")

    assert "profile-common.ps1" in common_text


def test_default_profile_normalizes_to_remote_contract():
    command = (
        ". ./scripts/profile-common.ps1; "
        "$normalizedProfile = Normalize-ExperimentProfile; "
        "$normalizedProfile | ConvertTo-Json -Depth 10"
    )
    result = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            command,
        ],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    profile = json.loads(result.stdout)

    assert profile["Id"] == "jakal-flow-local"
    assert normalize_path(profile["Source"]["CheckoutPath"]).endswith(".local/upstream/jakal-flow")
    assert normalize_path(profile["TargetRepositoryPath"]).endswith(".local/targets/jakal-flow-local")
    assert normalize_path(profile["WorkspacePath"]).endswith(".local/workspaces/jakal-flow-local")
    assert profile["RequiredEnvironmentVariables"] == ["OPENAI_API_KEY"]
    assert [phase["Id"] for phase in profile["VerificationPhases"]] == [
        "check-prereqs",
        "bootstrap-source",
        "pytest-target",
    ]
    assert profile["VerificationPhases"][0]["EntryScriptName"] == "checkPrereqs"
    assert profile["VerificationPhases"][1]["EntryScriptName"] == "bootstrap"
    assert profile["VerificationPhases"][2]["Command"] == "python"


def test_gitignore_keeps_local_state_untracked():
    gitignore_path = REPO_ROOT / ".gitignore"
    gitignore_text = gitignore_path.read_text(encoding="utf-8")

    assert ".local/" in gitignore_text


def test_architecture_doc_describes_local_contract():
    architecture_path = REPO_ROOT / "docs" / "ARCHITECTURE.md"
    architecture_text = architecture_path.read_text(encoding="utf-8")

    assert "Local experiment harness contract" in architecture_text
    assert "config/experiment.example.json" in architecture_text
    assert "scripts/profile-common.ps1" in architecture_text
    assert "jakal-flow-local" in architecture_text
