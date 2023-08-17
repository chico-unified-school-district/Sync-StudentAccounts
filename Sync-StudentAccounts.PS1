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
Param(
  $TestData,
  [switch]$OutputResults,
  [Parameter(Mandatory = $False)]
  $StopTime,
  [Parameter(Mandatory = $False)]
  [int]$Delay = (60 * 60),
  [Parameter(Mandatory = $True)]
  [Alias('DCs')]
  [string[]]$DomainControllers,
  # PSSession to Domain Controller and Use Active Directory CMDLETS
  [Parameter(Mandatory = $True)]
  [Alias('ADCred')]
  [System.Management.Automation.PSCredential]$ADCredential,
  [Parameter(Mandatory = $True)]
  [Alias('FSCred')]
  [System.Management.Automation.PSCredential]$FileServerCredential,
  [string[]]$HomeDirFullAccess,
  [string[]]$HomeDirModifyAccess,
  [Parameter(Mandatory = $true)]
  [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 3 })]
  [string]$SISServer,
  [Parameter(Mandatory = $true)]
  [string]$SISDatabase,
  [Parameter(Mandatory = $True)]
  [System.Management.Automation.PSCredential]$SISCredential,
  # [Parameter(Mandatory = $True)]
  # [Alias('mscred')]
  # [System.Management.Automation.PSCredential]$MSOLCredential,
  # [Parameter(Mandatory = $True)]
  # [Alias('MsolSku')]
  # [string]$MSOnlineLicenseSkuID,
  [Parameter(Mandatory = $True)]
  [string]$GSuiteDomain,
  [Alias('wi')]
  [switch]$WhatIf
)

function Add-GsuiteLicense ($gam) {
  process {
    if ($_.gsuiteAccount) {
      #SKU: 1010310003 = Google Workspace for Education Plus - Legacy (Student)
      $cmd = "& $gam user {0} add license 1010310003" -f $_.gmail
      Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $cmd) -F DarkCyan
      if ($_.gmail -and -not$WhatIf) { (& $gam user $_.gmail add license 1010310003) *>$null }
    }
    $_
  }
}
function Add-ObjData {
  begin {
    $lookUpTable = Get-Content -Path .\json\lookupTable.json -Raw | ConvertFrom-Json
    $tableProps = ($lookUpTable[0] | Get-Member -MemberType NoteProperty).name
  }
  process {
    Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.employeeId)
    Write-Debug ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.employeeId)
    $stuData = $_ | ConvertTo-Csv | ConvertFrom-Csv
    # Write-Verbose ($stuData | Out-String)
    $deptNum = $_.departmentNumber
    $site = $lookUpTable.Where({ [int]$_.SiteCode -eq [int]$deptNum }) | ConvertTo-Csv | ConvertFrom-Csv
    foreach ($prop in $tableProps) {
      Add-Member -InputObject $stuData -NotePropertyName $prop -NotePropertyValue $site.$prop
    }
    $obj = $_ | Get-StuObject
    if ($obj) {
      $sam = $obj.samaccountname
      $gmail = $obj.homePage
    }
    else {
      $sam = $_.givenName.Substring(0, 1).ToUpper() + $_.sn.Substring(0, 1).ToUpper() + $_.employeeId
      $gmail = ($sam + $GSuiteDomain)
    }
    $stuData.homePage = $gmail
    Add-Member -InputObject $stuData -NotePropertyName sam -NotePropertyValue $sam
    Add-Member -InputObject $stuData -NotePropertyName gmail -NotePropertyValue $gmail
    Add-Member -InputObject $stuData -NotePropertyName  physicalDeliveryOfficeName -NotePropertyValue $site.SiteName
    Add-Member -InputObject $stuData -NotePropertyName  department -NotePropertyValue $site.SiteName
    Write-Verbose ($stuData | Out-String)
    $stuData
  }
}
function Compare-Data {
  param (
    $ADData,
    $AeriesData
  )
  Write-Verbose $MyInvocation.MyCommand.name
  Write-Verbose ('{0},AD Count: {1}, Aeries Count {2}' -f $MyInvocation.MyCommand.name, $ADData.count, $AeriesData.count)
  # . .\lib\Compare-Object2.ps1
  $compareParams = @{
    ReferenceObject  = $AeriesData
    DifferenceObject = $ADData
    Property         = 'employeeId', 'departmentNumber', 'gecos', 'givenName', 'sn', 'homePage', 'Enabled'
    Debug            = $false
  }
  $results = Compare-Object @compareParams | Where-Object { $_.sideindicator -eq '<=' }
  $output = foreach ($item in $results) { $AeriesData.Where({ $_.employeeId -eq $item.employeeId }) }
  Write-Verbose ( '{0},Count: {1}' -f $MyInvocation.MyCommand.name, $output.count)
  Write-Debug 'Get a move on.'
  $output | Sort-Object -Descending
}
function Connect-ADSession {
  # AD Domain Controller Session
  $dc = Select-DomainController $DomainControllers
  $adCmdLets = @(
    'Get-ADDomain'
    'Get-ADUser'
    'Set-ADUser'
    'New-ADUser'
    'Move-ADObject'
    'Rename-ADObject'
    'Remove-ADPrincipalGroupMembership'
    'Add-ADPrincipalGroupMembership'
  )
  New-ADSession -dc $dc -cmdlets $adCmdLets -cred $ADCredential
}
function Connect-MsolSession {
  'MSOnline' | Load-Module
  Connect-MsolService -Credential $MSOLCredential
}
function Get-ActiveAD {
  Write-Verbose $MyInvocation.MyCommand.name
  # 'gecos' stores Aeries STU.GR (grade level)
  $adProperties = @(
    'employeeId'
    'departmentNumber'
    'gecos'
    'givenname'
    'sn'
    'AccountExpirationDate'
    'homePage'
    'info'
    'title'
    'lastlogondate'
    'Enabled'
  )
  $allStuParams = @{
    Filter     = { (homePage -like "*@*") -and (employeeId -like "*") }
    SearchBase = 'OU=Students,OU=Users,OU=Domain_Root,DC=chico,DC=usd'
    Properties = $adProperties
  }

  $output = Get-ADUser @allStuParams | Where-Object {
    $_.samaccountname -match "^\b[a-zA-Z][a-zA-Z]\d{5,6}\b$" -and
    # $_.employeeId -match "^\d{5,6}$" -and
    $_.title -notmatch 'test' -and
    $_.AccountExpirationDate -isnot [datetime] -and
    # $_.LastLogonDate -is [datetime] -and
    $_.Enabled -eq $True
  } | Sort-Object employeeId
  # Write-Host ('{0}, Count: {1}' -f $MyInvocation.MyCommand.name, $output.count) -F Green
  $output
}
function Get-ActiveAeries {
  Write-Verbose $MyInvocation.MyCommand.name
  'SqlServer' | Load-Module
  $sqlParams = @{
    Server     = $SISServer
    Database   = $SISDatabase
    Credential = $SISCredential
  }
  $sqlColumns = 'departmentNumber', 'employeeId', 'grade', 'sn', 'givenname', 'gecos', 'homePage', 'Enabled'
  $query = Get-Content -Path '.\sql\active-students2.sql' -Raw
  $output = Invoke-SqlCmd @sqlParams -Query $query | Select-Object -Property $sqlColumns
  # Write-Host ('{0}, Count: {1}' -f $MyInvocation.MyCommand.name, $output.count) -F Green
  foreach ($row in $output) { $row }
}
function Get-StuObject {
  process {
    $id = $_.employeeId
    $obj = Get-ADUser -Filter "employeeId -eq `'$id`'" -Properties *
    if ($obj.count -gt 1) { Write-Warning ('{0},{1} More than one AD Object with id' -f $_.employeeId, $MyInvocation.MyCommand.name) }
    # Write-Verbose  ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.employeeId )
    $obj
  }
}
function Get-GsuiteUser ($gam) {
  process {
    if ($_.freshness -ne 'tooFresh') {
      # Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $_.gmail)
      ($status = & $gam print users query "email:$gmail" fields suspended | ConvertFrom-Csv)*>$null
      # If Gsuite account is not yet synced then skip
      $gsuiteAccount = if ($null -eq $status) {
        Write-Host ('{0},[{1}], GSuite user NOT found' -f $MyInvocation.MyCommand.Name, $_.gmail) -f Yellow
        $False
      }
      else {
        Write-Host ('{0},[{1}], GSuite user found' -f $MyInvocation.MyCommand.Name, $_.gmail) -f Green
        $True
      }
      $_ | Add-Member -MemberType NoteProperty -Name gamStatus -Value $status.suspended
      $_ | Add-Member -MemberType NoteProperty -Name gsuiteAccount -Value $gsuiteAccount
    }
    Write-Debug ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $_.gmail)
    $_
  }
}
function New-StuADObject {
  begin {
    . .\lib\New-RandomPassword.ps1
  }
  process {
    Write-Verbose ('{0},Checking: [{1}]' -f $MyInvocation.MyCommand.name, $_.employeeId)
    # Write-Host ($_ | Out-String) -F Green
    # $id = $_.employeeId
    $obj = $_ | Get-StuObject
    if (-not$obj) {
      $tempPw = ConvertTo-SecureString -String (New-RandomPassword) -AsPlainText -Force
      #  # EmployeeId is Foreign DB key between AD and Aeries
      $newObjParams = @{
        employeeId        = $_.employeeId
        GivenName         = $_.GivenName
        Surname           = $_.sn
        DisplayName       = $_.sam
        Name              = $_.sam
        homePage          = $_.gmail
        userPrincipalName = $_.sam + '@chicousd.org'
        AccountPassword   = $tempPw
        Title             = 'Student'
        Description       = 'Student User Account'
        department        = $_.SiteName
      }
      Write-Host ( '{0},{1}' -f $MyInvocation.MyCommand.name, $_.sam) -F Green
      # Write-Verbose ($newObjParams | Out-String)
      # Write-Debug ( '{0},{1}' -f $MyInvocation.MyCommand.name, $sam)
      New-ADUser @newObjParams -WhatIf:$WhatIf # Create Simple User Object
      # Used for delayed syncing with external systems such as Gsuite and Azure
      # $global:newAzureUsers.Add($_.employeeId)
      if (-not$WhatIf) { Start-Sleep 10 } # wait while AD replicates
      # Skip the rest of the creation process until GSuite GADS Syncs
      return
    }
    $_ | Add-Member -MemberType NoteProperty -Name created -Value $obj.WhenCreated
    $_
  }
}
function New-StudentHomeDir {
  begin {
    . .\lib\New-HomeDir.ps1
  }
  process {
    if ($_.FileServer) {
      # Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.SiteName) -F Green
      # Write-Debug ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.SiteName)
      $obj = $_ | Get-StuObject
      if ($obj) {
        Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.name, $obj.samaccountname)
        # Write-Host ( '{0},{1},{2}' -f $MyInvocation.MyCommand.name, $sam, $site.FileServer)
        $HomeDirModifyAccess += $_.StaffGroup
        $domain = (Get-ADDomain).name
        $newHomeDirParams = @{
          FileServer = $_.FileServer
          ServerCred = $FileServerCredential
          Domain     = $domain
          Samid      = $obj.samaccountname
          FullAccess = $HomeDirFullAccess
          # ModifyAccess = $HomeDirModifyAccess
          WhatIf     = $WhatIf
        }
        # Write-Verbose ($newHomeDirParams | Out-String)
        New-HomeDir @newHomeDirParams
      }
      else { Write-Warning ('{0},{1},No Object Found' -f $MyInvocation.MyCommand.Name, $_.employeeId) }
    }
    $_
  }
}
function Out-Results {
  begin { Write-Host ( '{0},Outputing results only' -f $MyInvocation.MyCommand.name) -F Blue }
  process { $_ }
  end { Exit }
}
function Set-GSuiteStatus ($gam) {
  process {
    if ($_.gsuiteAccount) {
      $gmail = $_.gmail
      Write-Verbose "& $gam print users query `"email:$gmail`" fields suspended"
      # GSuite Suspended to 'OFF' if needed
      if ($_.gamStatus -eq 'suspended') {
        Write-Host ('{0},{1},Activating Account' -f $MyInvocation.MyCommand.name, $gmail)
        Write-Verbose "& $gam update user $gmail suspended off"
        if (-not$WhatIf) { (& $gam update user $gmail suspended off) *>$null }
      }
    }
    $_
  }
}
function Set-ObjAttributes {
  begin {
    # sql aliases must match AD attribute names
    $attributeNames = 'sn',
    'givenname', 'departmentNumber', 'gecos', 'physicalDeliveryOfficeName', 'department'
  }
  process {
    # Only set attributes if gsuite account exists
    Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.employeeId)
    if ($_.gsuiteAccount) {
      Write-Debug ( '{0},{1}' -f $MyInvocation.MyCommand.name, $_.employeeId)
      $obj = $_ | Get-StuObject
      if ($obj) {
        foreach ($name in $attributeNames) {
          if ( ($obj.$name -ne $_.$name) -and ($null -ne $_.$name) ) {
            $formatData = $MyInvocation.MyCommand.name, $obj.employeeId , $name , $obj.$name, $_.$name
            Write-Host ( '{0},id: [{1}],atrribute: [{2}],current:[{3}], new: [{4}]' -f $formatData) -F Blue
            Set-ADUser -identity $obj.ObjectGUID -Replace @{$name = $_.$name } -Confirm:$false -WhatIf:$WhatIf
          }
        }
        if ($obj.enabled -eq $false) {
          Write-Host ( '{0},{1},Enable User Account' -f $MyInvocation.MyCommand.name, $obj.name) -F Green
          Set-ADUser -identity $obj.ObjectGUID -Enabled:$True -Confirm:$false -WhatIf:$WhatIf
        }
        if ($obj.AccountExpirationDate -is [datetime]) {
          Write-Host ( '{0},{1},Clear Account Expiration' -f $MyInvocation.MyCommand.name, $obj.name) -F Green
          Set-ADUser -identity $obj.ObjectGUID -AccountExpirationDate $null -Confirm:$false -WhatIf:$WhatIf
        }
      }
    }
    $_
  }
}
function Set-OfficeLicense {
  process {
    Write-Verbose ( '{0},{1},{2}' -f $MyInvocation.MyCommand.name, $obj.name, $MSOnlineLicenseSkuID)
    if ($processedMsolUsers -notcontains $_.employeeId) {
      $obj = $_ | Get-StuObject
      $mObj = Get-MsolUser -SearchString $obj.userPrincipalName -All
      if ( $mobj ) {
        if ($mObj.IsLicensed -eq $false) {
          if (-not$WhatIf) {
            Write-Host ( '{0},{1},{2}' -f $MyInvocation.MyCommand.name, $obj.name, $MSOnlineLicenseSkuID) -F DarkGreen
            if (-not$WhatIf) {
              $mobj | Set-MsolUser -UserPrincipalName $_.emailWork -UsageLocation US
              $mobj | Set-MsolUserLicense -AddLicenses $MSOnlineLicenseSkuID
            }
            $global:processedMsolUsers += $_.employeeId
          }
        }
      }
      else {
        if ($global:unProcessedMsolUsers -notcontains $_.employeeId) {
          Write-Verbose ( '{0},{1},Process after Azure Sync.' -f $MyInvocation.MyCommand.name, $_.employeeId)
          $global:unProcessedMsolUsers += $_.employeeId
        }
      }
    }
    $_
  }
}
function Update-ADGroups {
  process {
    Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.employeeId)
    $obj = $_ | Get-StuObject
    if ($obj) {
      # Old Groups
      $oldGroups = $obj.memberof.ForEach( { if ($_ -notlike "*studentAdobeCC*") { $_.split(',')[0].TrimStart('CN=') } })
      if ($oldGroups.count -gt 0) {
        $removeGrpMsgVars = $MyInvocation.MyCommand.Name, $obj.name, ($oldGroups -join ', ')
        Write-Host ('{0},{1},REMOVE,Groups: [{2}]' -f $removeGrpMsgVars) -F DarkYellow
        Remove-ADPrincipalGroupMembership -Identity $obj.ObjectGUID -MemberOf $obj.memberof -Confirm:$False -WhatIf:$WhatIf
      }

      # New Groups
      $newGroups = $_.StudentGroup, $_.FilterGroup
      # Assign Password Policy Group for Secondary students
      if ([int]$_.grade -ge 6) { $newGroups += 'Password-Students-6-12' }
      $addGrpMsgVars = $MyInvocation.MyCommand.Name, $obj.name, ($newGroups -join ', ')
      Write-Host ('{0},{1},ADD,Groups: [{2}]' -f $addGrpMsgVars) -F DarkGreen
      Add-ADPrincipalGroupMembership -Identity $obj.ObjectGUID -MemberOf $newGroups -WhatIf:$WhatIf
      Write-Debug $MyInvocation.MyCommand.name
    }
    $_
  }
}
function Update-AeriesStuData {
  begin {
    'SqlServer' | Load-Module
    $sisParams = @{
      Server     = $SISServer
      Database   = $SISDatabase
      Credential = $SISCredential
    }
    $baseUpdateStuSem = "Update STU Set stu.sem = `'{0}`' Where stu.id = {1}"
    $baseUpdateStuNid = "Update STU Set stu.nid = `'{0}`' Where stu.id = {1}"
  }
  process {
    # Only set SIS data if gsuite account exists
    if ($_.gsuiteAccount) {
      Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.employeeId)
      $checkStuData = Invoke-SQLCmd @sisParams -query ('Select * from stu where id = {0};' -f $_.employeeId)
      if ( ($checkStuData.sem -notlike $_.gmail) -or ($checkStuData.nid -notlike $_.gmail)) {
        $updateStuSem = $baseUpdateStuSem -f $_.gmail, $_.employeeId
        $updateStuNid = $baseUpdateStuNid -f $_.gmail, $_.employeeId
        Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $updateStuSem)
        if (-not$WhatIf) { Invoke-SQLCmd @sisParams -query $updateStuSem }
        Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $updateStuNid)
        if (-not$WhatIf) { Invoke-SQLCmd @sisParams -query $updateStuNid }
      }
    }
    $_
  }
}
function Update-OrgUnit {
  begin {
    function Format-Grade ($grade) {
      switch ($grade) {
        -1 { 'Prek' }; -2 { 'Prek ' }; 0 { 'K' }; 1 { '1st' }; 2 { '2nd' }; 3 { '3rd' }; 4 { '4th' }; 5 { '5th' };
        6 { '6th' }; 7 { '7th' }; 8 { '8th' }; 9 { '9th' }; 10 { '10th' }; 11 { '11th' }; 12 { '12th' };
        13 { '12th' }; 14 { '12th' }; 17 { 'Prek' }; 18 { 'Prek' }
      }
    }
    function Format-OrgUnitPath {
      process {
        # Skip Handling of School 19 (Special Education) and Grades Over the 18th Level
        if (([int]$_.grade -le 18) -and ([int]$_.departmentNumber -ne 19)) {
          # Build proper OU path based on grade level
          'OU={0},{1}' -f (Format-Grade $_.grade), $_.OrgUnit
        }
        else { $_.OrgUnit }
      }
    }
  }
  process {
    $obj = $_ | Get-StuObject
    Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.employeeId)
    if ($obj) {
      $targOrgUnit = $_ | Format-OrgUnitPath
      if ($obj.DistinguishedName -notmatch $targOrgUnit) {
        Write-Host ( '{0},{1},{2}' -f $MyInvocation.MyCommand.name, $obj.name, $targOrgUnit ) -F Green
        Move-ADObject -Identity $obj.DistinguishedName -TargetPath $targOrgUnit -Confirm:$False -WhatIf:$WhatIf
      }
    }
    $_
  }
}
function Complete-Processing ($count) {
  begin {
    $i = 0
    $countDown = $count
  }
  process {
    $countDown--
    Write-Host ('{0},Remaining: {1}' -f $MyInvocation.MyCommand.Name, $countDown) -F Green
    Write-Verbose ('{0} Processing completed.' -f $_.employeeId)
    Write-Debug 'Continue with next user?'
    $i++
  }
  end {
    if ($i -gt 0) { Write-Host ('{0}, Total Processed: {1}' -f $MyInvocation.MyCommand.Name, $i) }
  }
}
function Confirm-Recursion {
  $nextRunDelay = $Delay
  $nextRunTime = Get-Date ((Get-Date).AddSeconds($nextRunDelay)) -Format "h:mm:ss tt"
  if ( (Get-Date) -lt (Get-Date $StopTime) -and (Get-Date) -lt (Get-Date).AddSeconds($nextRunDelay)) {
    Write-Host ( '{0},Delay: {1} secs, Next: {2}, StopTime: {3}' -f $MyInvocation.MyCommand.name, $nextRunDelay, $nextRunTime, $StopTime )
    # Write-Host ( '{0},Running again at [{1}]' -f $MyInvocation.MyCommand.name, $nextRunTime )
    # Write-Host ( '{0},Running until [{1}]' -f $MyInvocation.MyCommand.name, $StopTime )
    Start-Sleep $nextRunDelay
  }
  else {
    Write-Host ( '{0},Completed. StopTime [{1}] reached.' -f $MyInvocation.MyCommand.name, $StopTime)
    Exit
  }
}
filter Skip-BadName {
  if ($_.sam -match "^[A-Z][A-Z]\d{5,6}$") { $_ }
  else {
    Write-Warning ('{0},{1},[{2}]' -f $MyInvocation.MyCommand.Name, $_.employeeId, $_.sam)
  }
}
Write-Host ('{0},Start' -f $MyInvocation.MyCommand.name) -f Magenta
function Sync-Accounts {
  begin {
    $gam = '.\bin\gam.exe'
  }
  process {
    Write-Verbose $MyInvocation.MyCommand.name
    Show-TestRun
    Clear-SessionData
    Connect-ADSession
    Connect-MsolSession

    $results = if ($TestData) { $TestData }
    else {
      $activeAD = Get-ActiveAD
      $activeAeries = Get-ActiveAeries
      Compare-Data -AeriesData $activeAeries -ADData $activeAD
    }
    if ($OutputResults) { $results | Out-Results }

    $results |
    Sort-Object sn |
    Add-ObjData |
    Skip-BadName |
    New-StuADObject |
    Wait-GSuiteSync |
    Get-GsuiteUser $gam |
    Set-GSuiteStatus $gam |
    Add-GsuiteLicense $gam |
    Update-ADGroups |
    Update-OrgUnit |
    New-StudentHomeDir |
    Update-AeriesStuData |
    Set-ObjAttributes |
    Complete-Processing $results.count

    Clear-SessionData
    Show-TestRun
    if ($StopTime -and (-not$TestData)) {
      Confirm-Recursion
      Sync-Accounts
    }
  }
}
function Wait-GSuiteSync {
  process {
    $freshness = if ($_.created -gt (Get-Date).AddMinutes(-60)) { 'tooFresh' } else { 'ok' }
    Write-Host ('{0},[{1}],[{2}],[{3}]' -f $MyInvocation.MyCommand.Name, $_.sam, $_.created, $freshness) -f Blue
    $_ | Add-Member -MemberType NoteProperty -Name freshness -Value $freshness
    $_
  }
}

# Process =====================================================

# Import Functions ==========================================
. .\lib\Clear-SessionData.ps1
. .\lib\Load-Module
. .\lib\New-ADSession.ps1
. .\lib\Select-DomainController.ps1
. .\lib\Show-TestRun.ps1

# $global:newAzureUsers = [System.Collection.ArrayList]::new()
Sync-Accounts
Write-Verbose ( '{0},End' -f $MyInvocation.MyCommand.name )