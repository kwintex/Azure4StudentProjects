<#
    .DESCRIPTION
        Start (Startup) all VMs in the Subscription tagged by:
        - key="startup", value="<[all|weekdays]-[0-23]>" 
        - example: value="workweek-9" results in your server starting at 09:00 on mon, tue, wed, thu and fri
        - example: value="all-13"     results in your server starting at 13:00 on every day (UTC).
        
        key/value is not case sensitive. 
        Time (hours) is expressed in UTC. 
        Schedule for this runbook is Hourly this means that if you specify "all-9" as value for your startup-tag, your -deallocated- server will be started somewhere between 9:00 and 10:00 UTC.
    
    .NOTES
        AUTHOR(s): Rienk van der Ploeg (HU)
        KEYWORDS:  Azure Educate Higher Education Project | Cost Management
#>

Param(
)



$connectionName = "AzureRunAsConnection"
try {
    # Get the connection "AzureRunAsConnection"
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName  

    Connect-AzAccount `
        -ServicePrincipal `
        -Tenant $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
}
catch {
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    }
    else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

### Get current Tag Value: day and hour (UTC) ###
$Week="weekend"
$Day = (Get-Date).DayOfWeek  # 6=Saturday
if (($Day -gt 0) -and ($Day -lt 6)) {
    $Week="workweek"
}
$Hour = (Get-Date).Hour  # 9=9:00, 14=14:00 UTC !
write-Output "Current value for Week-Hour is: $($Week)-$($Hour)"

### Get a list of all VMs in subscription ###
if ($Week -eq "workweek") {
    $VMs = Get-Azvm | Where-Object {($_.Tags["startup"] -eq "week-$Hour") -or ($_.Tags["startup"] -eq "all-$Hour")}
}
if ($Week -eq "weekend") {
    $VMs = Get-Azvm | Where-Object {$_.Tags["startup"] -eq "all-$Hour" }
}
if (!$VMs) {
    Write-Output "No VMs to start were found in the subscription."
}
else {
	Write-Output "Number of Virtual Machines to start in this subscription: [$($VMs.Count)]"
    ForEach ($VM in $VMs) { 
        $vmStatus = Get-AzVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Status 

        # Start VM
        $statuses = $vmStatus.statuses | Where-Object { $_.code -like "Powerstate*" }
        if ($statuses.code -eq "PowerState/deallocated") {
            Write-Output "Starting VM [$($VM.Name)]"
            $VM | Start-AzVM -AsJob
        }
        else {
            Write-Output "VM [$($VM.Name)] is already running or does not have state deallocated. Current state [$($statuses.code)]"
        }
    }
}
