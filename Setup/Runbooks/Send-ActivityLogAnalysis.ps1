<#
    .DESCRIPTION
        Send "Activity Log Analysis" of a number of specific events that occurred in the past 24 hours by mail.

    .NOTES
        Thanks to Mathieu Rietman <marietma@microsoft.com>
        Require module az.monitor, az.resources, az.Compute, az.Storage, az.Network
        Please note that max row of powershell is 1000.
        The variable $analysedays determines the number of days from NOW() that will be analysed.
#>

Param(
    # recipients is written like: ["foo@bar.com","bar@foo.org"]
    [Parameter(Mandatory = $True)]
    [Array] $destEmailAddress,
    [Parameter(Mandatory = $True)]
    [String] $fromEmailAddress,
    [Parameter(Mandatory = $False)]
    [String] $subject = "Azure Activity Log Analysis Report"
)



class Activityinfo {
    [string]$ResourceGroupName
    [string]$Name
    [string]$Operation
    [string]$Status
    [string]$Details
    [string]$Errordetails
    [string]$ResourceType
    [string]$Location
    [string]$ResourceId
    [string]$ResourceProviderName
    [string]$SubscriptionId
    [string]$Caller
    [string]$ClaimName
    [string]$OperationId
    [DateTime]$EventTimestamp
    [DateTime]$SubmissionTimestamp
    [string]$CorrelationId

} 

$ActivityObject = @()
$Timezone = "W. Europe Standard Time"
$cstzone = [System.TimeZoneInfo]::FindSystemTimeZoneById($Timezone)
$analysedays = -1  # This means, get logging: "24 hours from now".
$timePeriodFrom = (get-date).AddDays(-1).ToString("d-M-yyyy (HH:MM)")   # 24 hours ago, for mail body
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



### Get all Activity Log items ###
# Keep in mind only 1000 records
# (get-azlog -MaxRecord 1000).OperationName.localizedValue | Sort-Object | Get-Unique  # provides you with the categories
# $azlogs = Get-AzLog -StartTime (Get-Date).AddDays($analysedays) -EndTime (Get-Date).AddDays($analysedays+1) 
$azlogs = Get-AzLog -StartTime (Get-Date).AddDays($analysedays)

foreach ($azlog in $azlogs) { 
    $ResourceGroupName = $azlog.ResourceGroupName
    $EventName = $azlog.EventName.Value
    $ResourceId = $azlog.ResourceId
    $ResourceProviderName = $azlog.ResourceProviderName.Value
    $ResourceType = $azlog.ResourceType.Value
    $OperationName = $azlog.OperationName.Value
    $OperationNameLocalizedValue = $azlog.OperationName.localizedValue
    $Level = $azlog.Level  
    $Category = $azlog.Category.Value
    $SubscriptionId = $azlog.SubscriptionId
    $status = $azlog.Status.Value
    $Properties = $azlog.Properties
    $Description = $azlog.Description
    $SubStatus = $azlog.SubStatus.Value
    $Caller = $azlog.Caller
    $ClaimName = $azlog.Claims.Content.name
    $OperationId = $azlog.OperationId 
    $EventTimestamp = $azlog.EventTimestamp
    $SubmissionTimestamp = $azlog.SubmissionTimestamp
    $action = $azlog.Authorization.Action
    $correlationId = $azlog.CorrelationId

    if (($null -ne $ResourceGroupName) ) {
        $name = $ResourceId.split("/")[-1]
  
        if (( ($OperationName -ne $OperationNameLocalizedValue) -and ($Category -ne "Policy") -and ($status -ne "started") -and ($status -ne "accepted") ) -or ( ($Category -ne "Policy") -and ($ResourceProviderName -eq "Microsoft.Compute") -and ($status -ne "started")) ) {
            $errordetails = "" 
            if (![string]::IsNullOrEmpty($Properties.content.statusMessage)) {
                $statusMessage = $Properties.content.statusMessage | ConvertFrom-Json
                $errordetails = $statusMessage.error.details.message
            }
            $resourcedetail = "" 
            $detailcreate = ""  # fills 'details'-column in table in mail.
            
            if ( ($ResourceProviderName -eq "Microsoft.Compute") ) {
                if (![string]::IsNullOrEmpty($Properties.content.responseBody)) {
                    $responsbody = $Properties.content.responseBody | ConvertFrom-Json
                    $vmtype = $responsbody.Properties.hardwareProfile.vmsize 
                    $vmoffer = $responsbody.Properties.storageProfile.imageReference.Offer
                    $vmsku = $responsbody.Properties.storageProfile.imageReference.sku
                    $detailcreate = "$vmtype - $vmoffer $vmsku"
                }
            }

            if ( ($status -eq "Succeeded") -and ($null -ne $ResourceGroupName) ) {
                $resourcedetail = Get-AzResource -ResourceId $azlog.ResourceId 
            }

            if ( ($OperationNameLocalizedValue -eq "Create or Update Public Ip Address") -and ($status -eq "Succeeded") ) {
                $publicIP = Get-AzPublicIpAddress -ResourceGroupName $azlog.ResourceGroupName -Name $resourcedetail.Name
                $detailcreate = "$($publicIP.IpAddress) - $($publicIP.Sku.Name)"
                $publicIP = "" 
            }
            
            if ( ($OperationNameLocalizedValue -eq "Create or Update Disk") -and ($status -eq "Succeeded") ) {
                $Disks = Get-AzDisk -ResourceGroupName $azlog.ResourceGroupName -DiskName $resourcedetail.Name
                $detailcreate = "$($disks.DiskSizeGB) GB - $($disks.sku.name) - $($disks.sku.Tier) -  $($disks.osType)"
                $Disks = ""
            }

            if ( ($OperationNameLocalizedValue -eq "Create or Update Network Interface") -and ($status -eq "Succeeded") ) {
                $Nic = Get-AzNetworkInterface -ResourceGroupName $azlog.ResourceGroupName -Name $resourcedetail.Name
                $detailcreate = "$($Nic.IpConfigurations.PrivateIPAddress)"
                $Nic = ""
            }

            if ( ($OperationNameLocalizedValue -eq "Create or Update Network Security Group") -and ($status -eq "Succeeded") ) {
                $NSG = Get-AzNetworkSecurityGroup -ResourceGroupName $azlog.ResourceGroupName -Name $resourcedetail.Name
                $detailcreate = ""
                foreach ($rule in $NSG.SecurityRules) {
                    $detailcreate += "[$($Rule.name)-$($Rule.Access)-$($Rule.Direction)-$($Rule.Protocol)-$($Rule.SourceAddressPrefix)-$($Rule.SourcePortRange)-$($Rule.DestinationAddressPrefix)-$($Rule.DestinationPortRange)]"
                }
                $NSG = ""
            }

            if ( ($OperationNameLocalizedValue -eq "Create/Update Storage Account") -and ($status -eq "Succeeded") ) {
  
                $storage = Get-AzStorageAccount -ResourceGroupName $azlog.ResourceGroupName -Name $resourcedetail.Name
                $detailcreate = "$($storage.sku.name) -$($storage.sku.Tier)"       
                $storage = ""
            }

            if ( ($OperationNameLocalizedValue -eq "Create or Update Virtual Network") -and ($status -eq "Succeeded") ) {

                $network = Get-AzVirtualNetwork -ResourceGroupName $azlog.ResourceGroupName -Name $resourcedetail.Name
                $detailcreate = "$($network.addressSpace.AddressPrefixes) "
                $network = ""
            }

            if ( ($OperationNameLocalizedValue -eq "Create or Update Virtual Machine") -and ($status -eq "Succeeded") ) {
                $vm = Get-AzVM -ResourceGroupName $azlog.ResourceGroupName -Name $resourcedetail.Name
                $detailcreate = "$($vm.HardwareProfile.VmSize) - $($vm.StorageProfile.OsDisk.OsType) - $($vm.StorageProfile.ImageReference.Offer) - $($vm.StorageProfile.ImageReference.Sku)"
                $vm = ""
            }

            if ( ($OperationNameLocalizedValue -eq "Update database account") -and ($status -eq "Succeeded") -and ($resourcedetail.ResourceType -eq "Microsoft.DocumentDB/databaseAccounts") ) {
                #Write-Output "databaseAccount  [$($databaseAccount.name)] in resourcegroup [$($databaseAccount.ResourceGroupName)] "
                $accountName = $name
                $resourceName = $accountName + "/sql/"
                $databases = Get-AzResource -ResourceType "Microsoft.DocumentDb/databaseAccounts/apis/databases" `
                    -ApiVersion "2015-04-08" -ResourceGroupName $ResourceGroupName `
                    -Name $resourceName | Select-Object Properties
                ForEach ($database in $databases) {
                    $databaseName = $database.Properties.id
                    #Write-Output "database [$databaseName ]  "
                    $databaseThroughputResourceType = "Microsoft.DocumentDb/databaseAccounts/apis/databases/settings"
                    $databaseThroughputResourceName = $accountName + "/sql/" + $databaseName + "/throughput"
                    $Troughput = Get-AzResource -ResourceType $databaseThroughputResourceType `
                        -ApiVersion "2015-04-08" -ResourceGroupName $resourceGroupName `
                        -Name $databaseThroughputResourceName | Select-Object Properties
                    $detailcreate += "[database $($databaseName )-$($Troughput.Properties.throughput) throughput]"
                }
                $databases = ""
            }

            #TODO add more $OperationNameLocalizedValue if appropriate to add details to the table...



            $ResourceType = $resourcedetail.ResourceType
            If ([string]::IsNullOrEmpty($ResourceType)) { $ResourceType = $ResourceProviderName }

            $ActivityObject += @([Activityinfo]@{
                    ResourceGroupName    = $ResourceGroupName
                    Name                 = $name
                    Operation            = $OperationNameLocalizedValue
                    Status               = $status
                    Details              = $detailcreate
                    Errordetails         = $errordetails
                    ResourceType         = $ResourceType
                    Location             = $resourcedetail.Location
                    ResourceId           = $ResourceId
                    ResourceProviderName = $ResourceProviderName
                    SubscriptionId       = $SubscriptionId
                    Caller               = $Caller
                    ClaimName            = $ClaimName
                    OperationId          = $OperationId 
                    EventTimestamp       = $EventTimestamp 
                    SubmissionTimestamp  = $SubmissionTimestamp
                    CorrelationId        = $correlationId
                })
        }
    }
}


if ($ActivityObject.Length -ne 0) {
    ### Create Mail contents ###
    $html = "<div style: overflow-x:auto> <HTML><HEAD><TITLE>Azure for StudentProjects</TITLE>"
    $html += "<STYLE>.header {font: normal 20px/150% Arial, Helvetica, sans-serif; color: #102b59; font-weight: bold;} .tableheader {font: normal 18px/150% Arial, Helvetica, sans-serif; color: #102b59; font-weight: bold;} .normal {font: normal 15px/150% Arial, Helvetica, sans-serif; color: #102b59;} .datagrid table { overflow-x:auto; border-collapse: collapse; border: 1px solid #E1EEF4; text-align: left; width: 1600px; } .datagrid {overflow-x:auto; font: normal 12px/150% Arial, Helvetica, sans-serif; background: #fff; overflow: hidden; }.datagrid table td, .datagrid table th { padding: 2px 10px; }.datagrid table thead th {background:-webkit-gradient( linear, left top, left bottom, color-stop(0.05, #006699), color-stop(1, #00557F) );background:-moz-linear-gradient( center top, #006699 5%, #00557F 100% );filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#006699', endColorstr='#00557F');background-color:#006699; color:#FFFFFF; font-size: 12px; font-weight: bold; border-left: 1px solid #0070A8; } .datagrid table thead th:first-child { border: 1px solid #E1EEF4; }.datagrid table tbody td { color: #00557F; border-left: 1px solid #E1EEF4;font-size: 12px;font-weight: normal; text-align: left;}.datagrid table tbody .alt td { background: #E1EEf4; color: #00557F; }.datagrid table tbody td:first-child { border-left: 1px solid #E1EEF4; }.datagrid table tbody tr:last-child td { border-bottom: 1px solid #E1EEF4; }</STYLE></HEAD><BODY>"
    $html += "<div class='header'>Report: Azure for Students Activity Log Report<br></div>"
    $html += "<div class='normal'>Activity Log from the latest 24 hours starting from $($timePeriodFrom) GMT.<br>"
    $html += "Note, Each table contains a single Resource Group Name (sorted by RG-Name, Ascending). Within each table, rows are sorted by DateTime (Descending).<br>Click on the CorrelationId link in the latest column for more information.<br></div>"

    $ActivityObject = $ActivityObject | Sort-Object -Property @{Expression = "ResourceGroupName"; Descending = $False }, @{Expression = "EventTimestamp"; Descending = $True }

    $oldresourcegroup = "none" 
    foreach ($Activity in $ActivityObject) {

        if (($Activity.ResourceGroupName -ne $oldresourcegroup ) -and ($null -ne $Activity.ResourceGroupName) ) {
            if ($oldresourcegroup -ne "none") {
                $html += "</tbody></TABLE></div></div>"
            }
            $oldresourcegroup = $Activity.ResourceGroupName 
            $html += "<div class='tableheader'><br>$($Activity.ResourceGroupName)</div>"
            $html += "<div class='datagrid'><div style='overflow-x:auto;'>"
            $html += "<TABLE width: 1600px>"
            $html += "<thead><TR><th width: 200px>Name</th><th width: 200px>ResourceType</th><th width: 400px>Operation</th><th width: 100px>EventTimestamp</th><th width: 100px>Status</th><th width: 400px>Details</th><th width: 200px>Caller</th><th width: 200px>Name</th><th width: 300px>CorrelationId</th></thead><tbody>"
        }

        if ($null -ne $oldresourcegroup) {
            $csttime = [System.TimeZoneInfo]::ConvertTimeFromUtc(($Activity.EventTimestamp).ToUniversalTime(), $cstzone)
            $linktime = $Activity.EventTimestamp.AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ss")
            $linktime2 = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            $DetailLink = [uri]::EscapeUriString("https://portal.azure.com/#blade/Microsoft_Azure_ActivityLog/ActivityLogBlade/queryInputs/{""query"":{""searchString"":""$($Activity.CorrelationId)"",""timeSpan"":""3"",""startTime"":""$linktime"",""endTime"":""$linktime2"",""subscriptions"":[""$($Activity.SubscriptionId)""]}}")
            $DetailLink = "<a href=""$DetailLink"">$($Activity.CorrelationId)</a>"
            $html += "<TR><TD width: 200px>$($Activity.Name)</TD><TD width: 200px>$($Activity.ResourceType)</TD><TD width: 400px>$($Activity.Operation)</TD><TD width: 100px>$($csttime)</TD><TD width: 100px>$($Activity.Status )</TD><TD width: 400px>$($Activity.Details)</TD><TD width: 200px>$($Activity.Caller)</TD><TD width: 200px>$($Activity.ClaimName)</TD><TD width: 200px>$($DetailLink)</TD>"
        }
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
    Invoke-RestMethod -Uri https://api.sendgrid.com/v3/mail/send -Method Post -Headers $headers -Body $bodyJson
}