$params = @{
 Filter     = "employeeid -like '*' -and homepage -like '*'"
 SearchBase = 'OU=Students,OU=Users,OU=Domain_Root,DC=chico,DC=usd'
 Properties = 'WhenCreated', 'EmployeeId', 'whenchanged', 'modified'
}
$cutoff = (Get-Date).AddDays(-7)
$allStudents = Get-ADUser @params | Where-Object {
 ($_.SamAccountName -match "[A-Za-z][A-Za-z]\d{5,6}") -and
 ($_.whenchanged[0] -ge $cutoff)
}
$allStudents.count

$lookUpTable = Get-Content -Path .\lookupTable.json -Raw | ConvertFrom-Json

foreach ( $item in ($lookUpTable.fileserver | ? { $_.length -ne 0 }) ) {
 $item
 if ( test-Path -path \\$item\user ) {
  foreach ( $dir in (ls -path \\$item\userS -Dir | select name ).name ) {
   # $dir
   if ($allStudents.samAccountName -match $dir) {
    $homeDir = "\\$item\users\$dir"
    $homePath = "\\$item\users\$dir\Documents"
    if (Test-Path -Path $homePath) {
     "icacls $homeDir /grant ${dir}:(oi)(ci)(rx)"
     icacls $homeDir /grant "${dir}:(oi)(ci)(rx)"
     "icacls $homePath /grant ${dir}:(oi)(ci)(m)"
     icacls $homePath /grant "${dir}:(oi)(ci)(m)"
     # Read-Host derp
    }
   }
  }
 }
}