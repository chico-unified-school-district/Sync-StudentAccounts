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
  Sync-StudentAccounts.ps1 -WhatIf -Verbose
  Runs a TEST Process on all newely added users with verbose output - No changes are made.
 .INPUTS
 .OUTPUTS
  AD Accounts
  AD Group Updates
  SIS database updates
  GSuite Account Set by homepage AD Obj Attribute and GADS
  Home Directories
  Web Shortcut
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
#Requires -Version 3.0

[cmdletbinding()]
Param(
 [Parameter(Mandatory = $True)]
 [Alias('DC', 'Server')]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$DomainController,
 # PSSession to Domain Controller and Use Active Directory CMDLETS
 [Parameter(Mandatory = $True)]
 [Alias('ADCred', 'ac')]
 [System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)]
 [Alias('FSCred', 'fc')]
 [System.Management.Automation.PSCredential]$FileServerCredential,
 [Parameter(Mandatory = $true)]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 3 })]
 [Alias('ss')]
 [string]$SISServer,
 [Parameter(Mandatory = $true)]
 [Alias('sd')]
 [string]$SISDatabase,
 [Parameter(Mandatory = $True)]
 [Alias('sc')]
 [System.Management.Automation.PSCredential]$SISCredential,
 [Parameter(Mandatory = $false)]
 [array]$SkipSiteCodes,
 [Parameter(Mandatory = $false)]
 [Alias('ol')]
 [SWITCH]$OneLoop,
 # Include PermID to process one user account
 [Parameter(Mandatory = $false)]
 [Alias('id', 'pid', 'pi')]
 [int]$PermId,
 # Run UserTasks for all active student accounts
 [Parameter(Mandatory = $false)]
 [Alias('ut')]
 [SWITCH]$UserTasks,
 [Alias('wi')]
 [switch]$WhatIf
)

Clear-Host ; $error.clear() # Clear screen and error log.
Get-PSSession | Remove-PSSession -WhatIf:$false

# AD Domain Controller Session
$adCmdLets = @(
 'Get-ADUser'
 'Set-ADUser'
 'New-ADUser'
 'Move-ADObject'
 'Rename-ADObject'
 'Remove-ADPrincipalGroupMembership'
 'Add-ADPrincipalGroupMembership'
)
$adSession = New-PSSession -ComputerName $DomainController -Credential $ADCredential
Import-PSSession -Session $adSession -Module ActiveDirectory -CommandName $adCmdLets -AllowClobber > $null

$gam = '.\lib\gam-64\gam.exe'

# This json table is used to match site parameters to database results
$lookUpTable = Get-Content -Path .\json\lookupTable.json -Raw | ConvertFrom-Json

# ♥ If current month is greater than 6 (June) Set userAccountExpireDate to August 15th of next year. ♥
# $year = "{0:yyyy}" -f $(if ((Get-Date -f MM) -gt 6) { (Get-Date).AddYears(1) } else { Get-Date })
# $userAccountExpireDate = Get-Date "August 18 $year"

# Imported Functions
. .\lib\Add-Log.ps1             # Format log strings
. .\lib\Compare-Object2.ps1     # Faster Compare Function
. .\lib\Create-GSuiteURL.ps1    # Create personal GSuite link in users's docs folder.
# . .\lib\Create-HomeShortCut.ps1 # Create Shortcut to old H drive
. .\lib\Create-HomeDir.ps1      # Create and configure the user's home directory
. .\lib\Random-Password.ps1     # Create random initial password
. .\lib\Invoke-SQLCommand.ps1   # Useful function for querying SQL and returning results

$adProperties = 'whenCreated', 'employeeId', 'homepage', 'memberof', 'departmentNumber'
function queryUser ($empId) {
 Get-ADUser -LDAPFilter "(employeeid=$empId)" -Properties $adProperties -Server $DomainController | Select-Object -First 1
}

function setGrade ($grade) {
 switch ($grade) {
  -1 { 'Prek' }; -2 { 'Prek '};0 { 'K' }; 1 { '1st' }; 2 { '2nd' }; 3 { '3rd' }; 4 { '4th' }; 5 { '5th' };
  6 { '6th' }; 7 { '7th' }; 8 { '8th' }; 9 { '9th' }; 10 { '10th' }; 11 { '11th' }; 12 { '12th' };
  13 { '12th' }; 14 { '12th' }; 17 { 'Prek' }; 18 { 'Prek' }
 }
}

# Stuff
function setRootOU ($grade, $rootOU, $departmentNumber) {
 # Skip Handling of School 19 (Special Education) and Grades Over the 18th Level
 if (($grade -le 18) -and ($departmentNumber -ne 19)) {
  "OU={0},{1}" -f (setGrade $grade), $rootOU # Build proper OU path based on grade level
 }
 else { $rootOU }
}

function userTasks { # Begin userTask function -----------------------------------------------------------------
 param(
  [Parameter(Mandatory = $True)]
  [ValidateNotNullOrEmpty()]
  $userGuid
 )
 Write-Verbose "Running Student User Tasks for $samid"
 # Read-Host "Pausing First, DUDE !!!"
 $userParams = @{
  AccountExpirationDate = $null
  CannotChangePassword  = $False
  ChangePasswordAtLogon = $False
  PasswordNeverExpires  = $False
  PasswordNotrequired   = $True
  Enabled               = $True
 }
 Set-ADuser -Identity $userGuid @userParams -Confirm:$False -WhatIf:$WhatIf
 $userAttributes = @{
  displayName                = $samid
  samAccountName             = $samid
  userPrincipalName          = "$samid@chicousd.org"
  givenName                  = $row.GivenName
  sn                         = $row.sn
  physicalDeliveryOfficeName = $site.SiteName
  title                      = 'Student'
  description                = 'Student User Account'
  department                 = $site.SiteName
  departmentNumber           = $row.DepartmentNumber
  gecos                      = $row.grade
 }
 # Add-Log userparams $samid $WhatIf
 Set-ADUser -Identity $userGuid -Replace $userAttributes -Confirm:$False -WhatIf:$WhatIf

 # Confirm target Org Unit
 if ( $userObj.DistinguishedName -notlike "*$rootOU*" ) {
  Write-Verbose ('''{0}'' not like ''{1}''' -f $rootOU, $userObj.DistinguishedName)
  Add-Log move ('{0},{1}' -f $samid, $rootOU.Split(",")[0] + ',' + $rootOU.Split(",")[1]) $WhatIf
  try { Move-ADObject -Identity $userGuid -TargetPath $rootOU -WhatIf:$WhatIf }
  catch { Add-Log warning "$samid,PATH INVALID:$rootOU" $WhatIf }
 }

 # Clear from Old Groups
 $oldGroups = $userObj.memberof
 if ( $oldGroups ) {
  # Add-Log groupremove $samid $WhatIf
  Remove-ADPrincipalGroupMembership -Identity $userGuid -MemberOf $oldGroups -Confirm:$False
 }

 # Add to New Groups
 $newGroups = $site.StudentGroup, $site.FilterGroup
 # Add-Log groupadd $samid $WhatIf
 # Assign Password Policy Group for Secondary students
 if ($row.grade -ge 6){
  $newGroups += 'Password-Students-6-12'
 }

 Add-ADPrincipalGroupMembership -Identity $userGuid -MemberOf $newGroups

 if ( $site.FileServer ) {
  $homeDirParams = @{
   FileServer       = $site.FileServer
   ShareName        = $site.ShareName
   samid            = $samid
   ServerCredential = $FileServerCredential
   StaffGroup       = $site.StaffGroup
  }
  Create-HomeDir @homeDirParams -WhatIf:$WhatIf
 }
 else { Write-Verbose ("No Site Fileserver set for {0} at {1}" -f $samid, $site.SiteName) }

 Write-Verbose "Checking GSuite Status"
 $gmail = $samid+'@chicousd.net'
 if ( $row.GSuiteStatus -ne "n" ) {
  # if 'n' then the parent requested no GSuite account/access
  <# We copy this shortcut to the user's homedir and rename it
   to his or her GSuite login. It points to a Google Doc containing helpful GSuite info. #>
  if ( ($site.FileServer) -and (Test-Connection -ComputerName $site.FileServer -Count 1) ) {
   Create-GSuiteURL -Server $site.FileServer -Share $site.ShareName -samid $samid -Cred $FileServerCredential -WhatIf:$WhatIf
  }
  else { Add-Log warning ("$samid,No FileServer for {0}. GSuite URL file not created" -f $site.SiteName) }
  # Update homePage to assit creation of GSUite account
  Set-ADUser -Identity $userGuid -HomePage $gmail
  # Update Chromebook site assignment in Aeries
  $updateDRI = (Get-Content -Path '.\sql\update-DRI.SCL.sql' -Raw) + $empId
  #  Invoke-SQLCommand @dbParams -SqlCmd  $updateDRI -WhatIf:$WhatIf
  $updateDRA = (Get-Content -Path '.\sql\update-DRA.SCL.sql' -Raw) + $empId
  #  Invoke-SQLCommand @dbParams -SqlCmd  $updateDRA -WhatIf:$WhatIf
 }
 else { "[WARNING],GSuite DISABLED for $samid" }
 # Update GSuite Address in SIS Database - STU.SEM and STU.NID
 # Aeries regardless of U12 (GSUITE Enabled) value

 $updateSEM = "Update STU Set stu.sem = `'$gmail`' Where stu.id = $empId"
 Invoke-SQLCommand @dbParams -SqlCmd $updateSEM -WhatIf:$WhatIf

 $updateNID = "Update STU Set stu.nid = `'$gmail`' Where stu.id = $empId"
 Invoke-SQLCommand @dbParams -SqlCmd $updateNID -WhatIf:$WhatIf
 Write-Verbose "Completed Student User Tasks for $samid"
} # End userTask function ----------------------------------------------------------------------------------------

# Student Information System (sis) DB Connection Info
$dbParams = @{
 Server     = $SISServer
 Database   = $SISDatabase
 Credential = $SISCredential
}
if ($Permid) { $query = $(Get-Content -Path .\sql\single-permid.sql -Raw) + $PermId }
else { $query = Get-Content -Path .\sql\active-students.sql -Raw }

# Begin Major Loop
do {
 ###########################
 #  Compare Aeries and AD  #
 ###########################
 $results = Invoke-SQLCommand @dbParams -Query $query
 if ( !$PermId ) {
  $adStuParams = @{
   filter     = { (employeeId -like "*") -and (homepage -like "*@chicousd.net") }
   properties = 'employeeId', 'departmentNumber', 'gecos'
   SearchBase = 'OU=Students,OU=Users,OU=Domain_Root,DC=chico,DC=usd'
  }
  Write-Verbose "Querying Active Directory for current student accounts"
  # "[a-zA-Z][a-zA-Z]\d{5,6}" matches out current naming standard FN+LN+PermID
  $adStudents = Get-ADUser @adStuParams | Where-Object {
   ($_.samAccountName -match "[a-zA-Z][a-zA-Z]\d{5,6}") -and ($_.employeeId -match "\d{5,6}") }
  Write-Verbose "Comparing Aeries and AD results."
  # This section greatly reduces the number of process entries as we only want results for objects that are not currently
  # in the 'OU=Students,OU=Users,OU=Domain_Root,DC=chico,DC=usd' OU
  $compareParams = @{
   ReferenceObject  = $Results
   DifferenceObject = $adStudents
   Debug            = $false
  }
  $diffObjects = Compare-Object2 @compareParams -Property employeeId, departmentNumber, gecos
  $idString = $null
  # need some descriptive comment here of the below logic
  ($diffObjects.Where( { $_.sideindicator -eq "<=" })).employeeId.foreach( { $idString += ("{0}," -f $_) })
  $idString = " ({0})" -f ($idString).Substring(0, $idString.Length - 1) # Trim the trailing comma
  if ($idString) {
   $diffQuery = (Get-Content .\sql\search-ids.sql -Raw) + $idString # Build a query just for the subset of ids
  }
  else { continue } # if idString array is empty then skip this loop.

  $results = Invoke-SQLCommand @dbParams -Query $diffQuery
 }
 ############################
 #  Process Aeries Results  #
 ############################
 foreach ( $row in $results ) {
  Write-Debug ("Process {0}" -f $row.employeeId)
  Write-Verbose  ($row | Out-String)

  # Check Enrollment Status Conflicts
  if ($row.enrstatus -eq "*"){

   $row
   read-host
  }
  $samid = $row.givenName.SubString(0, 1) + $row.sn.SubString(0, 1) + $row.employeeId
  $empId = $row.employeeId
  # We never use this ($secureInitialPW) password
  # as it is updated by another script shortly after account creation.
  $secureInitialPW = (ConvertTo-SecureString (Random-Password) -AsPlainText -force)
  $gmail = "$samid@ChicoUSD.Net" # Set the CUSD GMail address
  $site = $lookupTable | Where-Object { $_.SC -eq $row.departmentNumber } # Query the site table for a match
  $rootOU = setRootOU $row.grade $site.path $row.departmentNumber # Build final target OU path for object
  Write-Verbose $rootOU
  Write-Verbose ("{0} | {1} {2} | {3}" -f $samid, $row.givenName, $row.sn, $site.SiteName)
  $userObj = queryUser $empId

  if ( !$userObj ) {
   #####################
   #  Create New User  #
   #####################
   Add-Log New-ADUSer ('{0},{1}' -f $samid, $site.SiteName) $WhatIf
   $newUserParams = @{
    Name            = $samid
    GivenName       = $row.GivenName
    Surname         = $row.sn
    AccountPassword = $secureInitialPW
    employeeId      = $empId # Foreign DB key
    HomePage        = $gmail
    Path            = 'OU=Disabled_Student_Objects,OU=Disabled_User_Objects,DC=chico,DC=usd'
   }
   New-ADuser @newUserParams -WhatIf:$WhatIf # Create Simple User Object
   Start-Sleep 10 # wait while AD replicates
   if ($userObj = queryUser $empId) {
    # I keep removing this and then I keep putting it back. Just leave it, dude.
    Write-Verbose "$samid,New User - Syncing AD"
   }
   # Move object to student site OU, but not the grade OU to force userTasks funtion to run
   # On the next loop which ensures the Gsuite account has had time to sync.
   Add-Log new-move ('{0},{1}...' -f $samid, $site.path.substring(0,15)) $WhatIf
   Move-ADObject -Identity $userObj.ObjectGUID -TargetPath $site.path -Confirm:$false -WhatIf:$WhatIf
   Set-ADUser -Identity $userObj.ObjectGUID -Enabled $true -WhatIf:$WhatIf
  }
  ######################
  #  Move User Object  #
  ######################
  elseif ( $userObj.DistinguishedName -notlike "*$rootOU*" ) {
   Write-Verbose ('''{0}'' not like ''{1}''' -f $rootOU, $userObj.DistinguishedName)
   # Check GSuite account and unsuspend if needed
   ($gamStatusCheck = .$gam print users query "email:$gmail" fields suspended | convertfrom-csv)*>$null
   if ($gamStatusCheck.suspended -eq $true) {
    Add-Log gsuite ('{0},Activating Account' -f $gmail)
    if ($WhatIf){
     "[WHATIF] $gam update user $gmail suspended off"
    }
    else {
     (.$gam update user $gmail suspended off) *>$null
    }
   }
   if ($userObj.name -ne "$samid") {
    Add-Log Rename ("{0} => {1}" -f $userObj.name, $samid) $WhatIf
    Rename-ADObject -Identity $userObj.ObjectGUID -NewName $samid -WhatIf:$WhatIf # fixes object name whne updated from Aeries
   }

   # Skip operations for students assigned to specific school sites
   # Check number of entries
   $entries = $results | Where-Object ( { $_.employeeId -match $userObj.employeeId } )
   # Skip site if another site is detected and SkipSiteCode array present
   if ($SkipSiteCodes) {
    if ($entries.count -gt 1) {
     if ($SkipSiteCodes -contains [int]$row.departmentNumber) {
      Write-Verbose ('{0} {1} Alternate Site detected. Skipping' -f $samid, $row.departmentNumber)
      continue
     }
    }
   }

   UserTasks $userObj.ObjectGUID

  } # End Move User Object

  elseif ($UserTasks) { UserTasks $userObj.ObjectGUID }
  Write-Verbose "====== End Processing $samid ======"
 } # End Parse Database Query Results

 if ( $OneLoop -or $PermId -or $WhatIf ) { BREAK }
 else {
  #  Wait x minutes and run again until $endTime
  Write-Host ("Next run at {0}" -f ($nextRun = (Get-Date).AddHours(1))) -ForegroundColor Blue
  do { Start-Sleep 1 } until ( (Get-Date) -ge $nextRun )
 }
} until ( (Get-Date) -ge (Get-Date "5:00pm") ) # End Major Loop

Add-Log script "Tearing down PS Sessions..."
Get-PSSession | Remove-PSSession -WhatIf:$false