<#
 .Synopsis
  The process queries the Student Information System and creates missing H drives
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
 [string[]]$HomeDirFullAccess,
 [string[]]$HomeDirModifyAccess,
 [Parameter(Mandatory = $true)]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 3 })]
 [string]$SISServer,
 [Parameter(Mandatory = $true)]
 [string]$SISDatabase,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$SISCredential,
 [Alias('wi')]
 [switch]$WhatIf
)
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
  Add-Member -InputObject $stuData -NotePropertyName sam -NotePropertyValue $sam
  Add-Member -InputObject $stuData -NotePropertyName gmail -NotePropertyValue $gmail
  Add-Member -InputObject $stuData -NotePropertyName  physicalDeliveryOfficeName -NotePropertyValue $site.SiteName
  Add-Member -InputObject $stuData -NotePropertyName  department -NotePropertyValue $site.SiteName
  Write-Verbose ($stuData | Out-String)
  $stuData
 }
}

function Connect-ADSession {
 # AD Domain Controller Session
 $adCmdLets = @(
  'Get-ADDomain'
  'Get-ADUser'
 )
 $adSession = New-PSSession -ComputerName $DomainController -Credential $ADCredential
 Import-PSSession -Session $adSession -Module ActiveDirectory -CommandName $adCmdLets -AllowClobber | Out-Null
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
 # Write-Host ('{0}, Count: {1}' -f $MyInvocation.MyCommand.name, $output.count) -ForegroundColor Green
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
 # Write-Host ('{0}, Count: {1}' -f $MyInvocation.MyCommand.name, $output.count) -ForegroundColor Green
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

function New-StudentHomeDir {
 begin {
  . .\lib\New-HomeDir.ps1
 }
 process {
  if ($_.FileServer) {
   # Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.SiteName) -ForegroundColor Green
   # Write-Debug ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.SiteName)
   $obj = $_ | Get-StuObject
   if ($obj) {
    Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.name, $obj.samaccountname)
    # Write-Host ( '{0},{1},{2}' -f $MyInvocation.MyCommand.name, $sam, $site.FileServer)
    $HomeDirModifyAccess += $_.StaffGroup
    $domain = (Get-ADDomain).name
    $newHomeDirParams = @{
     FileServer   = $_.FileServer
     ServerCred   = $FileServerCredential
     Domain       = $domain
     Samid        = $obj.samaccountname
     FullAccess   = $HomeDirFullAccess
     ModifyAccess = $HomeDirModifyAccess
     WhatIf       = $WhatIf
    }
    # Write-Verbose ($newHomeDirParams | Out-String)
    New-HomeDir @newHomeDirParams
   }
   else { Write-Warning ('{0},{1},No Object Found' -f $MyInvocation.MyCommand.Name, $_.employeeId) }
  }
  $_
 }
}


filter Complete-StuProcessing {
 Write-Verbose ('{0} Processing completed.' -f $_.employeeId)
}

filter Skip-BadName {
 if ($_.sam -match "^[A-Z][A-Z]\d{5,6}$") { $_ }
 else {
  Write-Warning ('{0},{1},[{2}]' -f $MyInvocation.MyCommand.Name, $_.employeeId, $_.sam)
 }
}
# Import Functions ==========================================
. .\lib\Clear-SessionData.ps1
. .\lib\Load-Module
. .\lib\Show-TestRun.ps1

# Process =====================================================

Show-TestRun
Clear-SessionData
Connect-ADSession

$activeAD = Get-ActiveAD
$activeAeries = Get-ActiveAeries

$results |
Sort-Object sn |
Add-ObjData |
Skip-BadName |
New-StudentHomeDir |

Complete-StuProcessing

Show-TestRun
