### Initialization ###
$WorkingDirectory = $PSScriptRoot
Import-Module -Name "$($WorkingDirectory)/../../Resources/SharedScripts/AzureProjectFunctions.psm1"      -Force # (if module was updated)
$GeneralSettings = Connect-Azure -GeneralSettings "$($WorkingDirectory)/../../Settings/Settings.json"    
$GeneralSettings

$confirmation = Read-Host "Are you Sure You Want To cleanup this subscription including, but not limited to, removing ALL RESOURCE GROUPS? [yesiwantthis|no]"

if ($confirmation -ne 'yesiwantthis') {
    Throw "Script aborted"
}
else {

    # Remove ALL ResourceGroups (except for _Administration_Azure4StudentProjects)
    $list = Get-AzResourceGroup | Where-Object ResourceGroupName -ne "_Administration_Azure4StudentProjects"
    foreach ($rg in $list) {
        write-host "Removing any locks"
        Get-AzResourceLock -ResourceGroupName $rg | Remove-AzResourceLock
        write-host "Removing $($rg.ResourceGroupName)"
        Remove-AzResourceGroup -Name $rg.ResourceGroupName -Force
    }
    
    # Remove all budgets except for the budget of this subscription in total that was created manually
    Get-AzConsumptionBudget | Where-Object Name -ne "Azure4StudentsSubscriptionTotal" | Remove-AzConsumptionBudget

    # Remove all Custom Azure Policies
    Get-AzPolicyDefinition -Custom | Remove-AzPolicyDefinition

    # Remove all Custom Roles
    Get-AzRoleDefinition -Custom | Remove-AzRoleDefinition
    
    # Remove all Policy Assignments on subscriptionlevel
    Get-azpolicyAssignment | Remove-AzPolicyAssignment -Scope "/subscriptions/$($GeneralSettings.Subscription)" -Confirm
    
}
