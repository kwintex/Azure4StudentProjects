<#
    .SYNOPSIS
        Update the Policies defined in the template to the Resource Group provided.

    .DESCRIPTION
        Run this script to renew policies already provided to a ResourceGroup, after adding or modifying a policy. 
        Functionality:
        - Create Custom Policy if it is not available in Azure.
        - Modify Custom Policy if it already exists in Azure (becomes active for every existing ResourceGroup)
        - Assign Custom and Built-In Policies to the ResourceGroup.
        Note: Already assigned policies are not unassigned, so if you removed a policy from the template, unassign the policy by hand in the portal, or (more drastic): remove the ResourceGroup and create a new one.

    .EXAMPLE
        ./Administration/Scripts/Update-Policy.ps1 -GroupName Team1 -Template simpleVM

	.Notes
		AUTHOR(s): Rienk van der Ploeg (HU)
		KEYWORDS:  Azure Educate Higher Education Project
#>

Param (
    # GroupName where this policies should be assigned to
    [Parameter(Mandatory = $true)]  
    [ValidateNotNullOrEmpty()]
    [string]$GroupName,

    # Template (=ProjectDefinition)
    [Parameter(Mandatory = $true)]  
    [ValidateNotNullOrEmpty()]
    [string]$Template
)


### Initialization ###
$WorkingDirectory = $PSScriptRoot
$Logfile = "$($WorkingDirectory)/../../Logs/AzureProjectAdministration.log" # Log Path and File
$ResourceGroup = "$($Template)-$($GroupName)" 
Import-Module -Name "$($WorkingDirectory)/../../Resources/SharedScripts/AzureProjectFunctions.psm1"      -Force # (if module was updated)
$GeneralSettings = Connect-Azure -GeneralSettings "$($WorkingDirectory)/../../Settings/Settings.json"    
$GeneralSettings

Write-Host "Reapplying policies to your ResourceGroup $ResourceGroup"
Write-Host "Add/Modify of policies is supported, but Assigned Policies are not Removed automatically when you remove them from the template"


# Read Policy definitions in Project Definition
$CustomPolicyPath = "$($WorkingDirectory)/../../Resources/customPolicies/"  # Path to Custom Policy Definitions
$ProjectDefinitionPathFile = "$($WorkingDirectory)/../../Resources/ProjectDefinitions/$($Template).json"
If (Test-Path -Path "./Resources/ProjectDefinitions/$($Template).json") {
    $ProjectDefinition = Get-Content "./Resources/ProjectDefinitions/$($Template).json" | ConvertFrom-Json 
}
Else {
    Throw "Could not find Project Specific Definition File: $($ProjectDefinitionPathFile)."
}
$Policies = $ProjectDefinition.template.policies


### Define and Assign Policies ###
# Redefine all Custom policies and apply all policies on the ResourceGroup as defined in the Project Template
$Policies = $ProjectDefinition.template.policies
Set-Policy -Policies $Policies -CustomPolicyPath $CustomPolicyPath -SetCustomPolicyDefinition $True -Location $GeneralSettings.Location -ResourceGroup $ResourceGroup -Logfile $Logfile
