# User Stories and User Manual

Different roles within your educational organization have different needs. On this page this information is grouped per ICT role.

## Contents
* [Group of Students | Educator](#students)
* [Support Engineer](#support)
* [Senior Application Engineer](#engineer)
* [Education Delivery Manager](#manager)

<br/>

## <a id="students"></a>Group of Students | Educator
> *"As a student or educator, I want to use Azure in a real environment together with my fellow students and educators, so that I can support the results of my research projects with real data and become familiar with public cloud concepts and technology."*

This is possible using Azure4StudentProjects: onboarding is a matter of minutes.

The life cycle of a project group consists of a number of steps:
1.	Students download the request form.
2.	They read it, add output of the Azure Calculator, sign and submit the form.
3.	Administrator does the onboarding in 1 minute by executing "Add-AzureProject.ps1".
4.	Students can start using the new Resource Group and add resources to it.
5.	During the project students receive budget alerts by mail if needed.
6.	After “the end date has passed” or “when the budget is depleted” (whatever comes first), the resource group and all locks, budgets, roles and resources are removed (!) from the subscription and students are notified by mail.

![Onboarding](/Documentation/Images/onboarding.png)

*Figure: Steps for onboarding a new project group on Azure. Sorry, Dutch only at this moment.*

### Example1: Requesting a simple Virtual Machine
After your new Resource Group is created. You can add resources. In case you selected the template “simpleVM” follow the next steps to create a Virtual Machine:
1. Logon to the Azure Portal and navigate to your resource group.
2. Click the plus-sign to add a new resource. Select "Create a virtual machine".
3. Choose one of the following options:
   * Windows Server 2019-Datacenter
   * Windows Server 2016-Datacenter
   * Ubuntu 18.04-LTS
   * CentOS (OpenLogic) version 7.7 or 8.0
4. Select West-Europe as your region
5. Select one of the following options for your machine size (did you use the Azure Calculator to estimate costs?!)
   * B1LS, 
   * B1MS, 
   * B1S, 
   * B2MS, 
   * B2S
6. Select "Standard SSD", or "Standard HDD" as your disk type.

Securing the Virtual Machine is your responsibility! If you don’t know how to accomplish this: ask your educator.

Your VM will be shutdown at 17:00 (localtime) to save costs. If you want it differently study the contents of the file Stop-VMs.ps1 in Setup/Runbooks and you'll find a solution.

If you want your server to be started as well, you have to provide a tag "startup" to the server with a value of "<[all|weekdays]-[0-23]>" in which "all" means "every day of the week". "weekdays" means starting your server on mon,tue,wed,thu,fri. The number after the dash is the starting hour expressed in UTC.
Note: Schedule for this runbook is Hourly this means that if you specify "all-9" as value for your startup-tag, your -deallocated- server will be started every day somewhere between 9:00 and 10:00 UTC.

<br/>

### Example2: Requesting a Cosmosdb with MongoDB API
After your new Resource Group is created. You can add resources. In case you selected the template “cosmosDB” follow the next steps to create a database and one or more collections:
1. Logon to the Azure Portal and navigate to your resource group.
2. Click the plus-sign to add a new resource. Type "Cosmos DB Account".
3. Choose your subscription and Resource Group
4. Fabricate a unique Account Name
5. Choose "Azure Cosmos DB for MongoDB API" (that is not the default, but other choices are not allowed!)
6. Select West-Europe as your region
7. Accept all defaults.
8. Click "Review + create"

After the database is created, which takes about ten minutes, your database and collections can be created. Never use more than 1 database and do not alter throughput settings (400 RU/s is default).
<br/>


## <a id="support"></a>Support Engineer
> *As a Support Engineer I want to receive an overview of the projects and its spendings on a daily basis and expect minimal administration so that I am able to add this task to my daily work.*

This is reality using Azure4StudentProjects: Students do the heavy lifting by selecting the right profile and using the Azure Calculator. A support engineer performs onboarding within minutes with or without an additional approval workflow if you like. The Engineer receives a daily overview by mail with alerts colored in “red”. Students receive alerts if their budget is depleting. At the end of the project time window, or when the budget is depleted all resources are removed automatically with “zero administration”.

Administration is simple. Most of the tasks are automated. The budget overview e-mails are received on a daily basis: The first few lines and information in red on top of the mail is most important. If you do not receive mail, something must be wrong!

### Notes regarding budgets
When the budget notification thresholds are exceeded, students receive a notification. None of your resources are affected and your consumption isn't stopped! Cost and usage data is typically available within 12-16 hours and budgets are evaluated against these costs every four hours. Email notifications are normally received within 12-16 hours (https://github.com/MicrosoftDocs/azure-docs/blob/master/articles/cost-management/tutorial-acm-create-budgets.md ).

Budgets reset automatically at the end of a period (monthly/annually) for the same budget amount. For Azure EA subscriptions, you must have read access to view your budgets.

<br/>

### Create a new Project Group
Execute the `./Administration/Scripts/Add-AzureProject.ps1` script.
More information?
````PowerShell
help ./Administration/Scripts/Add-AzureProject.ps1 
help ./Administration/Scripts/Add-AzureProject.ps1 -full
help ./Administration/Scripts/Add-AzureProject.ps1 -example
````
Don’t forget to check the output of the logging in the file `.\Logs\AzureProjectAdministration.log`

<br/>

### Delete an existing resource group
Although it was already mentioned that deleting a resource group is done automatically, it might be necessary sometimes to do this manually for whatever reason. In that case, execute the `./Administration/Scripts/Remove-ResourceGroup.ps1` script.

More information?
````PowerShell
help ./Administration/Scripts/ Remove-ResourceGroup.ps1 
help ./Administration/Scripts/ Remove-ResourceGroup.ps1 -full
help ./Administration/Scripts/ Remove-ResourceGroup.ps1 -example
````
<br/>

### Viewing the log
Automation can send runbook job status and job streams to your Log Analytics workspace (https://github.com/MicrosoftDocs/azure-docs/blob/master/articles/automation/automation-manage-send-joblogs-log-analytics.md). With Azure Monitor logs an email or alert is triggered based on your runbook job status (failed or suspended).

Interested in what else can be done regarding logging? For instance, view the logging of a project group with the name “cosmosDB-Team2”:
````PowerShell
Get-AzLog -MaxRecord 10 -ResourceGroupName cosmosDB-Team2
````

<br/>

### View budget spendings using commandline
````PowerShell
Get-AzConsumptionBudget | select Name,@{label="Spent";expression={[math]::Round($_.currentspend.amount,2)}},amount | sort -Descending Spent
````
Name          |                        Spent |Amount
----          |                        -----:|------:
BudgetTotal   |                         9.34  | 4000
simpleVM-TeamA     |                    3.12   |   2
simpleVM-TeamB         |                2.18    |  2

Do you need more detail, use: `Get-AzConsumptionUsageDetail`

<br/>

### View Azure Limits
There are limits to the number of resources that can be created within a certain subscription. A Support Engineer could monitor these limits an its current usage by executing the commands below:
````PowerShell
Get-Command "get-az*usage"    
Get-AzNetworkUsage  -location westeurope | format-table
Get-AzVMUsage -location westeurope
Get-AzStorageUsage  -location westeurope | format-table
````
For instance, as possible output, note the counters below:
Name          |                    Current Value |Limit  |Unit
----            |                  ------------- |-----  |----
Total Regional vCPUs             |             3|    10 |Count
Virtual Machines                 |             2 |25000 |Count
Standard BS Family vCPUs          |            3 |   10 |Count


<br/>

## <a id="engineer"></a>Senior Application Engineer
> *As a Senior Application Engineer I want to be able to fix bugs and create new profiles so that I am able to extend the current functionality and help students with their projects.*

Application Engineers fix bugs, and create new functionality. One of the most requested new functionality will probably be to add a new profile exposing more Azure functionality to its users.


### Add New Profiles
Creating a new profile is possible within an hour depending on the complexity of the role being used/created and services added.
Below are the steps needed to create a new profile, such as webApp, simpleVM or cosmosDB which are already created.

Note, the profile “webApp” is still under contruction and should not be used at this time.
1.	Copy the file `.\Resources\ProjectDefinitions\simpleVM.json` to `.\Resources\ProjectDefinitions\<newTemplateName>.json`
2.	In this new file, modify the JSON object. In particular the elements described below (JSON dot notation): `.template.name`, `.template.description`, `.template.resourceGroupPrefix`, `.template.roles[0].type` (Custom or Built-in), `.template.roles[0].name` (see below) and `.template.policies` (see below).
3.	Roles: Select an already built-in role, or create a new custom role if needed. see comments below.
4.	Templates: Select an already built-in roles, or create new custom roles. see comments below.

### Roles
If you need to select a role for your project, first check if a ready-to-use role is already available. Some PowerShell commands that might be helpful:
````PowerShell
get-azroledefinition | where name -like "*contributor*"
````
to find a role based upon its name

````PowerShell
(get-azroledefinition | where name -eq "Web Plan Contributor").Actions
````
to see which actions are allowed. As an alternative: 
````PowerShell
Get-AzRoleDefinition -Name "Website Contributor" | ConvertTo-Json
````

More information about a certain operation available for a certain resource provider:
````PowerShell
Get-AzProviderOperation "Microsoft.Resources/subscriptions/resourceGroups/*" | format-table OperationName, Operation, Description -AutoSize
````
Reference: https://www.jorgebernhardt.com/custom-roles-using-azure-powershell/


Note: After modifying an existing Custom Role, execute `Update-Role` to activate your new role settings. For instance to update the role simpleVM after modifying your custom role in the file `.\Resources\CustomRoles\simpleVM-Role.json`, execute:
````PowerShell
./Administration/Scripts/Update-Role.ps1 -Role simpleVM
````

<br/>

### Policies
Unlike RBAC, Azure Policy is a default allow and explicit deny system. If a policy or initiative (group of policies) is newly assigned to a scope, it takes around 30 minutes for the assignment to be applied to the defined scope. Once every 24 hours, assignments are automatically (re)evaluated.

Resources that are non-compliant to a deployIfNotExists or modify policy can be put into a compliant state through Remediation. When Azure Policy runs the template in the deployIfNotExists policy definition, it does so using a managed identity. Azure Policy creates a managed identity for each assignment, but must have details about what roles to grant the managed identity.
A number of policies have already be assigned to the subscription by the `setup.ps1` script:
* Azure subscriptions should have a log profile for Activity Log
* Azure Monitor log profile should collect logs for categories 'write,' 'delete,' and 'action'
* Azure Monitor solution 'Security and Audit' must be deployed
* Azure Monitor should collect activity logs from all regions
* Activity log should be retained for at least one year
* There should be more than one owner assigned to your subscription
* Email notification to subscription owner for high severity alerts should be enabled
* A security contact email address should be provided for your subscription
* Email notification for high severity alerts should be enabled
* MFA should be enabled on accounts with owner permissions on your subscription
* A security contact phone number should be provided for your subscription


Note: After modifying an existing or adding a new Custom Policy, execute `Update-Policy` to activate your new policy. It creates a Custom Policy if it is not already available in Azure. Moreover, the script renews policies already provided to this and other resource groups using the same policy. For instance to renew the policy for Team1 using the Template "simpleVM" execute:
````PowerShell
./Administration/Scripts/Update-Policy.ps1 -GroupName Team1 -Template simpleVM
````

References:
* https://docs.microsoft.com/nl-nl/azure/governance/policy/overview
* https://docs.microsoft.com/nl-nl/azure/governance/policy/assign-policy-powershell
* https://docs.microsoft.com/nl-nl/azure/governance/policy/tutorials/create-and-manage
* https://github.com/Azure/azure-policy
* https://docs.microsoft.com/nl-nl/azure/governance/policy/samples/

<br/>

### webApp-profile:
Some effort has been done to create a *webApp-profile*. However, by using the App Service as PaaS platform, an app runs in an "App Service plan". An App Service plan defines a set of compute resources for a web app to run. These compute resources are analogous to the server farm in conventional web hosting. One or more apps can be configured to run on the same computing resources (or in the same App Service plan). In the Free and Shared tiers, an app receives CPU minutes on a shared VM instance and cannot scale out. Generally the price you pay is for the web app plan and not the web app (the shared plan is an exception to this, see later) so your costs do not increase as you add more applications to the same plan. The  free plan is, as you would expect, free so the web app plan has no impact on the pricing. The free tier is limited to 60 CPU minutes per day, and this limit is per app, so in reality it doesn’t really matter if you put each app in it’s own plan or share one (there is a limit of 10 apps per free plan).

It makes sense to create a service plans for multiple web apps using a role like “Website Contributor” (https://docs.microsoft.com/nl-nl/azure/role-based-access-control/built-in-roles#website-contributor). A Resource group to host the app Service plans was already created: “`_AppServicePlans`”. It hosts the AppServicePlanFreeWindows, but its usage is very limited: no linux, no docker, no python etcetera.
For anybody who wants to add to the profile, think about the following:
* How to combine a single App Service Plan with multiple resource groups and the teams they belong to?
* How to prevent one team deleting the web app of another team in the _AppServicePlans resource group?
* What about the costs? It seems that except for the Free Service Plan, a virtual machine is always running. 

<br/>

### Find a VM image
If you want to add or modify an approved VM image, use the PowerShell commands below to find some. 
````PowerShell
Get-AzVMImageSku -location westeurope -PublisherName MicrosoftWindowsServer -Offer WindowsServer | select-object skus,id | format-list
Get-AzVMImageSku -location westeurope -PublisherName OpenLogic -Offer CentOS | select-object skus,id | format-list
Get-AzVMImageSku -location westeurope -PublisherName Canonical -Offer UbuntuServer | select-object skus,id | format-list
````
Reference: https://vincentlauzon.com/2018/01/10/finding-a-vm-image-reference-publisher-sku/ 



<br/>

## <a id="manager"></a>Education Delivery Manager
> *As a manager in Education I want to encourage innovation, but minimize the risks thereby promoting an attractive learning environment for my students but managing risks for my institution.*

Azure4StudentProjects is using all available controls on the Azure platform to *minimize and manage costs* including but not limited to:
* Using an Azure test/dev subscription, 
* daily reporting, 
* automatically remove resource groups after budget depletion and at a certain datetime, 
* notify support and students, 
* using (custom) roles 
* using policies

Nevertheless: there is a window of time between the moment where resources are created and costs are registered for customers. This window can be as large as 16 hours.

*Regarding security*: Azure4StudentProjects is separated from the production environment of your institution because it is create in its own subscription in which each group of students have their own resource group. In the public cloud a shared security model is being used: The cloud provider provide secure services, Azure4StudentProjects provide a logical container (Resource Group) exclusively available for each group and secured by roles and policies, Students read and sign a “code of conduct” and are responsible for security of the resources created, especially if the IaaS service models is being used and resources like VMs are created.
