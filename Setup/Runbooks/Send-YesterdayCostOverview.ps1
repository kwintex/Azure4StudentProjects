<#
    .DESCRIPTION
        Sending a Cost Report by mail regarding yesterday's cost.
        Based on cost mananagement API as described on https://docs.microsoft.com/en-us/rest/api/cost-management/query

    .Notes
        Thanks to Mathieu Rietman <marietma@microsoft.com>
#>

Param(
    # recipients is written like: ["foo@bar.com","bar@foo.org"]
    [Parameter(Mandatory = $True)]
    [Array] $destEmailAddress,
    [Parameter(Mandatory = $True)]
    [String] $fromEmailAddress,
    [Parameter(Mandatory = $False)]
    [String] $subject = "Azure Yesterday Cost Report"
)


class Costinfo {
    [double]$PreTaxCost
    [String]$ResourceId
    [String]$ResourceType      
    [String]$ResourceLocation 
    [String]$ResourceGroupName
    [Array]$Tags 
    [String]$Currency 
}
$connectionName = "AzureRunAsConnection"
$startdate = (get-date).AddDays(-1).ToString("d-M-yyyy")   # Yesterday
$enddate = (get-date).ToString("d-M-yyyy")                 # Today
$timePeriodFrom =  (get-date).AddDays(-1).ToString("yyyy-MM-ddT00:00:00.000Z")   # Yesterday
$timePeriodTo = (get-date).ToString("yyyy-MM-ddT00:00:00.000Z")                  # Today


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

### Get a Token for invoking the REST API ###
$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Tenant.Id)

### Invoke the REST API ###
$apiVersion = "api-version=2019-10-01"
$uri = 'https://management.azure.com/subscriptions/' + $azContext.Subscription.ID + '/providers/Microsoft.CostManagement/query?' + $apiVersion
$RequestPayload = " {'type':'ActualCost','dataSet':{'granularity':'None','aggregation':{'totalCost':{'name':'PreTaxCost','function':'Sum'}},'grouping':[{'type':'Dimension','name':'ResourceId'},{'type':'Dimension','name':'ResourceType'},{'type':'Dimension','name':'ResourceLocation'},{'type':'Dimension','name':'ResourceGroupName'}],'include':['Tags']},'timeframe':'Custom','timePeriod':{'from':'$($timePeriodFrom)','to':'$($timePeriodTo)'}}"
$CostObject = @()
$Content = $null;
$headers2 = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers2.Add("Authorization", "Bearer " + $token.AccessToken)
$headers2.Add("Content-Type", "application/json")
$Response = Invoke-WebRequest -uri $uri -Method Post -Headers $headers2 -ContentType "application/json" -Body $RequestPayload -UseBasicParsing -TimeoutSec 300
If ($response.StatusCode -eq 200) {
    $content = $Response.Content | ConvertFrom-Json
}
else {
    Write-Error  "Error Executing: $Uri"
    throw "Error response: $response.StatusCode : $response.StatusDescription"
}


### Prepare cost object ###
While ( $null -ne $content.properties.nextLink -or $null -ne $content ) {
    ForEach ($meter in $content.properties.rows) {
        $CostObject += @([Costinfo]@{
                PreTaxCost        = $meter[0]
                ResourceId        = $meter[1]
                ResourceType      = $meter[2] 
                ResourceLocation  = $meter[3]
                ResourceGroupName = $meter[4]
                Tags              = $meter[5]
                Currency          = $meter[6]
            })
    }

    if ($null -ne $content.nextLink ) {
        $content = Add-AzureRequestManagemenytAPI -uri $content.nextLink -token $token 
    }
    else {
        $content = $null
    }
}

$CostObject = $CostObject | Sort-Object -Property @{Expression = "PreTaxCost"; Descending = $True }
#Write-Output "CostObject, sorted by PreTaxCost descending:" $CostObject
<# yields rows with this content:
    PreTaxCost        : 3.3602584808E-06
    ResourceId        : /subscriptions/e1f5f47e-c6f4-48e1-8406-849288e50bc3/resourcegroups/_administration_azure4studentproj
                        ects/providers/microsoft.keyvault/vaults/azure4studentprautvault
    ResourceType      : microsoft.keyvault/vaults
    ResourceLocation  : eu west
    ResourceGroupName : _administration_azure4studentprojects
    Tags              : {}
    Currency          : EUR
#>


$TotalCost = ($CostObject | Measure-Object -Sum PretaxCost).sum
$TotalCostResources = ($CostObject | Measure-Object -Sum PretaxCost).count
$currency = ($CostObject | Group-Object { $_.Currency }).Name


$Costgroups = $CostObject | Group-Object { $_.ResourceGroupName }
$CostgroupsOverview = $Costgroups | Select-Object -Property  @{ Name = 'ResourceGroupName'; Expression = { $_.Name } },
@{ Name = 'PreTaxCost'; Expression = { ($_.Group | Measure-Object -Property PretaxCost -Sum).sum } }
$CostgroupsOverview = $CostgroupsOverview | Sort-Object -Property @{Expression = "PreTaxCost"; Descending = $True }



### Create Mail contents ###
$html = "<HTML><HEAD><TITLE>Azure for StudentProjects</TITLE><STYLE>.header {font: normal 20px/150% Arial, Helvetica, sans-serif; color: #102b59; font-weight: bold;} .tableheader {font: normal 18px/150% Arial, Helvetica, sans-serif; color: #102b59; font-weight: bold;} .normal {font: normal 15px/150% Arial, Helvetica, sans-serif; color: #102b59;} .datagrid table { border-collapse: collapse; border: 1px solid #E1EEF4; text-align: right; width: 600px; } .datagrid {font: normal 12px/150% Arial, Helvetica, sans-serif; background: #fff; overflow: hidden; }.datagrid table td, .datagrid table th { padding: 2px 10px; }.datagrid table thead th {background:-webkit-gradient( linear, left top, left bottom, color-stop(0.05, #006699), color-stop(1, #00557F) );background:-moz-linear-gradient( center top, #006699 5%, #00557F 100% );filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#006699', endColorstr='#00557F');background-color:#006699; color:#FFFFFF; font-size: 14px; font-weight: bold; border-left: 1px solid #0070A8; } .datagrid table thead th:first-child { border: none; }.datagrid table tbody td { color: #00557F; border-left: 1px solid #E1EEF4;font-size: 14px;font-weight: normal; text-align: right;}.datagrid table tbody .alt td { background: #E1EEf4; color: #00557F; }.datagrid table tbody td:first-child { border-left: none; }.datagrid table tbody tr:last-child td { border-bottom: none; }</STYLE></HEAD><BODY>"
$html += "<div class='header'>Report: Azure for Student Spendings <font color=red>Yesterday</font><br></div>"
$html += "<div class='normal'>From: $($startdate) until: $($enddate).<br>"
$html += "<div class='normal'>Total (pretax) costs: <font color=red>$([math]::Round($TotalCost,2)) $($currency)</font>. Total cost objects:  <font color=red>$($TotalCostResources)</font>.<br><br>"

# First Table
$html += "<div class='tableheader'>Overview per Resource</div>"
$html += "Note, this table is sorted: Resources with the highest costs are shown at the top.<br></div>"
$html += "<div class='datagrid'><div style='overflow-x:auto;'>"
$html += "<TABLE><thead><TR><th>Resourcegroup</th><th>Cost</th><th>ResourceId</th><th>ResourceType</th></tr></thead><tbody>"  
ForEach ($meter in $CostObject) {
    $name = $meter.ResourceId.split("/")[-1]
    $metercost = [math]::Round($meter.PretaxCost,2)
    $output = "<tr><td>$($meter.ResourceGroupName)</td><td text-align: right>$metercost</td><td>$($name)</td><td>$($meter.ResourceType)</td></tr>"
    $html += $output
}
$html += "</tbody></TABLE></div></div><br>"

# Next Table
$html += "<div class='tableheader'>Overview per ResourceGroup</div>"
$html += "Note, this table is sorted: Resource Groups with the highest costs are shown at the top.</div>"
$html += "<div class='datagrid'><div style='overflow-x:auto;'>"
$html += "<TABLE><thead><TR><th>Resourcegroup</th><th>PreTaxCost</th></tr></thead><tbody>"  
ForEach ($meter in $CostgroupsOverview) {
    $output = "<tr><td>$($meter.ResourceGroupName)"
    $output += "</td><td text-align: right>$([math]::Round($meter.PretaxCost,2))</td></tr>"
    $html += $output
}
$html += "</tbody></TABLE></div></div>"
$html += "</BODY></HTML>"


### Prepare Mail ###
$VaultName = "Azure4StudentPrAutVault"
$SENDGRID_API_KEY = (Get-AzKeyVaultSecret -VaultName $VaultName -Name "SendGridAPIKey").SecretValueText
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer " + $SENDGRID_API_KEY)
$headers.Add("Content-Type", "application/json")

$tos = @()
foreach ($to in $destEmailAddress) {
    $tos += @{email = $to }
}

$body = @{
    personalizations = @(
        @{
            to = $tos    
        }
    )
    from             = @{
        email = $fromEmailAddress
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


### Send Mail ###
$response = Invoke-RestMethod -Uri https://api.sendgrid.com/v3/mail/send -Method Post -Headers $headers -Body $bodyJson
