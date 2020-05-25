Function Write-Log {
    <#
    .SYNOPSIS
        Processing Log Messages.

    .DESCRIPTION
        Write logging information to a File, Stdout, or maybe to Azure itself in a later version.

    .EXAMPLE
        Write-Log -Message "Deploy initiated by $($Account)" -Destination ALL -Logfile $Logfile
    #>

    [CmdletBinding()]
    Param(
        # Select the loglevel
        [Parameter(Mandatory=$False)]
        [ValidateSet("DEBUG","INFO","WARN","ERROR")]
        [String]$Level = "INFO",

        # Your Log Message
        [Parameter(Mandatory=$True)]
        [string]$Message,

        # Your Log Processing Engine
        [Parameter(Mandatory=$False)]
        [ValidateSet("FILE","STDOUT","ALL")]
        [string]$Destination = "STDOUT",        

        # Log Path and File
        [Parameter(Mandatory=$False)]
        [string]$Logfile = "AzureProjects.log"
    )

    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $Line = "$Stamp $Level $Message"

    If ($Logfile -and (($Destination -eq "FILE") -or ($Destination -eq "ALL"))) {
        Add-Content $Logfile -Value $Line
    }
    If (($Destination -eq "STDOUT") -or ($Destination -eq "ALL")) {
        If ($Level -eq "ERROR") {
            # TODO: Is not STDOUT, but STDERR I'm afraid
            Write-Error "LOG> $Line"
        } else {
            Write-Output "LOG> $Line"
        }
        
    }
}




Function Connect-Azure {
    <#
    .SYNOPSIS
        Login to Azure if needed.

    .DESCRIPTION
        Check the Azure Context and Connect to Azure and Set Context if needed.

    .OUTPUTS
        A hashmap containing subscription, account, tenant and location will be returned.

    .EXAMPLE
        Connect-Azure -GeneralSettings $GeneralSettingsPathFile
    #>

    [CmdletBinding()]
    Param(
        # JSON-configuration File containing SubscriptionId, TenantId etc.
        [Parameter(Mandatory=$True)]
        [string]$GeneralSettingsPathFile       
    )

    $GeneralSettings = @{}

    If (Test-Path -Path $GeneralSettingsPathFile ) {
        $Settings = Get-Content $GeneralSettingsPathFile | ConvertFrom-Json 
        $GeneralSettings.Subscription = $Settings.general.subscription
        $GeneralSettings.Tenant = $Settings.general.tenant
        $GeneralSettings.Location = $Settings.general.location
        $GeneralSettings.SendGridAPIKey = $Settings.general.SendGridAPIKey
    } Else {
        Throw "Could not find General Settings File: $($GeneralSettingsPathFile)."
    }
    $Context = Get-AzContext 
    If ($GeneralSettings.Subscription) { 
        If ($context.Subscription.id -ne $GeneralSettings.Subscription) { 
            Try {  
                # Clearall, if needed: Clear-AzContext
                Connect-AzAccount -Tenant $GeneralSettings.Tenant -Subscription $GeneralSettings.Subscription -UseDeviceAuthentication
                Set-AzContext -SubscriptionId $GeneralSettings.Subscription -ErrorAction Stop
                $Context = Get-AzContext 
            } 
            catch {
                Throw $_
            }
        }
    } Else {
        Throw "No subscription and/or tenant provided in $GeneralSettingsPathFile?"
    }
    $GeneralSettings.Account = $Context.Account

    return $GeneralSettings
}







Function Set-Policy {
    <#
    .SYNOPSIS
        Assign the given Policies to the Resource Group provided.

    .DESCRIPTION
        Create Custom Policy if it is not available on Azure.
        Assign the Custom and Built-In Policies to the Resource Group provided.
        This function is designed to be idempotent

    .EXAMPLE
        Apply-Policy -Policies $Policies -CustomPolicyPath $CustomPolicyPath -Location "westeurope" -ResourceGroup $ResourceGroup -Logfile $Logfile
    #>

    [CmdletBinding()]
    param (
                # JSON object containing a list of policies, being part of the Project Definition Template, section "policies"
                [Parameter(Mandatory=$True)]
                [Array]$Policies,
        
                # Path to the directory containing your Custom Policies
                [Parameter(Mandatory=$False)]
                [string]$CustomPolicyPath = "./Resources/Policies/",

                # Update Custom Policy Definition after modification
                [Parameter(Mandatory=$False)]
                [bool]$SetCustomPolicyDefinition = $False,
        
                # Location of storage of the Custom Policy Definitions
                [Parameter(Mandatory=$False)]
                [string]$Location = "westeurope",    

                # Resource Group where this policies should be assigned to
                [Parameter(Mandatory=$True)]
                [string]$ResourceGroup,
        
                # Log Path and File
                [Parameter(Mandatory=$False)]
                [string]$Logfile = "AzureProjects.log"
    )
    
    foreach ($Policy in $Policies) { 
        If ($policy.type -eq "Custom") { 
            # Create a new (Custom) Policy definition if policy is not available on Azure
            $result = Get-AzPolicyDefinition -Custom | Where-Object name -like $policy.name
            If ([string]::IsNullOrEmpty($result)) {
                # Custom Policy does not exist, create it
                Write-Log -Level "INFO" -Message "Create new Policy Definition on azure. Policy: $($CustomPolicyPath)/$($policy.policyFile),  Parameters: $($CustomPolicyPath)/$($policy.parameterFile)." -Destination ALL -Logfile $Logfile
                New-AzPolicyDefinition `
                    -Name $policy.name `
                    -DisplayName $policy.name `
                    -Policy "$($CustomPolicyPath)/$($policy.policyFile)" `
                    -Parameter "$($CustomPolicyPath)/$($policy.parameterFile)" `
                    -Mode All
            } elseif ($SetCustomPolicyDefinition) {
                # Custom Policy exists but should be defined again, maybe you made a change?
                # Note: This new definition is valid for every existing resource-group, so be careful.
                Write-Log -Level "INFO" -Message "Modify Custom Policy Definition on azure. Policy: $($CustomPolicyPath)/$($policy.policyFile),  Parameters: $($CustomPolicyPath)/$($policy.parameterFile)." -Destination ALL -Logfile $Logfile
                Set-AzPolicyDefinition `
                -Name $policy.name `
                -DisplayName $policy.name `
                -Policy "$($CustomPolicyPath)/$($policy.policyFile)" `
                -Parameter "$($CustomPolicyPath)/$($policy.parameterFile)" `
                -Mode All
            }
        }
        # Assign all (Custom & Built-in) policies to the ResourceGroup
        $definition = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq $policy.name }
        If ([string]::IsNullOrEmpty($definition)) {
            Write-Log -Level "ERROR" -Message "Policy '$($policy.name)' does not exist in Projectdefinition $ProjectDefinitionPathFile" -Destination ALL -Logfile $Logfile
        }
        else {
            [hashtable]$Params = @{ }
            foreach ( $parameter in $Policy.parameters) { 
                $Params[$parameter.Name] = $parameter.Value
            }
            # if json-policy contains: "deployIfNotExists":
            # This resources can be put into a compliant state through Remediation via a newly generated managed identity:
            # https://docs.microsoft.com/nl-nl/azure/governance/policy/how-to/remediate-resources#how-remediation-security-works
            $policyName = $policy.name
            if ($policyName.Length -ge 63) { $policyName = $policyName.Substring(0, 63) } 
            if ($policy.deployIfNotExists) {
                New-AzPolicyAssignment -Name $policyName -PolicyDefinition $definition -Scope (Get-AzResourceGroup -Name $ResourceGroup).ResourceId -Location $Location -AssignIdentity -PolicyParameterObject $Params
            }
            else {
                New-AzPolicyAssignment -Name $policyName -PolicyDefinition $definition -Scope (Get-AzResourceGroup -Name $ResourceGroup).ResourceId -Location $Location -PolicyParameterObject $Params
            }
        }
    }





}