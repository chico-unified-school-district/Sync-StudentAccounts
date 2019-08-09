#Requires -Version 3.0
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
[cmdletbinding()]
Param(
 [Parameter(Mandatory = $True)]
 [Alias('DC', 'Server')]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$DomainController,
 # PSSession to Domain Controller and Use Active Directory CMDLETS  
 [Parameter(Mandatory = $True)]
 [Alias('ADCred')]
 [System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)]
 [Alias('FSCred')]
 [System.Management.Automation.PSCredential]$FileServerCredential,
 [Parameter(Mandatory = $true)]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$SISServer,
 [Parameter(Mandatory = $true)]
 [string]$SISDatabase,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$SISCredential,
 [Parameter(Mandatory = $false)]
 [SWITCH]$OneLoop,
 # Include PermID to process one user account
 [Parameter(Mandatory = $false)]
 [int]$PermId,
 # Run UserTasks for all active student accounts 
 [Parameter(Mandatory = $false)]
 [Alias('Tasks')]
 [SWITCH]$UserTasks,
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
$year = "{0:yyyy}" -f $(if ((Get-Date -f MM) -gt 6) { (Get-Date).AddYears(1) } else { Get-Date })
$userAccountExpireDate = Get-Date "August 15 $year"

# Imported Functions
. '.\lib\Add-Log.ps1'           # Format log strings
. '.\lib\Create-GSuiteURL.ps1'  # Create personal GSuite link in users's docs folder.
. '.\lib\Create-HomeDir.ps1'     # Create and configure the user's home directory
. '.\lib\Random-Password.ps1'   # Create random initial password
. '.\lib\Invoke-SQLCommand.ps1 '# Useful function for querying SQL and returning results

$adProperties = 'whenCreated', 'employeeId', 'homepage', 'memberof', 'departmentNumber'
function queryUser ($empId) {
 Get-ADUser -LDAPFilter "(employeeid=$empId)" -Properties $adProperties -Server $DomainController | Select-Object -First 1
}

function setGrade ($grade) {
 switch ($grade) {
  -1 { 'Prek' }; 0 { 'K' }; 1 { '1st' }; 2 { '2nd' }; 3 { '3rd' }; 4 { '4th' }; 5 { '5th' };
  6 { '6th' }; 7 { '7th' }; 8 { '8th' }; 9 { '9th' }; 10 { '10th' }; 11 { '11th' }; 12 { '12th' };
  13 { '12th' }; 14 { '12th' }; 17 { 'Prek' }; 18 { 'Prek' }
 }
}

# Stuff
function setPath ($grade, $path, $departmentNumber) {
 # Skip Handling of School 19 (Special Education) and Grade Over the 18th Level
 if (($grade -le 18) -and ($departmentNumber -ne 19)) {
  "OU={0},{1}" -f (setGrade $grade), $Path # Build proper OU path based on grade level
 }
 else { $path }
}

function userTasks {
 param(
  [Parameter(Mandatory = $True)]
  [ValidateNotNullOrEmpty()]
  $userGuid
 )
 Write-Verbose "Running Student User Tasks for $samid"
 # Read-Host "Pausing First, DUDE !!!"
 $userParams = @{
  AccountExpirationDate = $userAccountExpireDate
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
 }
 Add-Log userparams $samid $WhatIf
 Set-ADUser -Identity $userGuid -Replace $userAttributes -Confirm:$False -WhatIf:$WhatIf

 if ([adsi]::Exists("LDAP://$path")) {
  Add-Log move "$samid,$path" $WhatIf
  Move-ADObject -Identity $userGuid -TargetPath $path -WhatIf:$WhatIf
 }
 else { Add-Log warning "$samid,PATH INVALID:$path" $WhatIf }

 # Clear from Old Groups
 $oldGroups = $userObj.memberof
 if ( $oldGroups ) { 
  Add-Log groupremove $samid $WhatIf
  Remove-ADPrincipalGroupMembership -Identity $userGuid -MemberOf $oldGroups -Confirm:$False
 }
 # Add to New Groups
 $newGroups = $site.StudentGroup, $site.FilterGroup
 Add-Log groupadd $samid $WhatIf
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
 $gmail = "$samid@chicousd.net"
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

do {
 # Begin Major Loop
 $results = Invoke-SQLCommand @dbParams -Query $query
 if ( !$PermId ) {
  $adStuParams = @{
   filter     = { (employeeId -like "*") -and (homepage -like "*@chicousd.net") }
   properties = 'employeeId', 'departmentNumber'
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
  $diffObjects = Compare-Object @compareParams -Property employeeId, departmentNumber
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

 foreach ( $row in $results ) {
  Write-Debug ("Process {0}" -f $row.employeeId)
  Write-Verbose  ($row | Out-String)
  $samid = $row.givenName.SubString(0, 1) + $row.sn.SubString(0, 1) + $row.employeeId
  $empId = $row.employeeId
  # $userRows = $diffResults.Where({})
  # $standardPW = [string](Get-date $row.dob -Format yyMMdd)
  # We never use this password as it is updated by another script shortly after account creation.
  $secureInitialPW = (ConvertTo-SecureString (Random-Password) -AsPlainText -force)
  $gmail = "$samid@ChicoUSD.Net" # Set the CUSD GMail address
  $site = $lookupTable | Where-Object { $_.SC -eq $row.departmentNumber } # Query the site table for a match
  $path = setPath $row.grade $site.path $row.departmentNumber # Build final target OU path for object
  Write-Verbose ("{0} | {1} {2} | {3}" -f $samid, $row.givenName, $row.sn, $site.SiteName)
  $userObj = queryUser $empId
  # New User
  if ( !$userObj ) {
   # Begin Check New User Object
   Add-Log New-ADUSer ('{0},{1}' -f $samid, $site.SiteName) $WhatIf
   $newUserParams = @{
    Name            = $samid
    AccountPassword = $secureInitialPW
    employeeId      = $empId # Foreign DB key
    Path            = 'OU=Disabled_Student_Objects,OU=Disabled_User_Objects,DC=chico,DC=usd'
   }
   New-ADuser @newUserParams -WhatIf:$WhatIf # Create Simple User Object
   if ($userObj = queryUser $empId) {
    # I keep removing this and then I keep putting it back. Just leave it, dude.
    Write-Verbose "$samid,New User - Syncing AD"; Start-Sleep 10 # wait while AD replicates
    UserTasks $userObj.ObjectGUID
   }
   # End  Check New User Object
  }
  elseif ( $userObj.DistinguishedName -notlike "*$path" ) {
   # Begins Move User Object
   # Check GSuite account and unsuspend if needed
   if ((.$gam info user $samid@chicousd.net) -match 'Account Suspended: True') {
    (.$gam update user $samid@chicousd.net suspended off) *>$null
   }
   if ($userObj.name -ne "$samid") {
    Add-Log Rename ("{0} => {1}" -f $userObj.name, $samid) $WhatIf
    Rename-ADObject -Identity $userObj.ObjectGUID -NewName $samid -WhatIf:$WhatIf # fixes object name
   }
   if ( ($userObj.departmentNumber) -and ([int]$userObj.departmentNumber[0] -lt [int]$row.departmentNumber) ) {
    Write-Verbose ("{0} | Lower departmentNumber preferred. Skipping" -f $userObj.samAccountName)
    continue
   }
   UserTasks $userObj.ObjectGUID
  }
  elseif ($UserTasks) { UserTasks $userObj.ObjectGUID }
  Write-Verbose "====== End Processing $samid ======"
 } # End Parse Database Query Results

 if ( $OneLoop -or $PermId -or $WhatIf ) { BREAK }
 else {
  #  Wait x munutes and run again until $endTime
  Write-Host ("Next run at {0}" -f ($nextRun = (Get-Date).AddHours(1))) -ForegroundColor Blue
  do { Start-Sleep 1 } until ( (Get-Date) -ge $nextRun )
 }
} until ( (Get-Date) -ge (Get-Date "5:00pm") ) # End Major Loop

Add-Log script "Tearing down PS Sessions..."
Get-PSSession | Remove-PSSession -WhatIf:$false