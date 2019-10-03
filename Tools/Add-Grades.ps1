#Requires -Version 3.0
<#
  The process queries the Student Information System and uses the results to modify current
  Active Directory accounts 'gecos' attribute
 .INPUTS
 .OUTPUTS
  AD User Accounts Updates
 .NOTES
  $Database must be updated yearly.
  A DB account with permission to query the Aeries SIS DB.
  The account running the script must have permissions to:
  Modifies Attributes on AD User Objects
#>
[cmdletbinding()]
Param(
 [Parameter(Mandatory = $true)]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$SISServer,
 [Parameter(Mandatory = $true)]
 [string]$SISDatabase,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$SISCredential,
 [switch]$WhatIf
)

Clear-Host ; $error.clear() # Clear screen and error log.

# Imported Functions
. '.\lib\Add-Log.ps1'           # Format log strings
. '.\lib\Create-HomeDir.ps1'     # Create and configure the user's home directory
. '.\lib\Invoke-SQLCommand.ps1 '# Useful function for querying SQL and returning results

$studentOU = 'OU=Students,OU=Users,OU=Domain_Root,DC=chico,DC=usd'
Add-Log info 'Getting student objects'
$studentADObjs = Get-AdUser -Filter { employeeid -like "*" -and homepage -like "*@*" } -Properties employeeid, gecos `
 -SearchBase $studentOU | Where-Object { $_.gecos -isnot 'Int' }

# Student Information System (sis) DB Connection Info
$dbParams = @{
 Server     = $SISServer
 Database   = $SISDatabase
 Credential = $SISCredential
}
$query = Get-Content -Path .\sql\active-students.sql -Raw
$results = Invoke-SQLCommand @dbParams -Query $query

foreach ( $user in $studentADObjs ) {
 # $samid = $row.givenName.SubString(0, 1) + $row.sn.SubString(0, 1) + $row.employeeId
 $grade = $results.Where( { [int]$_.employeeId -eq [int]$user.employeeId }).grade
 $samid = $user.samAccountName

 Write-Verbose ("{0} {1}" -f $samid, $grade)
 try {
  Set-ADUser -identity $user.ObjectGUID -Add @{ gecos = $grade } -WhatIf:$WhatIf 
 }
 catch { Add-Log error ("{0} {1} " -f $samid, $row.grade) }
} # End Parse Database Query Results