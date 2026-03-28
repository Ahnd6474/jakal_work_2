import json
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = REPO_ROOT / "config" / "jakal-flow-target.json"
HELPER_PATH = REPO_ROOT / "scripts" / "lib" / "TestWorkspace.ps1"
DOCSTRING = (
    "Managed Jakal-flow test workspace contract: keep the upstream checkout under "
    "`workspace/jakal-flow`, keep generated logs and summaries under `artifacts/`, "
    "expose stable entrypoints `bootstrap`, `test-backend`, `test-desktop`, and "
    "`test-all`, and report stage results through one shared schema without mutating "
    "upstream source files except dependency installs inside the managed checkout."
)


def run_powershell(script: str) -> str:
    completed = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr or completed.stdout
    return completed.stdout.strip()


def test_contract_config_freezes_roots_entrypoints_and_result_schema() -> None:
    contract = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))

    assert contract["docstring"] == DOCSTRING
    assert contract["schemaVersion"] == 1
    assert contract["workspaceRoot"] == "workspace"
    assert contract["managedCheckoutRoot"] == "workspace/jakal-flow"
    assert contract["artifactsRoot"] == "artifacts"
    assert contract["entrypoints"] == {
        "bootstrap": "scripts/bootstrap.ps1",
        "test-backend": "scripts/test-backend.ps1",
        "test-desktop": "scripts/test-desktop.ps1",
        "test-all": "scripts/test-all.ps1",
    }
    assert contract["stageResult"] == {
        "version": 1,
        "fileName": "result.json",
        "requiredFields": [
            "schemaVersion",
            "stage",
            "status",
            "timestampUtc",
            "managedCheckoutRoot",
            "stageArtifactRoot",
            "warnings",
            "errors",
            "data",
        ],
    }


def test_gitignore_ignores_generated_workspace_and_artifacts_roots() -> None:
    lines = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()

    assert "/workspace/" in lines
    assert "/artifacts/" in lines


def test_helper_resolves_layout_and_writes_stage_result() -> None:
    stage_name = "pytest-contract"
    stage_dir = REPO_ROOT / "artifacts" / stage_name
    if stage_dir.exists():
        shutil.rmtree(stage_dir)

    helper_literal = str(HELPER_PATH).replace("'", "''")
    script = f"""
. '{helper_literal}'
$layout = Get-TestWorkspaceLayout
$result = Write-TestStageResult -StageName '{stage_name}' -Status 'passed' -Data @{{ note = 'contract-test' }}
[pscustomobject]@{{
    ManagedCheckoutRootRelative = $layout.ManagedCheckoutRootRelative
    ArtifactsRootRelative = $layout.ArtifactsRootRelative
    Result = $result
}} | ConvertTo-Json -Depth 20 -Compress
"""

    try:
        payload = json.loads(run_powershell(script))
        written_path = REPO_ROOT / Path(payload["Result"]["ResultPathRelative"])
        written_result = json.loads(written_path.read_text(encoding="utf-8"))

        assert payload["ManagedCheckoutRootRelative"] == "workspace/jakal-flow"
        assert payload["ArtifactsRootRelative"] == "artifacts"
        assert payload["Result"]["StageArtifactRootRelative"] == f"artifacts/{stage_name}"
        assert payload["Result"]["ResultPathRelative"] == f"artifacts/{stage_name}/result.json"
        assert Path(payload["Result"]["ResultPath"]).resolve() == written_path.resolve()

        assert written_result == {
            "schemaVersion": 1,
            "stage": stage_name,
            "status": "passed",
            "timestampUtc": written_result["timestampUtc"],
            "managedCheckoutRoot": "workspace/jakal-flow",
            "stageArtifactRoot": f"artifacts/{stage_name}",
            "warnings": [],
            "errors": [],
            "data": {"note": "contract-test"},
        }
    finally:
        if stage_dir.exists():
            shutil.rmtree(stage_dir)
