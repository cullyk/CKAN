# Adds Windows Firewall inbound rules so other machines on the LAN can reach
# the Luna Multiplayer server on this PC. Must be run elevated (as Administrator).
#
#   UDP 8800 - LMP game traffic (required)
#   TCP 8900 - LMP status website / JSON info endpoint (optional)
#
# Scoped to the Private network profile only, so the server is NOT exposed
# when this machine is on a public/untrusted network.

$ErrorActionPreference = 'Stop'

Write-Host "Adding LMP firewall rules (Private profile only)..." -ForegroundColor Cyan

# Remove any prior versions of these rules so re-running is safe/idempotent
foreach ($n in @('Luna Multiplayer Server (UDP 8800)','Luna Multiplayer Status Site (TCP 8900)')) {
    Get-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue | Remove-NetFirewallRule
}

New-NetFirewallRule `
    -DisplayName 'Luna Multiplayer Server (UDP 8800)' `
    -Direction Inbound `
    -Action Allow `
    -Protocol UDP `
    -LocalPort 8800 `
    -Profile Private `
    -Description 'Allows LAN clients to connect to the Luna Multiplayer KSP server.' | Out-Null

New-NetFirewallRule `
    -DisplayName 'Luna Multiplayer Status Site (TCP 8900)' `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort 8900 `
    -Profile Private `
    -Description 'Allows LAN access to the Luna Multiplayer server status/JSON page.' | Out-Null

Write-Host "`nRules created:" -ForegroundColor Green
Get-NetFirewallRule -DisplayName 'Luna Multiplayer*' |
    Select-Object DisplayName, Enabled, Direction, Action, Profile |
    Format-Table -AutoSize

Write-Host "Done. Press Enter to close." -ForegroundColor Cyan
Read-Host
