# EntraIDProvisioningLogsReporter
Entra Provisioning Logs Reporting Script

# Function

Produce CSV report files based on downloaded JSON files of Entra Provisioning Logs.

# Purpose

Provide way to easily report on changes made in Target Systems via Entra Provisioning Connectors.

# JSON Structure Documentation

<https://learn.microsoft.com/en-us/graph/api/resources/provisioningobjectsummary?view=graph-rest-1.0>

# Reading Reports

The reports are CSV text files. Typically, these files are opened in Excel\\Sheets where various filtering techniques can be used to analyze the data. Further processing can also be done via other processes\\scripts capable of reading CSV text files.

## Standard Columns

Columns included in all reports generated via this script.

1. id
2. activityDateTime
3. tenantId
4. jobId
5. cycleId
6. changeId
7. provisioningAction
8. sourceSystemDisplayName
9. targetSystemDisplayName
10. initiatedByDisplayName
11. provisioningStatusInfoStatus
12. reportableIdentifier – In some cases, this is the only value available to identify objects in the Source system.

## Detailed Columns

Columns that provide relevant information about Source\\Target system attribute values. These attribute values are used by an Entra connector’s Synchronization Rule for Scoping Filters and Attribute Mappings.

These columns are included in Detailed reports.

### Static Columns

The values are Entra-generated GUIDs that represent each Source\\Target object. They exist only within the context of an Entra connector.

1. SourceIdentity_EntraId
2. TargetIdentity_EntraId

### Dynamic Columns

Columns used to identify an object’s attribute name and values in their respective Source\\Target systems. Attribute names that exist on an object in the Source system are prefixed with ‘SourceIdentity_’. Attribute names that exist on an object in the Target system are prefixed with ‘TargetIdentity_’.

These columns help provide detailed analysis of how data flows through an Entra connector by providing all the attributes from Source\\Target systems used by Entra when evaluating scoping, matching, and updating actions on objects.

**NOTE:** The values in these columns are the **existing** values in the Source\\Target system **before** changes are made by Entra.

#### Example

| Column Name | Description |
| --- | --- |
| SourceIdentity_LegalFirstName | LegalFirstName is the attribute name from the Source system |
| TargetIdentity_FirstName | FirstName is the attribute name from the Target system |

## Change Columns

Columns used to represent changes in the Target system made by an Entra connector. Each attribute that is changed will have a pair corresponding columns identifying old and new attribute values. Columns indicating the previous value are suffixed with ‘\_oldValue’. Columns indicating the updated value are suffixed with ‘\_newValue’.

**NOTE:** To identify where a new value is null, a value of ‘(Null)’ is used.

**NOTE:** To identify where a new value is whitespace or empty string, a value of ‘(EmptyString)’ is used.

#### Example

| Column Name | Description |
| --- | --- |
| FirstName_oldValue | Original value of FirstName attribute in the Target system |
| FirstName_newValue | Updated value of FirstName attribute in the Target system |

# Script Versions

| PowerShell Version | Script Name | Compatibility |
| --- | --- | --- |
| 5.1 | EntraProvisioningLogsReporter.ps1 | Will run in v7, but use substantially more memory |
| 7   | EntraProvisioningLogsReporter_PSv7.ps1 | Will fail in v5.1 |

# Script Parameters

Parameters used by the script to generate a report.

## Required

1. **JsonFile** – Path to the JSON file downloaded from Entra containing Provisioning Logs.
2. **OutputFolder** – Path to folder where the generated CSV report will be written.

## Optional Switches

| Name | Details | Default Value | Notes |
| --- | --- | --- | --- |
| AllRecords | Instructs script to generate a report containing all records within the JSON file. No filtering is applied. | False | Value of **false** results in report containing only records where at least 1 attribute was modified<br><br>Cannot be used with Failures switch |
| Failures | Instructs script to generate a report containing records within the JSON file without a Status of ‘success’ or ‘skipped’. | False | Value of **false** results in report containing only records with successful changes<br><br>Cannot be used with AllRecords switch |
| Detailed | Instructs script to generate a report that includes ‘sourceIdentity_’ and ‘targetIdentity_’ columns. | False | Value of **false** results in report not containing ‘sourceIdentity_’ and ‘targetIdentity_’ columns<br><br>Can be used with or without AllRecords or Failures switches |

# Script Output

## Report Naming Convention

Report names will include a prefix of ‘Report_’, the file name of the JsonFile used, value of ‘\_GeneratedOn_’, a timestamp (format - "yyyy-MM-dd_HHmmss") of when the report was generated, followed by any switches used.

**NOTE:** Cases where AllRecords switch is false, a value of ‘Changes’ is used to indicate which records are included in the file.

### Examples

**JsonFile** – C:\\Scripts\\provisioningLog.json

**Time report generated** – May 3<sup>rd</sup>, 2025, at 11:35:01AM

| Switches | Report File Name |
| --- | --- |
| None | Report_provisioningLog_GeneratedOn_2025_05_03_113501_Changes.csv |
| Detailed | Report_provisioningLog_GeneratedOn_2025_05_03_113501_Changes_Detailed.csv |
| AllRecords | Report_provisioningLog_GeneratedOn_2025_05_03_113501_AllRecords.csv |
| AllRecords, Detailed | Report_provisioningLog_GeneratedOn_2025_05_03_113501_AllRecords_Detailed.csv |
| Failures | Report_provisioningLog_GeneratedOn_2025_05_03_113501_Failures.csv |
| Failures, Detailed | Report_provisioningLog_GeneratedOn_2025_05_03_113501_Failures_Detailed.csv |

# Script Execution

## Examples

| Command | Description |
| --- | --- |
| C:\\Scripts\\entraProvisioningLogsReporter.ps1 -JsonFile “C:\\Scripts\\provisioningLog.json” -OutputFolder “C:\\Scripts” | Generates report with default value of **false** for _AllRecords_, _Failures_, and _Detailed_ switches. The report will include only records of where changes were made to the Target System. Report will NOT include ‘sourceIdentity_’ and ‘targetIdentity_’ columns. |
| C:\\Scripts\\entraProvisioningLogsReporter.ps1 -JsonFile “C:\\Scripts\\provisioningLog.json” -OutputFolder “C:\\Scripts” -Detailed | Generates report with default value of **false** for _AllRecords_ and _Failure_ switches and value of **true** for _Detailed_ switch. The report will include only records of where changes were made to the Target System. Report will include ‘sourceIdentity_’ and ‘targetIdentity_’ columns. |
| C:\\Scripts\\entraProvisioningLogsReporter.ps1 -JsonFile “C:\\Scripts\\provisioningLog.json” -OutputFolder “C:\\Scripts” -AllRecords | Generates report with default value of **false** for _Failures_ and _Detailed_ switches and value of **true** for _AllRecords_ switch. The report will include all records in the JSON file. Report will NOT include ‘sourceIdentity_’ and ‘targetIdentity_’ columns. |
| C:\\Scripts\\entraProvisioningLogsReporter.ps1 -JsonFile “C:\\Scripts\\provisioningLog.json” -OutputFolder “C:\\Scripts” -AllRecords -Detailed | Generates report with default value of **false** for _Failures_ switch and value of **true** for _AllRecords_ and _Detailed_ switches. The report will include all records in the JSON file. Report will include ‘sourceIdentity_’ and ‘targetIdentity_’ columns. |
| C:\\Scripts\\entraProvisioningLogsReporter.ps1 -JsonFile “C:\\Scripts\\provisioningLog.Json” -OutputFolder “C:\\Scripts” -Failures | Generates report with default value of **false** for _AllRecords_ and _Detailed_ switches and value of **true** for _Failures_ switch. The report will include only records of where Status is NOT ‘success’ or ‘skipped’. Report will NOT include ‘sourceIdentity_’ and ‘targetIdentity_’ columns. |
| C:\\Scripts\\entraProvisioningLogsReporter.ps1 -JsonFile “C:\\Scripts\\provisioningLog.Json” -OutputFolder “C:\\Scripts” -Failures -Detailed | Generates report with default value of **false** for _AllRecords_ switch and value of **true** for _Failures_ and _Detailed_ switches. The report will include only records of where Status is NOT ‘success’ or ‘skipped’. Report will include ‘sourceIdentity_’ and ‘targetIdentity_’ columns. |
