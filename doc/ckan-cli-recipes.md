# CKAN CLI recipes (Windows)

Practical notes for driving `ckan.exe` from a shell rather than the GUI —
bulk installs, upgrades, and scripted restores.

Verified against CKAN **v1.36.4** on Windows with KSP 1.12.5.

---

## The registry lock

The GUI holds an exclusive lock on the instance registry. Any CLI command that
touches it fails while the GUI is open:

```
CKAN.RegistryInUseKraken: Lock file with live process ID found at:
  ...\Kerbal Space Program\CKAN\registry.locked
```

**Close the CKAN GUI before running CLI commands.** Check first:

```bash
tasklist | grep -i ckan
```

Delete `registry.locked` manually *only* if you are certain no CKAN process is
live — two CKANs writing at once will corrupt the registry.

## Finding your instance

```bash
ckan instance list
```

```
Name                  Game  Version      Default  Path
--------------------  ----  -----------  -------  ------------------------------
Kerbal Space Program  KSP   1.12.5.3190  No       D:\SteamLibrary\...\Kerbal Space Program
```

Pass that name to every command via `--instance "Kerbal Space Program"`, or set
a default with `ckan instance default`.

## Resolving display names to identifiers

The GUI shows human-readable names ("Astronomer's Visual Pack"); the CLI needs
identifiers (`AstronomersVisualPack`). Rather than guessing, resolve them
against the local repository index:

```
%LOCALAPPDATA%\CKAN\repos\<hash>-KSP-default.json
```

```python
import json
d = json.load(open('4A85405A-KSP-default.json', encoding='utf-8'))
idx = {}
for ident, rec in d['available_modules'].items():
    versions = rec.get('module_version') or {}
    if not versions:
        continue
    idx.setdefault(list(versions.values())[-1].get('name', '').lower(), ident)

print(idx.get("astronomer's visual pack"))   # AstronomersVisualPack
```

Watch for names carrying an author suffix in the metadata — e.g. the GUI's
"SpaceY Heavy Lifters (SYL)" is stored as
*"SpaceY Heavy Lifters (SYL) by NecroBones"*, identifier `SpaceY-Lifters`. A
substring/fuzzy fallback catches these.

`ckan search <term>` works for one-offs, but is slow for bulk resolution.

## Bulk install

```bash
ckan install --instance "Kerbal Space Program" --headless --no-recommends \
    ModuleManager Harmony2 B9PartSwitch Kopernicus Scatterer
```

- `--headless` suppresses all prompts (required for scripting).
- `--no-recommends` installs only what you asked for plus hard dependencies.
  Without it CKAN pulls in a large recommended set.

Dependencies resolve automatically, so listing a dependency explicitly is
harmless.

Large installs (multi-GB texture packs) are best run in the background — a
60-mod visual/parts loadout can pull ~8 GB.

## Listing and reading the status flags

```bash
ckan list --instance "Kerbal Space Program" --porcelain
```

The leading character matters:

| Flag | Meaning |
|------|---------|
| `-` | Installed, current |
| `^` | Installed, **an upgrade is available** |
| `A` | Auto-detected / unmanaged (e.g. Steam DLC) |

`^` is easy to misread as an "orphaned auto-install" marker. It is not — it
means an upgrade is pending. Find them all:

```bash
ckan list --instance "Kerbal Space Program" --porcelain | grep "^\^"
```

Count only managed mods (excluding unmanaged DLC):

```bash
ckan list --instance "Kerbal Space Program" --porcelain | grep -c "^-"
```

## Upgrading

```bash
ckan upgrade --instance "Kerbal Space Program" --headless <identifier>
ckan upgrade --instance "Kerbal Space Program" --headless --all
```

**CKAN may install an older version than the newest available**, and this is
correct behaviour, not a bug: it picks the highest version whose `conflicts`
are satisfiable against your install.

Inspect conflicts in the repo index before assuming a failure:

```python
rec = d['available_modules']['RestockWaterfallExpansion']['module_version']
for v, m in list(rec.items())[-2:]:
    print(m['version'], m.get('conflicts'))
# 3.1.0  [{'name': 'StockWaterfallEffects'}]
# 3.1.1  [{'name': 'WaterfallRestock'}, {'name': 'StockWaterfallEffects'}]
```

Here 3.1.1 was held back purely because `WaterfallRestock` was installed.

## Removing

```bash
ckan remove --instance "Kerbal Space Program" --headless <identifier>
```

### Leftover GameData folders are not always orphans

After removing a mod you may still see its folder in `GameData/`. Before
deleting anything by hand, check whether another mod now *owns* those files:

```bash
ckan show --instance "Kerbal Space Program" <identifier> | grep -c "GameData/"
ckan show --instance "Kerbal Space Program" <identifier> | grep "GameData/SomeFolder"
```

Mods that absorb a predecessor ship the old folder structure themselves and
declare a `conflicts` against it. Deleting the folder would break the
*replacement*.

## Marking auto vs user-selected

```bash
ckan mark user --instance "Kerbal Space Program" --headless <identifier>
ckan mark auto --instance "Kerbal Space Program" --headless <identifier>
```

`mark user` protects a dependency from being auto-removed later.

## Exporting a loadout

**There is no `ckan export` subcommand in the CLI** as of v1.36.4 — export is
GUI-only (File → Export installed mods). To script a restore point, generate
the metapackage from `ckan list` output:

```python
import json, re, datetime

mods = []
for line in open('installed.txt', encoding='utf-8'):
    if line.startswith('A '):        # skip unmanaged DLC
        continue
    m = re.match(r'^[-^]\s+(\S+)\s+(.+)$', line.rstrip())
    if m:
        mods.append((m.group(1), m.group(2).strip()))

pack = {
    "spec_version": "v1.34",
    "identifier": "MyModpack",
    "name": "My Modpack",
    "abstract": "Snapshot of installed mods",
    "author": "me",
    "version": datetime.datetime.now().strftime("%Y.%m.%d"),
    "license": "unknown",
    "kind": "metapackage",
    "ksp_version": "1.12.5",
    "depends": [{"name": i, "version": v} for i, v in mods],
}
json.dump(pack, open('MyModpack.ckan', 'w', encoding='utf-8'), indent=2)
```

Import the resulting `.ckan` via the GUI, or keep a plain reinstall script
containing the identifier list — simpler and easier to diff in git.

## Windows shell notes

These apply when driving CKAN from git-bash / MSYS:

- MSYS path translation is disabled for native binaries. Pass
  `C:/Users/...`-style forward-slash paths to `ckan.exe`, not `/c/Users/...`.
- `taskkill //PID` (MSYS double-slash) fails. Use
  `cmd.exe /c "taskkill /PID <pid> /F"`.
- CKAN emits `\r`-heavy progress output. Filter it for readable logs:
  `ckan install ... | grep -v "left -"`.
- `find` across a Steam library with large texture mods is slow enough to hit
  command timeouts — scope searches narrowly.
