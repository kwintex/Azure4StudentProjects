# Technical Design
Azure4StudentProjects is living in its own subscription thereby minimizing the impact for other subscriptions like the Azure production environment of the organization. It uses the Active Directory to assign users of the organizational to a specific role (RBAC), but only within the scope of a single Resource Group. Within that Resource Group users can create, manage and use resources for which their role provides access, but within the limits of the policies, roles, time and budget.

![Azure4StudentProjects Scope](/Documentation/Images/azure4studentprojects_scope.png)
*Figure: The Scope of Azure4StudentProjects is confined to a single subscription in which each project group makes use of a single Resource Group.*

Creating a new project is done by starting a PowerShell script with parameters such as “budget”, “end date”, “e-mail addresses of its users” and a “project template”. In essence, the script successively executes:

    New-AzDeployment 
An ArmTemplate `.\Resources\ArmTemplates\rg-budget-notification.json` is deployed to create a new resource group, provide it with tags and a budget including notifications to its users.

    New-AzRoleDefinition
 
Create a new Custom Role for this project, but only if this is the first time that a specific custom role is being used.

    New-AzRoleAssignment
Assign the users to a specific role (Built-In or Custom), but only within the scope of their resource group.

    New-AzPolicyDefinition
Create one or more new Custom Policies for this project, but only if this is the first time that these policies are being used.

    New-AzPolicyAssignment
Assign each policy defined in the project definition for this template.

<br/>

![Azure4StudentProjects Scope](/Documentation/Images/add-azureprojects.png)

*Figure: Add-AzureProjects.ps1 creates and tags a resource group. Moreover, it assigns roles, users, policies, budgets and notification settings.*

For example, to provide access to Steve and Eve to create and manage a virtual machine until May 2020 or until the budget of 10 euros is depleted (whichever comes first), you execute: 
```PowerShell
 ./Administration/Scripts/Add-AzureProject.ps1 -Template simpleVM -GroupName Team1 -Budget 10 -StopDate 2020-05-01 -Users steve@student.organization.com,eve@organization.com
 ```
That’s all!

<br/>

## Automation
A few runbooks are developed to minimize the administration of the solution:

    Send-BudgetOverview
Sending a daily budget report by e-mail to a(n) administrator(s).
![Budget Report](/Documentation/Images/report.png)

<br/>

    Remove-ResourceGroupBudgetDepleted
Remove Resource Groups for which the budget is depleted and send mail to its users and Administrator as a notification. The runbook is event driven because it is implemented as an budget alert.
![Budget Depleted](/Documentation/Images/budget_depleted.png)

<br/>

    Remove-ResourceGroupStopDatePassed
Delete all resource groups for which the End Date has passed and send mail to its users and Administrator as a notification. The runbook is scheduled on a daily basis.
![Stop Date Passed](/Documentation/Images/stop_date_passed.png)


## Directory Structure:
Directory | Contents
---| ---
`Administration\Scripts\` | Scripts for Support Engineer
`Documentation\` | This documentation and images
`Logs\` | Logging from the PowerShell scripts
`Resources\ArmTemplates\` | Template for standard setup RG
`Resources\CustomPolicies\` | Your own created policies
`Resources\CustomRoles\` | Your own created roles
`Resources\ProjectDefinitions\` | A template for each project type
`Resources\sharedScripts\` | PowerShell Functions
`Settings\` | Your own settings for Azure
`Setup\ArmTemplates\` | Currently not in use
`Setup\Runbooks\` | Automation of daily management tasks
`Setup\Scripts\` | Run onces, but only after reading install.pdf
