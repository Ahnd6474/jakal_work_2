import json
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP_SCRIPT = REPO_ROOT / "scripts" / "bootstrap.ps1"
CHECK_PREREQS_SCRIPT = REPO_ROOT / "scripts" / "check-prereqs.ps1"
CLEAN_LOCAL_STATE_SCRIPT = REPO_ROOT / "scripts" / "clean-local-state.ps1"
GIT_EXE = shutil.which("git")
PYTHON_EXE = shutil.which("python") or sys.executable
TEST_PACKAGE_NAME = "bootstrap_sample_pkg"


def run_powershell(script_path: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script_path),
            *map(str, args),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )


def run_command(*args: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [*map(str, args)],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    )


def write_config(
    tmp_path: Path,
    *,
    git_command: str | None = None,
    python_command: str | None = None,
    python_minimum: str = "3.11",
    codex_command: str = "missing-codex",
) -> tuple[Path, Path]:
    local_root = tmp_path / ".local"
    config_path = tmp_path / "experiment.test.json"
    config = {
        "schemaVersion": 1,
        "paths": {
            "localRoot": str(local_root),
            "upstreamRoot": str(local_root / "upstream"),
            "upstreamCheckout": str(local_root / "upstream" / "jakal-flow"),
            "targetsRoot": str(local_root / "targets"),
            "workspaceRoot": str(local_root / "workspaces"),
            "logsRoot": str(local_root / "logs"),
            "profilesRoot": str(REPO_ROOT / "config" / "profiles"),
            "fixturesRoot": str(REPO_ROOT / "fixtures"),
        },
        "runtime": {
            "pythonCommand": python_command or PYTHON_EXE,
            "venvPath": str(local_root / "venv"),
            "defaultProfile": "jakal-flow-local",
            "shell": "powershell",
            "logLevel": "INFO",
        },
        "entryScripts": {
            "checkPrereqs": str(REPO_ROOT / "scripts" / "check-prereqs.ps1"),
            "bootstrap": str(REPO_ROOT / "scripts" / "bootstrap.ps1"),
            "cleanLocalState": str(REPO_ROOT / "scripts" / "clean-local-state.ps1"),
            "materializeTarget": str(REPO_ROOT / "scripts" / "materialize-target.ps1"),
            "invokeVerification": str(REPO_ROOT / "scripts" / "invoke-verification.ps1"),
        },
        "prerequisites": {
            "git": {
                "command": git_command or GIT_EXE,
                "required": True,
            },
            "python": {
                "command": python_command or PYTHON_EXE,
                "minimumVersion": python_minimum,
                "required": True,
            },
            "codex": {
                "command": codex_command,
                "required": False,
            },
        },
    }
    config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
    return config_path, local_root


def create_upstream_repo(tmp_path: Path) -> Path:
    if not GIT_EXE:
        raise AssertionError("git is required to prepare the local upstream test repository")

    repo_path = tmp_path / "upstream-source"
    package_path = repo_path / TEST_PACKAGE_NAME
    package_path.mkdir(parents=True)
    (repo_path / "pyproject.toml").write_text(
        "\n".join(
            [
                "[build-system]",
                'requires = ["setuptools>=69"]',
                'build-backend = "setuptools.build_meta"',
                "",
                "[project]",
                'name = "bootstrap-sample-pkg"',
                'version = "0.1.0"',
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    (package_path / "__init__.py").write_text('__version__ = "0.1.0"\n', encoding="utf-8")

    run_command(GIT_EXE, "init", "--initial-branch=main", cwd=repo_path)
    run_command(GIT_EXE, "add", ".", cwd=repo_path)
    run_command(
        GIT_EXE,
        "-c",
        "user.name=Test User",
        "-c",
        "user.email=test@example.com",
        "commit",
        "-m",
        "Initial commit",
        cwd=repo_path,
    )
    return repo_path


def update_upstream_repo(repo_path: Path, version: str) -> str:
    package_path = repo_path / TEST_PACKAGE_NAME / "__init__.py"
    package_path.write_text(f'__version__ = "{version}"\n', encoding="utf-8")
    run_command(GIT_EXE, "add", f"{TEST_PACKAGE_NAME}/__init__.py", cwd=repo_path)
    run_command(
        GIT_EXE,
        "-c",
        "user.name=Test User",
        "-c",
        "user.email=test@example.com",
        "commit",
        "-m",
        f"Release {version}",
        cwd=repo_path,
    )
    return run_command(GIT_EXE, "rev-parse", "HEAD", cwd=repo_path).stdout.strip()


def test_check_prereqs_reports_missing_required_and_optional_tools(tmp_path: Path):
    config_path, local_root = write_config(
        tmp_path,
        git_command="missing-git-command",
        codex_command="missing-codex-command",
    )

    result = run_powershell(CHECK_PREREQS_SCRIPT, "-ConfigPath", str(config_path))

    assert result.returncode != 0
    output = result.stdout + result.stderr
    assert "git" in output.lower()
    assert "missing-git-command" in output
    assert "codex" in output.lower()
    assert "missing-codex-command" in output
    assert not local_root.exists()


def test_check_prereqs_enforces_python_minimum_version(tmp_path: Path):
    config_path, _ = write_config(tmp_path, python_minimum="99.0")

    result = run_powershell(CHECK_PREREQS_SCRIPT, "-ConfigPath", str(config_path))

    assert result.returncode != 0
    output = result.stdout + result.stderr
    assert "python" in output.lower()
    assert "99.0" in output


def test_bootstrap_clones_refreshes_and_installs_editable_package(tmp_path: Path):
    upstream_repo = create_upstream_repo(tmp_path)
    config_path, local_root = write_config(tmp_path)

    first_run = run_powershell(
        BOOTSTRAP_SCRIPT,
        "-ConfigPath",
        str(config_path),
        "-UpstreamUrl",
        str(upstream_repo),
        "-Branch",
        "main",
    )

    assert first_run.returncode == 0, first_run.stdout + first_run.stderr

    checkout_path = local_root / "upstream" / "jakal-flow"
    venv_python = local_root / "venv" / "Scripts" / "python.exe"
    assert checkout_path.exists()
    assert venv_python.exists()

    import_path = run_command(
        venv_python,
        "-c",
        f"import pathlib, {TEST_PACKAGE_NAME}; print(pathlib.Path({TEST_PACKAGE_NAME}.__file__).resolve())",
        cwd=REPO_ROOT,
    ).stdout.strip()
    assert str(checkout_path.resolve()) in import_path

    original_head = run_command(GIT_EXE, "rev-parse", "HEAD", cwd=checkout_path).stdout.strip()
    junk_file = checkout_path / "junk.txt"
    junk_file.write_text("remove me\n", encoding="utf-8")
    updated_head = update_upstream_repo(upstream_repo, "0.2.0")

    second_run = run_powershell(
        BOOTSTRAP_SCRIPT,
        "-ConfigPath",
        str(config_path),
        "-UpstreamUrl",
        str(upstream_repo),
        "-Branch",
        "main",
    )

    assert second_run.returncode == 0, second_run.stdout + second_run.stderr
    assert not junk_file.exists()
    assert run_command(GIT_EXE, "rev-parse", "HEAD", cwd=checkout_path).stdout.strip() == updated_head
    assert updated_head != original_head

    package_version = run_command(
        venv_python,
        "-c",
        f"import {TEST_PACKAGE_NAME}; print({TEST_PACKAGE_NAME}.__version__)",
        cwd=REPO_ROOT,
    ).stdout.strip()
    assert package_version == "0.2.0"


def test_clean_local_state_removes_configured_local_root_idempotently(tmp_path: Path):
    config_path, local_root = write_config(tmp_path)
    workspace_file = local_root / "workspaces" / "session.txt"
    workspace_file.parent.mkdir(parents=True)
    workspace_file.write_text("temporary state\n", encoding="utf-8")

    first_run = run_powershell(CLEAN_LOCAL_STATE_SCRIPT, "-ConfigPath", str(config_path))
    second_run = run_powershell(CLEAN_LOCAL_STATE_SCRIPT, "-ConfigPath", str(config_path))

    assert first_run.returncode == 0, first_run.stdout + first_run.stderr
    assert second_run.returncode == 0, second_run.stdout + second_run.stderr
    assert not local_root.exists()
