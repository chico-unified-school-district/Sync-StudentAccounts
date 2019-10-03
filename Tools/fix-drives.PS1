#Requires -Version 3.0
<#
 .DESCRIPTION
  The process queries the Student Information System and uses the results to fix users' home drive permissions
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

# This json table is used to match site parameters to database results
$lookUpTable = Get-Content -Path .\json\lookupTable.json -Raw | ConvertFrom-Json

# Imported Functions
. '.\lib\Add-Log.ps1'           # Format log strings
. '.\lib\Create-HomeDir.ps1'     # Create and configure the user's home directory
. '.\lib\Invoke-SQLCommand.ps1 '# Useful function for querying SQL and returning results

# Student Information System (sis) DB Connection Info
$dbParams = @{
 Server     = $SISServer
 Database   = $SISDatabase
 Credential = $SISCredential
}
$query = Get-Content -Path .\sql\active-students.sql -Raw

$results = Invoke-SQLCommand @dbParams -Query $query

foreach ( $row in $results ) {
 $samid = $row.givenName.SubString(0, 1) + $row.sn.SubString(0, 1) + $row.employeeId
 $site = $lookupTable | Where-Object { $_.SC -eq $row.departmentNumber } # Query the site table for a match

 Write-Verbose ("{0} | {1} {2} | {3}" -f $samid, $row.givenName, $row.sn, $site.SiteName)
 if ( $site.FileServer ) {
  $FileServer = $site.FileServer
  $ShareName = $site.ShareName
  $StaffGroup = $site.StaffGroup

  $homePath = "\\$FileServer\$Sharename\$samid"
  $docsPath = "\\$FileServer\$Sharename\$samid\Documents"
  if ($WhatIf) {
   "$samid | $FileServer | $ShareName | $StaffGroup"
  }
  else {
   if (!(Test-Path -Path $docsPath)) {
    Write-Verbose "Creating HomeDir for $samid on $FileServer."
    New-Item -Path $docsPath -ItemType Directory -Confirm:$false | Out-Null
    # Remove Inheritance and add users and groups
    ICACLS $homePath /inheritance:r /grant "Chico\CreateHomeDir:(OI)(CI)(F)" "BUILTIN\Administrators:(OI)(CI)(F)" | Out-Null
    ICACLS $homePath /grant "SYSTEM:(OI)(CI)(F)" "chico\veritas:(OI)(CI)(M)" "Chico\Domain Admins:(OI)(CI)(F)" | Out-Null
    ICACLS $homePath /grant "${StaffGroup}:(OI)(CI)(M)" "Chico\IS-All:(OI)(CI)(M)" | Out-Null
    ICACLS $homePath /grant "${samid}:(OI)(CI)(RX)" | Out-Null
    ICACLS $docsPath /grant "${samid}:(OI)(CI)(M)" | Out-Null
   }
  }
 }
 else { Write-Verbose ("No Site Fileserver set for {0} at {1}" -f $samid, $site.SiteName) }
} # End Parse Database Query Results

Add-Log script "Tearing down PS Sessions..."