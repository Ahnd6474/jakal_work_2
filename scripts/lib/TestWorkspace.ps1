<#
Managed Jakal-flow test workspace contract: keep the upstream checkout under `workspace/jakal-flow`, keep generated logs and summaries under `artifacts/`, expose stable entrypoints `bootstrap`, `test-backend`, `test-desktop`, and `test-all`, and report stage results through one shared schema without mutating upstream source files except dependency installs inside the managed checkout.
#>

Set-StrictMode -Version Latest

function Get-TestWorkspaceRepositoryRoot {
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
}

function Join-TestWorkspaceContractPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Segment
    )

    $cleanSegments = @(
        foreach ($item in $Segment) {
            if ([string]::IsNullOrWhiteSpace($item)) {
                continue
            }

            $trimmed = $item.Trim() -replace "^[\\/]+", "" -replace "[\\/]+$", ""
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $trimmed
            }
        }
    )

    return ($cleanSegments -join "/")
}

function Resolve-TestWorkspaceContractPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [string]$RepositoryRoot = $(Get-TestWorkspaceRepositoryRoot)
    )

    $absolutePath = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $segments = $RelativePath -split "[\\/]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($segment in $segments) {
        $absolutePath = Join-Path $absolutePath $segment
    }

    return [System.IO.Path]::GetFullPath($absolutePath)
}

function Get-TestWorkspaceContract {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = $(Get-TestWorkspaceRepositoryRoot)
    )

    $configPath = Join-Path $RepositoryRoot "config/jakal-flow-target.json"
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Managed workspace contract file not found: $configPath"
    }

    return Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
}

function Get-TestWorkspaceLayout {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = $(Get-TestWorkspaceRepositoryRoot)
    )

    $contract = Get-TestWorkspaceContract -RepositoryRoot $RepositoryRoot

    return [pscustomobject]@{
        RepositoryRoot               = [System.IO.Path]::GetFullPath($RepositoryRoot)
        WorkspaceRoot                = Resolve-TestWorkspaceContractPath -RelativePath $contract.workspaceRoot -RepositoryRoot $RepositoryRoot
        WorkspaceRootRelative        = $contract.workspaceRoot
        ManagedCheckoutRoot          = Resolve-TestWorkspaceContractPath -RelativePath $contract.managedCheckoutRoot -RepositoryRoot $RepositoryRoot
        ManagedCheckoutRootRelative  = $contract.managedCheckoutRoot
        ArtifactsRoot                = Resolve-TestWorkspaceContractPath -RelativePath $contract.artifactsRoot -RepositoryRoot $RepositoryRoot
        ArtifactsRootRelative        = $contract.artifactsRoot
        Entrypoints                  = $contract.entrypoints
        StageResultFileName          = $contract.stageResult.fileName
        StageResultSchemaVersion     = [int]$contract.stageResult.version
        StageResultRequiredFields    = @($contract.stageResult.requiredFields)
    }
}

function Get-TestStagePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StageName,

        [string]$RepositoryRoot = $(Get-TestWorkspaceRepositoryRoot)
    )

    $contract = Get-TestWorkspaceContract -RepositoryRoot $RepositoryRoot
    $stageArtifactRootRelative = Join-TestWorkspaceContractPath -Segment @($contract.artifactsRoot, $StageName)
    $resultPathRelative = Join-TestWorkspaceContractPath -Segment @($stageArtifactRootRelative, $contract.stageResult.fileName)

    return [pscustomobject]@{
        Stage                    = $StageName
        StageArtifactRoot        = Resolve-TestWorkspaceContractPath -RelativePath $stageArtifactRootRelative -RepositoryRoot $RepositoryRoot
        StageArtifactRootRelative = $stageArtifactRootRelative
        ResultPath               = Resolve-TestWorkspaceContractPath -RelativePath $resultPathRelative -RepositoryRoot $RepositoryRoot
        ResultPathRelative       = $resultPathRelative
    }
}

function Write-TestStageResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StageName,

        [Parameter(Mandatory)]
        [ValidateSet("pending", "running", "passed", "failed", "skipped")]
        [string]$Status,

        [object]$Data = $null,

        [string[]]$Warnings = @(),

        [string[]]$Errors = @(),

        [string]$RepositoryRoot = $(Get-TestWorkspaceRepositoryRoot)
    )

    $contract = Get-TestWorkspaceContract -RepositoryRoot $RepositoryRoot
    $stagePaths = Get-TestStagePaths -StageName $StageName -RepositoryRoot $RepositoryRoot

    New-Item -ItemType Directory -Path $stagePaths.StageArtifactRoot -Force | Out-Null

    if ($null -eq $Data) {
        $Data = [ordered]@{}
    }

    $payload = [ordered]@{
        schemaVersion      = [int]$contract.stageResult.version
        stage              = $StageName
        status             = $Status
        timestampUtc       = [DateTime]::UtcNow.ToString("o")
        managedCheckoutRoot = $contract.managedCheckoutRoot
        stageArtifactRoot  = $stagePaths.StageArtifactRootRelative
        warnings           = @($Warnings)
        errors             = @($Errors)
        data               = $Data
    }

    $json = $payload | ConvertTo-Json -Depth 20
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($stagePaths.ResultPath, $json, $utf8NoBom)

    return [pscustomobject]@{
        Stage                    = $StageName
        StageArtifactRoot        = $stagePaths.StageArtifactRoot
        StageArtifactRootRelative = $stagePaths.StageArtifactRootRelative
        ResultPath               = $stagePaths.ResultPath
        ResultPathRelative       = $stagePaths.ResultPathRelative
        Payload                  = [pscustomobject]$payload
    }
}
