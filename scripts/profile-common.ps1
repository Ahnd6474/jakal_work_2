Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ExperimentRepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-ExperimentConfigPath {
    param(
        [string]$ConfigPath = "config/experiment.example.json"
    )

    if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
        return $ConfigPath
    }

    $repoRoot = Get-ExperimentRepoRoot
    return (Join-Path $repoRoot $ConfigPath)
}

function Assert-ExperimentRequiredKeys {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Context,

        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter(Mandatory = $true)]
        [string[]]$RequiredKeys
    )

    $propertyNames = @()
    if ($null -ne $Value) {
        $propertyNames = @($Value.PSObject.Properties.Name)
    }

    foreach ($requiredKey in $RequiredKeys) {
        if (-not $propertyNames.Contains($requiredKey)) {
            throw "$Context is missing required key '$requiredKey'."
        }
    }
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
    Assert-ExperimentRequiredKeys -Context "Experiment config" -Value $config -RequiredKeys @(
        "paths",
        "runtime",
        "entryScripts",
        "prerequisites"
    )

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

function Get-ExperimentEntryScripts {
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    $resolved = [ordered]@{}
    foreach ($property in $Config.entryScripts.PSObject.Properties) {
        $resolved[$property.Name] = Resolve-ExperimentPath -Path $property.Value
    }

    return [pscustomobject]$resolved
}

function Resolve-ExperimentProfilePath {
    param(
        [string]$ProfileName = "",
        [string]$ConfigPath = "config/experiment.example.json"
    )

    $config = Read-ExperimentConfig -ConfigPath $ConfigPath
    $paths = Get-ExperimentPaths -Config $config
    $profileReference = if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        $config.runtime.defaultProfile
    }
    else {
        $ProfileName
    }

    if ([string]::IsNullOrWhiteSpace($profileReference)) {
        throw "Experiment runtime.defaultProfile must be configured before resolving a profile."
    }

    if ([System.IO.Path]::IsPathRooted($profileReference)) {
        return $profileReference
    }

    $isRelativePath = $profileReference.Contains([System.IO.Path]::DirectorySeparatorChar) `
        -or $profileReference.Contains([System.IO.Path]::AltDirectorySeparatorChar) `
        -or $profileReference.EndsWith(".json")
    if ($isRelativePath) {
        return Resolve-ExperimentPath -Path $profileReference
    }

    return (Join-Path $paths.profilesRoot "$profileReference.json")
}

function Read-ExperimentProfile {
    param(
        [string]$ProfileName = "",
        [string]$ConfigPath = "config/experiment.example.json"
    )

    $resolvedProfilePath = Resolve-ExperimentProfilePath -ProfileName $ProfileName -ConfigPath $ConfigPath
    if (-not (Test-Path -LiteralPath $resolvedProfilePath)) {
        throw "Experiment profile not found: $resolvedProfilePath"
    }

    $profileData = Get-Content -LiteralPath $resolvedProfilePath -Raw | ConvertFrom-Json
    Assert-ExperimentRequiredKeys -Context "Experiment profile" -Value $profileData -RequiredKeys @(
        "id",
        "source",
        "target",
        "workspace",
        "environment",
        "prerequisites",
        "verification"
    )
    Assert-ExperimentRequiredKeys -Context "Experiment profile source" -Value $profileData.source -RequiredKeys @(
        "kind",
        "repositoryUrl",
        "defaultBranch",
        "checkoutPath"
    )
    Assert-ExperimentRequiredKeys -Context "Experiment profile target" -Value $profileData.target -RequiredKeys @(
        "kind",
        "repositoryPath"
    )
    Assert-ExperimentRequiredKeys -Context "Experiment profile workspace" -Value $profileData.workspace -RequiredKeys @(
        "path"
    )
    Assert-ExperimentRequiredKeys -Context "Experiment profile environment" -Value $profileData.environment -RequiredKeys @(
        "required",
        "optional"
    )
    Assert-ExperimentRequiredKeys -Context "Experiment profile prerequisites" -Value $profileData.prerequisites -RequiredKeys @(
        "overlays"
    )
    Assert-ExperimentRequiredKeys -Context "Experiment profile verification" -Value $profileData.verification -RequiredKeys @(
        "phases"
    )

    return $profileData
}

function Normalize-ExperimentProfile {
    <#
    """Normalize a declarative experiment profile for either fixture or remote targets into immutable metadata: source checkout, mutable target repo path, workspace path, environment requirements, prerequisite overlays, and ordered verification phases. This helper defines discovery and validation only; downstream scripts perform cloning, installation, and verification without changing the profile shape."""
    #>
    param(
        [string]$ProfileName = "",
        [string]$ConfigPath = "config/experiment.example.json"
    )

    $config = Read-ExperimentConfig -ConfigPath $ConfigPath
    $entryScripts = Get-ExperimentEntryScripts -Config $config
    $profileData = Read-ExperimentProfile -ProfileName $ProfileName -ConfigPath $ConfigPath
    $repoRoot = Get-ExperimentRepoRoot

    $requiredEnvironment = @($profileData.environment.required)
    $optionalEnvironment = @($profileData.environment.optional)
    $prerequisiteOverlays = [ordered]@{}
    foreach ($property in $profileData.prerequisites.overlays.PSObject.Properties) {
        $prerequisiteOverlays[$property.Name] = $property.Value
    }

    $normalizedPhases = @()
    foreach ($phase in @($profileData.verification.phases)) {
        Assert-ExperimentRequiredKeys -Context "Verification phase" -Value $phase -RequiredKeys @("id")

        $hasEntryScript = $phase.PSObject.Properties.Name.Contains("entryScript") -and -not [string]::IsNullOrWhiteSpace($phase.entryScript)
        $hasCommand = $phase.PSObject.Properties.Name.Contains("command") -and -not [string]::IsNullOrWhiteSpace($phase.command)
        if (-not $hasEntryScript -and -not $hasCommand) {
            throw "Verification phase '$($phase.id)' must define either entryScript or command."
        }

        $resolvedWorkingDirectory = if ($phase.PSObject.Properties.Name.Contains("workingDirectory") -and -not [string]::IsNullOrWhiteSpace($phase.workingDirectory)) {
            Resolve-ExperimentPath -Path $phase.workingDirectory
        }
        elseif ($hasEntryScript) {
            $repoRoot
        }
        else {
            throw "Verification phase '$($phase.id)' must set workingDirectory for direct commands."
        }

        $resolvedScriptPath = $null
        $phaseKind = if ($hasEntryScript) { "entryScript" } else { "command" }
        if ($hasEntryScript) {
            if (-not $entryScripts.PSObject.Properties.Name.Contains($phase.entryScript)) {
                throw "Verification phase '$($phase.id)' references unknown entry script '$($phase.entryScript)'."
            }

            $resolvedScriptPath = $entryScripts.$($phase.entryScript)
        }

        $arguments = if ($phase.PSObject.Properties.Name.Contains("args")) {
            @($phase.args)
        }
        else {
            @()
        }

        $normalizedPhases += [pscustomobject]@{
            Id = $phase.id
            Kind = $phaseKind
            Description = if ($phase.PSObject.Properties.Name.Contains("description")) { $phase.description } else { $null }
            EntryScriptName = if ($hasEntryScript) { $phase.entryScript } else { $null }
            ScriptPath = $resolvedScriptPath
            Command = if ($hasCommand) { $phase.command } else { $null }
            Arguments = $arguments
            WorkingDirectory = $resolvedWorkingDirectory
            TimeoutSeconds = if ($phase.PSObject.Properties.Name.Contains("timeoutSeconds")) { [int]$phase.timeoutSeconds } else { $null }
        }
    }

    $resolvedSourceCheckoutPath = Resolve-ExperimentPath -Path $profileData.source.checkoutPath
    $resolvedTargetRepositoryPath = Resolve-ExperimentPath -Path $profileData.target.repositoryPath
    $resolvedWorkspacePath = Resolve-ExperimentPath -Path $profileData.workspace.path

    return [pscustomobject]@{
        Id = $profileData.id
        DisplayName = if ($profileData.PSObject.Properties.Name.Contains("displayName")) { $profileData.displayName } else { $profileData.id }
        Description = if ($profileData.PSObject.Properties.Name.Contains("description")) { $profileData.description } else { $null }
        ProfilePath = Resolve-ExperimentProfilePath -ProfileName $ProfileName -ConfigPath $ConfigPath
        Source = [pscustomobject]@{
            Kind = $profileData.source.kind
            RepositoryUrl = $profileData.source.repositoryUrl
            DefaultBranch = $profileData.source.defaultBranch
            CheckoutPath = $resolvedSourceCheckoutPath
        }
        SourceCheckoutPath = $resolvedSourceCheckoutPath
        Target = [pscustomobject]@{
            Kind = $profileData.target.kind
            RepositoryPath = $resolvedTargetRepositoryPath
        }
        TargetRepositoryPath = $resolvedTargetRepositoryPath
        WorkspacePath = $resolvedWorkspacePath
        Environment = [pscustomobject]@{
            Required = $requiredEnvironment
            Optional = $optionalEnvironment
        }
        RequiredEnvironmentVariables = $requiredEnvironment
        OptionalEnvironmentVariables = $optionalEnvironment
        PrerequisiteOverlays = [pscustomobject]$prerequisiteOverlays
        VerificationPhases = $normalizedPhases
        EntryScripts = $entryScripts
    }
}

function Test-ExperimentPrerequisite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        $Definition
    )

    $commandInfo = Get-Command -Name $Definition.command -ErrorAction SilentlyContinue
    $minimumVersion = if ($Definition.PSObject.Properties.Name.Contains("minimumVersion")) {
        $Definition.minimumVersion
    }
    else {
        $null
    }

    return [pscustomobject]@{
        Name = $Name
        Command = $Definition.command
        Required = [bool]$Definition.required
        MinimumVersion = $minimumVersion
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
