<#
    .SYNOPSIS
        Remove a specific Resource Group
	   
    .EXAMPLE
        ./Administration/Scripts/Remove-ResourceGroup.ps1 -ResourceGroup myRG
#>


Param(
    # Target Resource Group to be removed.
    [Parameter(Mandatory = $True)]
    [String] $ResourceGroup
)


### Initialization ###
$WorkingDirectory = $PSScriptRoot
Import-Module -Name "$($WorkingDirectory)/../../Resources/SharedScripts/AzureProjectFunctions.psm1"      -Force # (if module was updated)
$GeneralSettings = Connect-Azure -GeneralSettings "$($WorkingDirectory)/../../Settings/Settings.json"    
$resourceGroupsExcluded = @(
    "_Administration_Azure4StudentProjects",
    "_AppServicePlans",
    "NetworkWatcherRG"
)
if ($resourceGroupsExcluded -contains $ResourceGroup) {
    Throw "Resource group $ResourceGroup is on the whitelist and will therefore not be removed."
}
Get-AzResourceGroup -Name $ResourceGroup -ErrorVariable notPresent -ErrorAction SilentlyContinue
If ($notPresent) {
    # Validate existence of RG
    Throw "ResourceGroup $ResourceGroup does not exist."
}

### Confirm removal ###
$confirmation = Read-Host "Are you Sure You Want to remove ResourceGroup $($ResourceGroup)? [yes|no]"
if ($confirmation -ne 'yes') {
    Throw "Script aborted, nothing done."
}


### Remove Resource Group, Locks and Budgets ###
Get-AzResourceLock -ResourceGroupName $ResourceGroup | Remove-AzResourceLock
Remove-AzResourceGroup -Name $ResourceGroup -Force 
$budgets = Get-AzConsumptionBudget -ResourceGroupName $ResourceGroup
foreach ($budget in $budgets ) {
    write-host "Remove Budgets $($budget.Name)"
    Remove-AzConsumptionBudget -name $budget.Name  -ResourceGroupName $ResourceGroup
}        
