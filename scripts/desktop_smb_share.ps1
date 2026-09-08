# Share ONE project directory (default: the platform workspace) over SMB to the tailnet only (owner 2026-09-08 10:44: "use smb instead of webdav").
# RUN IN AN ELEVATED POWERSHELL (Run as administrator). Idempotent. Byline: Claude Code · Fable 5.1 · 2026-09-08
#
# Result: \\100.65.61.2\AI_Workspace readable/writable by a dedicated local account `aiws` (password generated
# once into %USERPROFILE%\.secrets\desktop-smb.env), reachable ONLY from Tailscale addresses (100.64.0.0/10).
# The VPS mounts it with:  mount -t cifs //100.65.61.2/<ShareName> /mnt/desktop-share -o credentials=/root/.smb-desktop,uid=1000,gid=1000,vers=3.1.1
param(
  [string]$Path = "E:\AI_Workspace\Projects\the-platform-workspace",   # owner 2026-09-08 10:54: just the-platform-workspace
  [string]$ShareName = "platform-workspace"
)
$ErrorActionPreference = "Stop"
$share = $ShareName; $path = $Path; $user = "aiws"
$sec = Join-Path $env:USERPROFILE ".secrets\desktop-smb.env"
if (-not (Test-Path $sec)) {
    $pw = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 28 | ForEach-Object {[char]$_})
    "# local SMB account for the tailnet share of E:\AI_Workspace - 2026-09-08. Byline: Claude Code · Fable 5.1`nDESKTOP_SMB_HOST=100.65.61.2`nDESKTOP_SMB_SHARE=$share`nDESKTOP_SMB_PATH=$path`nDESKTOP_SMB_USER=$user`nDESKTOP_SMB_PASS=$pw" | Set-Content -Encoding UTF8 $sec
}
$pw = (Select-String -Path $sec -Pattern '^DESKTOP_SMB_PASS=(.+)$').Matches.Groups[1].Value.Trim()
$secure = ConvertTo-SecureString $pw -AsPlainText -Force
if (-not (Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name $user -Password $secure -PasswordNeverExpires -UserMayNotChangePassword -Description "SMB share account (tailnet only)" | Out-Null
} else { Set-LocalUser -Name $user -Password $secure }
# File-system rights: NOT touched. E:\AI_Workspace already carries an inherited
# "NT AUTHORITY\Authenticated Users:(OI)(CI)(M)" ACE (verified 2026-09-08), which covers the local `aiws`
# account. The first run tried Set-Acl on the whole tree and walked it for many minutes — never do that here.
# the share itself
if (-not (Get-SmbShare -Name $share -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $share -Path $path -ChangeAccess $user -CachingMode None -EncryptData $true | Out-Null
} else { Grant-SmbShareAccess -Name $share -AccountName $user -AccessRight Change -Force | Out-Null }
Set-SmbServerConfiguration -EncryptData $true -RejectUnencryptedAccess $true -EnableSMB1Protocol $false -Force
# firewall: SMB (445) from the tailnet only; make sure no broader SMB-in rule is enabled
Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue | Where-Object { $_.Direction -eq "Inbound" } | Disable-NetFirewallRule
if (-not (Get-NetFirewallRule -DisplayName "SMB in (tailnet only)" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "SMB in (tailnet only)" -Direction Inbound -Protocol TCP -LocalPort 445 -RemoteAddress 100.64.0.0/10 -Action Allow -Profile Any | Out-Null
}
Get-SmbShare -Name $share | Format-List Name, Path, EncryptData
Get-SmbShareAccess -Name $share | Format-Table -AutoSize
"share ready: \\$((tailscale ip -4 | Select-Object -First 1))\$share  user=$user  (password in $sec)"
