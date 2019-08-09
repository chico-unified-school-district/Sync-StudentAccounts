<#
Random Passwords - Special Thanks to Steve König!
https://activedirectoryfaq.com/2017/08/creating-individual-random-passwords/
#>

function Get-RandomCharacters($length, $characters) { 
 $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length } 
 $private:ofs="" 
 return [String]$characters[$random]
}
function Random-Password {
$chars = 'ABCDEFGHKLMNOPRSTUVWXYZabcdefghiklmnoprstuvwxyz1234567890!#'
do {$pw = (Get-RandomCharacters -length 16 -characters $chars)} 
until ($pw -match "\d" -and $pw -match "\w[A-Z]" -and $pw -match "[a-z]") # Make sure minimum criteria met.
$pw # Output random password
}