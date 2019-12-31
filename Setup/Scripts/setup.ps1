 <#
    .SYNOPSIS
        Setup of a new subscription.

    .DESCRIPTION
        Run this script after creating a new subscription for AzureForStudents.
  
    .EXAMPLE
        ./Administration/Scripts/setup.ps1

	.Notes
		AUTHOR(s): Rienk van der Ploeg (HU)
		KEYWORDS:  Azure Educate Higher Education Project
#>

### Initialization ###
$WorkingDirectory = $PSScriptRoot
Import-Module -Name "$($WorkingDirectory)/../../Resources/SharedScripts/AzureProjectFunctions.psm1"      -Force # (if module was updated)
$GeneralSettings = Connect-Azure -GeneralSettings "$($WorkingDirectory)/../../Settings/Settings.json"    
$GeneralSettings


### Add Resource Provider to create Budget Alerts ###
Register-AzResourceProvider -ProviderNamespace Microsoft.Insights


### Apply a number of Policies to your Subscription ###
$SubscriptionPolicies = @(
    "Azure subscriptions should have a log profile for Activity Log",
    "Azure Monitor log profile should collect logs for categories 'write,' 'delete,' and 'action'",
    "Azure Monitor solution 'Security and Audit' must be deployed",
    "Azure Monitor should collect activity logs from all regions",
    "Activity log should be retained for at least one year",
    "There should be more than one owner assigned to your subscription",
    "Email notification to subscription owner for high severity alerts should be enabled",
    "A security contact email address should be provided for your subscription",
    "Email notification for high severity alerts should be enabled",
    "MFA should be enabled on accounts with owner permissions on your subscription",
    "A security contact phone number should be provided for your subscription"
)
foreach ($Policy in $SubscriptionPolicies) {
    # Assign all (Custom & Built-in) policies to the ResourceGroup
    $definition = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq $Policy }
    If ([string]::IsNullOrEmpty($definition)) {
        Write-Error "Policy '$Policy' does not exist"
    }
    else {
        $policyName = $Policy
        if ($policyName.Length -ge 63) { $policyName = $policyName.Substring(0, 63) } 
        New-AzPolicyAssignment -Name $policyName -PolicyDefinition $definition -Scope "/subscriptions/$($GeneralSettings.Subscription)"
    }
}
