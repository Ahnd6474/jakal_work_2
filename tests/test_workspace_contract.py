import importlib
import sys
import tomllib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PYPROJECT_PATH = REPO_ROOT / "pyproject.toml"
PACKAGE_ROOT = REPO_ROOT / "src" / "jakal_flow"
DESKTOP_ROOT = REPO_ROOT / "desktop"
GITIGNORE_PATH = REPO_ROOT / ".gitignore"


def test_root_contract_freezes_canonical_surfaces():
    pyproject = tomllib.loads(PYPROJECT_PATH.read_text(encoding="utf-8"))
    gitignore_lines = GITIGNORE_PATH.read_text(encoding="utf-8").splitlines()

    assert PYPROJECT_PATH.is_file()
    assert PACKAGE_ROOT.is_dir()
    assert (PACKAGE_ROOT / "__init__.py").is_file()
    assert DESKTOP_ROOT.is_dir()
    assert (REPO_ROOT / "tests").is_dir()
    assert pyproject["project"]["name"] == "jakal-flow"
    assert pyproject["tool"]["setuptools"]["package-dir"] == {"": "src"}
    assert pyproject["tool"]["pytest"]["ini_options"]["testpaths"] == ["tests"]
    assert "_tmp_jakal_flow_remote/" in gitignore_lines


def test_package_stub_is_importable_from_root_src_layout():
    sys.path.insert(0, str(REPO_ROOT / "src"))
    try:
        package = importlib.import_module("jakal_flow")
    finally:
        sys.path.pop(0)

    assert package.__version__ == "0.0.0"
