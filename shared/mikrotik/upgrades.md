# MikroTik RouterOS — Upgrades, firmware, licensing and hardware limits

Part of the `mikrotik-routeros` skill. Every claim below was researched against
MikroTik's own documentation and changelogs, then independently fact-checked; where
the check found an error the corrected form is inline as **Review correction** and
the correction wins over the paragraph above it.


### Canonical documentation source moved — help.mikrotik.com is frozen

MikroTik's Confluence docs at help.mikrotik.com now carry a banner reading "This documentation site has been frozen, no further edits will be made here!" and point to https://manual.mikrotik.com/docs/introduction/. The new site is a Docusaurus site with two relevant trees: prose guides under /docs/<section>/<page> and a machine-generated per-menu CLI reference under /docs/cli-reference/<menu path>/. The CLI reference is generated from the firmware and is more current than the prose pages, which still contain stale property names in places (see the watchdog no-ping-delay entry).


**Versions.** Site migration; docs are versioned as "current" only.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328142/Upgrading+and+installation (frozen banner)


### Release channels and how to read the current version of each line programmatically

There are exactly four channels, named in RouterOS as long-term | stable | testing | development. Long term: released rarely, only the most critical fixes, no new features within a number branch; a Stable release is later promoted into long-term. Stable: every few months, all tested new features and fixes. Testing: every few weeks, only basic internal testing, explicitly "should not be used in production". Development: released when necessary, raw changes.


**Versions.** Channel set verified current for RouterOS 7.24.x. v6 long-term line is still maintained: 6.49.21 shipped 2026-09-03.


```routeros
/system/package/update/set channel=stable
/system/package/update/set channel=long-term
```


Source: https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/upgrade


### Standard upgrade: exact commands, properties and status polling

Sub-menu /system/package/update. Writable properties: channel (development | long-term | stable | testing), mode (http | https; default https), check-certificate (no | yes | yes-without-crl; default yes), ip-version (auto | ipv4 | ipv6; default auto). Read-only properties: installed-version, latest-version, status. check-for-updates takes fetch-changelog and exposes a read-only changelog string. install downloads AND installs AND reboots automatically. download downloads only — a manual reboot is required to apply.


**Versions.** /system/package/update/download and install gained ignore-missing at an unconfirmed release. 7.10 added "upgrade - do not run manual upgrade if some packages are missing" (CHANGELOG 7.10), which is the behaviour ignore-missing overrides.


```routeros
/system/package/update/set channel=stable mode=https ip-version=auto check-certificate=yes
/system/package/update/check-for-updates
/system/package/update/print
```


**Danger.** install reboots the device with no second confirmation. On a remote device with no out-of-band access, prefer download (no reboot) followed by a scheduled /system/reboot inside a maintenance window, so the download failure and the reboot are two separately obs…


Source: https://manual.mikrotik.com/docs/cli-reference/system/package/update/


### The upgrade path is gated: v6.x cannot reach current v7 in one hop

Using check-for-updates, a device running v6.x will only ever be offered v7.12.1, even on the major-release "Upgrade" channel. You must land on 7.12.1 first, then re-run check-for-updates to see newer v7 releases. Separately, RouterOS 7.13 split the wireless drivers out of the bundle, and the 7.13 CHANGELOG states: "Upgrade from v7.12 to v7.13 or later versions must be done through 7.12 in order to convert wireless packages automatically." So the fleet-safe ladder off v6 is: latest v6 long-term (currently 6.49.21) → 7.12.1 → target v7.


**Versions.** 7.12.1 released 2023-11-17. 7.13 released 2023-12-14.


```routeros
/system/package/update/set channel=stable
/system/package/update/check-for-updates
/system/package/update/print
```


**Danger.** Skipping 7.12 when moving a wireless device from ≤7.12 to ≥7.13 loses the automatic wireless→wifi package conversion. The radio comes back with no driver package and the AP is silently off the air; 7.13 added "package - added warning log about missing 'wireles…


Source: https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/upgrade


### The upgrade check now uses HTTPS by default (7.23) — new failure modes

RouterOS 7.23 CHANGELOG line: "!) upgrade - use HTTPS by default when connecting to MikroTik upgrade servers". The connection originates FROM the router, not from your management station, so the router itself needs outbound TCP/443 to upgrade.mikrotik.com. MikroTik's documented troubleshooting sequence is: resolve, ping, then test the port. The documented expected resolution is 159.148.147.251.


**Versions.** 7.23 (2026-05-25) flipped the default to HTTPS. 7.23 also added the option to configure HTTP/HTTPS mode explicitly.


```routeros
:put [:resolve upgrade.mikrotik.com]
/tool/ping address=159.148.147.251
/system/telnet 159.148.147.251 port=443
```


**Danger.** A device with a wrong clock or a missing root CA will fail check-for-updates with a TLS error after upgrading to 7.23+, where it previously worked over HTTP.


Source: https://download.mikrotik.com/routeros/7.23/CHANGELOG


### Manual upgrade, package lifecycle and the automatic .auto.npk path

Manual upgrade = upload .npk files to the router root (WinBox drag-drop into Files, WebFig upload, or FTP/SFTP to the root directory — NOT into the hotspot folder) then reboot; the reboot is what performs the install. Package state is managed with enable/disable/uninstall + apply-changes, and apply-changes prompts for a reboot. unschedule cancels a pending uninstall or disable. /system/package/print flags are X = DISABLED and A = AVAILABLE (available on the server but not yet downloaded).


```routeros
/file/print
/system/package/print
/system/package/enable gps,zerotier,container
```


**Danger.** Uploading a file whose name ends in .auto.npk over FTP/SFTP reboots the router immediately and unattended. Never use that suffix for staged or mirrored packages. Likewise, /system/package/apply-changes reboots.


Source: https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/packages


### Downgrade: the mechanism, and the hard floor it cannot cross

Downgrade is /system/package/downgrade — it prompts for a reboot and, during that reboot, downgrades to the oldest version it can find among the .npk packages you uploaded. So the procedure is: upload the older-architecture-matched .npk files, then run downgrade, then reboot. The absolute floor is the factory-installed version, exposed in /system/resource/print. That field was called factory-software and was RENAMED to minimum-version in RouterOS 7.24 (CHANGELOG 7.24: "system - renamed 'factory-software' to 'minimum-version' and 'factory-firmware' to 'minimum-firmware'"). Fleet tooling must read BOTH names.


**Versions.** factory-software → minimum-version and factory-firmware → minimum-firmware in 7.24 (released 2026-08-14). Pre-7.24 devices report the old names.


```routeros
/system/resource/print
/system/package/downgrade
/system/reboot
```


**Danger.** MikroTik's own warning: "The factory-software version is the absolute oldest release supported by your hardware's bootloader. Attempting to install a version older than this can cause severe system instability or brick the device." Also take a binary .backup A…


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/downgrading-routeros


### device-mode allowed-versions — the thing that will actually block your downgrade

/system/device-mode carries an allowed-versions list (a real device prints e.g. "allowed-versions: 7.13+,6.49.8+") of versions MikroTik considers free of serious exploitable vulnerabilities. RouterOS refuses to install anything outside that list unless the install-any-version feature is enabled. The list is a separate protection layer from the running version: upgrading refreshes it to a newer list, and DOWNGRADING does not roll it back — "If you downgrade RouterOS, the allowed-versions list will not change and will remain updated to the latest list." install-any-version is No in every shipped mode (home, basic,…


**Versions.** device-mode itself: 6.48.6 / 6.49.1 ("device-mode - added feature locking mechanism"). allowed-versions, install-any-version, partitions, routerboard features, the basic mode, and the enterprise→advanced rename all landed in 7.17 (2025-01-16).


```routeros
/system/device-mode/print
/system/device-mode/update install-any-version=yes
```


**Danger.** Enabling install-any-version (or any device-mode change) REQUIRES physical confirmation: after the update command you have a countdown (5 minutes by default) in which someone must press the reset/mode button or cut power, otherwise the change is cancelled and…


> **Review correction.** The enum value is `ros`. Prose: "Available device-modes are advanced, home, basic and ros." Both CLI reference pages agree: `/system/device-mode` read-only `mode enum — Current device mode: basic, home, advanced, or ros`, and `/system/device-mode/update` `mode enum — Device mode to apply: basic, home, advanced, or ros`.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/device-mode


### device-mode 'flagged' status — a compromised device disables itself, and only a human can clear it

At startup RouterOS analyses the whole configuration for signs of unauthorized access. If it finds any, it disables the suspicious configuration and sets flagged: yes in /system/device-mode. While flagged, the running config keeps working but the device refuses bandwidth-test, traffic-generator and sniffer, and refuses to ADD or ENABLE entries in system scheduler, SOCKS, PPTP, L2TP, IPsec, proxy and SMB (disable and delete still work). The error string is exactly: "failure: configuration flagged, check all router configuration for unauthorized changes and update device-mode".


**Versions.** Present from 7.17's device-mode rework; "device-mode - improved flagged router configuration detection" appears in later CHANGELOGs.


```routeros
/system/device-mode/print
/system/device-mode/update flagged=no
```


**Danger.** MikroTik: "If your system has been flagged, assume that your system has been compromised and do a full audit of all settings before re-enabling the system for use." A fleet automation must treat flagged=yes as a security incident, not as a config drift to auto…


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/device-mode


### Current security advisory (September 2026) and the fixed releases

MikroTik's security page carries "September 2026 vulnerability", dated Sep 3, 2026: "MikroTik has found a security vulnerability in RouterOS and releases containing a fix have been published in all channels. This is an important security update. Most configurations are not at risk, but upgrading is highly recommended. To give time to update your systems, we are not currently publishing detailed information." Fix is included in: 7.25 beta 3, 7.24.2, 7.23.4, 6.49.21.


**Versions.** 7.24.2 released 2026-09-03; 6.49.21 released 2026-09-03; 7.23.4 (long-term) — note 7.23.5, released 2026-09-04, is the one to deploy because 7.23.5 "additionally addresses an urgent issue introduced in 7.23.4" (broken IPv6 DHCP).


> **Review correction.** Drop the discovery attribution and say only that MikroTik is withholding details. Everything else in the entry is confirmed verbatim against all three changelogs and the advisory: fixed in 7.25beta3 / 7.24.2 / 7.23.4 / 6.49.21 all dated 2026-09-03; the Flagged-status text; the five shared changelog lines including 'ssh - refactor SSH inte…


Source: https://mikrotik.com/supportsec


### RouterBOOT: reading firmware state and upgrading it

/system/routerboard/print on a RouterBOARD shows routerboard (yes|no), board-name, model, revision, serial-number, firmware-type, minimum-firmware (the factory-installed bootloader version; called factory-firmware before 7.24), current-firmware (the RouterBOOT loader in use — explicitly NOT the RouterOS version), and upgrade-firmware (the newest RouterBOOT available on the device, either shipped inside the routeros-<ver>.npk you just installed or uploaded as a .FWF file). An upgrade is pending when upgrade-firmware > current-firmware.


**Versions.** factory-firmware renamed to minimum-firmware in 7.24. Every RouterOS release bundles a RouterBOOT image, so upgrade-firmware normally tracks the installed RouterOS version.


```routeros
/system/routerboard/print
/system/routerboard/upgrade
/system/reboot
```


**Danger.** RouterBOOT downgrade is possible only by uploading an older .FWF file. Only the MAIN RouterBOOT is upgradeable; if a RouterBOOT upgrade fails the device may not boot, and recovery is to hold the reset button before applying power (~3 s) to load the BACKUP load…


Source: https://manual.mikrotik.com/docs/hardware/routerboard/


### routerboard auto-upgrade: what it does and the extra reboot it costs

/system/routerboard/settings has auto-upgrade (bool), documented as "Whether to upgrade firmware automatically after a RouterOS upgrade. The latest firmware will be applied after an additional reboot." Default on shipped devices is no. The rest of the settings menu (verified print output): baud-rate 115200, boot-delay 2s, enter-setup-on any-key, boot-device nand-if-fail-then-ethernet, preboot-etherboot disabled, cpu-frequency, memory-frequency, boot-protocol bootp, enable-jumper-reset yes, force-backup-booter no, silent-boot yes, protected-routerboot disabled, reformat-hold-button 20s, reformat-hold-button-max 10…


**Versions.** device-mode's "Routerboard Settings" restriction covers /system/routerboard/settings "(except auto-upgrade option)" and is disabled by default in all four modes since 7.17.


```routeros
/system/routerboard/settings/print
/system/routerboard/settings/set auto-upgrade=yes
```


**Danger.** With auto-upgrade=yes a RouterOS upgrade costs TWO reboots, not one: the first applies RouterOS, the second applies RouterBOOT. Fleet health checks that expect the device back after one reboot window will page falsely.


Source: https://manual.mikrotik.com/docs/cli-reference/system/routerboard/settings/


### protected-routerboot: the single most effective way to permanently brick a fleet device

protected-routerboot=enabled disables the reset button and reset pin-hole, makes the RouterBOOT serial menu inaccessible, and disables Etherboot/Netinstall. The only remaining access is RouterOS with a valid admin password. From RouterOS v7, enabling or modifying it requires pressing the reset or mode button within 60 seconds; the LED blinks 1 s on / 1 s off to help you time it, and if the button is not pressed the change is not applied.


**Versions.** On older hardware whose minimum-firmware predates 7.19.3 you may get "The 'protected routerboot' feature requires a backup-routerboot upgrade". The documented fix is: install exactly RouterOS 7.19.3 (or 6.49.7 on v6), run /system/routerboard/upgrade and reboot…


```routeros
/system/routerboard/settings/set protected-routerboot=enabled
/system/routerboard/settings/set protected-routerboot=disabled
/system/routerboard/settings/print
```


**Danger.** MikroTik: "If you forget the RouterOS admin password while Protected RouterBOOT is enabled, the device cannot be recovered without performing a complete reformat" and elsewhere "your device can not be recovered!". Never enable this from an automation run.


Source: https://manual.mikrotik.com/docs/hardware/routerboard/


### Netinstall and remote re-installation via preboot-etherboot

Netinstall reformats the system drive and erases all configuration and user files, but does NOT remove the RouterOS license key and does NOT reset RouterBOOT settings (CPU frequency, for example, survives). The host must be on the same L2 segment. Entering Etherboot: regular booter — hold Control+E on serial, or press Reset 1–2 s after power-on; backup booter — hold Reset while powering on, wait for blink → steady → off, then release.


**Versions.** From RouterOS 7.24beta1 the netinstall package is available for all architectures except SMIPS, so a MikroTik router can act as the Netinstall server. From 7.22 device-mode and protected-routerboot can be preconfigured via Netinstall/FlashFig.


```routeros
/system/routerboard/settings/set preboot-etherboot=9s preboot-etherboot-server=10.10.10.100
/system/routerboard/settings/set preboot-etherboot=disabled
```


**Danger.** If preboot-etherboot-server is left unset, the device accepts an address from ANY Netinstall/BOOTP server on the segment and drops into Etherboot waiting to be reinstalled.


Source: https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/netinstall/


### Partitions — the only genuinely safe remote-upgrade mechanism on NAND RouterBOARDs

Supported on ARM, ARM64, MIPS, TILE and PowerPC RouterBOARDs with NAND. Each partition holds its own RouterOS installation; fallback-to (etherboot | next | <partition-name>, default next) makes the device boot the other partition automatically if the active one fails to boot after a bad upgrade. Workflow: copy-to a spare partition, activate it, upgrade there, and only when proven, save-config-to the others.


**Versions.** 7.17 gated partitions behind device-mode. 7.20beta2 raised the minimum repartitionable storage to 128 MiB and the minimum RouterOS partition to 60 MiB.


```routeros
/partitions/print
/partitions/copy-to part1
/partitions/activate part1
```


**Danger.** repartition reboots the router and reformats the NAND, leaving only the active partition — everything on the other partitions is destroyed. copy-to also erases whatever was on the target partition. Repartitioning requires the latest bootloader.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/partitions


### RouterOS 6 → 7 migration: what actually breaks

MikroTik's position is that most setups convert automatically. Explicit "attention required" items: BGP (complete redesign — connection/template/session menus; remote.address, template, connect, listen and local.role are the minimum set; local.role is now mandatory; networks moved to firewall address-lists), OSPF (OSPFv2 and OSPFv3 merged into /routing/ospf, no default instance or area, template-based interface matching), MPLS ("Upgrade MPLS setups with caution"), routing filters (script-like if..then syntax; unsupported options become an EMPTY entry — silent policy loss).


**Versions.** v7 rebased on Linux kernel 5.6.3.


```routeros
/system/backup/load name=<v6backup> force-v6-to-v7-configuration-upgrade=yes
```


**Danger.** The routing-protocol configuration conversion runs ONCE. If you upgrade to v7, downgrade to v6, change config, and upgrade back, you get the pre-downgrade converted config, not a fresh conversion.


> **Review correction.** The archived RouterOS 6 scripting manual carries an explicit note: "Variable value size is limited to 4096bytes". So on RouterOS 6 a fetch response read via `output=user` is bounded at ~4 KB, not 64 KB, regardless of what the fetch documentation says.


Source: https://manual.mikrotik.com/docs/getting-started/upgrading-to-v7


### The v7 memory floor and memory-constrained models

MikroTik states plainly: "You should not run v7 on hardware that does not have at least 64 MB of RAM." Related hard numbers: RouterOS 7.12 added a "single-process" routing configuration setting that is enabled by default on devices with 64 MB or less RAM. RouterOS 7.9 added "storage - mount RAM drive for devices with 32MB flash". The SMIPS architecture is the low-flash/low-RAM tier and MikroTik has repeatedly cut features out of its main package to keep it fitting: 6.45.3 disabled LTE modem, dot1x and SwOS support on smips; a later release removed ip-scan, mac-scan, ping-speed and flood-ping; 7.20 removed hotspot…


**Versions.** 7.16 added "system - added critical log message when not enough space to store new configuration" — a log signal worth alerting on.


```routeros
/system/resource/print
```


**Danger.** Do not push v7 onto <64 MB RAM devices in a fleet job. On 16 MB flash devices, an upgrade can fail for space even when it reports success on other models — 6.48.2 shipped "upgrade - fixed upgrade procedure on 16MB devices", 6.49 shipped "upgrade - fixed free s…


Source: https://manual.mikrotik.com/docs/getting-started/upgrading-to-v7


### Wireless package matrix — which .npk a device needs after 7.13

Before 7.13 the wireless drivers were inside the routeros bundle. 7.13 split them: the legacy "wireless" package (802.11 a/b/g/n/ac, 60 GHz, and the legacy CAPsMAN) became standalone, and the old "wifiwave2" package was split into wifi-qcom and wifi-qcom-ac. Current mapping (from the packages page): wifi-qcom (arm, arm64) — required driver for 802.11ax, introduced 7.13; wifi-qcom-ac (arm) — optional driver for compatible 802.11ac, introduced 7.13; wifi-qcom-be (arm64) — required for WiFi-7 802.11be; wifi-mediatek (arm) — required for MediaTek radios; wireless (arm, arm64, mipsbe, mmips, tile, ppc, x86, CHR) — leg…


**Versions.** wifiwave2 was the pre-7.13 name for the 802.11ax package; 7.13 also made the console resolve the "wifiwave2" directory to "wifi". The menu is /interface/wifi on modern releases.


**Danger.** Pushing the wrong wireless package (or none) leaves the radio with no driver and the AP dark, while the router itself is up, reachable and reporting healthy.


Source: https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/packages


### CAPsMAN: the two controllers do not interoperate

There are two independent CAPsMAN implementations. WiFi CAPsMAN drives /interface/wifi devices (wifi-qcom / wifi-qcom-ac / wifi-qcom-be); legacy CAPsMAN drives /interface/wireless devices via /caps-man. MikroTik: "WiFi CAPsMAN can only control WiFi interfaces, and WiFi CAPs can join only WiFi CAPsMAN. Similarly, regular CAPsMAN only supports non-WiFi caps." Both can run on one box in most cases, but on an AX router running both, the built-in cards cannot be used.


```routeros
/interface/wifi/radio/print
/interface/wifi/capsman/remote-cap/provision
/interface/wifi/provisioning/print
```


**Danger.** Manual provisioning DELETES and re-creates the wifi interface: "If you manually provision interfaces, the interface ID or name can change, resulting in broken references to other objects, for example, bridge ports." Do not script manual provisioning as a routi…


Source: https://manual.mikrotik.com/docs/wireless/wifi/capsman


### RouterBOARD licensing: levels, what they limit, and immovability

MikroTik hardware ships with an embedded license; /system/license/print shows software-id and nlevel (0-6) plus a features bitmask and, in trial, expires-in. Level 0 is 24-hour trial mode, Level 1 is a free demo requiring registration, Level 3 is wireless-station/CPE only and not for sale, Levels 4/5/6 are $45/$95/$250. Published limits per level (L1/L3/L4/L5/L6): PPPoE, PPTP and L2TP tunnels 1/200/200/500/unlimited; OVPN tunnels 1/200/200/unlimited/unlimited; HotSpot active users 1/1/200/500/unlimited; User Manager active sessions 1/10/20/50/unlimited; Wireless AP (PtMP) mode requires L4+ for 802.11a/b/g/n/ac ("…


**Versions.** Level 2 is a legacy pre-2.8 transitional license — still functions, but upgrading requires buying a new license. Note the carve-out: "wifi-qcom drivers support PTMP operations regardless of license level.


```routeros
/system/license/print
```


Source: https://manual.mikrotik.com/docs/getting-started/routeros-licensing/mikrotik-hardware/


### x86 licensing: the trial clock and the demo-license upgrade trap

On x86 the Software ID is bound to the storage device MBR (NAND/SSD/HDD/NVMe) and can change if the storage or controller is unstable — MikroTik lists failing drives, non-persistent RAID and different storage controllers between boots as causes, and advises verifying that the Software ID survives a reboot BEFORE buying. After installation RouterOS runs in Trial mode with no limitations for 24 hours (expires-in counts down), during which you must register a Level 1 free demo or apply a purchased L4/L5/L6 key. A reboot is required for a pasted key to take effect.


**Versions.** 7.8 is the gate for demo-license upgrade refusal.


```routeros
/system/license/print
```


**Danger.** The Level 1 demo license "does not allow RouterOS version upgrades, starting from version 7.8" — a demo-licensed x86 box in a fleet will silently refuse every upgrade.


Source: https://manual.mikrotik.com/docs/getting-started/routeros-licensing/x86/


### CHR licensing: renewal, deadline-at, and what expiry actually does

CHR licensing keys on system-id, not software-id. Levels: free (1 Mbit/s upload per interface, free, runs indefinitely), p1 (1 Gbit, $45), p10 (10 Gbit, $95), p-unlimited ($250). Paid levels are perpetual and transferable between CHR instances under the same MikroTik account. A 60-day trial of any paid level is available via /system/license/renew with mikrotik.com account credentials. /system/license/print on CHR exposes system-id, level (free | p1 | p10 | p-unlimited), limited-upgrades (bool), next-renewal-at and deadline-at.


**Versions.** IP/Cloud functionality on CHR requires a paid perpetual license. Trial instances that are not purchased within 2 months of expiry are removed from the account and require a fresh install.


```routeros
/system/license/print
/system/license/renew
/system/license/generate-new-id
```


**Danger.** Expiry does NOT stop traffic — the router keeps running at its current level — but RouterOS upgrades are blocked and package changes (enable/disable/install/remove) are blocked.


Source: https://manual.mikrotik.com/docs/getting-started/routeros-licensing/chr/chr-licensing


### Connection tracking: the table ceiling and behaviour at exhaustion

Settings live at /ip/firewall/connection/tracking. enabled is yes | no | auto (default auto — tracking stays off until at least one firewall rule exists). max-entries is READ-ONLY and derived from installed RAM; the system does not allocate the full table at boot, it grows on demand while free RAM lasts, "but the size will not exceed 1048576". total-entries is the live count. When the ceiling is hit, entries flagged assured are protected: assured "Indicates that this connection is assured and that it will not be erased if the maximum possible tracked connection count is reached" — i.e.


**Versions.** FastTracked connections bypass connection tracking entirely, so a heavily FastTracked router will show a small total-entries that does not reflect real session count.


```routeros
/ip/firewall/connection/tracking/print
/ip/firewall/connection/print count-only
/ip/firewall/connection/tracking/set tcp-established-timeout=1d
```


**Danger.** tcp-established-timeout=1d is the usual cause of a slowly filling table on a NAT box; cutting it is the standard remedy but it will tear down genuinely idle long-lived sessions (SSH, BGP without keepalives, IPsec management).


Source: https://manual.mikrotik.com/docs/firewall-and-quality-of-service/connection-tracking


### /system/health and the SNMP/API scaling factor

The health menu shape differs by platform. On i386 it is a flat settings directory with named fields (core, 3.3v, 5v, 12v, lm87-temp, cpu-temp, board-temp, voltage1..10, temp1..3, fan1..3, state, state-after-reboot). On everything else it is a DIRECTORY of rows with name / value / type, where type is one of C | RPM | V | A | W. Parse it as rows, not as fixed properties. THE SCALING GOTCHA: "In CLI/Winbox it will display volts. In scripts/API/SNMP this will be dV" (decivolts, i.e. ×10) and for temperature "Using scripts/API/SNMP this value will be shown in CLI/Winbox multiplied by 10".


**Versions.** Manual fan control added 7.9 for CRS3xx/CRS5xx/CCR2xxx, and 7.14 for CCR1036-8G-2S+-r2, CCR1036-12G-4S-r2 and CCR1016-12S-1S+-r2. fan-min-speed-percent default became 12 in 7.14 (0 in earlier releases).


```routeros
/system/health/print
/system/health/settings/print
/system/health/settings/set fan-target-temp=58 fan-full-speed-temp=65 fan-min-speed-percent=12 fan-control-interval=30
```


**Danger.** Do not alert on raw SNMP/API health values without dividing by 10, and do not assume the menu exists — 7.23 shipped "health - hide health menu for RB951ui-2nD".


> **Review correction.** Temperature scaling IS unambiguous and the entry is right about it: "Using scripts/API/SNMP this value will be shown in CLI/Winbox multiplied by 10." Voltage is not — treat the unit as per-device and calibrate against a known-good CLI reading rather than assuming dV.


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/health


### SFP/QSFP DDM monitoring: fields, and when DDM silently returns nothing

Everything comes from /interface/ethernet/monitor <iface>. DDM fields: sfp-temperature (C), sfp-supply-voltage (V), sfp-tx-bias-current (mA), sfp-tx-power (dBm), sfp-rx-power (dBm). Presence/fault: sfp-module-present, sfp-rx-loss, sfp-tx-fault, combo-state (copper|sfp). Inventory: sfp-vendor-name, sfp-vendor-part-number, sfp-vendor-revision, sfp-vendor-serial, sfp-manufacturing-date, sfp-type, sfp-connector-type, sfp-wavelength (nm), sfp-power-class, sfp-max-power (W), sfp-encoding, the sfp-link-length-* family, and eeprom-checksum (good|bad) plus a raw eeprom hex dump.


**Versions.** sfp-shutdown-temperature introduced in v6.48; default 95 °C for SFP/SFP+/SFP28. The 80 °C default for QSFP+/QSFP28 was introduced in v7.6. 7.19.3 added sfp-power-class and sfp-max-power monitor values for QSFP.


```routeros
/interface/ethernet/monitor sfp-sfpplus1 once
/interface/ethernet/monitor [find] once
/interface/ethernet/set [find default-name=sfp-sfpplus1] sfp-shutdown-temperature=95
```


**Danger.** "Modules with bad EEPROM checksum do not output any EEPROM information to the Ethernet monitor, which will also mean that the SFP DDM monitor does not work for such modules." A poller must treat missing DDM as "unknown", not "0 dBm", and should check eeprom-ch…


Source: https://manual.mikrotik.com/docs/cli-reference/interface/ethernet/monitor


### Binary backup: encryption, portability, and what it does NOT contain

/system/backup/save arguments: name (file), password (string), dont-encrypt (bool), encryption (aes-sha256 | rc4). /system/backup/load arguments: name, password, force-v6-to-v7-configuration-upgrade (bool). The backup is binary, contains the device's MAC addresses (which are restored on load), and MikroTik states "You should restore the backup on the same version of RouterOS." It does NOT contain The Dude or User Manager configuration — those have their own export mechanisms.


**Versions.** 6.43 (2018-09-06) is the encryption-default boundary. force-v6-to-v7-configuration-upgrade on load is the only documented way to re-run v6→v7 config conversion.


```routeros
/system/backup/save name=pre-upgrade password=<SECRET> encryption=aes-sha256
/system/backup/save name=plain dont-encrypt=yes
/system/backup/load name=pre-upgrade password=<SECRET>
```


**Danger.** encryption=rc4 exists only for compatibility with old RouterOS and is documented as "not a secure encryption method" — never select it for archived fleet backups.


Source: https://manual.mikrotik.com/docs/getting-started/configuration-management/backup


### Text export: options, and the show-sensitive / hide-sensitive difference between v6 and v7

/export is CLI-only and can be run from any menu (exporting that menu and its sub-menus) or from root. Options: compact (default since v6rc1 — "export" and "export compact" are identical), file (write to a .rsc instead of the terminal), path (include/exclude specific menus), show-sensitive, terse (one full command per line including the menu path — the right choice for diffing), verbose (all parameters and items including defaults). CURRENT (v7) behaviour, quoted: "show-sensitive — Shows sensitive information, like passwords, keys, etc.


**Versions.** compact became the default in v6rc1. 7.11 added a per-menu timeout error printed into the export output as `#error exporting "/xxx" (timeout)` instead of aborting. 7.13 added `export where` for filtering within a menu.


```routeros
/export terse file=config
/export show-sensitive terse file=config-full
/export path=/ip/firewall,!/ip/firewall/nat
```


**Danger.** A fleet config-collector that runs plain /export on v6 devices captures every PSK, IPsec secret and RADIUS secret into your archive, while the same command on v7 devices quietly redacts them — so a v6/v7 mixed fleet produces archives with inconsistent secrecy…


Source: https://manual.mikrotik.com/docs/getting-started/configuration-management/


### 7.21 extended sensitive-hiding to the print command — a silent scraper breakage

RouterOS 7.21 (2026-01-12) CHANGELOG: "console - added show-sensitive option for print command, hide sensitive settings in print output by default". Before 7.21, `print` returned secrets that `export` had already been redacting; from 7.21 both redact by default. Any fleet tool that harvests configuration by parsing `print` output (including over the API and REST) will start receiving masked values on 7.21+ without any error.


**Versions.** 7.21 for print. 7.10 added "console - hide past commands with sensitive arguments" (so command history no longer replays secrets); 7.11 added a 'sensitive' policy requirement for SSH key and certificate export.


```routeros
/ip/ipsec/identity/print show-sensitive
/interface/wireguard/print show-sensitive
```


**Danger.** Detect this by version, not by output shape — a masked secret still looks like a value. Reading secrets requires the 'sensitive' user policy; a collector account deliberately created without it will get masked output on every version, which is usually the corr…


Source: https://download.mikrotik.com/routeros/7.21/CHANGELOG


### Configuration reset and .rsc restore semantics

/system/reset-configuration erases the configuration and, by default, writes a backup of the existing configuration first. Options: keep-users (do not remove existing users), no-defaults (clear only, do not load the default config), skip-backup (skip the automatic pre-reset backup), run-after-reset=<file.rsc> (load your own config after reset), caps-mode (run the caps-mode script). Import options are file-name, verbose, from-line and dry-run (both from-line and dry-run are available only in verbose mode).


```routeros
/system/reset-configuration no-defaults=yes skip-backup=yes
/system/reset-configuration keep-users=yes run-after-reset=base.rsc
/import file-name=base.rsc verbose=yes dry-run=yes
```


**Danger.** Two traps. (1) "If the router was installed using Netinstall and had a script specified as the initial configuration, the reset command executes this script after purging the configuration.


Source: https://manual.mikrotik.com/docs/getting-started/configuration-management/


### Safe mode — and exactly where it stops protecting you

Safe mode is entered with F4 or Control+X in the CLI ("[Safe Mode taken]", prompt gains <SAFE>) and by the Safe Mode button in WinBox. Every configuration change made while the router is in safe mode — including changes made from OTHER login sessions — is automatically undone if the safe-mode session terminates abnormally. Changes queued for undo appear in /system/history flagged F (FLOATING-UNDO). Control+D exits and undoes; /quit exits WITHOUT undoing. If the session is cut, the undo fires after the TCP timeout, documented as 9 minutes. Read-only state is at /safe-mode (enabled, user, current, owner).


```routeros
/system/history/print
/safe-mode/print
```


**Danger.** Two hard limits an automation must respect. (1) The undo buffer is the console history, currently 100 most recent actions: "If too many changes are made while in safe mode, and there's no room in history to hold them all ...


Source: https://manual.mikrotik.com/docs/management-tools/console


### Watchdog: two independent mechanisms, and a documentation trap in the property name

/system/watchdog holds two separate features. The software watchdog (watchdog-timer, default yes) reboots if the system is unresponsive for a minute. The ping watchdog is disabled until you set watch-address, after which "the system will reboot, in case 6 sequential pings to the given IP address fail", and "By default, the router will reboot every 6 minutes if the watch-address is set and not reachable". automatic-supout defaults to yes: on a software failure the router writes autosupout.rif and renames the previous one to autosupout.old.rif.


**Versions.** ping-timeout added in 6.43. no-ping-delay → ping-start-after-boot in 6.44.6 / 6.45.5.


```routeros
/system/watchdog/print
/system/watchdog/set watch-address=none
/system/watchdog/set watch-address=8.8.8.8 ping-start-after-boot=5m ping-timeout=60s
```


**Danger.** Setting watch-address to something behind the very link you are about to reconfigure turns a routing mistake into a 6-minute reboot loop that you cannot log into to fix.


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/watchdog


### Detecting an unexpected reboot, and why the watchdog leaves no supout

Baseline signal is /system/resource uptime plus write-sect-since-reboot resetting. The critical nuance, stated by MikroTik: "Watchdog reboot is not a system failure. Such a reboot also will not generate an autosupout file. Watchdog reboot is /system/reboot automatically triggered by the operating system when some service is not responding as fast as it should.


**Versions.** On some ARM/ARM64 devices you will get no useful reboot reason at all unless RouterBOOT has been upgraded — another concrete cost of skipping /system/routerboard/upgrade.


```routeros
/system/resource/print
/file/print where name~"supout"
/log/print without-paging
```


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/watchdog


### supout.rif: generating it and what it is safe to hand over

/system/sup-output name=supout.rif produces MikroTik's binary support file containing the complete configuration, logs and additional diagnostics. It accepts output-width (num) to widen the captured text when the supout viewer truncates columns. On devices with flash-type memory or external storage you can write it to the flash folder by giving the full path. MikroTik states: "The supout.rif file does not contain sensitive information such as router passwords." It is read with the Supout.rif viewer in a mikrotik.com account. The watchdog can produce them automatically as autosupout.rif (see the watchdog entry).


**Versions.** 7.19.3 added an IPv6 NAT section to supout; 7.17 added a device-mode section.


```routeros
/system/sup-output name=supout.rif
/system/sup-output name=supout.rif output-width=300
/system/sup-output name=flash/supout.rif
```


**Danger.** Generating a supout is CPU- and I/O-heavy and writes a sizeable file; on a 16 MB-flash device with little free-hdd-space it can fail or push the device into the low-space condition.


Source: https://manual.mikrotik.com/docs/getting-started/supout-rif


### Detecting known-bad releases: the (introduced in vX) convention

MikroTik tags every regression fix in its CHANGELOG with the release that caused it, in the exact form "(introduced in v7.20)" or "(introduced in v7.23.4)". Each release's changelog is at https://download.mikrotik.com/routeros/<version>/CHANGELOG as plain text, so a fleet tool can fetch the changelogs of every release NEWER than the one it runs and grep for `introduced in v<running-version>` to enumerate the known defects it is currently exposed to. Measured on the 7.2x series changelogs: 38 fixes attributed to v7.20, 24 to v7.21, 16 to v7.22.


```routeros
/system/package/update/check-for-updates fetch-changelog=yes
/system/package/update/get changelog
```


**Danger.** Do not treat 'newest in channel' as 'safest'. The 7.23.4→7.23.5 pair shows MikroTik shipping a security fix that broke DHCPv6 and correcting it the next day.


Source: https://download.mikrotik.com/routeros/7.23.5/CHANGELOG


### Local package distribution for fleets without internet egress

/system/package/local-update lets one router with the .npk files serve upgrades to others on the LAN. A mirror device can be pointed at a Primary Server with a check interval (minimum documented 00:07:12); it stores fetched packages in a new "packs" folder. Target routers add a package source pointing at the mirror, then Refresh, choose packages, Download, and reboot. /system/package/local-update/refresh is the scriptable entry point. Packages can also be pulled directly with the fetch tool, e.g. /tool/fetch url=https://download.mikrotik.com/routeros/7.16.1/routeros-7.16.1-arm.npk.


**Versions.** The menu is /system/package/local-update only from 7.17 — CHANGELOG 7.17: "system - moved '/system/upgrade' to '/system/package/local-update'". On RouterOS older than 7.17 the menu is /system/upgrade. 7.24 made the mirror's password a sensitive parameter.


```routeros
/system/package/local-update/refresh
/system/package/local-update/download
/system/package/local-update/download-all
```


Source: https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/upgrade


### MikroTik cloud endpoints a fleet firewall must allow (or deliberately block)

Complete documented list of outbound connections RouterOS makes to MikroTik, with the setting that controls each: /system/clock time-zone-autodetect → cloud2.mikrotik.com (ON by default; disable with /system/clock/set time-zone-autodetect=no); /system/backup/cloud → cloud2.mikrotik.com (only on upload-file / download-file / remove-file); /ip/cloud update-time → cloud2.mikrotik.com (ON by default; /ip/cloud/set update-time=no); /ip/cloud ddns-enabled → cloud2.mikrotik.com; /ip/cloud back-to-home-vpn and back-to-home-file → cloud2.mikrotik.com; /system/license → licence.mikrotik.com (ON for CHR, and CANNOT be disab…


```routeros
/system/clock/set time-zone-autodetect=no
/ip/cloud/set update-time=no ddns-enabled=auto back-to-home-vpn=revoked-and-disabled
/interface/detect-internet/set detect-interface-list=none
```


**Danger.** Blocking upgrade.mikrotik.com makes check-for-updates fail closed and the fleet silently stops learning about security releases. Blocking licence.mikrotik.com on CHR eventually passes deadline-at and permanently blocks upgrades and package changes on those ins…


Source: https://manual.mikrotik.com/docs/network-management/cloud/communication-mikrotik-cloud-servers


### /system/resource fields worth polling for hardware failure prediction

Read-only properties on /system/resource: uptime, version, build-time, minimum-version (was factory-software), free-memory, total-memory, cpu, cpu-count, cpu-frequency, cpu-load, free-hdd-space, total-hdd-space, write-sect-since-reboot, write-sect-total, bad-blocks, architecture-name, board-name, platform. bad-blocks is documented as "Shows percentage of bad blocks on the NAND" — it is a PERCENT, not a count, and a rising value is the flash wearing out.


**Versions.** minimum-version is the 7.24 name; on 7.23 and earlier the same field is factory-software. Poll for both.


```routeros
/system/resource/print
/system/resource/cpu/print
/system/resource/monitor once
```


**Danger.** free-hdd-space is the pre-flight check for any upgrade or supout on a flash device; an upgrade that runs out of space mid-install is how a remote device ends up needing Netinstall.


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/resource


### CHR sizing and hypervisor constraints

Host requirements: 64-bit CPU with virtualization support, RAM 256 MB or more, disk 128 MB or more, RouterOS 6.34 or newer. Minimum RAM formula — v6: RAM = 128 + [8 × CPU_COUNT × (INTERFACE_COUNT − 1)]; v7: RAM = 512 + [8 × CPU_COUNT × (INTERFACE_COUNT − 1)]; MikroTik's recommendation is to allocate at least 1024 MiB. RouterOS v6 caps the CHR virtual disk at 16 GB; v7's limits come from Linux kernel 5.6.3 and the hardware. Images ship as .img, .vdi, .vmdk, .vhdx and .ova. FastPath works with vmxnet3 and virtio-net on v7 and not at all on v6. Default credentials on first boot: user admin, no password.


```routeros
/system/resource/print
/system/license/print
```


**Danger.** Cloning a booted CHR image can duplicate the System ID (MikroTik names Linode as an example), which breaks licensing for every clone. Make image copies BEFORE first boot and registration; if you must fix it after the fact, /system/license/generate-new-id works…


Source: https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/install/chr-installation/


### Version numbering semantics — do not compare RouterOS versions as decimals

MikroTik: "RouterOS versions are numbered sequentially, where a period is used to separate sequences; it does not represent a decimal point, and the sequences do not have positional significance. An identifier of 2.5, for instance, is not 'two and a half' or 'halfway to version three'; it is the fifth second-level revision of the second first-level revision.


```routeros
/system/resource/get version
/system/package/print
```


**Danger.** A string or float comparison marks 7.9 as newer than 7.24 and 6.49.21 as older than 6.49.3. This is the single most common bug in third-party MikroTik fleet tooling and it causes upgrade jobs to target the wrong direction.


Source: https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/upgrade


### Could not verify

The exact RouterOS release where the /export default flipped from showing sensitive values (v6 style, opt-out via `hide-sensitive`) to hiding them (v7 style, opt-in via `show-sensitive`). Verified: v6 had a `hide-sensitive` export mode (6.43 CHANGELOG: 'export - do not show w60g password on "hide-sensitive" type of export'), and current v7 docs state sensitive data is hidden by default with `show-sensitive` to reveal. No CHANGELOG line in any 6.4x or 7.x release I fetched announces the flip, and no 7.0.x CHANGELOG is published on download.mikrotik.com (earliest v7 changelog available is 7.1). Whether `hide-sensitive` is still accepted as a no-op on v7 is also unverified.
