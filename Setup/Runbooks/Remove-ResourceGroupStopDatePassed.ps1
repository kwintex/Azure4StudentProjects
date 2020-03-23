<#
    .DESCRIPTION
        Remove Resource Groups for which the End Date has passed and send mail to its users and Administrator as a notification.
#>

Param(
    # adminEmailAddress are written like: ["foo@bar.com","bar@foo.org"]
    [Parameter(Mandatory = $False)]
    [Array] $adminEmailAddress,    
    # adminEmailAddress are written like: ["foo@bar.com","bar@foo.org"]
    [Parameter(Mandatory = $False)]
    [String] $fromEmailAddress,
    # If a target Resource Group was specified, only this specific Resource Group was removed if enddate has passed.
    [Parameter(Mandatory = $False)]
    [String] $targetResourceGroup,
    # Subject of e-mail sent to its users and admins.
    [Parameter(Mandatory = $False)]
    [String] $subject = "Azure Resource Group was removed (Stop Date has passed)."
)

Import-Module Az.Accounts
Import-Module Az.Automation
Import-Module Az.Compute
Import-Module Az.KeyVault
Import-Module Az.Resources


function Remove-myResourceGroup {
    Param(
        # Sender of the e-mail
        [Parameter(Mandatory = $True)]
        [String] $Sender,
        # Recipients of the e-mail
        [Parameter(Mandatory = $True)]
        [Array] $Recipients,
        # Subject of e-mail sent to its users and admins.
        [Parameter(Mandatory = $True)]
        [String] $subject ,
        # If a target Resource Group was specified, only this specific Resource Group will be removed if Stop Date has passed.
        [Parameter(Mandatory = $True)]
        [String] $targetResourceGroup,
        # stopDate
        [Parameter(Mandatory = $True)]
        [String] $stopDate,
        # Spendings until today
        [Parameter(Mandatory = $True)]
        [String] $currentSpend
    )

    # Create Mail contents
    $html = "<HTML><HEAD><TITLE>Azure for StudentProjects</TITLE><STYLE>.header {font: normal 20px/150% Arial, Helvetica, sans-serif; color: #102b59; font-weight: bold;} .normal {font: normal 15px/150% Arial, Helvetica, sans-serif; color: #102b59;} .datagrid table { border-collapse: collapse; border: 1px solid #E1EEF4; text-align: right; width: 600px; } .datagrid {font: normal 12px/150% Arial, Helvetica, sans-serif; background: #fff; overflow: hidden; }.datagrid table td, .datagrid table th { padding: 2px 10px; }.datagrid table thead th {background:-webkit-gradient( linear, left top, left bottom, color-stop(0.05, #006699), color-stop(1, #00557F) );background:-moz-linear-gradient( center top, #006699 5%, #00557F 100% );filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#006699', endColorstr='#00557F');background-color:#006699; color:#FFFFFF; font-size: 14px; font-weight: bold; border-left: 1px solid #0070A8; } .datagrid table thead th:first-child { border: none; }.datagrid table tbody td { color: #00557F; border-left: 1px solid #E1EEF4;font-size: 14px;font-weight: normal; text-align: right;}.datagrid table tbody .alt td { background: #E1EEf4; color: #00557F; }.datagrid table tbody td:first-child { border-left: none; }.datagrid table tbody tr:last-child td { border-bottom: none; }</STYLE></HEAD><BODY>"
    $html += "<div class='header'>Resource Group '$targetResourceGroup' removed.<br><br></div>"
    $html += "<div class='normal'>Via this e-mail we want to inform you that the Resource Group with name '$targetResourceGroup' was removed from the 'Azure for Students Platform' because its Stop Date has passed.<br>
        Unfortunately, there is no possibility to reverse this action, or to restore information that was part of this Resource Group.<br>$currentSpend Euro was spent in this Resource Group until today.<br>"
    $html += "</BODY></HTML>"

    # Create header object
    $VaultName = "Azure4StudentPrAutVault"
    $SENDGRID_API_KEY = (Get-AzKeyVaultSecret -VaultName $VaultName -Name "SendGridAPIKey").SecretValueText
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer " + $SENDGRID_API_KEY)
    $headers.Add("Content-Type", "application/json")

    $Recipients = $Recipients | Select-Object -unique
    $tos = @()
    foreach ($to in $Recipients) {
        $tos += @{email = $to }
    }

    $body = @{
        personalizations = @(
            @{
                to = $tos    
            }
        )
        from             = @{
            email = $Sender
        }
        subject          = $subject
        content          = @(
            @{
                type  = "text/html"
                value = $html
            }
        )
    }
    $bodyJson = $body | ConvertTo-Json -Depth 4

    # Remove Resource Group, Locks and Budgets and Send Email
    Get-AzResourceLock -ResourceGroupName $targetResourceGroup | Remove-AzResourceLock -Force
    Remove-AzResourceGroup -Name $targetResourceGroup -Force 
    $budgets = Get-AzConsumptionBudget -ResourceGroupName $targetResourceGroup
    foreach ($budget in $budgets ) {
        write-host "Remove Budgets $($budget.Name)"
        Remove-AzConsumptionBudget -name $budget.Name  -ResourceGroupName $targetResourceGroup -ErrorAction Stop
    }
    Invoke-RestMethod -Uri https://api.sendgrid.com/v3/mail/send -Method Post -Headers $headers -Body $bodyJson | Out-Null
}



$connectionName = "AzureRunAsConnection"
$resourceGroupsExcluded = @(
    "_Administration_Azure4StudentProjects",
    "_AppServicePlans",
    "NetworkWatcherRG"
)

try {
    # Get the connection "AzureRunAsConnection "
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

### Get a list of all Resource Groups OR single Resource Group provided as parameter ###
if ([string]::IsNullOrEmpty($targetResourceGroup)) {
    $ResourceGroups = Get-AzResourceGroup
}
else {
    $ResourceGroups = Get-AzResourceGroup -Name $targetResourceGroup
}

### Remove the Resource Group in the list if the End Date has passed and it is not on a whitelist ###
foreach ($ResourceGroup in $ResourceGroups) {    
    if (! $resourceGroupsExcluded.Contains($ResourceGroup.ResourceGroupName)) {
        # RG not on the whitelist.
        $Today = (Get-Date -format "yyyy-MM-dd")
        $StopDate = (Get-AzResourceGroup -Name $ResourceGroup.ResourceGroupName).Tags.StopDate
        $Budget = Get-AzConsumptionBudget -ResourceGroupName $ResourceGroup.ResourceGroupName
        $CurrentSpend = [math]::Round($Budget.CurrentSpend.Amount, 2)
        $Users = $Budget."Notification"."first-Notification"."ContactEmails" + $adminEmailAddress
        if (($Today -ge $StopDate) -and ($StopDate -ne "infinite")) { 
            Remove-myResourceGroup -targetResourceGroup $($ResourceGroup.ResourceGroupName) -stopDate $stopDate -CurrentSpend $CurrentSpend -Sender $fromEmailAddress -Recipients $Users -Subject $Subject
        }
    }
}

