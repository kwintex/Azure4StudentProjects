# Azure4StudentProjects 

> *Azure4StudentProjects provides access to an Azure subscription for a group of people. In this environment costs are controlled, access to resources are limited and administration tasks are reduced to a minimum.*



## Introduction
Public Cloud Technology enables its users to create powerful IT solutions within minutes using emerging technologies such as artificial intelligence and Internet of Things. Thanks to the power of Public Cloud platforms and its attractive “pay-as-you-go” financial model, the public cloud is also very suitable for conducting research projects and ICT education: Creating a large ICT infrastructure, website, IoT solution or Blockchain Service is possible within minutes and when a lab or project is finished the ICT resources can easily be deleted.<br/>
However, despite these advantages, cloud adoption within Education is still in its infancy. Reasons for this include:
* Educators have no prior experience with this technology and are sometimes reluctant to use it.
* Most students do not have a credit card.
* Educators and its organizations are worried about security issues and costs.

This project is an attempt to unleash the power of the cloud for small groups of students working on their ICT projects in a controlled Public Cloud environment.

<br/>

## Usage
After installation, usage is technically just executing a single PowerShell script. It creates a new resource group, assigns roles and policies, tags the resource group, add the budget, setup notifications for its users and makes sure that everything is removed when the end date has passed or its budget is depleted. 

![Azure4StudentProjects Scope](/Documentation/Images/add-azureprojects.png)

For example:
```PowerShell
./Administration/Scripts/Add-AzureProject.ps1 -Template simpleVM -GroupName Team1 -Budget 10 -StopDate 2020-05-01 -Users foo@bar.com,bar@foo.com
```

## Install
It all starts with a fresh Azure Dev/Test Subscription, dedicated for your deployment. It is assumed that you are the owner of the subscription having a trust relationship with an Azure Active Directory containing the Users of your organization. For a detailed installation guide, read the [installation guide](Documentation/INSTALL.pdf).


## Documentation
In depth documentation for end users and those who are  interested in the project:
* [Selecting a Cloud Landing Zone](Documentation/LandingZone.md)
* [Technical Design](Documentation/TechnicalDesign.md)
* [User Stories and User Manual](Documentation/UserManual.md)
  * [Group of Students | Educator](Documentation/UserManual.md#students)
  * [Support Engineer](Documentation/UserManual.md#support)
  * [Senior Application Engineer](Documentation/UserManual.md#engineer)
  * [Education Delivery Manager](Documentation/UserManual.md#manager)

## Authors and Acknowledgement
Author of the project is Rienk van der Ploeg (https://www.kwintex.nl). This project is inspired by the work of Mathieu Rietman (Microsoft) and created with help of Rutger Tromp (Surf).

## Contributing
If you want to add to this project, contact Rienk van der Ploeg (https://www.kwintex.nl).

## License
The GNU GPLv3 is chosen as its license model because it lets people do almost anything they want with the project, except distributing closed source versions: https://choosealicense.com/licenses/gpl-3.0/#
