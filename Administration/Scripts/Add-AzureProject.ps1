<#
	.SYNOPSIS
        Create a Resource Group accessible by specific users being able to create resources specified in a template.

	.DESCRIPTION
        Create a new Resource Group. The array of users supplied will be able to create resources within this resource group. 
        Available Templates: simpleVM, webApp (work in progress), cosmosDB.
        There are limitations as specified in a template. These limitations are related to:
        - Budget (user supplied)
        - Start date: is not yet supported, will be 'today'
        - End date (user supplied)
        - Combined Policies (defined in a template)
        - [Custom] Roles (defined in a template)
        - Azure limits on this subscription (part of the subscription).

    .EXAMPLE
        ./Administration/Scripts/Add-AzureProject.ps1 -Template simpleVM -StopDate 2020-05-01 -Users foo@bar.com

    .EXAMPLE
        ./Administration/Scripts/Add-AzureProject.ps1 -Template webApp -GroupName Team1 -Budget 2 -StopDate 2020-02-01 -Users foo@bar.com

	.EXAMPLE
        ./Administration/Scripts/Add-AzureProject.ps1 -Template simpleVM -GroupName Team1 -Budget 10 -StopDate 2020-05-01 -Users foo@bar.com,bar@foo.com

    .LINK
        https://dev.azure.com/rienkvanderploeg/Azure%20four%20Student%20Projects

	.Notes
		AUTHOR(s): Rienk van der Ploeg (HU), inspired by Mathieu Rietman (MS)
		KEYWORDS:  Azure Educate Higher Education Project
#>

Param (
    # The project template to be used for this project, must be a name selected from the list in ./Resources/Projects/<template>.json
    [Parameter(Mandatory = $true)]  
    [ValidateNotNullOrEmpty()]
    [string]$Template,

    # Group Suffix to [provide a name to the resource group, max length is 30 (only word characters and dash allowed), default is seconds since epoch. Should be unique.
    [Parameter(Mandatory = $false)]
    [ValidatePattern("^[\w-]{1,30}$")] 
    [string]$GroupName = [string][int][double]::Parse((Get-Date -UFormat %s)),

    # Budget amount for this project expressed in Euros with a limit of 500
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 500)]
    [int]$Budget = 10,

    # Start date of this project defined by yyyy-mm-dd, for example 2020-02-28
    #[Parameter(Mandatory = $false)]
    #[ValidatePattern("^20\d{2}-\d{2}-\d{2}$")] 
    #[string]$StartDate = (Get-Date -format "yyyy-MM-01"),

    # Stop date of this project defined by yyyy-mm-dd, for example 2020-03-28
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^20\d{2}-\d{2}-\d{2}$")] 
    [string]$StopDate,

    # List of users, validate e-mail addresses?
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^\w+([-+.']\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*$")] 
    [string[]]$Users
)



### Initialization ###
$ResourceGroup = "$($Template)-$($GroupName)"
$WorkingDirectory = $PSScriptRoot
Import-Module -Name "$($WorkingDirectory)/../../Resources/SharedScripts/AzureProjectFunctions.psm1" -Force # -Force if module was updated
$Logfile = "$($WorkingDirectory)/../../Logs/AzureProjectAdministration.log"
$ProjectDefinitionPathFile = "$($WorkingDirectory)/../../Resources/ProjectDefinitions/$($Template).json"# Project Definition File
$CustomPolicyPath = "$($WorkingDirectory)/../../Resources/customPolicies/"                              # Path to Custom Policy Definitions
$GeneralSettingsPathFile = "$($WorkingDirectory)/../../Settings/Settings.json"                          # Read Settings for this Subscription
$StartDate = (Get-Date -format "yyyy-MM-01")
$actionGroupRemoveResourceGroup = "RemoveRGBudgetAlert"                                                 # Name for action group create in the portal to remove the resource group


### Login if needed ###
$GeneralSettings = Connect-Azure -GeneralSettings $GeneralSettingsPathFile
Write-Log -Message "Deploy initiated by $($GeneralSettings.Account)" -Destination ALL -Logfile $Logfile


### Validations, going a step further than just checking using regexp ###
If ($StartDate -ge $StopDate) {
    # Validate Startdate
    Throw "Startdate should not be choosen after, or equal to the StopDate!"
}
Get-AzResourceGroup -Name $ResourceGroup -ErrorVariable notPresent -ErrorAction SilentlyContinue
If (! $notPresent) {
    # Validate existence of RG
    Throw "ResourceGroup $ResourceGroup already exists, try another groupname."
}
foreach ($User in $Users) {
    $result = Get-AzADUser -Mail $User -ErrorAction Stop
    if ([string]::IsNullOrEmpty($result)) {
        Throw "User $User does not exist in AD."
    }
}
$result = Get-AzTag -Detailed | Where-Object Name -eq GroupName
if (! [string]::IsNullOrEmpty($result)) {
    # Preventing error in empty subscription
    $result = (Get-AzTag -Detailed | Where-Object Name -eq GroupName).Values.name.Contains($GroupName)
    If ($result) {
        Throw "Groupname $Groupname already exists in this subscription."
    }
}



### Read all json-templates ###
# Read Project Definition
If (Test-Path -Path $ProjectDefinitionPathFile ) {
    $ProjectDefinition = Get-Content $ProjectDefinitionPathFile | ConvertFrom-Json 
    Write-Log -Message "Using Project Definition: $($ProjectDefinition.template.name)" -Destination ALL -Logfile $Logfile
    $Roles = $ProjectDefinition.template.Roles
}
Else {
    Throw "Could not find Project Specific Definition File: $($ProjectDefinitionPathFile)."
}
# Read Standard ARMTemplate to define new Resources like RG/Budget/Notifications
$StandardARMTemplatePathFile = "$($WorkingDirectory)/../../Resources/ArmTemplates/$($ProjectDefinition.template.ARMtemplateStandard)" 
If (Test-Path -Path $StandardARMTemplatePathFile ) {
    Write-Log -Message "Using Standard ARM template: $StandardARMTemplatePathFile" -Destination ALL -Logfile $Logfile
}
Else {
    Throw "Could not find Standard ARMTemplate File: $($StandardARMTemplatePathFile)."
}
# Read Role(s) Definition
$Role = $Roles | Select-Object -first 1 # Current Limitation: Only the first role from the definition will be created.
$RoleName = $Role.name
If ($Role.type -eq "Custom") {
    $RoleDefinitionPathFile = "$($WorkingDirectory)/../../Resources/CustomRoles/$($RoleName)-Role.json" 
    If (Test-Path -Path $RoleDefinitionPathFile ) {
        $RoleDefinition = Get-Content $RoleDefinitionPathFile | ConvertFrom-Json    # Load CustomRole for this project template
        $RoleName = $RoleDefinition.Name # Overrule name in projecttemplate
    }
    Else {
        Throw "Could not find Project Role Definition File: $($RoleDefinitionPathFile)."
    }
    if ([string]::IsNullOrEmpty($RoleDefinition.Name)) {
        Throw "Role Definition File: $($RoleDefinitionPathFile) does not contain a name."
    }
}



### Deploy Resource Group ###
# https://dzone.com/articles/deploying-resource-groups-with-arm-templates
#Start deployment of a Tagged Resource Group + Budgets with Notifications
$Params = @{
    'TemplateFile' = $StandardARMTemplatePathFile;
    'Name'         = $ResourceGroup;
    'Location'     = $($GeneralSettings.Location);
    #'ScopeType' = "Subscription"; # For Future Usage, from version 3.0
    'rgName'       = $ResourceGroup;
    'rgLocation'   = $($GeneralSettings.Location); # needed?
    'rgTemplate'   = $Template; # needed as tag for rg
    'GroupName'    = $GroupName;
    'Budget'       = $Budget; 
    'actionGroup'  = "/subscriptions/$($GeneralSettings.Subscription)/resourceGroups/$ResourceGroup/providers/microsoft.insights/actionGroups/$actionGroupRemoveResourceGroup";
    'StartDate'    = $StartDate;
    'StopDate'     = $StopDate;
    'Users'        = $Users;
}
$Status = New-AzDeployment @Params
$TemplateStatus = $Status.ProvisioningState 
Write-Log -Message "Deploy of Project Template '$($ProjectDefinition.template.name)' status: $TemplateStatus" -Destination ALL -Logfile $Logfile


### Define and Assign Roles ###
# Create a new role, if this is the first time the role is needed, and assign it to the subscription.
If ($Role.type -eq "Custom") {
    $RoleDefinition.AssignableScopes += "/subscriptions/$($GeneralSettings.Subscription)"
    $myRole = Get-AzRoleDefinition -Name $RoleDefinition.Name
    if ([string]::IsNullOrEmpty($myRole)) {
        New-AzRoleDefinition -Role $RoleDefinition  # Will fail if this role already exists in another subscription.
        do {  
            $myRole = Get-AzRoleDefinition -Name $RoleDefinition.Name
            Write-host -NoNewline ". "
            start-sleep 1
        } until (![string]::IsNullOrEmpty($myRole))

        Write-Log -Message "Role $($myRole.Name) Created" -Destination ALL -Logfile $Logfile
    }
}

# Assign the Role to each User with the Scope of a single RG (connecting Role-User-RG)
$Scope = "/subscriptions/$($GeneralSettings.Subscription)/resourcegroups/$($ResourceGroup)"
foreach ($User in $Users) {
    New-AzRoleAssignment -SignInName $User -Scope $Scope -RoleDefinitionName $RoleName # TODO: despite the waitloop after creating the new role (once per profile), sometime it takes a minute. In that case: assign by hand.
    Write-Log -Message "$User assigned to role: $($RoleName) for resourcegroup: $($ResourceGroup)" -Destination ALL -Logfile $Logfile
}


### (Define and) Assign Policies ###
# Apply all policies on the ResourceGroup as defined in the Project Template
$Policies = $ProjectDefinition.template.policies
Set-Policy -Policies $Policies -CustomPolicyPath $CustomPolicyPath -Location $GeneralSettings.Location -ResourceGroup $ResourceGroup -Logfile $Logfile


Write-Log -Message "Deploy template '$Template' for group '$GroupName' with users '$users', budget '$budget', startdate '$StartDate', stopdate '$StopDate' is Done!" -Destination ALL -Logfile $Logfile

