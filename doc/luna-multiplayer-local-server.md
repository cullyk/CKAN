# Luna Multiplayer: local server setup on Windows

Notes from setting up a LAN-accessible Luna Multiplayer (LMP) server on Windows
alongside a CKAN-managed KSP 1.12.5 install.

The short version: **CKAN installs the LMP _client_ only.** There is no server
package in the CKAN repository, so pointing the client at `127.0.0.1:8800`
fails until you download and run the server yourself.

---

## 1. Why the client can't connect out of the box

The CKAN module is named *Luna Multiplayer **Client***, and that is literal.

```bash
ckan show --instance "Kerbal Space Program" LunaMultiplayer | grep -c "GameData/"
# 409 files installed

ckan show --instance "Kerbal Space Program" LunaMultiplayer | grep -i server
# only icons (server.png, restartServer.png) and ServerList*.xml localisation
```

No `Server.exe`, no server DLLs. Confirm nothing is listening:

```bash
netstat -an | grep ":8800"     # empty == no server running
tasklist | grep -i Server.exe  # no process
```

Searching the CKAN repo index confirms there is no server package at all —
only `LunaMultiplayer`, `LunaCompat`, and the unrelated `LunarTransferPlanner`.

The client config at
`GameData/LunaMultiplayer/Data/settings.xml` is usually **fine**; don't go
editing it chasing this fault. A working local entry looks like:

```xml
<Servers>
  <ServerEntry>
    <Port>8800</Port>
    <Name>Local</Name>
    <Address>127.0.0.1</Address>
    <Password></Password>
  </ServerEntry>
</Servers>
```

## 2. Install the server

Download the server from GitHub releases, **matching your client version
exactly** — LMP refuses mismatched builds.

Check the installed client version first:

```bash
ckan list --instance "Kerbal Space Program" --porcelain | grep LunaMultiplayer
# - LunaMultiplayer 0.29.2
```

Then grab the matching server asset:

```bash
curl -sL -o server.zip \
  https://github.com/LunaMultiplayer/LunaMultiplayer/releases/download/0.29.2/LunaMultiplayer-Server-Release.zip
```

Extract it **outside the KSP folder** — the bundled readme is emphatic:

> DO NOT put LMPServer in your GameData folder!!!

A location such as `C:\Users\<you>\LMPServer\` is fine.

## 3. Install the .NET 6 runtime

`Server.exe` targets `net6.0` and performs an explicit runtime version check.
Newer runtimes do **not** satisfy it, and `DOTNET_ROLL_FORWARD=Major` does not
help — the server prints:

```
ERROR: Incorrect .NET runtime detected.
LunaServer requires the .NET 6.0 Runtime to run.
Detected runtime version: 8.0.30
```

Install .NET 6 alongside whatever you already have:

```powershell
winget install --id Microsoft.DotNet.Runtime.6 --accept-package-agreements --silent
```

This triggers a UAC prompt. If run non-interactively the installer will sit
apparently frozen — check for waiting `consent.exe` processes:

```bash
tasklist | grep -i consent
```

Verify afterwards:

```bash
dotnet --list-runtimes | grep "NETCore.App 6"
# Microsoft.NETCore.App 6.0.36 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
```

## 4. First run

Launch via the bundled batch file, which pre-flight checks the runtime and
keeps the window open on error:

```
LMPServer\StartLunaServer.bat
```

Success looks like:

```
[LMP]: Starting 'Luna Server' on Address :: Port 8800...
[LMP]: All systems up and running. Поехали!
```

Verify the socket rather than trusting the log:

```bash
netstat -an | grep ":8800"
#   UDP    0.0.0.0:8800           *:*
#   UDP    [::]:8800              *:*
```

**Stop the server with Ctrl+C, not by closing the window** — a universe backup
is only written on clean shutdown.

## 5. Server config for a modded install

Config lives in `LMPServer/Config/`. Two defaults commonly bite.

### Mod control blocks modded parts

`Config/GeneralSettings.xml` ships with:

```xml
<ModControl>true</ModControl>
```

This enforces a **stock-parts-only whitelist** (`Config/LMPModControl.xml`,
~557 entries). Any craft using modded parts is rejected. Note
`AllowNonListedPlugins` is already `true`, so plugins load fine — the
restriction is specifically on *parts*.

For a private server with a heavily modded install:

```xml
<ModControl>false</ModControl>
```

Trade-off, per the config's own comment: with mod control off, clients missing
mods that others have will get constant "missing part" complaints. Fine when
every client shares an identical mod set.

You can confirm the change took effect: with `ModControl=false` the
`Loading mod control...` line disappears from the startup log.

### The server advertises itself publicly by default

`Config/MasterServerSettings.xml`:

```xml
<RegisterWithMasterServer>true</RegisterWithMasterServer>
```

That publishes your server to the public LMP server list. For a private/LAN
game, set it to `false`. Confirm via the startup log — the line
`Master server registration is active` should no longer appear.

A `Detected NAT addresses: <public-ip>:<port>` debug line may still show; that
is UPnP probing the network, not an advertisement.

## 6. Allowing other machines on the LAN to connect

The server already listens on all interfaces — `Config/ConnectionSettings.xml`
defaults to `<ListenAddress>::</ListenAddress>`, which binds dual-stack
(visible as `0.0.0.0:8800` in `netstat`). **No config change is needed.**

The only blocker is Windows Firewall. Add inbound rules from an **elevated**
PowerShell:

```powershell
New-NetFirewallRule -DisplayName 'Luna Multiplayer Server (UDP 8800)' `
    -Direction Inbound -Action Allow -Protocol UDP -LocalPort 8800 -Profile Private

# Optional: the status/JSON website (WebsiteSettings.xml, EnableWebsite=true)
New-NetFirewallRule -DisplayName 'Luna Multiplayer Status Site (TCP 8900)' `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8900 -Profile Private
```

Scoping to `-Profile Private` keeps the server off untrusted networks. Verify:

```powershell
Get-NetFirewallRule -DisplayName 'Luna Multiplayer*' |
    Select-Object DisplayName, Enabled, Direction, Action, Profile
```

Find the LAN address for the other player to enter:

```bash
ipconfig | grep "IPv4"
```

Ignore virtual adapters (Hyper-V `172.x`, WSL, Docker) — you want the address
on the physical adapter's subnet, e.g. `192.168.8.147`.

The second player adds a server entry with **that LAN IP** and port `8800`.
Both players must have matching LMP client versions, and (with mod control
disabled) ideally identical mod sets.

### Ports summary

| Port | Protocol | Purpose | Needed for LAN play |
|------|----------|---------|---------------------|
| 8800 | UDP | Game traffic | **Yes** |
| 8900 | TCP | Status website / JSON | Optional |

Only forward these on your **router** if you want players from outside your
network — not required for LAN, and not recommended without a password.

## 7. Troubleshooting checklist

| Symptom | Likely cause |
|---|---|
| Client can't connect to `127.0.0.1` | No server installed — CKAN ships client only (§1) |
| Server window flashes and closes | Missing .NET 6 runtime (§3) |
| winget install appears frozen | Waiting UAC prompt; check `tasklist \| grep consent` |
| LAN clients time out, localhost works | Windows Firewall (§6) |
| "Missing part" errors joining | `ModControl` mismatch, or differing mod sets (§5) |
| Universe changes lost after restart | Server closed without Ctrl+C (§4) |

## 8. Compatibility note

LMP's own readme is blunt about heavily modded installs:

> We cannot provide support for other mods in a multiplayer environment so if
> you have other mods besides LMP expect issues!

`LunaCompat` (available via CKAN) smooths over some of this. Test the
connection with a minimal setup before layering on Kopernicus, Parallax, and
similar deep-hooking mods.
