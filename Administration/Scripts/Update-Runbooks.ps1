 <#
    .SYNOPSIS
        Update the Runbooks.

    .DESCRIPTION
        Run this script after modifying or adding a Runbook.
        The Runbooks are defined in the Setup\Runbooks -directory .
        
        Functionality:
        - Remove the current runbook if exists,
        - Create a new one and publish it
        - Link it to an existing schedule.

        Dependencies: 
        - Schedules "Daily-1700" and "Daily"
        - Automation account and resource group
  
    .EXAMPLE
        ./Administration/Scripts/Update-Runbooks.ps1 -Runbook Stop-VMs -Schedule Daily-1700
    .EXAMPLE    
        ./Administration/Scripts/Update-Runbooks.ps1 -Runbook Remove-ResourceGroupBudgetDepleted -Schedule Daily -Parameters @{"fromEmailAddress"="foo@bar.nl";"adminEmailAddress"="foo@bar.nl"}
    .EXAMPLE    
        ./Administration/Scripts/Update-Runbooks.ps1 -Runbook Remove-ResourceGroupStopDatePassed -Schedule Daily -Parameters @{"fromEmailAddress"="foo@bar.nl";"adminEmailAddress"="foo@bar.nl"}
    .EXAMPLE    
        ./Administration/Scripts/Update-Runbooks.ps1 -Runbook Send-BudgetOverview -Schedule Daily -Parameters @{"fromEmailAddress"="foo@bar.nl";"destEmailAddress"=@('foo@bar.nl','foobar@bar.nl')}
    .EXAMPLE    
        ./Administration/Scripts/Update-Runbooks.ps1 -Runbook Send-YesterdayCostOverview -Schedule Daily -Parameters @{"fromEmailAddress"="foo@bar.nl";"destEmailAddress"=@('foo@bar.nl','foobar@bar.nl')}
    .EXAMPLE    
        ./Administration/Scripts/Update-Runbooks.ps1 -Runbook Send-ObjectAlert -Schedule Hourly -Parameters @{"fromEmailAddress"="foo@bar.nl";"destEmailAddress"=@('foo@bar.nl','foobar@bar.nl')}
    .EXAMPLE
        ./Administration/Scripts/Update-Runbooks.ps1 -Runbook Send-ActivityLogAnalysis -Schedule Daily -Parameters @{"fromEmailAddress"="foo@bar.nl";"destEmailAddress"=@('foo@bar.nl','foobar@bar.nl')}

	.Notes
		AUTHOR(s): Rienk van der Ploeg (HU)
		KEYWORDS:  Azure Educate Higher Education Project
#>

Param (
    # Runbook without path and without ".ps1" suffix
    [Parameter(Mandatory = $true)]  
    [ValidateNotNullOrEmpty()]
    [string]$Runbook,

    # Specify the optional schedule, e.g. "Daily" or "Daily-1700"
    [Parameter(Mandatory = $false)]  
    [ValidateSet("Daily", "Daily-1700", "Hourly")]
    [string]$Schedule,

    # Hashtable with parameters if needed.
    [Parameter(Mandatory = $false)]  
    [hashtable]$Parameters = $null
)


### Initialization ###
$WorkingDirectory = $PSScriptRoot
$Logfile = "$($WorkingDirectory)/../../Logs/AzureProjectAdministration.log" # Log Path and File
Import-Module -Name "$($WorkingDirectory)/../../Resources/SharedScripts/AzureProjectFunctions.psm1"      -Force # (if module was updated)
$GeneralSettings = Connect-Azure -GeneralSettings "$($WorkingDirectory)/../../Settings/Settings.json"    
$GeneralSettings

$RunbookDefinitionPathFile = "$($WorkingDirectory)/../../Setup/Runbooks/$($Runbook).ps1" 
If (! (Test-Path -Path $RunbookDefinitionPathFile)) {
    Throw "Could not find Runbook Definition File: $($RunbookDefinitionPathFile)."
}

$ResourceGroupName="_Administration_Azure4StudentProjects"
$AutomationAccountName="Azure4StudentProjects"



### Create and linke Runbook ###
write-host "All available runbooks:"
Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName | Select-Object Name | format-table

Remove-AzAutomationRunbook -Name $Runbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Verbose -Force
Import-AzAutomationRunbook -Name $Runbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Path $RunbookDefinitionPathFile -Type PowerShell -Verbose -Published
If ($Schedule) {
        Register-AzAutomationScheduledRunbook -Name $Runbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ScheduleName $Schedule -Parameters $Parameters
}

Write-Log -Message "Runbook: $Runbook with Schedule: $schedule Modified or Added" -Destination ALL -Logfile $Logfile
