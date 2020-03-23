<#
    .DESCRIPTION
        Sending a Budget Report by mail.
#>

Param(
  # recipients is written like: ["foo@bar.com","bar@foo.org"]
  [Parameter(Mandatory=$True)]
  [Array] $destEmailAddress,
  [Parameter(Mandatory=$True)]
  [String] $fromEmailAddress,
  [Parameter(Mandatory=$False)]
  [String] $subject = "Azure Budget Status Report"
)

Import-Module Az.Accounts
Import-Module Az.Automation
Import-Module Az.Compute
Import-Module Az.KeyVault
Import-Module Az.Resources

$connectionName = "AzureRunAsConnection"
$budgetNameTotalSubscription = "BudgetTotal"
$resourceGroupsExcluded = @()
# $resourceGroupsExcluded = @(
#     "_Administration_Azure4StudentProjects",
#     "_AppServicePlans",
#     "NetworkWatcherRG"
# )


try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName  

    Connect-AzAccount `
        -ServicePrincipal `
        -Tenant $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}


### Get budget/resources from subscription in total ###
$totalBudget = Get-AzConsumptionBudget -Name $budgetNameTotalSubscription
$totalAmount = $totalBudget.Amount
$totalCurrentSpend = [math]::Round($totalBudget.CurrentSpend.Amount,2)
$totalResources=(Get-AzResource | measure-object).Count

$html = "<HTML><HEAD><TITLE>Azure for StudentProjects</TITLE><STYLE>.header {font: normal 20px/150% Arial, Helvetica, sans-serif; color: #102b59; font-weight: bold;} .normal {font: normal 15px/150% Arial, Helvetica, sans-serif; color: #102b59;} .datagrid table { border-collapse: collapse; border: 1px solid #E1EEF4; text-align: right; width: 600px; } .datagrid {font: normal 12px/150% Arial, Helvetica, sans-serif; background: #fff; overflow: hidden; }.datagrid table td, .datagrid table th { padding: 2px 10px; }.datagrid table thead th {background:-webkit-gradient( linear, left top, left bottom, color-stop(0.05, #006699), color-stop(1, #00557F) );background:-moz-linear-gradient( center top, #006699 5%, #00557F 100% );filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#006699', endColorstr='#00557F');background-color:#006699; color:#FFFFFF; font-size: 14px; font-weight: bold; border-left: 1px solid #0070A8; } .datagrid table thead th:first-child { border: none; }.datagrid table tbody td { color: #00557F; border-left: 1px solid #E1EEF4;font-size: 14px;font-weight: normal; text-align: right;}.datagrid table tbody .alt td { background: #E1EEf4; color: #00557F; }.datagrid table tbody td:first-child { border-left: none; }.datagrid table tbody tr:last-child td { border-bottom: none; }</STYLE></HEAD><BODY>"
$html += "<div class='header'>Report: Azure for Student Projects Spending<br><br></div>"
$html += "<div class='normal'>Total Cost this year: <font color=red>$totalCurrentSpend Euro</font> (from a budget of $totalAmount Euro in total).<br>"
$html += "<div class='normal'>Total Number of resources in the subscription: <font color=red>$totalResources</font>.<br>"
$html += "Note, this table is sorted: Resource Groups with the least remaining budget are shown at the top of the list.<br><br></div>"


### Get budgets from all resource groups ###
$ResourceGroups = Get-AzResourceGroup
$ResourceGroupsCosts = @()
$ResourceGroupsCostsSorted = @()

$html += "<div class='datagrid'><TABLE>"

foreach ($ResourceGroup in $ResourceGroups)
{    
    $Budget =  Get-AzConsumptionBudget -ResourceGroupName $ResourceGroup.ResourceGroupName
    $CurrentSpend = [math]::Round($Budget.CurrentSpend.Amount,2)
    $ResourceGroupsCosts += ,@(
            $ResourceGroup.ResourceGroupName,
            $Budget.Amount,
            $CurrentSpend,
            ($Budget.Amount - $CurrentSpend)
        )
    $ResourceGroupsCostsSorted = $ResourceGroupsCosts | sort-object @{Expression={$_[3]}; Ascending=$true} 
} 

$html += "<thead><TR><th>Resource Group</th><th>Budget</th><th>Spent</th><th>Budget Left</th></thead><tbody>"

foreach($ResourceGroup in $ResourceGroupsCostsSorted) {
    if (! $resourceGroupsExcluded.Contains($ResourceGroup[0])) {
        if ($($ResourceGroup[3]) -lt 20) {
                $html += "<TR><TD>$($ResourceGroup[0])</TD><TD>$($ResourceGroup[1])</TD><TD>$($ResourceGroup[2])</TD><TD style=color:red;>$($ResourceGroup[3])</TD>"
        } else {
                $html += "<TR><TD>$($ResourceGroup[0])</TD><TD>$($ResourceGroup[1])</TD><TD>$($ResourceGroup[2])</TD><TD>$($ResourceGroup[3])</TD>"
        }
    }
}

$html += "</tbody></TABLE></div>"
$html += "</BODY></HTML>"


### Prepare Mail ###
$VaultName = "Azure4StudentPrAutVault"
$SENDGRID_API_KEY = (Get-AzKeyVaultSecret -VaultName $VaultName -Name "SendGridAPIKey").SecretValueText
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer " + $SENDGRID_API_KEY)
$headers.Add("Content-Type", "application/json")

$tos = @()
foreach($to in $destEmailAddress) {
    $tos += @{email = $to}
}

$body = @{
personalizations = @(
    @{
        to = $tos    
    }
)
from = @{
    email = $fromEmailAddress
}
subject = $subject
content = @(
    @{
        type = "text/html"
        value = $html
    }
)
}
$bodyJson = $body | ConvertTo-Json -Depth 4


### Send Mail ###
Invoke-RestMethod -Uri https://api.sendgrid.com/v3/mail/send -Method Post -Headers $headers -Body $bodyJson
