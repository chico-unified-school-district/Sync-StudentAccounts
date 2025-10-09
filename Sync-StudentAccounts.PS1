<#
 .Synopsis
  The process queries the Student Information System and uses the results to generate or modify current
  Active Directory accounts. Here is a list of what the account creates:
  - AD user accounts
  - Home Folders
  - GSuite accounts via an outside syncing process
  - GSuite shortcuts placed in the Users' home folders
  - SIS database updates for student GSuite email accounts
  This script relies upon several external scripts
 .DESCRIPTION
  This script queries the SIS Database
  and creates Student Active Directory User accounts and home directories from the results.
 .EXAMPLE
  Sync-StudentAccounts.ps1 -StopTime '5:00 PM'
 .EXAMPLE
  Sync-StudentAccounts.ps1 -WhatIf -Verbose -Debug
  Runs a TEST Process on all newely added users with verbose output - No changes are made.
 .INPUTS
 .OUTPUTS
  AD Accounts
  AD Group Updates
  SIS database updates
  GSuite Account Set by homePage AD Obj Attribute and GADS
  Home Directories
 .NOTES
  $Database must be updated yearly.
  A DB account with permission to query the Aeries SIS DB.
   and update the STU.NID field.
  The account running the script must have permissions to:
  Add/Move/Modify AD UserObjects
  Modifies Groups Memberships on AD Group Objects
  Creates folders and set permissions on target Home folders via the Windows share name.
  -WhatIf Support Added
#>
[cmdletbinding()]
param(
 $TestData,
 [switch]$OutputResults,
 [Parameter(Mandatory = $True)][Alias('DCs')]  [string[]]$DomainControllers,
 # PSSession to Domain Controller and Use Active Directory CMDLETS
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)][string]$StudentOrgUnit,
 [string[]]$ProtectedADGroups,
 [string]$SecondaryGroup,
 [Parameter(Mandatory = $True)][Alias('FSCred')][System.Management.Automation.PSCredential]$FileServerCredential,
 [string[]]$HomeDirFullAccess,
 [Parameter(Mandatory = $true)][string]$SISServer,
 [Parameter(Mandatory = $true)][string]$SISDatabase,
 [Parameter(Mandatory = $True)][System.Management.Automation.PSCredential]$SISCredential,
 [Parameter(Mandatory = $True)][int[]]$ValidSiteCodes,
 [Parameter(Mandatory = $True)][string]$DistrictDomain,
 [Parameter(Mandatory = $True)][string]$GSuiteDomain,
 [Alias('wi')][switch]$WhatIf
)

function Compare-Data ($adData, $aeriesData) {
 begin { Write-Verbose ('{0}' -f $MyInvocation.MyCommand.Name) }
 process {
  $compareParams = @{
   ReferenceObject  = $aeriesData
   DifferenceObject = $adData
   Property         = 'ID', 'GR', 'SC'
  }
  $results = Compare-Object @compareParams | Where-Object { $_.sideindicator -eq '<=' }
  Write-Verbose ( '{0},Count: {1}' -f $MyInvocation.MyCommand.name, @($output).count)
  $results | Sort-Object
 }
}

function Complete-Processing {
 begin { $i = 0 }
 process {
  $i++
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.sam) -F DarkGreen
  # TODO
  if (!$_.sam) {
   Write-Host ($_ | Out-String)
   # Read-Host 'SAM MISSING'
  }
  Write-Verbose ($MyInvocation.MyCommand.Name, $_ | Out-String )
 }
 end { Write-Host "Total Processed: $i ==================================================" -F Green }
}

function Format-UsrObj ($sisData, $dDomain, $gDomain) {
 process {
  Write-Verbose ($MyInvocation.MyCommand.Name, $_ | Out-String )
  $id = $_.ID
  $stuData = $sisData.Where({ $_.ID -eq $id })
  $sam = $stuData.FN.Substring(0, 1).ToUpper() + $stuData.LN.Substring(0, 1).ToUpper() + $id
  [PSCustomObject]@{
   id         = $id
   sis        = $stuData
   sam        = $sam
   upn        = $sam + $dDomain
   gmail      = $sam + $gDomain
   ad         = $null
   targetOU   = $null
   groupData  = $null
   site       = $null
   gsuiteData = $null
  }
 }
}

function Get-ActiveAD ($ou) {
 begin { Write-Verbose ('{0}' -f $MyInvocation.MyCommand.Name) }
 process {
  # 'gecos' stores Aeries STU.GR (grade level)
  $adProperties = 'EmployeeId', 'departmentNumber', 'Department', 'gecos', 'homePage'
  $params = @{
   Filter     = "EmployeeId -like '*' -and Enabled -eq 'True'"
   # Filter     = "HomePage -like '*@*' -and EmployeeId -like '*' -and Enabled -eq 'True'"
   SearchBase = $ou
   Properties = $adProperties
  }
  $output = Get-ADUser @params |
   Select-Object -Property SamAccountName,
   @{n = 'ID'; e = { [string]$_.EmployeeId.Trim() } },
   @{n = 'SC'; e = { [string]$_.departmentNumber[0].Trim() } } ,
   @{n = 'GR'; e = { [string]$_.gecos.Trim() } }
  Write-Host ('{0}, Count: {1}' -f $MyInvocation.MyCommand.name, @($output).count) -F Green
  $output
 }
}

function Get-ActiveSiS ($sqlParams, $query) {
 begin { Write-Verbose ('{0}' -f $MyInvocation.MyCommand.Name) }
 process {
  $output = New-SqlOperation @sqlParams -Query $query
  Write-Host ('{0}, Count: {1}' -f $MyInvocation.MyCommand.name, @($output).count) -F Green
  $output | ConvertTo-Csv | ConvertFrom-Csv
 }
}

function Get-StuObject ($id) { Get-ADUser -Filter "EmployeeId -eq '$id'" -Properties * }

function New-StuADObject ($stuOu) {
 process {
  if ($_.ad) { return $_ }
  $tempPw = ConvertTo-SecureString -String (New-RandomPassword -length 16) -AsPlainText -Force
  # EmployeeId is Foreign DB key between AD and SiS
  $newObjParams = @{
   EmployeeId        = $_.id
   GivenName         = $_.sis.FN
   Surname           = $_.sis.LN
   DisplayName       = $_.sam
   Name              = $_.sam
   homePage          = $_.gmail
   userPrincipalName = $_.upn
   AccountPassword   = $tempPw
   Title             = 'Student'
   Description       = ($_.site.SiteName + ' Student').Trim()
   department        = $_.site.SiteName
   Path              = $stuOu
  }
  Write-Verbose ($MyInvocation.MyCommand.Name, $newObjParams | Out-String)
  Write-Host ( '{0},{1}' -f $MyInvocation.MyCommand.name, $_.sam) -F DarkMagenta
  New-ADUser @newObjParams -WhatIf:$WhatIf # Create Simple User Object

  return # Complete account creation tasks on the next run cycle
 }
}

function New-StudentHomeDir ($serverUser, $fullAccess) {
 begin {
  . .\lib\New-HomeDir.ps1
  $myDomain = (Get-ADDomain).name.ToUpper()
 }
 process {
  if (!$_.ad -or !$_.site) { return $_ }
  $params = @{
   FileServer = $_.site.FileServer
   ShareName  = $_.site.ShareName
   Credential = $serverUser
   Domain     = $myDomain
   Samid      = $_.sam
   FullAccess = $fullAccess
   WhatIf     = $WhatIf
  }
  New-HomeDir @params
  $_
 }
}

function Out-Results {
 begin {
  Write-Host ( '{0},Outputting results only' -f $MyInvocation.MyCommand.name) -F Blue
  $i = 0
 }
 process {
  $i++
  $_
 }
 end { Write-Host $i -F Blue }
}

function Set-ADData {
 process {
  $_.ad = Get-StuObject $_.id
  if ($_.ad) {
   $_.sam = $_.ad.SamAccountName
   $_.gmail = $_.ad.HomePage
  }
  $_
 }
}

function Set-GroupData ($protectedGroups, $pwGroupSecondary) {
 process {
  if (!$_.ad -or !$_.site) { return $_ }

  $_.groupData = [PSCustomObject]@{current = $null; remove = $null; add = $null }
  $current = $_.ad.memberof | ForEach-Object { $_.split(',')[0].TrimStart('CN').TrimStart('=') }
  $_.groupData.current = $current

  $addGroups = $_.site.StudentGroup, $_.site.FilterGroup
  if ([int]$_.sis.GR -ge 6) { $addGroups += $pwGroupSecondary }

  # Remove - If the group is not in protected and not in the add list then include in the remove group
  $_.groupData.remove = $_.groupData.current | ForEach-Object { if ( ($protectedGroups -notcontains $_ ) -and ($addGroups -notcontains $_)) { $_ } }
  $_.groupData.add = $addGroups | ForEach-Object { if ($current -notcontains $_) { $_ } }

  Write-Verbose ($MyInvocation.MyCommand.Name, $_.sam, $_.groupData | Out-String)
  $_
 }
}

function Set-GsuiteData {
 process {
  if ($_.ad.created -gt (Get-Date).AddMinutes(-60)) { return $_ } # If AD account too new then skip
  ($_.GsuiteData = & $gam print users query "email:$($_.gmail)" fields suspended, archived | ConvertFrom-Csv)*>$null
  $_
 }
}

function Set-OrgUnit {
 process {
  if (!$_.ad -or !$_.site) { return $_ }
  $gradeOU = switch ([int]$_.sis.GR) {
   { $_ -lt 0 } { 'PreK' }; 0 { 'K' }; 1 { '1st' }; 2 { '2nd' }; 3 { '3rd' }
   { $_ -ge 4 -and $_ -le 12 } { "$($_)th" }; default { '12th' }
  }
  # Special Handling of School 19 (Special Education) and Grades Over the 18th Level
  $_.targetOU = if (([int]$_.sis.GR -le 18) -and ([int]$_.sis.SC -ne 19)) {
   # Build proper OU path based on grade level
   'OU={0},{1}' -f $gradeOU, $_.site.OrgUnit
  }
  else { $_.site.OrgUnit }
  $_
 }
}

function Set-SiteData {
 begin { $lookUpTable = Get-Content -Path .\json\lookupTable.json -Raw | ConvertFrom-Json }
 process {
  $siteCode = $_.sis.SC
  $site = $lookUpTable.Where({ [int]$_.SiteCode -eq [int]$siteCode })
  $_.site = if ($site.SiteCode -match '\d') { $site }
  if (!$_.site) { Write-Verbose ('{0},{1},[{2}],No site data' -f $MyInvocation.MyCommand.Name, $_.sam, $siteCode) }
  $_
 }
}

function Skip-BadName {
 process {
  # Skips processing if first and/or last name is missing. Includes latin characters.
  if ($_.sam -match '^[A-Z|\p{L}][A-Z|\p{L}]\d{5,}$') { return $_ }
  Write-Warning ('{0},{1},[{2}]' -f $MyInvocation.MyCommand.Name, $_.id, $_.sam)
 }
}

function Update-ADAttributes {
 process {
  # Only set attributes if gsuite and ad accounts exist
  if (!$_.ad -or !$_.gsuiteData) { return $_ }
  $adDeptNum = try { $_.ad.departmentNumber[0] } catch { $null }
  $description = ($_.site.SiteName + ' Student').Trim()
  $attributeList = @(
   'name,ad,new'
   "sn, $($_.ad.sn),$($_.sis.LN)"
   "GivenName, $($_.ad.GivenName),$($_.sis.FN)"
   "departmentNumber,$adDeptNum,$($_.sis.SC)"
   "department,$($_.ad.department), $($_.site.SiteName)"
   "Description,$($_.ad.Description), $description"
   "gecos,$($_.ad.gecos),$($_.sis.GR)"
   "employeeType,$($_.ad.employeeType),student"
  ) | ConvertFrom-Csv

  foreach ($attrib in $attributeList) {
   if (($attrib.new -is [string]) -and ($attrib.ad -ne $attrib.new)) {
    $msg = $MyInvocation.MyCommand.name, $_.sam , $attrib.name , $attrib.ad, $attrib.new
    Write-Host ( '{0},{1},Attribute:[{2}],Current:[{3}],New:[{4}]' -f $msg) -F DarkMagenta
    Set-ADUser -Identity $_.ad.ObjectGUID -Replace @{$attrib.name = $attrib.new.Trim() } -Confirm:$false -WhatIf:$WhatIf
   }
  }

  if (($_.ad.Enabled -eq $true) -and ($_.ad.AccountExpirationDate -isnot [datetime])) { return $_ }
  Write-Host ('{0},{1},Enabling AD account and clearing AD account expiration' -f $MyInvocation.MyCommand.Name, $_.sam) -F DarkMagenta
  Set-ADUser -Identity $_.ad.ObjectGUID -Enabled:$True -AccountExpirationDate $null -Confirm:$false -WhatIf:$WhatIf
  $_
 }
}

function Update-AeriesStuData ($sqlParams) {
 begin {
  $updateStuSem = 'UPDATE STU SET STU.SEM = @sem Where STU.ID = @id'
  $updateStuNid = 'UPDATE STU SET STU.NID = @nid Where STU.ID = @id'
 }
 process {
  # Only set SIS data if gsuite account exists
  if (!$_.gsuiteData) { return $_ }

  $checkStuData = New-SqlOperation @sqlParams -Query 'SELECT * FROM STU WHERE ID = @id' -Parameters "id=$($_.EmployeeId)"
  if ( ($checkStuData.sem -eq $_.gmail) -and ($checkStuData.nid -eq $_.gmail)) { return $_ }

  $sqlVarsSem = "sem=$($_.gmail)", "id=$($_.id)"
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $updateStuSem, ($sqlVarsSem -join ',')) -F DarkBlue
  if (!$WhatIf) { New-SqlOperation @sqlParams -Query $updateStuSem -Parameters $sqlVarsSem }
  $sqlVarsNid = "nid=$($_.gmail)", "id=$($_.id)"
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $updateStuNid, ($sqlVarsNid -join ',')) -F DarkBlue
  if (!$WhatIf) { New-SqlOperation @sqlParams -Query $updateStuNid -Parameters $sqlVarsNid }
  $_
 }
}

function Update-ADGroupsAdd {
 process {
  if (!$_.ad -and !$_.groupData.add) { return $_ }
  foreach ($group in $_.groupData.add) {
   Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.sam, $group) -F DarkYellow
   Add-ADGroupMember -Identity $group -Members $_.sam -Confirm:$false -WhatIf:$WhatIf
  }
  $_
 }
}

function Update-ADGroupsRemove {
 process {
  if (!$_.ad -and !$_.groupData.remove) { return $_ }
  foreach ($group in $_.groupData.remove) {
   Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.sam, $group) -F DarkYellow
   Add-ADGroupMember -Identity $group -Members $_.sam -Confirm:$false -WhatIf:$WhatIf
  }
  $_
 }
}

function Update-GSuiteArchivedOff {
 process {
  if (!$_.gsuiteData -or $_.gsuiteData.archived -eq 'False') { return $_ }
  # GSuite Archived to 'OFF' if needed```
  $cmd = "& $gam update user $($_.gmail) archived off"
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $_.gmail, $cmd) -F DarkMagenta
  if (!$WhatIf) { (& $gam update user $_.gmail archived off) *>$null }
  $_
 }
}

function Update-GSuiteToActive {
 process {
  if (!$_.gsuiteData -or ($_.gsuiteData.suspended -eq 'False')) { return $_ }
  # GSuite Suspended to 'OFF' if needed```
  $cmd = "& $gam update user $($_.gmail) suspended off"
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $_.gmail, $cmd) -F DarkMagenta
  if (!$WhatIf) { (& $gam update user $_.gmail suspended off) *>$null }
  $_
 }
}

function Update-GsuiteLicense {
 process {
  if (!$_.gsuiteData) { return $_ }
  #SKU: 1010310003 = Google Workspace for Education Plus - Legacy (Student)
  #SKU: 1010310008 = Google Workspace for Education Plus
  $cmd = "& $gam user $($_.gmail) add license 1010310008"
  Write-Host ('{0},{1},[{2}]' -f $MyInvocation.MyCommand.Name, $_.gmail, $cmd) -F DarkCyan
  if (!$WhatIf) { (& $gam user $_.gmail add license 1010310008) *>$null }
  $_
 }
}

function Update-MissingGrade {
 process {
  if ($_.ad.gecos -match '\d') { return $_ } # If grade (gecos) an integer then move on
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.sam)
  # set grade (gecos) to 0 for elementary and set it to 100 for non-elementary
  $tempGrade = if ($_.site.SiteName -match 'Elementary') { 0 } else { 100 }
  Set-ADUser -Identity $_.ad.ObjectGUID -Replace @{gecos = $tempGrade } -WhatIf:$WhatIf
  $_
 }
}

function Update-OrgUnit {
 process {
  if (!$_.targetOU) { return $_ }
  if ($_.ad.DistinguishedName -notmatch $_.targetOU) {
   Write-Host ( '{0},{1},{2}' -f $MyInvocation.MyCommand.name, $_.sam, $_.targetOU ) -F Magenta
   Move-ADObject -Identity $_.ad.ObjectGUID -TargetPath $_.targetOU -Confirm:$False -WhatIf:$WhatIf
  }
  $_
 }
}

function Restore-GSuiteDeleted {
 begin {
  Write-Verbose ('{0},Getting deleted gSuite accounts' -f $MyInvocation.MyCommand.Name)
  ($deletedGSuite = & $gam print users deleted_only | ConvertFrom-Csv) *>$null
 }
 process {
  if ($deletedGSuite.primaryEmail -notmatch $_.gmail) { return $_ }
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.gmail)
  if (!$WhatIf) { (& $gam undelete user $_.gmail) *>$null }
  $_
 }
}

# ============================================================================================

Import-Module -Name dbatools -Cmdlet Invoke-DbaQuery, Connect-DbaInstance, Set-DBAToolConfig
Import-Module -Name CommonScriptFunctions

if ($WhatIf) { Show-TestRun }
Show-BlockInfo main
Show-BlockInfo $SISDatabase

$gam = '.\bin\gam.exe'
$adCmdLets = 'Get-ADDomain', 'Get-ADUser', 'Set-ADUser', 'New-ADUser', 'Move-ADObject',
'Rename-ADObject', 'Remove-ADGroupMember', 'Add-ADGroupMember'

$sqlInstance = @{ Server = Connect-DbaInstance -SqlInstance $SISServer -SqlCredential $SISCredential -Database $SISDatabase }

$siteCodes = $ValidSiteCodes -join ','
$studentQuery = (Get-Content -Path '.\sql\active-students3.sql' -Raw) -replace 'VALID_SITE_CODES', $siteCodes
Write-Verbose ($studentQuery | Out-String)

do {
 Connect-ADSession $DomainControllers $ADCredential $adCmdLets
 $activeSIS = Get-ActiveSiS $sqlInstance $studentQuery
 $activeAD = Get-ActiveAD $StudentOrgUnit
 $results = if ($TestData) { $TestData } else { Compare-Data -AeriesData $activeSIS -ADData $activeAD }
 if ($OutputResults) { $results | Out-Results; exit }

 $results | Format-UsrObj $activeSIS $DistrictDomain $GSuiteDomain | Skip-BadName |
  Set-SiteData |
   Set-ADData |
    Set-OrgUnit |
     New-StuADObject $StudentOrgUnit |
      Update-OrgUnit |
       Update-MissingGrade |
        Set-GroupData $ProtectedADGroups $SecondaryGroup |
         Update-ADGroupsRemove |
          Update-ADGroupsAdd |
           Restore-GSuiteDeleted |
            Set-GsuiteData |
             Update-GSuiteToActive |
              Update-GSuiteArchivedOff |
               Update-GsuiteLicense |
                Update-ADAttributes |
                 Update-AeriesStuData $sqlInstance |
                  New-StudentHomeDir $FileServerCredential $HomeDirFullAccess $DistrictDomain |
                   Complete-Processing

 Clear-SessionData
 if (!$WhatIf) {
  $waitMinutes = 60 - (Get-Date).Minute
  $nextRun = (Get-Date).AddMinutes($waitMinutes)
  Write-Host ('Next run time: {0}' -f $nextRun) -F Green
  Start-Sleep (60 * $waitMinutes)
 }
}
until ( $WhatIf -or ((Get-Date) -gt (Get-Date '5:00PM')))
Show-BlockInfo end
if ($WhatIf) { Show-TestRun }