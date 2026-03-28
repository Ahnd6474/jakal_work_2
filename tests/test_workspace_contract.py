import json
import pathlib
import subprocess


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTRACT_PATH = REPO_ROOT / "config" / "jakal-flow-target.json"
HELPER_PATH = REPO_ROOT / "scripts" / "lib" / "TestWorkspace.ps1"


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
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def test_contract_declares_stable_roots_and_entrypoints():
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))

    assert contract["contractVersion"] == 1
    assert contract["paths"]["managedCheckoutRoot"] == "workspace/jakal-flow"
    assert contract["paths"]["artifactsRoot"] == "artifacts"
    assert contract["resultSchema"]["stageResultPathTemplate"] == "artifacts/stages/{stage}/result.json"
    assert contract["entrypoints"] == {
        "bootstrap": "scripts/bootstrap.ps1",
        "test-backend": "scripts/test-backend.ps1",
        "test-desktop": "scripts/test-desktop.ps1",
        "test-all": "scripts/test-all.ps1",
    }


def test_helper_resolves_contract_and_writes_stage_result():
    script = f"""
    . "{HELPER_PATH}"
    $contract = Get-TestWorkspaceContract -RepositoryRoot "{REPO_ROOT}"
    $result = New-TestStageResult -StageName "bootstrap" -Status "passed" -Summary "preflight ok" -RepositoryRoot "{REPO_ROOT}" -Details @{{ runner = "pytest" }}
    $resultPath = Write-TestStageResult -InputObject $result -RepositoryRoot "{REPO_ROOT}"
    [ordered]@{{
        managedCheckoutRoot = $contract.ManagedCheckoutRoot
        artifactsRoot = $contract.ArtifactsRoot
        resultPath = $resultPath
    }} | ConvertTo-Json -Compress
    """

    output = json.loads(run_powershell(script))
    result_path = pathlib.Path(output["resultPath"])
    written = json.loads(result_path.read_text(encoding="utf-8-sig"))

    assert pathlib.Path(output["managedCheckoutRoot"]) == REPO_ROOT / "workspace" / "jakal-flow"
    assert pathlib.Path(output["artifactsRoot"]) == REPO_ROOT / "artifacts"
    assert result_path == REPO_ROOT / "artifacts" / "stages" / "bootstrap" / "result.json"
    assert written["schemaVersion"] == 1
    assert written["stage"] == "bootstrap"
    assert written["status"] == "passed"
    assert written["summary"] == "preflight ok"
    assert written["details"] == {"runner": "pytest"}
