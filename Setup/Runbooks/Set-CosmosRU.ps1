<#
    .DESCRIPTION
        Downgrade the RU sizing of all cosmos db if needed.
        Reasoning: preventing high costs as a result of high throughput specification (RU/s). 
        The cost of all Azure Cosmos DB database operations is normalized and expressed in terms of Request Units (RUs). 
        RU/s is a rate-based currency, which abstracts the system resources such as CPU, IOPS, and memory that are required.
        The runbook should be scheduled every hour to be effective.
        Due to all Cosmosdb options, the custom cosmosdb-role is limited to mongodb only
        Module is depending on  az.Account, az.Compute and az.Resources

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
    [String] $subject = "Azure CosmosDB RU ALERT",
    [Parameter(Mandatory = $False)]
    [int] $RuLimit = 400
)



$RuLimit = 400
$throughputObject = @()
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


### Get all Cosmos DB Accounts in your subscription ###
$databaseAccounts = Get-AzResource -ResourceType Microsoft.DocumentDb/databaseAccounts

#Print VMs status
if (!$databaseAccounts) {
    Write-Output "No Cosmos DB Accounts were found in the subscription."
}
else {
    Write-Output "Number of Cosmos DB Accounts found in subscription: [$($databaseAccounts.Count)]"

    # Loop through all database accounts
    ForEach ( $databaseAccount in $databaseAccounts) { 
        $resourceGroupName = $databaseAccount.ResourceGroupName
        $accountName = $databaseAccount.Name
        Write-Output ""
        Write-Output "DatabaseAccount [$($databaseAccount.name)] found in resourcegroup [$($resourceGroupName)] "
        
        # Check Throughput on the database level
        $mongoDatabases = Get-AzCosmosDBMongoDBDatabase -ResourceGroup $resourceGroupName -AccountName $accountName
        ForEach ($mongoDatabase in $mongoDatabases) {
            $databaseName = $mongoDatabase.Name
            $currentThroughput = (Get-AzCosmosDBMongoDBDatabaseThroughput -ResourceGroup $resourceGroupName -AccountName $accountName -Name $databaseName -ErrorAction Ignore).Throughput # no RU set on database level, no error message.
            write-output "- Database [$databaseName]. Current Throughput Specified: [$currentThroughput]"
            if ($currentThroughput -gt $RuLimit) {
                $throughputObject += "Resource Group [$resourceGroupName] contains a database [$($mongoDatabase.Name)] with throughput [$($currentThroughput)]. This will be lowered to [$($RuLimit)].<br>"
                write-output "  Database [$databaseName]. Throughput must be lowered to: [$RuLimit]."
                Set-AzCosmosDBMongoDBDatabase -ResourceGroup $resourceGroupName -AccountName $accountName -Name $databaseName -Throughput $RuLimit
            }

            # Check Throughput on the collection level
            $mongoCollections = Get-AzCosmosDBMongoDBCollection -ResourceGroup $resourceGroupName -AccountName $accountName -DatabaseName $databaseName
            ForEach ($mongoCollection in $mongoCollections) {
                $collectionName = $mongoCollection.Name
                $currentThroughput = (Get-AzCosmosDBMongoDBCollectionThroughput -ResourceGroup $resourceGroupName -AccountName $accountName -DatabaseName $databaseName -Name $collectionName -ErrorAction Ignore).Throughput # no RU set on collection level, no error message.
                write-output "  - Collection [$collectionName] in database [$databaseName]. Current Throughput Specified: [$currentThroughput]"
                if ($currentThroughput -gt $RuLimit) {
                    $throughputObject += "<font color=red>Resource Group [$resourceGroupName] contains a database [$($mongoDatabase.Name)] with collection [$collectionName] and throughput [$($currentThroughput)]. This must be lowered to [$($RuLimit)] via the Portal (by hand!).</font><br>"
                    write-output "    Collection [$collectionName]. Throughput must be lowered to: [$RuLimit]."
                    # Doesn't work! Seems to be a bug? Can be changed using the portal by the way.
                    # Message: Set-AzCosmosDBMongoDBCollection : Long running operation failed with status 'Failed'. Additional Info:'Message: {"code":"BadRequest","message":"Message: {\"Errors\":[\"Document collection partition key cannot be changed.\"]}
                    #Set-AzCosmosDBMongoDBCollection -ResourceGroup $resourceGroupName -AccountName $accountName -DatabaseName $databaseName -Name $collectionName -Throughput $RuLimit
                }
            }
        }
    }

    if ($throughputObject.Length -ne 0) {
        ### Create Mail contents ###
        $html = "<HTML><HEAD><TITLE>Azure for StudentProjects</TITLE><STYLE>.header {font: normal 20px/150% Arial, Helvetica, sans-serif; color: #102b59; font-weight: bold;} .tableheader {font: normal 18px/150% Arial, Helvetica, sans-serif; color: #102b59; font-weight: bold;} .normal {font: normal 15px/150% Arial, Helvetica, sans-serif; color: #102b59;} .datagrid table { border-collapse: collapse; border: 1px solid #E1EEF4; text-align: right; width: 600px; } .datagrid {font: normal 12px/150% Arial, Helvetica, sans-serif; background: #fff; overflow: hidden; }.datagrid table td, .datagrid table th { padding: 2px 10px; }.datagrid table thead th {background:-webkit-gradient( linear, left top, left bottom, color-stop(0.05, #006699), color-stop(1, #00557F) );background:-moz-linear-gradient( center top, #006699 5%, #00557F 100% );filter:progid:DXImageTransform.Microsoft.gradient(startColorstr='#006699', endColorstr='#00557F');background-color:#006699; color:#FFFFFF; font-size: 14px; font-weight: bold; border-left: 1px solid #0070A8; } .datagrid table thead th:first-child { border: none; }.datagrid table tbody td { color: #00557F; border-left: 1px solid #E1EEF4;font-size: 14px;font-weight: normal; text-align: right;}.datagrid table tbody .alt td { background: #E1EEf4; color: #00557F; }.datagrid table tbody td:first-child { border-left: none; }.datagrid table tbody tr:last-child td { border-bottom: none; }</STYLE></HEAD><BODY>"
        $html += "<div class='header'>Azure for Students Cosmosdb RU/s settings exceeded <font color=red>ALERT</font><br></div>"
        $html += "<div class='normal'>$($throughputObject)<br>"
        $html += "<div class='normal'>High values for RU/s on a collection level cannot be remediated by lowering RU/s automatically. An Azure administrator should fix this.<br><br>"

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
}
