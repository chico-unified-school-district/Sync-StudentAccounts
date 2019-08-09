<##>
function Create-HomeDir {
	[cmdletbinding()]
	param (
  [Parameter(Mandatory = $True)]
  [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
  [string]$FileServer,
  [Parameter(Position = 1, Mandatory = $True)]
  [string]$ShareName,
  [Parameter(Mandatory = $True)]
  [System.Management.Automation.PSCredential]$ServerCredential,
  [Parameter(Mandatory = $True)]
  [string]$samid,
  [Parameter(Mandatory = $True)]
  [string]$StaffGroup,
  [switch]$WhatIf
	)

 Write-Verbose "Running $($MyInvocation.MyCommand.Name)"
 
 if ($WhatIf) { "[TEST],[CREATE-HOMEDIR],$samid,\\$FileServer\$ShareName" }
 else {
  $originalPath = Get-Location
 
  Write-Verbose "Adding PSDrive"
  New-PSDrive -name share -Root \\$FileServer\$ShareName -PSProvider FileSystem -Credential $ServerCredential | Out-Null
 
  Set-Location -Path share:
 
  $homePath = ".\$samid"
  $docsPath = ".\$samid\Documents"
 
  if (!(Test-Path -Path $docsPath)) {
   Write-Verbose "Creating HomeDir for $samid on $FileServer."
   New-Item -Path $docsPath -ItemType Directory -Confirm:$false | Out-Null
   # Remove Inheritance and add users and groups
   ICACLS $homePath /inheritance:r /grant "Chico\CreateHomeDir:(OI)(CI)(F)" "BUILTIN\Administrators:(OI)(CI)(F)" | Out-Null
   ICACLS $homePath /grant "SYSTEM:(OI)(CI)(F)" "chico\veritas:(OI)(CI)(M)" "Chico\Domain Admins:(OI)(CI)(F)" | Out-Null
   ICACLS $homePath /grant "${StaffGroup}:(OI)(CI)(M)" "Chico\IS-All:(OI)(CI)(M)" | Out-Null
   ICACLS $homePath /grant "${samid}:(OI)(CI)(RX)" | Out-Null
   ICACLS $docsPath /grant "${samid}:(OI)(CI)(M)" | Out-Null
   $regthis = "($($samid):\(OI\)\(CI\)\(M\))"
   if ( (ICACLS $docsPath) -match $regthis ) {
    Write-Verbose "HomeDir Created,ACLs correct,\\$FileServer\$ShareName\$samid"
   }
   else {
    "ERROR,ACLs not correct for \\$FileServer\$ShareName\$samid\Documents"  
   } 
  }
 
  Set-Location $originalPath 
 
  Write-Verbose "Removing PSDrive"
  Remove-PSDrive -Name share -Confirm:$false -Force | Out-Null
 }
}