import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def read_text(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


def assert_contains(source: str, *expected_fragments: str) -> None:
    for fragment in expected_fragments:
        assert fragment in source


def run_node(script: str) -> str:
    completed = subprocess.run(
        ["node", "--input-type=module", "-e", script],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def test_desktop_package_freezes_react_entrypoint_metadata():
    package_json = json.loads(read_text("desktop/package.json"))

    assert package_json["name"] == "jakal-workspace-desktop"
    assert package_json["type"] == "module"
    assert package_json["devDependencies"]["vite"] == "8.0.3"
    assert package_json["dependencies"]["react"] == "18.2.0"
    assert package_json["dependencies"]["react-dom"] == "18.2.0"


def test_routes_contract_exposes_the_four_stable_shell_surfaces():
    routes_source = read_text("desktop/src/app/routes/index.js")

    assert_contains(
        routes_source,
        'key: "projects"',
        'key: "tasks"',
        'key: "ideas"',
        'key: "files"',
        "export const AppShellRoutes",
        "routeFromHash",
    )


def test_snapshot_contract_freezes_cross_link_refs_and_seed_data():
    contracts_source = read_text("desktop/src/shared/contracts/index.js")

    assert_contains(
        contracts_source,
        "export const CrossLinkRefs",
        "export const WorkspaceSnapshot",
        "createSeedWorkspaceSnapshot",
        '"project-shell"',
        '"task-shell"',
        '"idea-shell"',
        '"file-shell"',
    )


def test_repository_adapter_is_seed_backed_and_migration_ready():
    storage_source = read_text("desktop/src/shared/storage/workspaceRepository.js")

    assert_contains(
        storage_source,
        "export class WorkspaceRepository",
        "migrations = []",
        "readSnapshot()",
        "writeSnapshot(updater)",
        "replaceSnapshot(snapshot)",
        "#migrateSnapshot",
        "createSeedWorkspaceSnapshot",
    )


def test_app_shell_mounts_routes_against_a_single_repository_boundary():
    app_source = read_text("desktop/src/App.jsx")
    main_source = read_text("desktop/src/main.jsx")

    assert_contains(main_source, "<App repository={workspaceRepository} />")
    assert_contains(
        app_source,
        "AppShellRoutes.map",
        "WorkspaceRepository",
        'href={route.path}',
        "repository.writeSnapshot",
    )


def test_tauri_entrypoint_exists_for_the_desktop_shell():
    tauri_source = read_text("src-tauri/src/main.rs")

    assert_contains(tauri_source, "tauri::Builder::default()", "generate_context!")


def test_repository_runtime_persists_and_updates_snapshot_shape():
    result = run_node(
        """
        import { createWorkspaceRepository } from "./desktop/src/shared/storage/workspaceRepository.js";

        const storage = {
          cache: new Map(),
          getItem(key) { return this.cache.has(key) ? this.cache.get(key) : null; },
          setItem(key, value) { this.cache.set(key, value); },
          removeItem(key) { this.cache.delete(key); },
        };

        const repository = createWorkspaceRepository({ storage });
        const seeded = repository.readSnapshot();
        const updated = repository.writeSnapshot((current) => ({
          ...current,
          projects: [
            ...current.projects,
            {
              id: "project-2",
              title: "Second project",
              summary: "Added during runtime verification.",
              links: { taskIds: [], ideaIds: [], fileIds: [] },
            },
          ],
        }));

        console.log(JSON.stringify({
          seededRoute: seeded.navigation.lastRoute,
          seededProjects: seeded.projects.length,
          updatedProjects: updated.projects.length,
          storedProjects: JSON.parse(storage.getItem("jakal.workspace.snapshot")).projects.length,
          schemaVersion: updated.meta.schemaVersion,
        }));
        """
    )
    payload = json.loads(result)

    assert payload == {
        "seededRoute": "projects",
        "seededProjects": 1,
        "updatedProjects": 2,
        "storedProjects": 2,
        "schemaVersion": 1,
    }


def test_routes_and_html_entrypoint_match_the_shell_contract():
    result = run_node(
        """
        import { AppShellRoutes, routeFromHash } from "./desktop/src/app/routes/index.js";

        console.log(JSON.stringify({
          routeKeys: AppShellRoutes.map((route) => route.key),
          filesHash: routeFromHash("#/files"),
          fallbackHash: routeFromHash("#/missing"),
        }));
        """
    )
    payload = json.loads(result)
    index_html = read_text("desktop/index.html")

    assert payload == {
        "routeKeys": ["projects", "tasks", "ideas", "files"],
        "filesHash": "files",
        "fallbackHash": "projects",
    }
    assert '<div id="root"></div>' in index_html
    assert 'src="/src/main.jsx"' in index_html
