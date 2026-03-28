<#
Managed Jakal-flow test workspace contract: keep the upstream checkout under `workspace/jakal-flow`, keep generated logs and summaries under `artifacts/`, expose stable entrypoints `bootstrap`, `test-backend`, `test-desktop`, and `test-all`, and report stage results through one shared schema without mutating upstream source files except dependency installs inside the managed checkout.
#>

Set-StrictMode -Version Latest

function Get-TestWorkspaceRepositoryRoot {
    param(
        [string]$StartDirectory = $PSScriptRoot
    )

    $resolvedStartDirectory = (Resolve-Path -LiteralPath $StartDirectory).Path
    $current = Get-Item -LiteralPath $resolvedStartDirectory
    while ($null -ne $current) {
        $contractPath = Join-Path $current.FullName "config/jakal-flow-target.json"
        if (Test-Path -LiteralPath $contractPath) {
            return $current.FullName
        }

        $current = $current.Parent
    }

    throw "Unable to locate repository root from '$StartDirectory'."
}

function Get-TestWorkspaceContract {
    param(
        [string]$RepositoryRoot = $(Get-TestWorkspaceRepositoryRoot)
    )

    $contractPath = Join-Path $RepositoryRoot "config/jakal-flow-target.json"
    if (-not (Test-Path -LiteralPath $contractPath)) {
        throw "Workspace contract file not found at '$contractPath'."
    }

    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    [pscustomobject]@{
        ContractPath         = $contractPath
        RepositoryRoot       = $RepositoryRoot
        WorkspaceRoot        = Join-Path $RepositoryRoot $contract.paths.workspaceRoot
        ManagedCheckoutRoot  = Join-Path $RepositoryRoot $contract.paths.managedCheckoutRoot
        ArtifactsRoot        = Join-Path $RepositoryRoot $contract.paths.artifactsRoot
        StageResultsRoot     = Join-Path $RepositoryRoot $contract.paths.stageResultsRoot
        Entrypoints          = $contract.entrypoints
        ResultSchema         = $contract.resultSchema
        Contract             = $contract
    }
}

function Resolve-TestWorkspacePath {
    param(
        [ValidateSet("workspaceRoot", "managedCheckoutRoot", "artifactsRoot", "stageResultsRoot", "stageResult")]
        [string]$Name,
        [string]$StageName,
        [string]$ChildPath,
        [string]$RepositoryRoot = $(Get-TestWorkspaceRepositoryRoot)
    )

    $contract = Get-TestWorkspaceContract -RepositoryRoot $RepositoryRoot
    switch ($Name) {
        "workspaceRoot" { $path = $contract.WorkspaceRoot }
        "managedCheckoutRoot" { $path = $contract.ManagedCheckoutRoot }
        "artifactsRoot" { $path = $contract.ArtifactsRoot }
        "stageResultsRoot" { $path = $contract.StageResultsRoot }
        "stageResult" {
            if ([string]::IsNullOrWhiteSpace($StageName)) {
                throw "StageName is required when resolving a stage result path."
            }

            $path = Join-Path (Join-Path $contract.StageResultsRoot $StageName) "result.json"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ChildPath)) {
        return Join-Path $path $ChildPath
    }

    return $path
}

function New-TestStageResult {
    param(
        [Parameter(Mandatory)]
        [string]$StageName,
        [Parameter(Mandatory)]
        [ValidateSet("passed", "failed", "skipped", "blocked", "unknown")]
        [string]$Status,
        [string]$Summary = "",
        [hashtable]$Details = @{},
        [datetime]$StartedAt = (Get-Date),
        [datetime]$FinishedAt = (Get-Date),
        [string]$RepositoryRoot = $(Get-TestWorkspaceRepositoryRoot)
    )

    $contract = Get-TestWorkspaceContract -RepositoryRoot $RepositoryRoot
    $resultPath = Resolve-TestWorkspacePath -Name stageResult -StageName $StageName -RepositoryRoot $RepositoryRoot

    [ordered]@{
        schemaVersion = $contract.ResultSchema.version
        stage         = $StageName
        status        = $Status
        summary       = $Summary
        timestamps    = [ordered]@{
            startedAt  = $StartedAt.ToUniversalTime().ToString("o")
            finishedAt = $FinishedAt.ToUniversalTime().ToString("o")
        }
        paths         = [ordered]@{
            repositoryRoot      = $contract.RepositoryRoot
            managedCheckoutRoot = $contract.ManagedCheckoutRoot
            artifactsRoot       = $contract.ArtifactsRoot
            result              = $resultPath
        }
        details       = if ($null -eq $Details) { @{} } else { $Details }
    }
}

function Write-TestStageResult {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$InputObject,
        [string]$RepositoryRoot = $(Get-TestWorkspaceRepositoryRoot)
    )

    if (-not $InputObject.Contains("stage")) {
        throw "InputObject must contain a 'stage' field."
    }

    $resultPath = Resolve-TestWorkspacePath -Name stageResult -StageName $InputObject.stage -RepositoryRoot $RepositoryRoot
    $resultDirectory = Split-Path -Parent $resultPath
    New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null

    $InputObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding utf8
    return $resultPath
}
