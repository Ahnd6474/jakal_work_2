<#
"""Centralize the local Jakal-flow environment contract. Resolve the managed upstream checkout, branch, project virtualenv, desktop path, and launcher commands from this layer so every setup, run, and verification script targets the same source tree and never falls back to a globally installed `jakal_flow` package."""
#>

$script:JakalFlowContract = $null

function Get-JakalFlowContract {
    [CmdletBinding()]
    param()

    if ($null -ne $script:JakalFlowContract) {
        return $script:JakalFlowContract
    }

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $configPath = Join-Path $repoRoot 'config/jakal-flow.paths.psd1'
    $rawContract = Import-PowerShellDataFile -Path $configPath

    $managedCheckout = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $rawContract.Repository.ManagedCheckoutRelativePath))
    $venvRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $rawContract.Runtime.VenvRelativePath))
    $venvPython = [System.IO.Path]::GetFullPath((Join-Path $venvRoot 'Scripts\python.exe'))
    $desktopRoot = [System.IO.Path]::GetFullPath((Join-Path $managedCheckout $rawContract.Runtime.DesktopRelativePath))

    $launcherEnvironment = [ordered]@{
        $rawContract.Runtime.LauncherVariableNames.RepoUrl = $rawContract.Repository.UpstreamUrl
        $rawContract.Runtime.LauncherVariableNames.Branch = $rawContract.Repository.Branch
        $rawContract.Runtime.LauncherVariableNames.Checkout = $managedCheckout
        $rawContract.Runtime.LauncherVariableNames.Python = $venvPython
        $rawContract.Runtime.LauncherVariableNames.Desktop = $desktopRoot
    }

    foreach ($variableName in $rawContract.Runtime.ClearEnvironmentVariables) {
        $launcherEnvironment[$variableName] = $null
    }

    $script:JakalFlowContract = [ordered]@{
        Docstring = $rawContract.ContractDocstring
        Repository = [ordered]@{
            UpstreamUrl = $rawContract.Repository.UpstreamUrl
            Branch = $rawContract.Repository.Branch
        }
        Paths = [ordered]@{
            RepoRoot = $repoRoot
            ManagedCheckout = $managedCheckout
            VenvRoot = $venvRoot
            VenvPython = $venvPython
            DesktopRoot = $desktopRoot
        }
        Runtime = [ordered]@{
            ClearEnvironmentVariables = @($rawContract.Runtime.ClearEnvironmentVariables)
            LauncherVariableNames = [ordered]@{
                RepoUrl = $rawContract.Runtime.LauncherVariableNames.RepoUrl
                Branch = $rawContract.Runtime.LauncherVariableNames.Branch
                Checkout = $rawContract.Runtime.LauncherVariableNames.Checkout
                Python = $rawContract.Runtime.LauncherVariableNames.Python
                Desktop = $rawContract.Runtime.LauncherVariableNames.Desktop
            }
        }
        Launcher = [ordered]@{
            Environment = $launcherEnvironment
            Python = [ordered]@{
                FilePath = $venvPython
                WorkingDirectory = $managedCheckout
                Environment = $launcherEnvironment
            }
            Desktop = [ordered]@{
                WorkingDirectory = $desktopRoot
                Environment = $launcherEnvironment
            }
        }
    }

    return $script:JakalFlowContract
}

function Get-JakalFlowLauncherEnvironment {
    [CmdletBinding()]
    param(
        $Contract = (Get-JakalFlowContract)
    )

    $environment = [ordered]@{}
    foreach ($entry in $Contract.Launcher.Environment.GetEnumerator()) {
        $environment[$entry.Key] = $entry.Value
    }

    return $environment
}

function Invoke-JakalFlowPython {
    [CmdletBinding()]
    param(
        [string] $WorkingDirectory,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $ArgumentList
    )

    $contract = Get-JakalFlowContract
    $launcher = $contract.Launcher.Python
    $environment = Get-JakalFlowLauncherEnvironment -Contract $contract

    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = $launcher.WorkingDirectory
    }

    if (-not (Test-Path -Path $launcher.FilePath)) {
        throw "Configured Jakal-flow Python was not found at '$($launcher.FilePath)'."
    }

    $previousEnvironment = @{}
    foreach ($entry in $environment.GetEnumerator()) {
        $name = [string] $entry.Key
        if (Test-Path -Path "Env:$name") {
            $previousEnvironment[$name] = (Get-Item -Path "Env:$name").Value
        }
        else {
            $previousEnvironment[$name] = $null
        }
    }

    $originalLocation = Get-Location

    try {
        foreach ($entry in $environment.GetEnumerator()) {
            $name = [string] $entry.Key
            if ($null -eq $entry.Value) {
                Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -Path "Env:$name" -Value ([string] $entry.Value)
            }
        }

        Set-Location -Path $WorkingDirectory
        & $launcher.FilePath @ArgumentList
        return $LASTEXITCODE
    }
    finally {
        Set-Location -Path $originalLocation
        foreach ($entry in $environment.GetEnumerator()) {
            $name = [string] $entry.Key
            if ($null -eq $previousEnvironment[$name]) {
                Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -Path "Env:$name" -Value ([string] $previousEnvironment[$name])
            }
        }
    }
}
