 <#
    .SYNOPSIS
        Setup of a Key Vault for your Automation account e.g. for sending e-mails.

    .DESCRIPTION
        Run this script after creating a new subscription for AzureForStudents.
  
    .EXAMPLE
        ./Administration/Scripts/createAzureAutomationVault.ps1

	.Notes
		AUTHOR(s): Rienk van der Ploeg (HU)
		KEYWORDS:  Azure Educate Higher Education Project
#>


### Initialization ###
$WorkingDirectory = $PSScriptRoot
Import-Module -Name "$($WorkingDirectory)/../../Resources/SharedScripts/AzureProjectFunctions.psm1"      -Force # (if module was updated)
$GeneralSettings = Connect-Azure -GeneralSettings "$($WorkingDirectory)/../../Settings/Settings.json"    
$GeneralSettings

$ResourceGroup = "_Administration_Azure4StudentProjects" 
$VaultName = "Azure4StudentPrAutVault"
$AutomationAccountName = "Azure4StudentProjects"

$result = Get-AzAutomationConnection -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccountName -Name AzureRunAsConnection
If (![string]::IsNullOrEmpty($result)) {
    $result
    Throw "Vault $Vaultname in Resourcegroup $ResourceGroup for Automationaccount $AutomationAccountName already exists."
}


# Create the new key vault
Register-AzResourceProvider -ProviderNamespace "Microsoft.KeyVault"
New-AzKeyVault -VaultName $VaultName -ResourceGroupName $ResourceGroup -Location $GeneralSettings.Location

# Convert the SendGrid API key into a SecureString
$Secret = ConvertTo-SecureString -String $GeneralSettings.SendGridAPIKey -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $VaultName -Name 'SendGridAPIKey' -SecretValue $Secret

# Grant access to the KeyVault to the Automation RunAs account.
$connection = Get-AzAutomationConnection -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccountName -Name AzureRunAsConnection
$appID = $connection.FieldDefinitionValues.ApplicationId
Set-AzKeyVaultAccessPolicy -VaultName $VaultName -ServicePrincipalName $appID -PermissionsToSecrets Set, Get
