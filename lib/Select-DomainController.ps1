function Select-DomainController([string[]]$DomainControllers) {
 foreach ($dc in $DomainControllers) {
  if (Test-Connection -ComputerName $dc -Count 1) {
   Write-Host ('Checking {0}' -f $dc)
   $dc
   return
  }
 }
}