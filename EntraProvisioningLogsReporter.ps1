[CmdletBinding(DefaultParameterSetName = 'Changes')]
Param(
    [Parameter(Mandatory=$true, ParameterSetName = 'AllRecords')]
    [Parameter(Mandatory=$true, ParameterSetName = 'Changes')]
    [Parameter(Mandatory=$true, ParameterSetName = 'Failures')]
    [ValidateScript({Test-Path -Path $_ -PathType Leaf })]
    [String]$JsonFile,
    [Parameter(Mandatory=$true, ParameterSetName = 'AllRecords')]
    [Parameter(Mandatory=$true, ParameterSetName = 'Changes')]
    [Parameter(Mandatory=$true, ParameterSetName = 'Failures')]
    [ValidateScript({Test-Path -Path $_ -PathType Container })]
    [String]$OutputFolder,
    [Parameter(Mandatory=$true, ParameterSetName = 'AllRecords')]
    [switch]$AllRecords = $false,
    [Parameter(Mandatory=$true, ParameterSetName = 'Failures')]
    [switch]$Failures = $false,
    [Parameter(Mandatory=$false, ParameterSetName = 'AllRecords')]
    [Parameter(Mandatory=$false, ParameterSetName = 'Changes')]
    [Parameter(Mandatory=$false, ParameterSetName = 'Failures')]
    [switch]$Detailed = $false
)

# Functions required
Function Append-HashTable
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]
        $Source,
        [Parameter(Mandatory = $true)]
        [object]
        $Target,
        [Parameter(Mandatory = $false)]
        [object]
        $PropertyNamePrefix
    )

    if ($null -eq $Source) {
        return $Target
    }
    if ($null -eq $Target) {
        return $null
    }
    if ($Source -is [System.Collections.IDictionary] -or $Source -is [Hashtable])
    {
        foreach ($prop in $Source.Keys)
        {
            $Target.Add(($PropertyNamePrefix + $prop), $Source[$prop])
        }
    }
    else
    {
        foreach ($prop in ($Source.PSObject.Properties | sort -Property name))
        {
            if ($prop.MemberType -notin @('AliasProperty', 'ScriptProperty', 'NoteProperty'))
            {
                continue
            }
            $Target.Add(($PropertyNamePrefix + $prop.Name), $prop.value)
        }
    }
    return $Target
}


$fileTime = (Get-Date).ToString("yyyy-MM-dd_HHmmss")
$baseFileName = ($JsonFile.split('\') | Select-Object -Last 1) -split '\.' | Select-Object -First 1
$OutputCSVFile = "$($OutputFolder)\Report_$($baseFileName)_GeneratedOn_$($fileTime)_$($PSCmdlet.ParameterSetName).csv"

if ($Detailed)
{
    $OutputCSVFile = $OutputCSVFile.Replace(".csv","_Detailed.csv")
}

$StartDate = Get-Date

"Reading JSON - $((Get-Date).ToString("g"))" | Write-Host
if ($PSVersionTable.PSVersion.Major -eq 5)
{
	# Multiple times faster and less memory intensive than other options
    Add-Type -AssemblyName system.web.extensions

    Function Parse-JsonFile([string]$File) {
        $text = [IO.File]::ReadAllText($File)
        $parser = New-Object Web.Script.Serialization.JavaScriptSerializer
        $parser.MaxJsonLength = $text.length
        Write-Output -NoEnumerate $parser.Deserialize($text, [System.Collections.Hashtable[]])
        Remove-Variable text
        [System.GC]::Collect()
    }
    $logObj = Parse-JsonFile -File ($JsonFile | Convert-Path)
}
#included for PS 6 and 7 compatibility, but very inefficient
elseif ($PSVersionTable.PSVersion.Major -eq 6 -or $PSVersionTable.PSVersion.Major -eq 7)
{
    #Memory hog
    $logObj = Get-Content -Path $JsonFile -Raw | ConvertFrom-Json -AsHashTable -DateKind String -NoEnumerate
}

"Reading JSON COMPLETED - $((Get-Date).ToString("g"))" | Write-Host

"Records in file: $($logObj.Count) - $((Get-Date).ToString("g"))" | Write-Host
switch ($PSCmdlet.ParameterSetName)
{
    'AllRecords'
    {
        # all entries
        "No filtering. All log events" | Write-Host
    }
    'Changes'
    {
        # successful exports. Filtering on ProvisioningStatusInfo:Status=Success includes non-changes
        "Filtering for successful exports" | Write-Host
        $logObj = $logObj | where { $_['provisioningSteps'] | where { $_['provisioningStepType'] -eq "export" -and $_['status'] -eq "success" } }
    }
    'Failures'
    {
        # failures
        "Filtering for failures" | Write-Host
        $logObj = $logObj | where {$_['provisioningStatusInfo']['status'] -eq "failure" }
    }
}
"Number of items to process: $($logObj.Count)" | Write-Host
"Processing items - $((Get-Date).ToString("g"))" | Write-Host

$totalProcessedItems = [system.collections.generic.List[Object]]::new($logObj.Count)
$counter = 0
$dynamicColumns = [System.Collections.Generic.HashSet[string]]::new(200)
for ($i = 0; $i -lt $logObj.Count; $i++)
{
    if ($counter -gt 0 -and (($counter % 500) -eq 0 -or $counter -eq $logObj.count))
    {
        Write-Progress -Activity "Processing items" -Status "$($counter) of $($logObj.Count)" -PercentComplete (($counter/$logObj.Count) * 100)
    }
    try
    {
        # *****
        # *****NOTE: logObj[$i] is hashtable. Property\Key names ARE case-sensitive
        # *****

        # prep hashTable with known fields on all objects
        $updateHT = [System.Collections.Hashtable]::new(200)
        $updateHT.Add("id", $logObj[$i]['id'])
        $updateHT.Add("activityDateTime", $logObj[$i]['activityDateTime'].Replace('T', ' ').Replace('Z',''))
        $updateHT.Add("tenantId", $logObj[$i]['tenantId'])
        $updateHT.Add("jobId", $logObj[$i]['jobId'])
        $updateHT.Add("cycleId", $logObj[$i]['cycleId'])
        $updateHT.Add("changeId", $logObj[$i]['changeId'])
        $updateHT.Add("provisioningAction", $logObj[$i]['provisioningAction'])
        $updateHT.Add("sourceSystemDisplayName", $logObj[$i]['sourceSystem']['displayName'])
        $updateHT.Add("targetSystemDisplayName", $logObj[$i]['targetSystem']['displayName'])
        $updateHT.Add("initiatedByDisplayName", $logObj[$i]['initiatedBy']['displayName'])
        $updateHT.Add("provisioningStatusInfoStatus", $logObj[$i]['provisioningStatusInfo']['status'])
        $updateHT.Add("reportableIdentifier", $logObj[$i]['provisioningSteps'].Where({$_['provisioningStepType'] -in "export", "matching", "processing" -and $null -ne $_['details']['ReportableIdentifier']})[0]['details']['ReportableIdentifier'])

        # if AllRecords or Failures selected, include failure details
        switch ($PSCmdlet.ParameterSetName)
        {
            { $_ -in 'AllRecords','Failures' }
            {
                if ($logObj[$i]['provisioningStatusInfo']['status'] -notin "success", "skipped")
                {
                    # failure known fields
                    $updateHT.Add("provisioningStatusInfo_Status", $logObj[$i]['provisioningStatusInfo']['status'])
                    $updateHT.Add("provisioningStatusInfo_errorCode", $logObj[$i]['provisioningStatusInfo']['errorInformation']['errorCode'])
                    $updateHT.Add("provisioningStatusInfo_reason", $logObj[$i]['provisioningStatusInfo']['errorInformation']['reason'])
                    $updateHT.Add("provisioningStatusInfo_additionalDetails", $logObj[$i]['provisioningStatusInfo']['errorInformation']['additionalDetails'])
                    $updateHT.Add("provisioningStatusInfo_errorCategory", $logObj[$i]['provisioningStatusInfo']['errorInformation']['errorCategory'])
                    $updateHT.Add("provisioningStatusInfo_recommendedAction", $logObj[$i]['provisioningStatusInfo']['errorInformation']['recommendedAction'])

                    # not sure if there can be multiple failed steps. Would seem unlikely. Why continue after one step failed?
                    $failedStep = $logObj[$i]['provisioningSteps'].Where({$_['status'] -in "failure", "warning"})[0]
                    $updateHT.Add("provisioningSteps_Status", $failedStep['status'])
                    $updateHT.Add("provisioningSteps_name", $failedStep['name'])
                    $updateHT.Add("provisioningSteps_provisioningStepType", $failedStep['provisioningStepType'])
                    $updateHT.Add("provisioningSteps_description", $failedStep['description'])
                    # append dynamic details properties
                    $updateHT = Append-HashTable -Source $failedStep['details'] -Target $updateHT -PropertyNamePrefix "provisioningSteps_"
                }
            }
        }
        # add sourceIdentity_ properties
        # SourceIdentity object doesn't have any real details, use this to get details of identity in source system.
        # import stepType can have name of EntryImportAdd or EntryImport. Use either and pick 1st
        $updateHT.Add("sourceIdentity_EntraId", $logObj[$i]['sourceIdentity']['id'])

        # Detailed switch determines if we add sourceIdentity_ columns
        if ($Detailed -and $logObj[$i]['provisioningSteps'].Where({$_['provisioningStepType'] -eq "import" -and $_['name'] -in "EntryImportAdd", "EntryImport"}).Count -gt 0)
        {
            $temp = $logObj[$i]['provisioningSteps'].Where({$_['provisioningStepType'] -eq "import" -and $_['name'] -in "EntryImportAdd", "EntryImport"})[0]['details']
            $updateHT = Append-HashTable -Source $temp -Target $updateHT -PropertyNamePrefix "sourceIdentity_"
        }

        # add targetIdentity_ properties
        # TargetIdentity object doesn't have any real details, use this to get details of identity in target system.
        # matching stepType can have name of EntryImportByJoiningProperty or EntryImportByMatchingProperty or EntryImport. Use either and pick 1st
        $updateHT.Add("targetIdentity_EntraId", $logObj[$i]['targetIdentity']['id'])

        # Detailed switch determines if we add targetIdentity_ columns
        if ($Detailed -and $logObj[$i]['provisioningSteps'].Where({$_['provisioningStepType'] -eq "matching" -and $_['name'] -in "EntryImport", "EntryImportByMatchingProperty", "EntryImportByJoiningProperty"}).Count -gt 0)
        {
            $temp = $logObj[$i]['provisioningSteps'].Where({$_['provisioningStepType'] -eq "matching" -and $_['name'] -in "EntryImport", "EntryImportByMatchingProperty", "EntryImportByJoiningProperty"})[0]['details']
            $updateHT = Append-HashTable -Source $temp -Target $updateHT -PropertyNamePrefix "targetIdentity_"
        }

        # add modified properties
        foreach ($property in $logObj[$i]['modifiedProperties'])
        {
            $targetValue = $null
            # If old value is null, use target value from provisioning steps. Else leave null so oldValue will be used
            if ($null -eq $property['oldValue'])
            {
                if ($logObj[$i]['provisioningSteps'].Where({$_['provisioningStepType'] -eq "matching" -and $_['name'] -in "EntryImport", "EntryImportByMatchingProperty", "EntryImportByJoiningProperty"}).Count -gt 0)
                {
                    $targetDetails = $logObj[$i]['provisioningSteps'].Where({$_['provisioningStepType'] -eq "matching" -and $_['name'] -in "EntryImport", "EntryImportByMatchingProperty", "EntryImportByJoiningProperty"})[0]['details']
                    if ($null -ne $targetDetails -and $null -ne $targetDetails[$property['displayName']])
                    {
                        $targetValue = $targetDetails[$property['displayName']]
                    }
                }
            }

            # determine whether to use oldValue or targetValue
            if ($property['oldValue'] -eq $targetValue)
            {
                $updateHT.Add("$($property['displayName'])_oldValue", $property['oldValue'])
            }
            elseif ($null -ne $property['oldValue'])
            {
                $updateHT.Add("$($property['displayName'])_oldValue", $property['oldValue'])
            }
            elseif ($null -ne $targetValue)
            {
                $updateHT.Add("$($property['displayName'])_oldValue", $targetValue)
            }
            # Write warning that neither is null and values not equal
            else
            {
                "Neither oldValue or targetValue are null, but they're not equal - oldValue: '$($property['oldValue'])', targetValue: '$($targetValue)'" | Write-Warning
            }

            if ($null -eq $property['newValue'])
            {
                $updateHT.Add("$($property['displayName'])_updatedValue", "(Null)")
            }
            elseif ([string]::IsNullOrWhiteSpace($property['newValue']))
            {
                $updateHT.Add("$($property['displayName'])_updatedValue", "(EmptyString)")
            }
            else
            {
                $updateHT.Add("$($property['displayName'])_updatedValue", $property['newValue'])
            }
        }
    }
    catch
    {
        "Error parsing record #$($i) with unique id: $($logObj[$i]['id'])" | Write-Host
        $_ | Write-Host
        "Skipping and continuing on" | Write-Host
        continue
    }
    $totalProcessedItems.Add([PSCustomObject]$updateHT)

    foreach ($propertyName in $updateHT.Keys)
    {
        $null = $dynamicColumns.Add($propertyName)
    }
    Clear-Variable updateHT
    $counter++
}
Write-Progress -Activity "Processing items" -Completed
"Processing items COMPLETED - $((Get-Date).ToString("g"))" | Write-Host

# dynamic sourceIdentity\targetIdentity columns
$totalSourceTargetColumns = [System.Collections.Generic.HashSet[string]]::new()
# dynamic oldValue\updatedValue columns
$totalOldNewColumns = [System.Collections.Generic.HashSet[string]]::new()
# dynamic failed columns
$totalFailedColumns = [System.Collections.Generic.HashSet[string]]::new()

# populate columns that DO NOT contain oldValue\updatedValue. These will be the dynamic sourceIdentity_ and targetIdentity_ columns
# populate columns that ONLY contain oldValue\updatedValue. These will be the dynamic oldValue_ and updatedValue_ columns
$dynamicColumns | where { $_.Contains("sourceIdentity") -or $_.Contains("targetIdentity") } | % { $null = $totalSourceTargetColumns.Add($_) }
$dynamicColumns | where { $_.Contains("oldValue") -or $_.Contains("updatedValue") } | % { $null = $totalOldNewColumns.Add($_) }
$dynamicColumns | where { $_.Contains("provisioningStatusInfo") -or $_.Contains("provisioningSteps") } | % { $null = $totalFailedColumns.Add($_) }

# Beginning of CSV always has these columns
$totalColumns = [ordered]@{
    id = $null
    activityDateTime = $null
    tenantId = $null
    jobId = $null
    cycleId = $null
    changeId = $null
    provisioningAction = $null
    sourceSystemDisplayName = $null
    targetSystemDisplayName = $null
    initiatedByDisplayName = $null
    provisioningStatusInfoStatus = $null
    reportableIdentifier = $null
}

# ensure sourceIdentity\targetIdentity columns are always on towards the left of CSV by adding after required columns
foreach ($key in $totalSourceTargetColumns | sort)
{
    try{$totalColumns.Add($key, $null)}catch{ $Error.RemoveAt(0) }
}

# ensure failed columns are always after sourceIdentity\targetIdentity columns
foreach ($key in $totalFailedColumns | sort)
{
    try{$totalColumns.Add($key, $null)}catch{ $Error.RemoveAt(0) }
}

# ensure old\updated columns are always on far right of CSV by adding to end of columns
foreach ($key in $totalOldNewColumns | sort)
{
    try{$totalColumns.Add($key, $null)}catch{ $Error.RemoveAt(0) }
}

"Exporting to CSV - $((Get-Date).ToString("g"))" | Write-Host
if ($totalProcessedItems.Count -gt 0)
{
    "Number of items to export to CSV: $($totalProcessedItems.Count)" | Write-Host
    $totalProcessedItems | select -Property ($totalColumns.Keys -join ',').Split(',') | Export-Csv -Path $OutputCSVFile -NoTypeInformation -Encoding UTF8
}
else
{
    "No items to export to CSV: $($totalProcessedItems.Count)" | Write-Host -ForegroundColor Red
}
"Exporting to CSV COMPLETED - $((Get-Date).ToString("g"))" | Write-Host

Remove-Variable logObj,totalProcessedItems,totalColumns,totalSourceTargetColumns,totalOldNewColumns,dynamicColumns
$EndDate = Get-Date
$ElapsedTime = ($EndDate - $StartDate)
if ($ElapsedTime.Hours -eq 0)
{
    "Elapsed Time : " + $ElapsedTime.Minutes + " Minutes " + $ElapsedTime.Seconds + " Seconds" | Write-Host
}
else
{
    "Elapsed Time : " + $ElapsedTime.Hours + "Hours " + $ElapsedTime.Minutes + " Minutes " + $ElapsedTime.Seconds + " Seconds" | Write-Host
}
[System.GC]::Collect()