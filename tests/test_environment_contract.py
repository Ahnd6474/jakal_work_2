import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def run_powershell(script: str) -> str:
    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", script],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def load_contract() -> dict:
    script = (
        ". \"$PWD/scripts/common.ps1\"; "
        "Get-JakalFlowContract | ConvertTo-Json -Depth 8 -Compress"
    )
    return json.loads(run_powershell(script))


def load_launcher_environment() -> dict:
    script = (
        ". \"$PWD/scripts/common.ps1\"; "
        "Get-JakalFlowLauncherEnvironment | ConvertTo-Json -Depth 4 -Compress"
    )
    return json.loads(run_powershell(script))


def test_contract_resolves_shared_paths_and_metadata() -> None:
    contract = load_contract()

    assert contract["Docstring"] == (
        "Centralize the local Jakal-flow environment contract. Resolve the "
        "managed upstream checkout, branch, project virtualenv, desktop path, "
        "and launcher commands from this layer so every setup, run, and "
        "verification script targets the same source tree and never falls back "
        "to a globally installed `jakal_flow` package."
    )
    assert contract["Repository"] == {
        "UpstreamUrl": "https://github.com/Ahnd6474/Jakal-flow",
        "Branch": "main",
    }
    assert contract["Paths"]["RepoRoot"] == str(REPO_ROOT)
    assert contract["Paths"]["ManagedCheckout"] == str(REPO_ROOT / "managed" / "jakal-flow")
    assert contract["Paths"]["VenvRoot"] == str(REPO_ROOT / ".venv")
    assert contract["Paths"]["VenvPython"] == str(REPO_ROOT / ".venv" / "Scripts" / "python.exe")
    assert contract["Paths"]["DesktopRoot"] == str(REPO_ROOT / "managed" / "jakal-flow" / "desktop")
    assert contract["Runtime"]["ClearEnvironmentVariables"] == ["PYTHONPATH"]


def test_launcher_environment_exports_contract_values_and_clears_pythonpath() -> None:
    contract = load_contract()
    launcher_environment = load_launcher_environment()

    assert launcher_environment["JAKAL_FLOW_REPO_URL"] == contract["Repository"]["UpstreamUrl"]
    assert launcher_environment["JAKAL_FLOW_BRANCH"] == contract["Repository"]["Branch"]
    assert launcher_environment["JAKAL_FLOW_CHECKOUT"] == contract["Paths"]["ManagedCheckout"]
    assert launcher_environment["JAKAL_FLOW_PYTHON"] == contract["Paths"]["VenvPython"]
    assert launcher_environment["JAKAL_FLOW_DESKTOP"] == contract["Paths"]["DesktopRoot"]
    assert launcher_environment["PYTHONPATH"] is None
