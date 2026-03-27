import json
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def test_example_config_points_to_profile_directory_and_default_jakal_flow_profile():
    config_path = REPO_ROOT / "config" / "experiment.example.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))

    assert config["paths"]["profilesRoot"] == "config/profiles"
    assert config["runtime"]["defaultProfile"] == "jakal-flow-local"
    assert config["entryScripts"]["bootstrap"] == "scripts/bootstrap.ps1"
    assert config["entryScripts"]["materializeTarget"] == "scripts/materialize-target.ps1"


def test_jakal_flow_profile_freezes_remote_target_contract():
    profile_path = REPO_ROOT / "config" / "profiles" / "jakal-flow-local.json"
    profile = json.loads(profile_path.read_text(encoding="utf-8"))

    assert profile["schemaVersion"] == 1
    assert profile["id"] == "jakal-flow-local"
    assert profile["source"]["kind"] == "remoteGit"
    assert profile["source"]["repositoryUrl"] == "https://github.com/Ahnd6474/Jakal-flow.git"
    assert profile["source"]["defaultBranch"] == "main"
    assert profile["source"]["checkoutPath"] == ".local/upstream/jakal-flow"
    assert profile["target"]["kind"] == "remoteTarget"
    assert profile["target"]["repositoryPath"] == ".local/targets/jakal-flow-local"
    assert profile["workspace"]["path"] == ".local/workspaces/jakal-flow-local"
    assert profile["environment"]["required"] == ["OPENAI_API_KEY"]
    assert profile["environment"]["optional"] == ["GITHUB_TOKEN"]
    assert profile["prerequisites"]["overlays"]["codex"]["required"] is True
    assert [phase["id"] for phase in profile["verification"]["phases"]] == [
        "check-prereqs",
        "bootstrap-source",
        "pytest-target",
    ]
    assert profile["verification"]["phases"][0]["entryScript"] == "checkPrereqs"
    assert profile["verification"]["phases"][1]["entryScript"] == "bootstrap"
    assert profile["verification"]["phases"][2]["command"] == "python"
    assert profile["verification"]["phases"][2]["args"] == ["-m", "pytest"]
    assert profile["verification"]["phases"][2]["workingDirectory"] == ".local/targets/jakal-flow-local"
    assert profile["verification"]["phases"][2]["timeoutSeconds"] == 120


def test_sample_profile_is_declarative_and_bounded():
    profile_path = REPO_ROOT / "config" / "profiles" / "sample-local.json"
    profile = json.loads(profile_path.read_text(encoding="utf-8"))

    assert profile["schemaVersion"] == 1
    assert profile["id"] == "sample-local"
    assert profile["target"]["kind"] == "fixture"
    assert profile["target"]["seedRoot"] == "fixtures/sample-seed"
    assert profile["target"]["repositoryPath"] == ".local/targets/sample-local"
    assert profile["verification"]["workingDirectory"] == ".local/targets/sample-local"
    assert profile["verification"]["command"] == "python"
    assert profile["verification"]["args"] == ["-m", "pytest"]
    assert profile["verification"]["timeoutSeconds"] == 60
    assert profile["environment"]["required"] == []


def test_env_example_documents_secret_inputs_without_values():
    env_example = (REPO_ROOT / ".env.example").read_text(encoding="utf-8")

    assert "OPENAI_API_KEY=" in env_example
    assert "GITHUB_TOKEN=" in env_example
    assert "sample-local" in env_example


def test_materialize_sample_target_creates_valid_local_repository():
    script_path = REPO_ROOT / "scripts" / "materialize-sample-target.ps1"
    target_repository = REPO_ROOT / ".local" / "targets" / "sample-local"

    if target_repository.exists():
        shutil.rmtree(target_repository)

    subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script_path),
        ],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )

    assert (target_repository / ".git").exists()
    assert (target_repository / "sample_target.py").exists()
    assert (target_repository / "tests" / "test_smoke.py").exists()

    git_status = subprocess.run(
        ["git", "-C", str(target_repository), "rev-parse", "--is-inside-work-tree"],
        check=True,
        capture_output=True,
        text=True,
    )
    assert git_status.stdout.strip() == "true"

    profile_path = REPO_ROOT / "config" / "profiles" / "sample-local.json"
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    verification = subprocess.run(
        [profile["verification"]["command"], *profile["verification"]["args"]],
        cwd=REPO_ROOT / profile["verification"]["workingDirectory"],
        check=True,
        capture_output=True,
        text=True,
        timeout=profile["verification"]["timeoutSeconds"],
    )

    assert "1 passed" in verification.stdout
