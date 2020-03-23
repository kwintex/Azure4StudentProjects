<#
    .DESCRIPTION
        Sending an object Alert if more than N Objects are created.
        Reasoning: preventing high costs as a result of creating too many objects. The runbook should be scheduled every hour to be effective.
#>

Param(
    # recipients is written like: ["foo@bar.com","bar@foo.org"]
    [Parameter(Mandatory = $True)]
    [Array] $destEmailAddress,
    [Parameter(Mandatory = $True)]
    [String] $fromEmailAddress,
    [Parameter(Mandatory = $False)]
    [String] $subject = "Azure Too Many Objects Created ALERT!",
    [Parameter(Mandatory = $False)]
    [int] $MaximumNumberObjects = 200
)


$connectionName = "AzureRunAsConnection"

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


### Send Alert? ###
$totalResources=(Get-AzResource | measure-object).Count
if ( $totalResources -le $MaximumNumberObjects) {
    Write-Output "Current number of resources is: $($totalResources). That number is lower or equal than the maximum number of objects being: $($MaximumNumberObjects), so nothing done."
} else {
    Write-Output "Current number of resources is: $($totalResources). That number is higher than the maximum number of objects being: $($MaximumNumberObjects), so sending mail alert."

    ### Create Mail contents ###
    $html = "<HTML><HEAD><TITLE>Azure for StudentProjects</TITLE><STYLE>.header {font: normal 20px/150% Arial, Helvetica, sans-serif; color: #102b59; font-weight: bold;} .tableheader {font: normal 18px/150% Arial, Helvetica, sans-serif; color: #102b59; font-weight: bold;} .normal {font: normal 15px/150% Arial, Helvetica, sans-serif; color: #102b59;} .datagrid table { border-collapse: collapse; border: 1px solid #E1EEF4; text-align: right; width: 600px; } .datagrid {font: normal 12px/150% Arial, Helvetica, sans-serif; background: #fff; overflow: hidden; }.datagrid table td, .datagrid table th { padding: 2px 10px; }.datagrid table thead th {background:-webkit-gradient( linear, left top, left bottom, color-stop(0.05, #006699), color-stop(1, #00557F) );background:-moz-linear-gradient( center top, #006699 5%, #00557F 100% );filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#006699', endColorstr='#00557F');background-color:#006699; color:#FFFFFF; font-size: 14px; font-weight: bold; border-left: 1px solid #0070A8; } .datagrid table thead th:first-child { border: none; }.datagrid table tbody td { color: #00557F; border-left: 1px solid #E1EEF4;font-size: 14px;font-weight: normal; text-align: right;}.datagrid table tbody .alt td { background: #E1EEf4; color: #00557F; }.datagrid table tbody td:first-child { border-left: none; }.datagrid table tbody tr:last-child td { border-bottom: none; }</STYLE></HEAD><BODY>"
    $html += "<div class='header'>Azure for Student <font color=red>ALERT!</font><br></div>"
    $html += "<div class='normal'><font color=red>Too many objects created!<br>Allowed value: $($MaximumNumberObjects), Created number of objects: $($totalResources)</font><br><br>"
    $html += "<div class='normal'>An Azure administrator should investigate if this is legitimate.<br>If allowed, increase the 'MaximumNumberObjects'-variable in this runbook. If not allowed, investigate which objects are created by whom and remove these objects.<br><br>"

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
    Invoke-RestMethod -Uri https://api.sendgrid.com/v3/mail/send -Method Post -Headers $headers -Body $bodyJson

}
