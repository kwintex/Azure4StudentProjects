<#
    .DESCRIPTION
        Stop (Shutdown) all VMs in the Subscription except VMs tagged by:
        - key="shutdown", value="no" 
        - key="shutdown", value="maintenance"
        Note: key/value is not case sensitive.

        Depending on  az.Account, az.Compute and az.Resources modules that require az import in Modules of the Automation Account
    
    .NOTES
        AUTHOR(s): Rienk van der Ploeg (HU), inspired by Mathieu Rietman (MS)
        KEYWORDS:  Azure Educate Higher Education Project | Cost Management
#>

Param(
)


# Import-Module Az.Accounts
# Import-Module Az.Compute
# Import-Module Az.Resources


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


### Get a list of all VMs in subscription ###
$VMs = Get-Azvm
if (!$VMs) {
    Write-Output "No VMs were found in subscription."
}
else {
	Write-Output "Number of Virtual Machines found in subscription: [$($VMs.Count)]"
    
    ForEach ($VM in $VMs) { 
        $vmStatus = Get-AzVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Status 
        $vmInfo = Get-AzVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name 
        $TagShutdown = $vmInfo.tags["shutdown"]

        if (($TagShutdown -ne "no") -and ($TagShutdown -ne "maintenance")) {
            # Stop VM
            $statuses = $vmStatus.statuses | Where-Object { $_.code -like "Powerstate*" }
            if ($statuses.code -eq "PowerState/running") {
                Write-Output "Stopping VM [$($VM.Name)]"
                $VM | Stop-AzVM -AsJob -Force
            }
            else {
                Write-Output "VM [$($VM.Name)] is already deallocated! or not have state running. Current state [$($statuses.code)]"
            }
        } else {
            Write-Output "VM [$($VM.Name)] has a 'shutdown' tag with value of '$($TagShutdown)', so nothing done."
        }
    }
}
