Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ExperimentRepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-ExperimentConfigPath {
    param(
        [string]$ConfigPath = "config/experiment.example.json"
    )

    $repoRoot = Get-ExperimentRepoRoot
    return (Join-Path $repoRoot $ConfigPath)
}

function Read-ExperimentConfig {
    param(
        [string]$ConfigPath = "config/experiment.example.json"
    )

    $resolvedConfigPath = Get-ExperimentConfigPath -ConfigPath $ConfigPath
    if (-not (Test-Path -LiteralPath $resolvedConfigPath)) {
        throw "Experiment config not found: $resolvedConfigPath"
    }

    $config = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json
    foreach ($requiredKey in @("paths", "runtime", "prerequisites")) {
        if (-not $config.PSObject.Properties.Name.Contains($requiredKey)) {
            throw "Experiment config is missing required key '$requiredKey'."
        }
    }

    return $config
}

function Resolve-ExperimentPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path (Get-ExperimentRepoRoot) $Path)
}

function Get-ExperimentPaths {
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    $resolved = [ordered]@{}
    foreach ($property in $Config.paths.PSObject.Properties) {
        $resolved[$property.Name] = Resolve-ExperimentPath -Path $property.Value
    }

    return [pscustomobject]$resolved
}

function Get-ExperimentRuntimeDefaults {
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    return $Config.runtime
}

function Test-ExperimentPrerequisite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        $Definition
    )

    $commandInfo = Get-Command -Name $Definition.command -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        Name = $Name
        Command = $Definition.command
        Required = [bool]$Definition.required
        MinimumVersion = $Definition.minimumVersion
        IsAvailable = $null -ne $commandInfo
        CommandPath = if ($null -ne $commandInfo) { $commandInfo.Source } else { $null }
    }
}

function Assert-ExperimentPrerequisites {
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    $failures = @()
    foreach ($property in $Config.prerequisites.PSObject.Properties) {
        $result = Test-ExperimentPrerequisite -Name $property.Name -Definition $property.Value
        if ($result.Required -and -not $result.IsAvailable) {
            $failures += $result
        }
    }

    if ($failures.Count -gt 0) {
        $missing = $failures | ForEach-Object { "$($_.Name) [$($_.Command)]" }
        throw "Missing required prerequisites: $($missing -join ', ')"
    }
}
