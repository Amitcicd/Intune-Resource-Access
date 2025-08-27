$reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'CompanyLogonNotice' -ErrorAction SilentlyContinue
$file = Test-Path 'C:\Program Files\Company\LogonNotice\LogonNotice.ps1'
$lnk  = Test-Path "$Env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\GEHealthcare Logon Notice.lnk"
if ($reg -and $file -and $lnk) { exit 0 } else { exit 1 }
