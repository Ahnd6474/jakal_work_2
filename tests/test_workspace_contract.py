import json
import shutil
import subprocess
import uuid
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = REPO_ROOT / "config" / "jakal-flow-target.json"
HELPER_PATH = REPO_ROOT / "scripts" / "lib" / "TestWorkspace.ps1"


def run_powershell(script: str) -> str:
    completed = subprocess.run(
        ["powershell", "-NoProfile", "-Command", script],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def test_contract_config_exposes_managed_workspace_surface() -> None:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))

    assert contract["workspace"] == {
        "root": "workspace",
        "managedCheckout": "workspace/jakal-flow",
    }
    assert contract["artifacts"] == {"root": "artifacts"}
    assert contract["entrypoints"] == {
        "bootstrap": "scripts/bootstrap.ps1",
        "test-backend": "scripts/test-backend.ps1",
        "test-desktop": "scripts/test-desktop.ps1",
        "test-all": "scripts/test-all.ps1",
    }
    assert contract["results"] == {
        "schemaVersion": 1,
        "stagesRoot": "artifacts/stages",
        "fileName": "result.json",
    }


def test_powershell_helper_resolves_layout_and_writes_stage_result() -> None:
    stage_name = f"pytest-contract-{uuid.uuid4().hex[:8]}"
    stage_directory = REPO_ROOT / "artifacts" / "stages" / stage_name

    try:
        layout_json = run_powershell(
            f"""
$ErrorActionPreference = 'Stop'
. '{HELPER_PATH}'
Get-TestWorkspaceLayout -RepoRoot '{REPO_ROOT}' | ConvertTo-Json -Depth 10 -Compress
""".strip()
        )
        layout = json.loads(layout_json)

        assert Path(layout["managedCheckoutRoot"]) == REPO_ROOT / "workspace" / "jakal-flow"
        assert Path(layout["artifactsRoot"]) == REPO_ROOT / "artifacts"
        assert Path(layout["stagesRoot"]) == REPO_ROOT / "artifacts" / "stages"
        assert layout["resultSchema"] == {"schemaVersion": 1, "fileName": "result.json"}

        result_json = run_powershell(
            f"""
$ErrorActionPreference = 'Stop'
. '{HELPER_PATH}'
Write-TestWorkspaceStageResult -RepoRoot '{REPO_ROOT}' -StageName '{stage_name}' -Status 'passed' -Summary 'contract smoke test' -Details @{{ source = 'pytest' }} | ConvertTo-Json -Depth 10 -Compress
""".strip()
        )
        result = json.loads(result_json)

        result_path = stage_directory / "result.json"
        on_disk = json.loads(result_path.read_text(encoding="utf-8"))

        assert result["schemaVersion"] == 1
        assert result["stage"] == stage_name
        assert result["status"] == "passed"
        assert result["summary"] == "contract smoke test"
        assert Path(result["paths"]["resultFile"]) == result_path
        assert on_disk == result
    finally:
        shutil.rmtree(stage_directory, ignore_errors=True)
