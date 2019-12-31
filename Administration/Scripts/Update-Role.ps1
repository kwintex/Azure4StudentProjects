 <#
    .SYNOPSIS
        Update the Role defined in the template provided.

    .DESCRIPTION
        Run this script after modifying or adding a custom Role.
        The custom roles are defined in the Resources\CustomRoles -directory .
        Functionality:
        - Create Custom Role if it is not available in Azure.
        - Modify Custom Role if it already exists in Azure (becomes active immediately for every ResourceGroup where users are assigned that role.)
        Note: No modifications are made in assignments of this role.
  
    .EXAMPLE
        ./Administration/Scripts/Update-Role.ps1 -Role simpleVM

	.Notes
		AUTHOR(s): Rienk van der Ploeg (HU)
		KEYWORDS:  Azure Educate Higher Education Project
#>

Param (
    # Rolename without path and without "-Role.json" suffix
    [Parameter(Mandatory = $true)]  
    [ValidateNotNullOrEmpty()]
    [string]$Role
)


### Initialization ###
$WorkingDirectory = $PSScriptRoot
$Logfile = "$($WorkingDirectory)/../../Logs/AzureProjectAdministration.log" # Log Path and File
Import-Module -Name "$($WorkingDirectory)/../../Resources/SharedScripts/AzureProjectFunctions.psm1"      -Force # (if module was updated)
$GeneralSettings = Connect-Azure -GeneralSettings "$($WorkingDirectory)/../../Settings/Settings.json"    
$GeneralSettings

$RoleDefinitionPathFile = "$($WorkingDirectory)/../../Resources/CustomRoles/$($Role)-Role.json" 
If (Test-Path -Path $RoleDefinitionPathFile ) {
    $NewRoleDefinition = Get-Content $RoleDefinitionPathFile | ConvertFrom-Json    # Load CustomRole for this project template
} Else {
    Throw "Could not find Project Role Definition File: $($RoleDefinitionPathFile)."
}
if ([string]::IsNullOrEmpty($NewRoleDefinition.Name)) {
    Throw "Role Definition File: $($RoleDefinitionPathFile) does not contain a name."
}


### Define and Assign Roles ###
# Create a new role, if this is the first time the role is needed, and assign it to the subscription.
$NewRoleDefinition.AssignableScopes += "/subscriptions/$($GeneralSettings.Subscription)"
$CurrentRoleDefinition = Get-AzRoleDefinition -Name $NewRoleDefinition.Name
if ([string]::IsNullOrEmpty($CurrentRoleDefinition)) {
    # Custom Role does not exist, create it
    New-AzRoleDefinition -Role $NewRoleDefinition 
    Write-Log -Message "Role $CurrentRoleDefinition Created" -Destination ALL -Logfile $Logfile
} else {
    # Custom Role exists but should be defined again, maybe you made a change?
    # Note: This new definition is valid for every existing user assigned the role to a resource-group, so be careful.
    $NewRoleDefinition.Id = $CurrentRoleDefinition.Id
    Set-AzRoleDefinition -Role $NewRoleDefinition 
    Write-Log -Message "Role $CurrentRoleDefinition Modified" -Destination ALL -Logfile $Logfile
}
