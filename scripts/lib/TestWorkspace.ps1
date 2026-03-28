<#
Managed Jakal-flow test workspace contract: keep the upstream checkout under `workspace/jakal-flow`, keep generated logs and summaries under `artifacts/`, expose stable entrypoints `bootstrap`, `test-backend`, `test-desktop`, and `test-all`, and report stage results through one shared schema without mutating upstream source files except dependency installs inside the managed checkout.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Join-TestWorkspacePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $RelativePath))
}

function Get-TestWorkspaceRepoRoot {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )

    if ($RepoRoot) {
        return [System.IO.Path]::GetFullPath($RepoRoot)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..\..'))
}

function Get-TestWorkspaceContract {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )

    $resolvedRepoRoot = Get-TestWorkspaceRepoRoot -RepoRoot $RepoRoot
    $contractPath = Join-TestWorkspacePath -BasePath $resolvedRepoRoot -RelativePath 'config/jakal-flow-target.json'

    if (-not (Test-Path -LiteralPath $contractPath)) {
        throw "Managed workspace contract was not found at '$contractPath'."
    }

    return Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
}

function Get-TestWorkspaceLayout {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )

    $resolvedRepoRoot = Get-TestWorkspaceRepoRoot -RepoRoot $RepoRoot
    $contractPath = Join-TestWorkspacePath -BasePath $resolvedRepoRoot -RelativePath 'config/jakal-flow-target.json'
    $contract = Get-TestWorkspaceContract -RepoRoot $resolvedRepoRoot

    return [pscustomobject]@{
        repoRoot = $resolvedRepoRoot
        contractPath = $contractPath
        workspaceRoot = Join-TestWorkspacePath -BasePath $resolvedRepoRoot -RelativePath $contract.workspace.root
        managedCheckoutRoot = Join-TestWorkspacePath -BasePath $resolvedRepoRoot -RelativePath $contract.workspace.managedCheckout
        artifactsRoot = Join-TestWorkspacePath -BasePath $resolvedRepoRoot -RelativePath $contract.artifacts.root
        stagesRoot = Join-TestWorkspacePath -BasePath $resolvedRepoRoot -RelativePath $contract.results.stagesRoot
        entrypoints = [pscustomobject]@{
            bootstrap = Join-TestWorkspacePath -BasePath $resolvedRepoRoot -RelativePath $contract.entrypoints.bootstrap
            'test-backend' = Join-TestWorkspacePath -BasePath $resolvedRepoRoot -RelativePath $contract.entrypoints.'test-backend'
            'test-desktop' = Join-TestWorkspacePath -BasePath $resolvedRepoRoot -RelativePath $contract.entrypoints.'test-desktop'
            'test-all' = Join-TestWorkspacePath -BasePath $resolvedRepoRoot -RelativePath $contract.entrypoints.'test-all'
        }
        resultSchema = [pscustomobject]@{
            schemaVersion = $contract.results.schemaVersion
            fileName = $contract.results.fileName
        }
    }
}

function Get-TestWorkspaceStageDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StageName,

        [string]$RepoRoot,

        [switch]$Create
    )

    $layout = Get-TestWorkspaceLayout -RepoRoot $RepoRoot
    $stageDirectory = Join-TestWorkspacePath -BasePath $layout.stagesRoot -RelativePath $StageName

    if ($Create.IsPresent) {
        New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    }

    return $stageDirectory
}

function Write-TestWorkspaceStageResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StageName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Status,

        [string]$Summary = '',

        [object]$Details = $null,

        [hashtable]$Metadata = @{},

        [datetime]$StartedAt = (Get-Date),

        [datetime]$FinishedAt = (Get-Date),

        [string]$RepoRoot
    )

    $layout = Get-TestWorkspaceLayout -RepoRoot $RepoRoot
    $stageDirectory = Get-TestWorkspaceStageDirectory -StageName $StageName -RepoRoot $layout.repoRoot -Create
    $resultPath = Join-TestWorkspacePath -BasePath $stageDirectory -RelativePath $layout.resultSchema.fileName

    $payload = [ordered]@{
        schemaVersion = $layout.resultSchema.schemaVersion
        stage = $StageName
        status = $Status
        summary = $Summary
        details = $Details
        metadata = [pscustomobject]$Metadata
        startedAt = $StartedAt.ToUniversalTime().ToString('o')
        finishedAt = $FinishedAt.ToUniversalTime().ToString('o')
        paths = [ordered]@{
            stageDirectory = $stageDirectory
            resultFile = $resultPath
        }
    }

    $json = $payload | ConvertTo-Json -Depth 10
    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($resultPath, ($json + [Environment]::NewLine), $encoding)

    return [pscustomobject]$payload
}
