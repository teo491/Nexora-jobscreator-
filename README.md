# Nexora Advanced Jobs Creator

An in-game job creation suite for FiveM. Create jobs, grade ladders, markers,
blips, boss menus, stashes, garages, vehicle lists, duty points, clothing rooms,
shops, armories, crafting benches and teleports from a modern NUI — no file
editing, no restarts.

Works on **QBCore**, **QBox**, **ESX Legacy**, **ox_core** and **standalone**,
with automatic detection and a config override. Inventory, target, clothing,
fuel and key resources are all behind adapters.

---

## Table of contents

1. [Features](#features)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Database setup](#database-setup)
5. [Permissions](#permissions)
6. [Framework configuration examples](#framework-configuration-examples)
7. [Using the creator](#using-the-creator)
8. [Location types](#location-types)
9. [Boss menu](#boss-menu)
10. [Exports / API](#exports--api)
11. [Architecture](#architecture)
12. [Adding your own adapter](#adding-your-own-adapter)
13. [Security model](#security-model)
14. [Performance](#performance)
15. [Troubleshooting](#troubleshooting)
16. [Known limitations](#known-limitations)

---

## Features

**Job creator**
`/jobcreator` opens a dark dashboard NUI with Dashboard, Jobs, Grades, Markers,
Boss Menus, Stashes, Garages, Vehicles and Settings sections. Create, edit,
rename, duplicate, enable/disable and delete jobs. Search, filters, confirmation
dialogs and toasts throughout.

**Grades**
Unlimited grades per job with grade id, internal name, label, salary, boss flag,
per-grade boss permissions and custom metadata. Add, remove, reorder and edit in
the grade editor; the ladder is always renumbered 0..n so there are never gaps.

**Markers & locations**
Per-location marker type, size, colour + alpha, rotation, draw distance,
interaction distance, bob/face-camera/rotate, plus a full blip editor (sprite,
colour palette, scale, alpha, short range, display mode, category, name) with a
live preview in the page and a one-click preview on the in-game map.

**Live world placement**
Enter placement mode from any coordinate field: the page hides, a ghost marker
follows you, the interaction radius and heading are previewed, and ENTER captures
the position back into the form.

**Boss menu**
Employee list (online + offline), hire nearby players, fire, promote, demote, set
an exact grade, edit grade salaries, force employee duty, view the society
balance, deposit, withdraw and read the transaction history — all gated per
feature and per grade permission.

**Stashes**
Multiple stashes per job: id, label, slots, weight, access distance, required
grade / item / permission, optional access code, and job / grade / personal /
shared ownership. Supports `ox_inventory`, `qb-inventory` and `lj-inventory`.

**Garages & vehicles**
Garage name, spawn point + heading, return point + heading, required grade, plate
prefix, warp/keys/fuel/category settings, and a vehicle list where every vehicle
has a category, a minimum grade **or** an explicit grade allow-list, livery,
extras, colours and an optional price paid into the society account.

**Vehicle spawning**
Server-authoritative by default: the server validates everything, checks the
spawn point is clear, creates the entity, tracks it, and cleans up orphans.
Per-player limits, cooldowns, return points, "return all", disconnect cleanup and
optional persistence. Fuel and keys go through adapters
(`ox_fuel`, `LegacyFuel`, `cdn-fuel`, `ps-fuel`; `qb-vehiclekeys`,
`qs-vehiclekeys`, `wasabi_carlock`, `vehicles_keys`, `mk_vehiclekeys`).

**Duty**
Clock-in points, optional auto-duty zones, auto-duty on join, duty state in the
player state bag, and per-job off-duty restrictions for vehicles, stashes, boss
menu, shops, crafting and salary.

**Interaction**
`ox_target` → `qb-target` → marker + key fallback, plus 3D text and `ox_lib`
zones. Per location kind and per location you can force a style. Target systems
are never required.

**ox_lib (optional)**
Used for notifications, context menus, input dialogs, progress bars and zones
when it is installed — and never required: the resource ships its own NUI
fallbacks for all of them.

---

## Requirements

| Requirement | Notes |
|---|---|
| FiveM server (artifact 6683+) | needs `lua54`, server-side entity creation and state bags |
| MySQL / MariaDB | MySQL 5.7+ or MariaDB 10.4+ |
| `oxmysql` **(recommended)** | `mysql-async` and `ghmattimysql` also work |
| A framework | QBCore, QBox, ESX Legacy, ox_core — or none (standalone) |
| An inventory *(optional)* | `ox_inventory`, `qb-inventory`, `lj-inventory` |
| A target system *(optional)* | `ox_target`, `qb-target` |
| `ox_lib` *(optional)* | nicer menus/dialogs; loaded dynamically when present |

Nothing except a database is a hard dependency — the resource starts and reports
what it found in the console.

---

## Installation

1. Drop the folder into your `resources` directory.

2. **The folder name is the resource name.** If you keep the folder as
   `Nexora-jobscreator`, start it with that exact name. For consistency with the
   manifest, renaming the folder to `nexora_jobscreator` is recommended.

3. Add it to `server.cfg` **after** your framework, database and inventory:

   ```cfg
   ensure oxmysql
   ensure qb-core          # or es_extended / ox_core
   ensure ox_lib           # optional
   ensure ox_inventory     # optional
   ensure ox_target        # optional
   ensure nexora_jobscreator
   ```

4. Give yourself permission (see [Permissions](#permissions)):

   ```cfg
   add_ace group.admin jobcreator.admin allow
   ```

5. Start the server. The tables are created automatically and the console prints:

   ```
   [Nexora] database driver: oxmysql
   [Nexora] database schema created
   [Nexora] framework: qbcore (auto detected)
   [Nexora] inventory: ox_inventory
   [Nexora] seeding example jobs...
   [Nexora] loaded 5 jobs, 44 locations
   [Nexora] ready - framework: qbcore | inventory: ox_inventory | database: oxmysql | ox_lib: yes
   ```

6. Type `/jobcreator` in game.

7. Once you are happy, set `Config.SeedExampleJobs = false` (or delete the
   example jobs in the UI).

---

## Database setup

Tables are created and upgraded automatically on start
(`Config.DB.autoMigrate = true`). The applied schema version lives in
`nexora_schema`.

If the MySQL user has no `CREATE` privileges, import [`sql/install.sql`](sql/install.sql)
by hand and set `Config.DB.autoMigrate = false`.

| Table | Holds |
|---|---|
| `nexora_jobs` | job metadata |
| `nexora_job_grades` | the grade ladder (FK → jobs, cascades) |
| `nexora_locations` | every world location, marker, blip and access rule |
| `nexora_stashes` | stash definitions |
| `nexora_garages` | garages, spawn and return points |
| `nexora_garage_vehicles` | vehicle lists and grade restrictions |
| `nexora_boss_menus` | boss menus and which features they expose |
| `nexora_spawned_vehicles` | optional vehicle persistence |
| `nexora_society_accounts` | internal society balances (fallback backend) |
| `nexora_society_transactions` | deposits, withdrawals, purchases, salaries |
| `nexora_job_logs` | audit log of every management action |
| `nexora_settings` | runtime settings edited from the NUI |
| `nexora_players` | standalone-mode job/grade storage |

Relational where it matters (jobs → grades → locations → stashes/garages/
vehicles with real foreign keys); JSON only for whole-object presentation blobs
like a marker or blip definition.

---

## Permissions

Three independent checks, any one of which grants creator access:

**1. ACE permission (works on every framework)**

```cfg
add_ace group.admin jobcreator.admin allow
add_principal identifier.license:abc123... group.admin
```

**2. Framework groups**

```lua
Config.AdminGroups = { 'admin', 'superadmin', 'god' }
```

* QBCore / QBox — checked with `QBCore.Functions.HasPermission`
* ESX — checked against `xPlayer.getGroup()`
* ox_core — checked with `player:getGroup(name)`

**3. Identifier allow-list**

```lua
Config.AdminIdentifiers = {
    ['license:1a2b3c4d5e6f...'] = true,
    ['ABC12345'] = true,   -- citizenid / ESX identifier / ox stateId also work
}
```

Admin status is re-checked on the **server** for every single creator request,
and cached for `Config.PermissionCacheTime` seconds per player.

Boss menu rights are separate: they come from the player's grade
(`is_boss`, or an explicit grade permission such as `hire` or `withdraw`).

---

## Framework configuration examples

### QBCore / QBox

```lua
Config.Framework = 'auto'        -- or 'qbcore'
Config.Inventory = 'auto'        -- or 'qb-inventory' / 'ox_inventory'
Config.Target    = 'auto'        -- or 'qb-target'
Config.AdminGroups = { 'admin', 'god' }
```

Jobs are pushed into `QBCore.Shared.Jobs` (via `AddJob` when available) so
`SetJob`, duty and `qb-management` / `qb-banking` society accounts all work.

### ESX Legacy

```lua
Config.Framework = 'esx'
Config.Inventory = 'ox_inventory'
Config.Duty = { enabled = true, esxOffDutyJobSuffix = false }
```

Jobs are written into the ESX `jobs` / `job_grades` tables and `ESX.RefreshJobs()`
is called, so the job exists for every other ESX resource too. Society money uses
`esx_addonaccount` (`society_<job>`) when installed, otherwise the internal
account table. ESX has no native duty flag, so duty is tracked in the player
state bag; set `esxOffDutyJobSuffix = true` if you also want the classic
`<job>_offduty` swap.

### ox_core

```lua
Config.Framework = 'ox'
Config.Inventory = 'ox_inventory'
Config.Target    = 'ox_target'
```

Jobs become ox_core **groups** with the same grade ladder (`Ox.CreateGroup`),
and a player's job is their group. ox_core already depends on `ox_lib`, so the
`require '@ox_core.lib.init'` path is available.

### Standalone

```lua
Config.Framework = 'standalone'
Config.Inventory = 'none'        -- or ox_inventory, which works standalone
```

Jobs, grades and duty are stored in `nexora_players` keyed by license. Everything
except money works out of the box — see [Known limitations](#known-limitations)
for how to hook up an economy.

---

## Theming

The whole interface — creator, boss menu and the in-game dialogs — is tinted
from one setting:

```lua
Config.Theme = 'azure'   -- azure | violet | emerald | amber | crimson | mono
```

| Theme | Accent |
|---|---|
| `azure` *(default)* | blue to cyan |
| `violet` | indigo to violet |
| `emerald` | green to teal |
| `amber` | amber to orange |
| `crimson` | rose to red |
| `mono` | minimal white / steel |

Every accent in the stylesheet is derived from two RGB triples, so your own
theme is one line in [`web/style.css`](web/style.css):

```css
:root[data-theme="myserver"] { --a1: 236 72 153; --a2: 168 85 247; --accent-text: #fbcfe8; }
```

Then set `Config.Theme = 'myserver'`. Nothing else needs to change.

Job cards also carry their own colour: whatever you set as the job's accent in
the creator (`meta.color`) becomes the coloured rail on that job's cards.

---

## Using the creator

Open it with `/jobcreator` (configurable via `Config.AdminCommand`).

**Create a job**
Jobs → *+ New job* → name (`police`), display name, type, duty and off-duty
rules. A new job starts with an *Employee* and a *Boss* grade.

**Build the ladder**
Grades → *Edit grade ladder*. Each row is a grade; the up arrow reorders them and
they are renumbered from 0 on save. Tick **boss** on the top rank and tick
individual permissions for middle ranks (e.g. a Lieutenant with `hire` and
`promote` but no `withdraw`).

**Place locations**
Markers → *+ New location* → pick the type → **Place in world**. The page hides,
a ghost marker follows you:

| Key | Action |
|---|---|
| `ENTER` | save the position |
| `BACKSPACE` | cancel |
| `ARROW UP` / `ARROW DOWN` | raise / lower |
| `ARROW LEFT` / `ARROW RIGHT` | rotate the heading |
| `G` / `H` | grow / shrink the interaction radius |
| `X` | toggle snap-to-ground |

**Use my position** captures where you are standing without entering placement
mode, and **Go** teleports you to an existing location to check it.

Creating a `stash` or `boss` location automatically creates the matching record,
so you never end up with a dead marker — then tune slots, codes or features in
the Stashes / Boss Menus sections.

**Garages**
Garages → *+ New garage* → place the **spawn point** where vehicles should appear
and optionally a **return point**. Then Vehicles → *+ Add vehicle*: set the spawn
name, category and either a minimum grade or an exact grade allow-list.

> Example: `police` with cruiser at min grade 0, SUV at min grade 2 and the
> helicopter restricted to grade 4 only.

**Settings**
Runtime values stored in `nexora_settings` that override `config.lua` without a
restart: blips, markers, target use, duty behaviour, salary, garage limits,
streaming distances and the security switches.

---

## Location types

| Type | What it does |
|---|---|
| `duty` | clock in / out (optionally automatic on entering the zone) |
| `boss` | opens the boss menu |
| `management` | alias for a boss menu at a second office |
| `stash` | opens a job stash through the inventory adapter |
| `garage` | vehicle list + spawn |
| `vehicle_spawn` | spawn-only point for a garage |
| `vehicle_return` | return / store the vehicle you brought |
| `clothing` | clothing menu and/or named job outfits |
| `shop` | buy items, money goes to the society account |
| `armory` | same as a shop but free by default and permission gated |
| `crafting` | recipes with ingredients, duration and grade gate |
| `teleport` | move to another coordinate (optionally two-way) |
| `custom` | fire your own client or server event |

Each one carries its own marker, blip, access rules (grade, item, permission,
duty) and interaction style.

---

## Boss menu

Walk to a `boss` location and interact. The menu is rendered by this resource's
own NUI, so it looks identical on every framework.

Tabs appear only when the boss menu record enables the feature **and** the
player's grade grants the permission:

| Tab | Needs |
|---|---|
| Employees | `employees` feature |
| Hire | `hire` feature + `hire` permission |
| Grades & salaries | `salary` feature + `manage_salary` permission |
| Funds | `funds` feature + `deposit` / `withdraw` permission |
| Transactions | `transactions` feature + `view_transactions` permission |

Guard rails that are enforced server-side:

* you can only hire players standing next to you,
* you can never promote someone to your own grade or above (unless you are the
  boss grade),
* you cannot fire or demote yourself unless `Config.BossMenu` allows it,
* you cannot act on an employee of an equal or higher grade,
* a non-boss with `manage_salary` cannot set a salary above their own,
* deposits and withdrawals are validated, capped and rolled back if the second
  half of the transfer fails.

Society money uses `qb-banking` / `qb-management` / `esx_addonaccount` /
ox accounts when available, otherwise the internal `nexora_society_accounts`
table. Every movement is written to `nexora_society_transactions`.

---

## Exports / API

Server exports:

```lua
local jobs    = exports['nexora_jobscreator']:GetJobs()
local police  = exports['nexora_jobscreator']:GetJob('police')
local grade   = exports['nexora_jobscreator']:GetJobGrade('police', 2)

local onDuty  = exports['nexora_jobscreator']:IsOnDuty(source)
exports['nexora_jobscreator']:SetDuty(source, true)

local isAdmin = exports['nexora_jobscreator']:IsAdmin(source)
local canFire = exports['nexora_jobscreator']:HasBossPermission(source, 'police', 'fire')

local balance = exports['nexora_jobscreator']:GetSocietyBalance('police')
exports['nexora_jobscreator']:AddSocietyMoney('police', 500, 'fine revenue')
exports['nexora_jobscreator']:RemoveSocietyMoney('police', 500, 'equipment')

exports['nexora_jobscreator']:ReloadJobs()
```

Console commands:

```
jobcreator reload     # re-read every job from the database
jobcreator seed       # (re)import the example jobs
jobcreator list       # print every job
```

Client events you can listen to:

```lua
AddEventHandler('nexora:client:dutyChanged', function(onDuty) end)
AddEventHandler('nexora:client:outfitSelected', function(data) end)  -- { job, grade, outfit, location }
```

A `custom` location fires the event you configure — on the client with the
location as its argument, or on the server as `event(source, location)` when
*Server event* is ticked (the server reads the event name from its own copy of
the location, so a client can never ask it to fire something else).

---

## Architecture

```
nexora_jobscreator/
├── fxmanifest.lua
├── config.lua                 every default, documented inline
├── README.md
├── sql/install.sql            manual schema (optional)
├── shared/
│   ├── oxlib.lua              optional ox_lib bootstrap
│   ├── definitions.lua        enums, defaults, NUI definitions
│   ├── utils.lua              logging, tables, json, geometry, notify
│   ├── validate.lua           payload validation / sanitisation
│   ├── callback.lua           client -> server callbacks + rate limiting
│   └── examples.lua           the five example jobs
├── client/
│   ├── main.lua               state, sync, UI facade (menu/input/confirm/progress)
│   ├── creator.lua            NUI bridge + live world placement
│   ├── markers.lua            spatial-hash streaming, markers, blips
│   ├── interactions.lua       location -> handler wiring, duty zones
│   ├── duty.lua               clock in/out
│   ├── boss.lua               boss menu bridge
│   ├── stash.lua              stashes, shops, armories, crafting
│   ├── garage.lua             vehicle list, spawn, cosmetics, fuel, keys
│   └── clothing.lua           clothing resource adapters
├── server/
│   ├── database.lua           driver adapter + migrations
│   ├── permissions.lua        admin / boss permission checks + audit log
│   ├── society.lua            society accounts + transactions
│   ├── jobs.lua               the job store, CRUD, client sync, seeding
│   ├── duty.lua               duty state + location access validation
│   ├── boss.lua               boss menu endpoints
│   ├── stash.lua              stash / shop / crafting endpoints
│   ├── garage.lua             spawn authorisation, tracking, cleanup
│   └── main.lua               settings, boot, command, exports
├── adapters/                  framework.lua + qbcore / esx / ox / standalone
├── inventory/                 inventory.lua + ox / qb / lj
├── interaction/               interaction.lua + ox_target / qb-target / fallback
└── web/                       index.html, style.css, app.js
```

The rule the whole resource follows: **no framework, inventory or target specific
code outside its adapter.** Everything else talks to
`Framework.*`, `Inventory.*` and `Interaction.*`.

```lua
Framework.GetPlayer(source)
Framework.GetJob(source)
Framework.SetJob(source, job, grade)
Framework.SetJobOffline(identifier, job, grade)
Framework.GetDuty(source) / Framework.SetDuty(source, state)
Framework.GetPlayers() / Framework.GetPlayersByJob(job) / Framework.GetOfflineEmployees(job, limit)
Framework.AddMoney(source, account, amount) / RemoveMoney / GetMoney
Framework.GetSocietyMoney(job) / AddSocietyMoney / RemoveSocietyMoney
Framework.RegisterJob(job, grades) / UnregisterJob(job)
Framework.GetGroup(source) / HasGroup(source, groups)
Framework.GetItemCount(source, item)
```

Anything an adapter does not implement falls back to a safe no-op, so a partial
adapter degrades instead of erroring.

---

## Adding your own adapter

**Framework** — create `adapters/myframework.lua`, add it to `shared_scripts`:

```lua
local function detect()
    return GetResourceState('my_core') == 'started'
end

Framework.Register('myframework', {
    priority = 15,            -- lower wins during auto detection
    detect = detect,
    init = function() end,
    server = {
        GetJob = function(src) ... end,
        SetJob = function(src, job, grade) ... end,
        -- implement as much or as little as you like
    },
    client = {
        GetJob = function() ... end,
        Subscribe = function(cb) ... end,
    },
})
```

**Inventory** — `inventory/my_inventory.lua`:

```lua
Inventory.Register('my_inventory', {
    priority = 15,
    detect = function() return GetResourceState('my_inventory') == 'started' end,
    server = {
        RegisterStash = function(stash, key) ... end,
        OpenStash = function(src, stash, key) ... end,
        GetItemCount = function(src, item) ... end,
        AddItem = function(src, item, count) ... end,
        RemoveItem = function(src, item, count) ... end,
    },
    client = { OpenStash = function(key) ... end },
})
```

**Target** — `interaction/my_target.lua`:

```lua
Interaction.Register('my_target', {
    kind = 'target', priority = 15,
    detect = function() return GetResourceState('my_target') == 'started' end,
    Add = function(zone) ... return true end,
    Remove = function(id) ... end,
})
```

Fuel and key resources are plain tables at the top of `client/garage.lua`; add an
entry with `name`, `detect` and `set` / `give`.

---

## Security model

The resource is server-authoritative throughout.

* **Nothing the NUI sends is trusted.** Creator requests go
  client → server callback, and the server re-checks the admin permission on
  *every* request before touching the database.
* **Every payload is validated** by `shared/validate.lua`: types are rejected,
  numbers are clamped to `Config.Security`, strings are trimmed and stripped of
  control characters, coordinates are bounds- and NaN-checked, unknown keys are
  dropped, and enums must match `shared/definitions.lua`.
* **Prepared statements only** — no user input is ever concatenated into SQL.
* **Rate limiting**: a per-player token bucket
  (`Config.Security.maxCallbacksPerSecond`) drops callback floods, and unknown
  endpoints are logged.
* **Distance validation**: the server reads the player's real ped coordinates
  and refuses stash/boss/garage/duty actions from out of range
  (`Config.Security.validateDistance`).
* **Grade and permission checks** happen server-side using the server's own copy
  of the job, not the client's.
* **Money**: amounts must be positive integers under `maxSocietyTransaction`;
  every transfer is two-phase with a rollback if the second half fails; every
  movement is logged with the actor.
* **Stash keys are computed on the server** from the stash record plus the
  player's identity — the client only names a location id, never a stash.
* **Vehicles**: the server decides which models a grade may take, generates the
  plate, checks the spawn point, creates the entity and tracks it. In client-spawn
  mode the grant is single-use and the reported entity's model and position are
  verified, then deleted if they do not match.
* **Crafting** is two-phase with a server-side timestamp so the duration cannot
  be skipped, and ingredients are re-checked and rolled back on failure.
* **Custom events** are read from the server's own location record, so a client
  cannot ask the server to fire an arbitrary event.
* Boss menu requests take their location id from the menu the client actually
  opened, not from the page.
* Every management action is written to `nexora_job_logs`.

---

## Performance

* Locations are bucketed into a spatial hash (`Config.World.gridSize`); only the
  3×3 cells around the player are ever scanned.
* The proximity scan runs on an interval (`Config.World.scanInterval`, default
  500 ms) and sleeps for `idleInterval` when nothing is nearby.
* The per-frame draw thread only spins while a marker is within its draw
  distance — otherwise it sleeps 500 ms.
* Interaction zones are registered and unregistered as you move, so a target
  system only ever holds the handful of zones that are nearby, even with hundreds
  of locations.
* The marker/key fallback keeps one 250 ms scan thread and only goes per-frame
  while you are inside a zone.
* Clients receive the full location set for **their own job only**, plus the
  public blip list. No client ever holds the whole world.
* Everything is loaded in 7 queries on start and kept in memory; a save writes
  and reloads rather than querying per interaction.
* Blips are rebuilt only on sync and duty changes.

---

## Troubleshooting

**`no MySQL resource found`**
`oxmysql` (or `mysql-async` / `ghmattimysql`) is not started before this
resource. Fix the start order in `server.cfg`.

**`/jobcreator` does nothing**
You do not have permission. Check the console for
`tried to use "jobcreator" without permission`, then add
`add_ace group.admin jobcreator.admin allow` and make sure you are in that
group, or add your license to `Config.AdminIdentifiers`.

**`framework: standalone` but I run QBCore/ESX**
The framework resource was not started yet when detection ran. Start this
resource after your framework, or force it: `Config.Framework = 'qbcore'`.

**`ox_lib found but failed to initialise`**
Harmless — the resource falls back to its own menus and dialogs. Update `ox_lib`,
or set `Config.UseOxLib = false` to stop trying.

**Stashes do nothing**
`inventory: none` in the console means no supported inventory was detected. Set
`Config.Inventory` explicitly, or add an adapter in `inventory/`.

**Markers show but nothing happens when I press E**
Another resource is using the same key, or the location has an access rule you do
not meet (grade, item, duty). Set `Config.Debug = true` and watch the console —
the server tells you which check failed.

**`the vehicle could not be created`**
Server-side spawning needs the model to exist on the server. For custom add-on
vehicles that are client-only, set
`Config.Garages.serverSideSpawn = false` to use the verified client-spawn path.

**Vehicle spawns then disappears**
Another garage/vehicle cleanup script is deleting it, or
`Config.Garages.orphanTimeout` expired while it sat empty. Raise the timeout or
set it to `0`.

**Jobs do not show up in my framework's own menus**
A job must be **enabled** to be registered with the framework. For ESX, check
that the rows landed in the ESX `jobs` / `job_grades` tables.

**Example jobs came back after I deleted them**
`Config.SeedOverwrite` is `true`. Set it to `false` (seeding is normally a
one-time action tracked by the `examples_seeded` row in `nexora_settings`).

---

## Known limitations

Stated plainly so there are no surprises:

* **Standalone mode has no economy.** `Framework.AddMoney` / `RemoveMoney`
  return `false`, so paid shop items, vehicle prices and salaries do nothing.
  Jobs, grades, duty, stashes, garages and society balances all work. To add an
  economy, implement those three functions in `adapters/standalone.lua`.
* **ox_core** support is built on the documented `Ox.*` API
  (`GetPlayer`, `setGroup`, `CreateGroup`) and its `characters` /
  `character_groups` tables. Group bank accounts are attempted through
  `Ox.GetGroupAccount`; if that is unavailable the internal society table is used
  instead. ox_core requires `ox_lib`.
* **Clothing outfits**: opening the clothing menu is adapter-driven and works
  with `illenium-appearance`, `fivem-appearance`, `qb-clothing`, `esx_skin` and
  `ox_appearance`. *Applying a named job outfit* depends on the wardrobe
  resource; the best-effort call is attempted and the selection is always
  broadcast as `nexora:client:outfitSelected` so you can wire your own in one
  line.
* **Example job coordinates are approximate** interior positions meant to be
  repositioned with the placement tool.
* Framework and inventory integrations call the public APIs of those resources.
  If an upstream API changes, the affected call degrades to the internal fallback
  (and says so in the console) rather than breaking the resource.
* The audit log grows forever — prune `nexora_job_logs` and
  `nexora_society_transactions` periodically on a busy server, or set
  `Config.Security.logActions = false`.

---

## License

Provided as-is for use on your own server. No warranty.
