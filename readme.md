# Apex Reef

Displays your reef tank's key parameters from a Neptune Systems Apex:

| Row  | Source                                   |
| ---- | ---------------------------------------- |
| TEMP | Temperature probe (`Temp`)               |
| PH   | pH probe (`pH`)                          |
| ALK  | Trident alkalinity (`alk`)               |
| CA   | Trident calcium (`ca`)                   |
| MG   | Trident magnesium (`mg`)                 |
| SALT | Conductivity/salinity probe (`Cond`)     |

An Apex Fusion logo sits in the top-left corner. On a standard 64x32 display
the readings alternate between two pages below it: TEMP / PH / SALT, then
ALK / CA / MG. 2x and 64x64 displays show all six at once.

## Setup

- **Apex address** – the Apex's LAN IP (e.g. `192.168.1.230`).
- **Username / Password** – the Apex's local login (default user is `admin`).

The app talks to the Apex directly, so it only works when your Tronbyt server
is on the same network as the Apex. It uses the REST API on firmware 5.x and
later, and falls back to `/cgi-bin/status.json` with basic auth on older firmware.

If you have more than one probe of the same type, enter the probe's Apex name
(as shown in Apex Fusion, e.g. `Tmp`, `Alkx4`) in the optional name fields.

Units are inferred from the values: temperatures under 50 are shown as °C,
alkalinity under 5 as meq/L, and salinity under 2 as specific gravity.
