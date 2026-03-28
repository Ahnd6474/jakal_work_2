@{
    ContractDocstring = 'Centralize the local Jakal-flow environment contract. Resolve the managed upstream checkout, branch, project virtualenv, desktop path, and launcher commands from this layer so every setup, run, and verification script targets the same source tree and never falls back to a globally installed `jakal_flow` package.'
    Repository = @{
        UpstreamUrl = 'https://github.com/Ahnd6474/Jakal-flow'
        Branch = 'main'
        ManagedCheckoutRelativePath = 'managed\jakal-flow'
    }
    Runtime = @{
        VenvRelativePath = '.venv'
        DesktopRelativePath = 'desktop'
        ClearEnvironmentVariables = @(
            'PYTHONPATH'
        )
        LauncherVariableNames = @{
            RepoUrl = 'JAKAL_FLOW_REPO_URL'
            Branch = 'JAKAL_FLOW_BRANCH'
            Checkout = 'JAKAL_FLOW_CHECKOUT'
            Python = 'JAKAL_FLOW_PYTHON'
            Desktop = 'JAKAL_FLOW_DESKTOP'
        }
    }
}
