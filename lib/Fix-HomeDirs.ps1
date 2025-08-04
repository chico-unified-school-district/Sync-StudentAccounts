[cmdletbinding()]
param (
 $Students,
 [Alias('wi')]
 [switch]$WhatIf
)
# ==================== Main =====================
. .\lib\New-HomeDir.ps1
$lookupTable = Get-Content .\json\lookupTable.json -Raw | ConvertFrom-Json

foreach ($stu in $Students) {
 $sc = [int]$stu.departmentNumber[0]
 $site = $lookupTable.where({ $_.SiteCode -eq $sc })
 $newDirParams = @{
  FileServer   = $site.FileServer
  ShareName    = $site.ShareName
  Credential   = $CreateHomeDir
  Domain       = 'Chico'
  Samid        = $stu.SamAccountName
  ModifyAccess = 'chico\is-all'
  FullAccess   = 'chico\Server Admins'
 }
 New-HomeDir @newDirParams -WhatIf:$WhatIf
}
