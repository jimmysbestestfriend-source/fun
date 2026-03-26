# 1. Enumerate all 'Server' OS machines in the domain via ADSI
$searcher = [adsisearcher]"(&(objectCategory=computer)(operatingSystem=*Server*)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
$fileServers = $searcher.FindAll() | ForEach-Object { $_.Properties.name }

# 2. Discover user-accessible shares on those servers
foreach ($server in $fileServers) {
    # 'net view' lists visible shares; we filter for 'Disk' to avoid printers/pipes
    $shares = net view "\\$server" 2>$null | Select-String "Disk"
    
    if ($shares) {
        foreach ($line in $shares) {
            # Extract share name (logic to split the 'net view' string)
            $shareName = ($line -split '\s{2,}')[0]
            "Found Accessible Share: \\$server\$shareName" -ForegroundColor Cyan | Set-Content -Path "C:\Users\Public\enum.txt"
        }
    }
}
