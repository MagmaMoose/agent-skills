# MikroTik RouterOS — Operating a fleet: what actually goes wrong

Part of the `mikrotik-routeros` skill. Every claim below was researched against
MikroTik's own documentation and changelogs, then independently fact-checked; where
the check found an error the corrected form is inline as **Review correction** and
the correction wins over the paragraph above it.


### Safe Mode — the only built-in change-rollback mechanism

RouterOS has no candidate-config/commit model. Safe Mode is the nearest equivalent and it is session-scoped. Enter it in the CLI with Ctrl+X or F4; the console prints "Safe Mode taken" and the prompt gains a <SAFE> marker. Documented behaviour: "All configuration changes that are made (also from other login sessions), while the router is in safe mode, are automatically undone if the safe mode session terminates abnormally." Abnormal termination is detected by TCP timeout, roughly 9 minutes — so a lockout self-heals only after that delay, not instantly.


**Versions.** Present in RouterOS 6 and 7. The 100-action history limit and 9-minute TCP timeout are documented for current versions.


```routeros
Ctrl+X   (or F4) — take safe mode
Ctrl+X   — keep changes, leave safe mode
Ctrl+D   — leave safe mode and undo everything
```


**Danger.** A config push of more than 100 actions silently drops out of safe mode with no rollback. For scripted/bulk pushes, chunk the change under 100 actions or use a scheduler/backup safety net instead.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8978498/Console


### RouterOS commits immediately — a reboot is NOT a rollback

Unlike IOS/JunOS there is no running-config vs startup-config split and no commit command. Every CLI/Winbox/API change is written to persistent storage as it is made. The operational consequence that trips up people coming from Cisco: scheduling `/system reboot` as a 'safety net' does nothing at all — the router comes back with the broken config. Any hand-built commit-confirm on RouterOS must restore a *snapshot* (binary backup or an .rsc), not merely reboot. The only in-band undo primitives are /system history's /undo and /redo, and Safe Mode's floating undo.


**Versions.** True for RouterOS 6 and 7 alike.


```routeros
/system history print
/undo
/redo
```


**Danger.** Do not build a rollback that only reboots. It will not revert anything and will additionally drop all sessions/tunnels for the boot time.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328155/Configuration+Management


### The scheduler safety-net (hand-built commit-confirm) — canonical pattern

The pattern operators build by hand: snapshot to a binary backup, arm a scheduler entry that will restore that backup, make the change, and disarm the scheduler if you still have access. If you lose access, the scheduler fires, `/system backup load` restores and the router reboots into the last-known-good config. Three details make or break it: (1) the scheduler entry needs `policy=` broad enough — backup save/load touch files, which needs `ftp`, and the restore reboots, which needs `reboot`; a scheduler with only read,write will fail silently.


**Versions.** Scheduler semantics are stable across RouterOS 6 and 7. On RouterOS 7.17+ verify `/system/device-mode/print` first: in `home` mode the scheduler feature is disabled outright and the entry will never run.


```routeros
/system backup save name=pre-change dont-encrypt=yes
/system scheduler add name=rollback interval=10m policy=read,write,ftp,reboot,test on-event="/system backup load name=pre-change"
/system scheduler print detail
```


**Danger.** DANGEROUS if armed and forgotten: the router will restore-and-reboot mid-production and silently discard every legitimate change made since the snapshot. Always confirm removal. Also DANGEROUS if the change you are testing deletes the scheduler entry (e.g.


> **Review correction.** Demote the pattern to unvalidated until it is proven on a lab device, and give the alternative that is non-interactive by construction: `/system/reset-configuration no-defaults=yes keep-users=yes run-after-reset=<file>.rsc` (all four arguments confirmed in the CLI reference), with the .rsc confirmed present via `/file print` first.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/40992881/Scheduler + https://help.mikrotik.com/docs/spaces/ROS/pages/283574370/Scr…


### Scheduler property semantics — start-time=startup, interval, policy

Documented: "if scheduler item has start-time set to startup, it behaves as if start-time and start-date were set to time 3 seconds after console starts up", "Scripts with start-time=startup and interval=0 will be executed once each time the router boots", and "If the interval is set to a value other than 0 the scheduler will not run at startup." So a boot-time one-shot is `start-time=startup interval=0`; adding a non-zero interval turns it into a periodic job that does NOT fire at boot.


**Versions.** Same in RouterOS 6 and 7.


```routeros
/system scheduler add name=run-1h interval=1h on-event=log-test
/system scheduler add name=boot-once start-time=startup interval=0 on-event="/log info booted"
/system scheduler add interval=10s name=test on-event=script2 policy=read,write,ftp
```


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/40992881/Scheduler


### Script and scheduler permissions — the silent-failure trap

A script runs with the policies of whatever invoked it, and "A script with higher or more permissions than the user/scheduler cannot be run; use-script-permissions won't override this." The classic symptom is a scheduled job that appears configured, never logs an error a human notices, and simply does nothing. The documented example: "script requires policy 'ftp', to create a file, but scheduler has only 'read' and 'write' policies." Critically for rollback design: netwatch and PPP on-event hooks are hard-limited to "read,write,test,reboot" — so a netwatch down-script CANNOT save or load a backup, or write any fi…


**Versions.** Policy model is the same in RouterOS 6 and 7. The 64 kB script limit is documented for current versions.


```routeros
/system scheduler add interval=10s name=test on-event=script2 policy=read,write,ftp
/system script add name=x policy=read,write,ftp,reboot source="..."
/system script run x
```


**Danger.** Do not design a netwatch-based rollback around /system backup load — netwatch is capped at read,write,test,reboot and the restore will never run. Use a scheduler entry with policy including ftp and reboot instead.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/283574370/Scripting+Tips+and+Tricks


### Netwatch as a liveness-triggered rollback, and its version gates

Netwatch can fire a script on an OK→fail transition, which operators use as 'if the router can no longer reach upstream, undo'. Properties: host, type (simple|icmp|tcp-conn|http-get|https-get|dns), interval (default 10s), timeout (default 3s), src-address, start-delay (default 3s), startup-delay (default 5m), up-script, down-script, test-script, ignore-initial-up, ignore-initial-down. ICMP type adds packet-interval, packet-count, packet-size, and thresholds thr-max/thr-avg/thr-stdev/thr-jitter/thr-loss-percent/thr-loss-count.


**Versions.** RouterOS 6 and early 7 support only the simple ICMP probe. "netwatch - added support for more advanced probing" landed in 7.4 (icmp/tcp-conn/http-get/dns types). https-get added 7.7 (CLI only), Winbox 7.8. startup-delay added 7.9 (CLI only), Winbox 7.12.


```routeros
/tool netwatch add host=8.8.8.8 interval=30s up-script=":log info \"Ping successful\""
/tool netwatch add host=1.1.1.1 type=icmp start-delay=10s down-script=rollback-script
/tool netwatch print detail
```


**Danger.** A netwatch rollback armed too early during boot can revert a perfectly good config because the network has not converged yet. Use startup-delay/start-delay deliberately.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8323208/Netwatch


### Binary backup vs .rsc export — what each is for and where restore fails

`/system backup save` writes an opaque binary clone. MikroTik states the backup "also contains the device's MAC addresses, which are restored when the backup file is loaded" and "You should restore the backup on the same version of RouterOS." That makes the binary backup a same-device, same-version artefact — restoring it to a replacement unit duplicates MAC addresses on the wire. `/export` writes a human-readable .rsc that is portable across models and versions and is what you want for RMA swaps, config-as-code diffing and fleet templating.


**Versions.** Encryption-default change at v6.43. `/export compact` has been the default output since v6rc1.


```routeros
/system backup save name=flash/router-backup password=<secret>
/system backup save name=flash/router-backup dont-encrypt=yes
/system backup load name=flash/router-backup.backup password=<secret>
```


**Danger.** Restoring a binary backup onto a different physical unit clones the original's MAC addresses — expect duplicate-MAC symptoms across the L2 domain. For hardware replacement, restore from .rsc and strip any hardcoded mac-address= lines.


Source: https://manual.mikrotik.com/docs/getting-started/configuration-management/backup/


### Importing config: failure semantics and the dry-run gate

`/import` is NOT transactional — it reads and executes, so a syntax error or a rejected command partway through leaves the device in a half-applied state. Parameters: `file-name`, `verbose` (execute line-by-line for easier debugging), `dry-run` (simulate without changing config; verbose only), `from-line` (start at line N; verbose only). Files named `*.auto.rsc` are executed automatically after FTP/SFTP upload and produce a matching `*.auto.log` — useful for hands-off provisioning, and a supply-chain hazard if anyone can write to the router's filesystem.


**Versions.** `:onerror` added in 7.13 ("console - added ':onerror' command"), fixed in 7.14 and 7.15. `dry-run` for import added in 7.16 ("console - added dry-run parameter to simulate import of files and find syntax errors without making configuration changes (verbose onl…


```routeros
/import file-name=config.rsc
/import file-name=config.rsc verbose=yes dry-run=yes
/import file-name=config.rsc verbose=yes from-line=42
```


**Danger.** A half-applied import is the most common way a config-as-code pipeline bricks a remote device. Always pair an import with an armed rollback, and prefer dry-run first on 7.16+.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328155/Configuration+Management


### device-mode — the RouterOS 7.17 change that breaks fleet automation

device-mode is a capability gate that sits BELOW user permissions: a full-privilege admin cannot enable a gated feature remotely. Modes are home, basic, advanced (renamed from enterprise) and rose. Documented matrix — Home disables scheduler, fetch, email, sniffer, romon, socks, bandwidth-test, hotspot, proxy, zerotier; Basic enables email, fetch, romon, scheduler, sniffer but not bandwidth-test, hotspot, proxy, socks, zerotier or container; Advanced adds bandwidth-test, hotspot, proxy, socks, zerotier; ROSE additionally allows container.


**Versions.** Overhauled in 7.17: basic mode added; routerboard/install-any-version/partitions features added; enterprise renamed to advanced; ping-speed and flood-ping moved under traffic-gen; update attempt count limited.


```routeros
/system/device-mode/print
/system/device-mode/update mode=advanced
/system/device-mode/update mode=home email=yes fetch=yes
```


**Danger.** CRITICAL for any fleet tool. On 7.17 upgrade, mode 'enterprise' is renamed 'advanced' AND traffic-gen, partitions, routerboard and install-any-version are disabled.


> **Review correction.** Treat the list as non-exhaustive, or read the per-port capability set from `/interface/ethernet monitor` `supported`/`sfp-supported` (added in 7.12, which the entry correctly notes) rather than validating against a hardcoded list.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/device-mode/


### Connection tracking exhaustion — the CCR/NAT box failure at scale

Path is `/ip firewall connection tracking`. `max-entries` and `total-entries` are read-only. "This value depends on the installed amount of RAM" and "the system does not create a maximum-size connection tracking table when it starts, it may increase if the situation demands it and the system still has free RAM, but the size will not exceed 1048576" — so 2^20 is the hard ceiling regardless of RAM.


**Versions.** 7.20 added the `liberal-tcp-tracking` setting, added `total-ip4-entries`/`total-ip6-entries` counters, made the conntrack table values persistent between IPv4 and IPv6, and added SNMP OIDs for total-entries, total-ip4-entries and total-ip6-entries — so per-fam…


```routeros
/ip firewall connection tracking print
/ip firewall connection tracking set tcp-established-timeout=2h
/ip firewall connection tracking set enabled=auto
```


**Danger.** Setting `enabled=no` to shed CPU also disables NAT, connection-state firewall matching and FastTrack — an instant outage on any NAT edge. Lower the timeouts or FastTrack the bulk flows instead.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/130220087/Connection+tracking


### FastTrack — what it actually bypasses (and why the customer's queue stopped working)

Documented verbatim: "FastTrack packets bypass firewall, connection tracking, simple queues, queue tree with parent=global, ip traffic-flow, IP accounting, IPSec, hotspot universal client, VRF assignment." Only TCP and UDP can be fast-tracked, and "to maintain connection tracking entries, some random packets will still be sent to a slow path" — which is why torch/sniffer still show a trickle and why byte counters under-report. The action is `action=fasttrack-connection` and it must be followed by an `action=accept` rule for the same match, because not every packet of the connection takes the fast path.


**Versions.** IPv4 FastTrack exists in RouterOS 6 and 7.


```routeros
/ip firewall filter add chain=forward action=fasttrack-connection connection-state=established,related
/ip firewall filter add chain=forward action=accept connection-state=established,related
/ip firewall filter print where action=fasttrack-connection
```


**Danger.** Enabling FastTrack on a box that shapes customers with simple queues silently removes the rate limit for those flows — customers get unmetered speed and the NOC sees no error. Enabling it on a router with IPsec tunnels breaks the tunnels.


Source: https://manual.mikrotik.com/docs/firewall-and-quality-of-service/packet-flow-in-routeros/


### Bridge VLAN filtering — the number-one remote lockout

Enabling `vlan-filtering=yes` starts filtering traffic destined for the CPU. MikroTik's guidance: "By enabling vlan-filtering you will be filtering out traffic destined to the CPU, before enabling VLAN filtering you should make sure that you set up a Management port", "It is always recommended to configure VLAN filtering while using a serial console" or through a port not in the bridge, and "you might get disconnected since the bridge must reset itself in order for VLAN filtering to take any effect" (particularly relevant to MAC-telnet).


**Versions.** Bridge VLAN filtering is the RouterOS 7 canonical VLAN method. On RouterOS 6, per-chip /interface ethernet switch configuration was still required on many switch models.


```routeros
/interface bridge add name=bridge vlan-filtering=no
/interface bridge port add bridge=bridge interface=ether1
/interface bridge port add bridge=bridge interface=ether2 pvid=99
```


**Danger.** DANGEROUS: flipping vlan-filtering=yes without the bridge as a tagged member of the management VLAN locks you out immediately and survives reboot.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/28606465/Bridge+VLAN+Table


### Hardware offload — the H flag is your throughput canary

MikroTik's Layer2-misconfiguration catalogue names 'Bridges on a single switch chip' and 'Bridge VLAN filtering without hardware offloading' with identical symptoms: "Missing 'H' flag to bridge ports", "Low throughput", "High CPU usage". `/interface bridge port print` shows H on ports actually offloaded to the switch chip. Two bridges spanning one switch chip breaks offload — the documented fix is to keep offload on one bridge only.


**Versions.** Bridge hardware offload with VLAN filtering works on Marvell Prestera chips (CRS3xx/CRS5xx) and, from RouterOS 7, on several additional chip types.


```routeros
/interface bridge port print
/interface bridge port set [find where bridge=bridge1] hw=no
/interface bridge port set [find where bridge=bridge2] hw=yes
```


**Danger.** Losing the H flag is silent. Any automated config push that touches bridge ports should re-read /interface bridge port print and alert on H flags that disappeared.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/19136718/Layer2+misconfiguration


### Other documented L2 misconfigurations that cause outages

From MikroTik's own catalogue, each with the symptoms they produce: (1) VLAN interface on a slave interface — symptoms "DHCP Client/Server not working properly", "Device is unreachable"; fix is to bind the VLAN to the bridge, `/interface vlan set VLAN99 interface=bridge1`. (2) Bridged VLAN / VLAN-in-bridge-in-bridge — "Port blocked by RSTP", "Loops in network", "Port flapping", "MAC telnet unable to connect"; fix is a single vlan-filtering bridge with a proper VLAN table.


**Versions.** 7.16 "bridge - added forward-reserved-addresses property which controls forwarding of MAC 01:80:C2:00:00:0x range (separated from 'protocol-mode=none' functionality, disabled by default after upgrade)". Source: download.mikrotik.com/routeros/7.16/CHANGELOG


```routeros
/interface vlan set VLAN99 interface=bridge1
/interface bridge set bridge1 protocol-mode=none
/interface ethernet set ether1,ether2 l2mtu=9018
```


**Danger.** `protocol-mode=none` fixes reserved-MAC forwarding but also turns off (R)STP loop protection — on a meshed L2 network that trades one outage for a worse one. From 7.16 the separate `forward-reserved-addresses` property does this without disabling STP.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/19136718/Layer2+misconfiguration


### PPPoE at scale — PPP is single-threaded

MikroTik support's own answer to multi-year performance tickets is that PPP is processed on one core. Operators report a CCR2116 unable to exceed ~2 Gbps as a PPPoE client with a single CPU pinned above 95%. The practical consequence for a BNG design: adding cores does not add PPPoE throughput, so concentrators are scaled horizontally (multiple NAS boxes each terminating a slice of subscribers, feeding a shared core for routing and CGNAT) rather than vertically.


**Versions.** 7.17 "pppoe - added support for PPPoE server over 802.1Q VLANs" — one server instance covering a VLAN range instead of one server per VLAN interface, which is the scaling change for VLAN-per-subscriber access networks.


```routeros
/interface pppoe-server server add interface=bridge-subs service-name=isp one-session-per-host=yes max-mtu=1480 max-mru=1480 keepalive-timeout=10 default-profile=subs
/interface pppoe-server server print
/ppp active print count-only
```


**Danger.** keepalive-timeout=0 leaves half-dead sessions holding IP-pool addresses and licence slots until reboot. Do not set it on a production BNG.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/2031625/PPPoE


### PPPoE disconnect storms — the CPU collapse pattern

The characteristic BNG outage: a fibre cut or upstream switch reload drops several hundred sessions at once, every session teardown triggers connection-tracking cleanup, and the CCR's CPU saturates and stops forwarding — so the sessions that survived also fail, and the reconnect storm keeps it pinned. Operators report that once the number of simultaneously disconnecting sessions exceeds roughly 200–300 the system stops passing traffic entirely. It is aggravated by masquerade/NAT on the same box, because conntrack is recalculated on each interface up/down.


**Versions.** Community-reported behaviour on CCR-class hardware, not a documented MikroTik limit.


```routeros
/tool profile cpu=all duration=10
/ip firewall connection tracking print
/ppp active print count-only
```


**Danger.** Do not respond to a live disconnect storm by disabling connection tracking — that breaks NAT instantly. Shed load by disabling the PPPoE server interface briefly to let the box drain, then re-enable.


Source: https://forum.mikrotik.com/t/high-cpu-load-when-pppoe-sessions-disconnects/105999


### RouterOS licence levels cap PPPoE/tunnel counts

Interface/tunnel limits are enforced per licence level: Level1 limited to 1 interface, Level3 and Level4 limited to 200, Level5 limited to 500, Level6 unlimited. A BNG that grows past 200 or 500 active sessions stops accepting new ones with no hardware symptom at all. CHR uses a separate model (Free, P1, P10, P-Unlimited) with throughput rather than session limits. Check the installed level before sizing a concentrator.


**Versions.** 7.13 "pppoe-server - fixed connection count limit per license level" — behaviour before that release may differ from the documented caps.


```routeros
/system license print
/system resource print
```


> **Review correction.** Say tunnels/sessions, not interfaces. Note that OVPN diverges from the others (200/200/unlimited/unlimited) if that matters. The numeric caps themselves and the CHR Free/P1/P10/P-Unlimited model are correct.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328149/RouterOS+license+keys


### CAPsMAN — transport, discovery and the ports to allow

CAP↔CAPsMAN runs over two transports. MAC layer: "no IP configuration necessary on CAP" but "CAP and CAPsMAN must be on the same Layer 2 segment". IP layer: "can traverse NAT if necessary", "CAP must be able to reach CAPsMAN using IP protocol", carried over UDP — community and vendor references give UDP 5246 for control and 5247 for data. IP multicast-based discovery does not cross L3, so any CAP not on the manager's L2 segment must be given the manager's address explicitly via `caps-man-addresses`.


**Versions.** UDP 5246/5247 is widely documented in community sources; the official CAPsMAN page states UDP transport without naming the port. Treat the port numbers as strong community consensus rather than a MikroTik-published fact.


```routeros
/caps-man manager set enabled=yes
/interface wireless cap set enabled=yes
/interface wireless cap set discovery-interfaces=bridge bridge=bridge
```


**Danger.** Choosing manager forwarding for a large CAP fleet centralises every client's traffic on the controller — a capacity decision, not just a config flag.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/1409149/AP+Controller+CAPsMAN


### The wireless package split — the 7.12→7.13 upgrade wall

RouterOS 7.13 reorganised wireless into separate packages, and the upgrade is gated: routers running below 7.12 do not see 7.13 as an available upgrade and must go to 7.12 first, at which point packages are converted automatically. The changelog is explicit: "package - convert 'wireless' and 'wifi' packages automatically, if upgrading from v7.12"; "wifi - split existing 'wifiwave2' package into separate packages 'wifi-qcom', 'wifi-qcom-ac', and include required utilities for WiFi management into bundle"; "wireless - separate 'wireless' package from bundle and build as a standalone package".


**Versions.** The menu was called 'wifiwave2' before 7.13 and 'wifi' from 7.13. wifiwave2 originally required an ARM CPU and 256 MB RAM (7.1 changelog).


```routeros
/system package print
/system package update check-for-updates
/interface wireless print
```


**Danger.** Jumping a fleet of APs straight from an old 7.x to 7.13+ in one step will simply not offer the upgrade, or will leave devices without the wireless package if it was not present — an AP that boots with no wireless package has no radios and no CAPsMAN connection…


Source: download.mikrotik.com/routeros/7.13/CHANGELOG


### RouterOS 6 → 7 migration: what does not carry over

MikroTik's own upgrade page: "We do not recommend running v7 on hardware that does not have at least 64 MB of RAM." Flagged as "OK, but attention is required": BGP (complete redesign — no more instance and peer menus, replaced by connection/template/session) and OSPF (OSPFv2 and OSPFv3 merged into one /routing ospf menu, with no default instances or areas). MPLS: "Upgrade MPLS setups with caution, and make sure to backup configuration before the upgrade." NOT preserved at all: "Upgrading RouterOS to v7 will not preserve PIM-related configuration", and "Direct migration from older User Manager is not possible".


**Versions.** v6 latest long-term is 6.49.21 (2026-09-03). v7 long-term is 7.23.5 (2026-09-04).


```routeros
/routing filter add chain=ospf_in prefix=172.16.0.0/16 prefix-length=24 protocol=static action=accept
/routing/filter/rule add chain=ospf_in rule="if (dst in 172.16.0.0/16 && dst-len==24 && protocol static) { accept }"
/routing/bgp/connection add remote.address=10.155.101.0/24 listen=yes template=default local.role=ibgp
```


**Danger.** Upgrading a route reflector or an MPLS PE from 6 to 7 without a pre-tested v7 config is a full-site outage: the filters do not convert and the sessions come up with no policy applied, which can leak or blackhole prefixes.


> **Review correction.** The archived RouterOS 6 scripting manual carries an explicit note: "Variable value size is limited to 4096bytes". So on RouterOS 6 a fetch response read via `output=user` is bounded at ~4 KB, not 64 KB, regardless of what the fetch documentation says.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/115736772/Upgrading+to+v7


### Upgrade mechanics: channels, the two-step gate, and the bootloader

`/system package update` checks MikroTik's servers for a newer release in the selected channel. It is not always a single hop: "It is not possible to upgrade from an older version to the latest version in one step" — an old v6 box on the 'upgrade' channel is offered an intermediate v7 release first, and you repeat check-for-updates after that lands. Separately, the RouterBOOT bootloader is versioned independently of RouterOS and does NOT update with the package: "It is strongly recommended to upgrade the bootloader after RouterOS update.


**Versions.** 7.23: "upgrade - use HTTPS by default when connecting to MikroTik upgrade servers" — before 7.23 the update check was not HTTPS by default. Channels include long-term, stable, testing and development.


```routeros
/system package update set channel=long-term
/system package update check-for-updates
/system package update download
```


**Danger.** `/system routerboard upgrade` writes the bootloader; a power cut during that write can leave a device that only Netinstall over a physical Ethernet port can recover. Never run it on a site without hands or reliable power.


> **Review correction.** State that device-mode gates `/system/routerboard/settings`, and that `/system/routerboard/upgrade` is not in the gated set. The rest of the entry (two-step upgrade path, bootloader versioned independently, two reboots per device, 7.23 HTTPS-by-default) is confirmed verbatim.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328142/Upgrading+and+installation


### Locked out: the recovery ladder

In rough order of destructiveness. (1) Wait out Safe Mode's ~9-minute TCP timeout if you had taken it. (2) MAC-telnet or MAC-Winbox from a device on the same L2 segment — works with no IP at all, but only between two RouterOS devices, and only if `/tool mac-server allowed-interface-list` still permits that interface. (3) RoMON: a MAC-layer overlay (EtherType 0x88bf, DST-MAC 01:80:c2:00:88:bf) that "operates independently of L2 or L3 forwarding configuration" — so it survives an IP/firewall mistake, and `/tool romon discover` finds neighbours through intermediate RoMON-enabled routers. (4) Serial console.


**Versions.** Reset-button hold semantics are consistent across RouterBOARD generations; some EOL devices confirm only on power cycle.


```routeros
/tool mac-telnet 00:11:22:33:44:55 interface=ether1
/tool mac-server set allowed-interface-list=listBridge
/tool mac-server mac-winbox set allowed-interface-list=listBridge
```


**Danger.** DANGEROUS: `/system reset-configuration` wipes everything and reboots. `keep-users=yes` retains logins; `no-defaults=yes` skips the default config so the device comes back with NO addresses and NO services — reachable only by MAC-telnet/RoMON/serial.


> **Review correction.** Drop the duration. The rest of the ladder (5s flashing = config reset, +5s solid = CAPs mode, +5s off = Netinstall search) is confirmed verbatim, as are the RoMON EtherType 0x88bf / DST-MAC 01:80:c2:00:88:bf details and the mac-server allowed-interface-list commands.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/24805498/RouterOS+configuration+reset


### /ip service address= is not a firewall

MikroTik states plainly: "When this parameter is set, packets are not dropped at the network level, but access to the service is denied for sources not matching the specified addresses", and "To block access from external or untrusted networks, we recommend using a Firewall instead." So an allowlist on the service still lets an attacker reach the listening socket and consume CPU — it is a defence-in-depth layer, not perimeter control. Defaults: telnet 23, ftp 21, www 80, ssh 22, api 8728, winbox 8291, api-ssl 8729 all enabled; www-ssl 443 disabled.


```routeros
/ip service print
/ip service disable telnet,ftp,www,api
/ip service set winbox address=192.168.88.0/24
```


**Danger.** Adding an input-chain drop rule remotely is the classic self-lockout. Take Safe Mode first, and place the management-accept rule ABOVE the drop with `place-before=`, never append the drop and then add the accept.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/services/


### MikroTik's own hardening checklist

Verbatim from the Securing your router page: change the default admin username ("/user add name=myname password=mypassword group=full" then "/user disable admin"); passwords should be at least 12 characters mixing numbers, symbols, upper and lower case and must not be dictionary words. Turn off the MAC-layer access surface on untrusted segments: `/tool mac-server set allowed-interface-list=none`, `/tool mac-server mac-winbox set allowed-interface-list=none`, `/tool mac-server ping set enabled=no`. Turn off neighbour discovery: `/ip neighbor discovery-settings set discover-interface-list=none`.


```routeros
/user add name=myname password=mypassword group=full
/user disable admin
/tool mac-server set allowed-interface-list=none
```


**Danger.** `allow-remote-requests=yes` on a router with a public IP turns it into an open DNS resolver and a DNS-amplification reflector — a well-known way an ISP's own edge ends up in a DDoS.


> **Review correction.** Use `/ip/cloud/set ddns-enabled=auto update-time=no`. On RouterOS 6 and pre-7.17, `ddns-enabled=no` is correct — this is a version-gated command and must be branched, not stated flatly.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328353/Securing+your+router


### Security advisories you must be able to answer for

CVE-2018-14847: directory traversal in RouterOS through 6.42 via Winbox (port 8291) allowing unauthenticated arbitrary file read and, with authentication, arbitrary file write. Fixed in 6.40.8, 6.42.1 and 6.43rc4. This was mass-exploited to extract admin credentials and is why exposed 8291 is treated as compromised-until-proven-otherwise. CVE-2023-30799: authenticated privilege escalation from admin to super-admin over Winbox or HTTP. MikroTik's own advisory: an authenticated administrator "can send specially crafted internal configuration commands that would normally be rejected...


**Versions.** CVE-2018-14847 fixed 6.40.8 / 6.42.1 / 6.43rc4. CVE-2023-30799 fixed 6.49.7 and 7.7. September 2026 advisory fixed in 6.49.21, 7.23.4, 7.24.2, 7.25beta3.


```routeros
/system resource print
/system package print
/ip service print
```


Source: https://mikrotik.com/supportsec


### Finding out what is actually eating the CPU

`/tool profile` breaks CPU time down by RouterOS subsystem rather than by Linux process, which is what makes it usable. Documented classifications include networking ("common set of services included in the networking"), firewall ("Firewall-related processes"), firewall-mgmt ("Filtering, NAT, Mangle"), ipsec ("xfrm, drivers/crypto, IKE protocols, AH, ESP"), encrypting, queue-mgmt ("Simple queues, Queue tree, Queue types"), bridging, ethernet, wireless, management ("scheduler, networking, file management"), console, winbox, profiling, idle ("Free CPU resources") and unclassified ("processes or services that are no…


**Versions.** Per-core `cpu=` parameter is RouterOS 7. RouterOS 6's profiler shows a similar classification but the exact category names differ between releases.


```routeros
/tool profile cpu=all
/tool profile cpu=total
/system resource print
```


> **Review correction.** Drop `duration=`. The only valid forms are `/tool/profile cpu=all` and `/tool/profile cpu=total`. Everything else in this entry — the full classifier table including `firewall-mgmt`, `queue-mgmt`, the ipsec xfrm/drivers-crypto/IKE-AH-ESP breakdown, `management` = "different subsystems: scheduler, networking, file management", and `unclass…


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8323153/Profiler


### What operators actually monitor, and how to get the OIDs

SNMP is the fleet-wide path; MikroTik's enterprise OID root is 1.3.6.1.4.1.14988 and the MIB is downloadable from mikrotik.com/download/tools. The trick that saves guessing: "you can also print individual OID information in the console with the print oid command at any menu level" — so `/interface print oid` or `/system resource print oid` gives you the exact OID for anything visible in the CLI.


**Versions.** SNMP OIDs for connection-tracking total-entries, total-ip4-entries and total-ip6-entries were added in 7.20 — before that, conntrack occupancy is not pollable per address family. Source: download.mikrotik.com/routeros/7.20/CHANGELOG


```routeros
/snmp set enabled=yes contact=noc@example.net location=site1
/snmp community set [find default=yes] addresses=10.0.0.0/24
/system resource print oid
```


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8978519/SNMP


### /system watchdog — the last-resort auto-reboot

A hardware/software watchdog that reboots the router when a chosen address stops answering. Properties: watch-address, watchdog-timer, no-ping-delay, automatic-supout, auto-send-supout, ping-timeout, send-email-to, send-email-from, send-smtp-server. Behaviour: when the watched address becomes unreachable the device is pinged 6 times (after no-ping-delay) and the router reboots; the documentation describes this cycle recurring roughly every 6 minutes while the watch-address stays unreachable. It also captures a supout.rif on software failure and can mail it.


```routeros
/system watchdog print
/system watchdog set watch-address=10.0.0.1
/system watchdog set auto-send-supout=yes send-email-to=support@example.com send-smtp-server=192.0.2.1
```


**Danger.** DANGEROUS as a general safety net: if the watch-address is upstream of a link that goes down for a real, unrelated reason, the router reboots every few minutes forever and you cannot get in long enough to disable it.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8978694/Watchdog


### Flash wear on small CPE — the slow brick

MikroTik states NAND is guaranteed for roughly 100,000 write cycles per sector, and that up to 5 blocks can be bad from manufacture with up to 80 more developing during operation, so a few bad blocks are normal and not a defect. The operational failure is different: on most RouterBOARD hardware the 'disk' logging target is the same soldered flash that holds RouterOS, so continuous `action=disk` logging (especially firewall logging or debug topics left on after troubleshooting) is a slow-motion hardware failure.


```routeros
/system logging action print
/system logging add topics=wireless,debug action=memory
/system logging action add name=remote target=remote remote=10.0.0.5 remote-port=514
```


**Danger.** Never ship a fleet default that logs firewall matches to disk. On hAP/hEX-class hardware that is a device-killer over months, and it fails as filesystem corruption rather than a clean error.


> **Review correction.** Emit four separate rules: `/system/logging/add topics=info action=remote`, then the same for `error`, `warning`, `critical`. Reserve multi-topic rules for facility+severity intersections (`topics=firewall,warning`).


Source: https://wiki.mikrotik.com/wiki/Manual:RouterBOARD_bad_blocks


### Wireless troubleshooting: CCQ, debug logging and spectrum

CCQ is "a value in percent that shows how effective the bandwidth is used regarding the theoretically maximum available bandwidth" — a weighted average of Tmin/Treal per transmitted frame, where Tmin is the time to send at the highest rate with no retries and Treal is what it actually took. So falling CCQ at unchanged signal means retries, i.e. interference or a duty-cycle problem, not a link-budget problem; that distinction is what separates 're-aim the dish' from 'change channel'.


**Versions.** These `/interface wireless` commands belong to the legacy wireless package. On devices running the `wifi` package (7.13+, formerly wifiwave2) the menu is `/interface wifi` and spectral-scan is not available in the same form.


```routeros
/system logging add topics=wireless,debug action=memory
/log print where topics~"wireless"
/interface wireless registration-table print
```


**Danger.** Spectral scan takes the radio off-channel — running it on a production AP drops every client for the duration. Schedule it, or run it from a spare radio.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/122388523/Wireless+Troubleshooting


### Torch and sniffer lie on offloaded and fasttracked paths

Two independent reasons a packet capture on a MikroTik shows nothing while traffic is clearly flowing. (1) Hardware offload: MikroTik lists "Packets not visible by Sniffer or Torch tool" and "Filter rules not working" as symptoms of hardware offloading with MAC learning — offloaded frames are switched in silicon and never reach the CPU; you must add an explicit switch rule with copy-to-cpu=yes to see them.


```routeros
/tool torch interface=ether1
/tool sniffer quick
/interface ethernet switch rule add copy-to-cpu=yes dst-mac-address=4C:5E:0C:4D:12:4B/FF:FF:FF:FF:FF:FF ports=ether1 switch=switch1
```


**Danger.** `/tool sniffer` writing to file on a flash-only device is another flash-wear vector; stream to a remote target or use quick mode.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/19136718/Layer2+misconfiguration


### RPS — spreading soft-interrupt work across cores

"Receive Packet Steering (RPS) is similar to Receive Side Scaling (RSS) in that it is used to direct packets to specific CPUs for processing. RPS is implemented at the software level, and helps to prevent the hardware queue of a single network interface card from becoming a bottleneck." It is documented as useful "when packets require additional processing that uses a relatively large amount of CPU time, such as PPP tunnel termination, VPLS, or firewall processing" — exactly the WISP BNG workload — because the classification cost is then outweighed by the work being spread.


**Versions.** Available on multi-core RouterOS platforms; the exact property location differs by platform and RouterOS version — read /interface ethernet print detail on the target device rather than assuming a path.


```routeros
/tool profile cpu=all
/system resource irq print
/interface ethernet print detail
```


**Danger.** Enabling RPS on a box that is already balanced by RSS adds classification overhead for no gain. Measure with /tool profile cpu=all first: only turn it on when one core is saturated while others idle.


> **Review correction.** Cite the Resource page. Enable per interface under `/system/resource/irq/rps` (entry disabled=no), and state that IRQ affinity IS settable via `/system/resource/irq set <n> cpu=<n>`. Remove the "cannot be changed from RouterOS" sentence.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8323191/Ethernet


### Capacity-planning signals worth alerting on

Derived from the documented limits above, these are the numbers that predict an outage rather than describe one. (1) conntrack total-entries as a fraction of max-entries, remembering the 1,048,576 hard ceiling regardless of RAM — and that max-entries itself grows with free RAM, so a rising ratio can mean memory pressure rather than session growth. (2) Per-core CPU, never the aggregate: PPP is single-threaded, so a BNG at 25% total CPU can be 100% on the core that matters. (3) Active PPPoE sessions against the licence cap (200 for L3/L4, 500 for L5).


```routeros
/ip firewall connection tracking print
/tool profile cpu=all
/ppp active print count-only
```


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/130220087/Connection+tracking


### Managing thousands of devices: what the platform gives you

Fleet-relevant primitives, in the order they matter. `*.auto.rsc` auto-import: a file uploaded over FTP/SFTP with that suffix executes on arrival and writes a `*.auto.log` with success/failure — zero-touch provisioning without an agent, and a serious write-access hazard. FlashFig and Netinstall for bulk factory staging, with 7.22 adding device-mode configuration via a Netinstall/FlashFig 'mode script' — the only scalable way to pre-authorise device-mode features without touching each unit. RoMON for reaching devices whose IP config is wrong, through intermediate routers.


**Versions.** REST API introduced in 7.1. Device-mode via Netinstall/FlashFig mode script added in 7.22.


```routeros
/export compact file=config
/import file-name=config.rsc verbose=yes dry-run=yes
/file print
```


**Danger.** The `*.auto.rsc` mechanism means anyone who can write a file to the router executes commands on it. If FTP is enabled and reachable, that is remote code execution by design.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328155/Configuration+Management


### Sequencing a safe remote change — the composite procedure

What experienced operators actually do, combining the verified primitives. Before: confirm out-of-band reach (RoMON neighbour or a second path) and record it; read `/system/device-mode/print` on 7.17+ so you know whether scheduler even runs; take `/export compact file=pre-change` and pull it off-box; take `/system backup save name=pre-change dont-encrypt=yes`. Arm: add the rollback scheduler with policy including ftp and reboot, then read `/system scheduler print detail` and confirm `next-run` is where you expect.


**Versions.** On 7.17+ this whole procedure depends on the scheduler feature being permitted by device-mode. In `home` mode it is not, and the rollback will never fire.


```routeros
/tool romon discover
/system/device-mode/print
/export compact file=pre-change
```


**Danger.** HamWAN's own guidance on their auto-restore script is worth repeating: "If you are doing anything remotely risky on RouterOS, you should be using RouterOS Safe-Mode" — the scheduler net is for the cases Safe Mode cannot cover, not a replacement for it.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8978498/Console


### Could not verify

When a /system scheduler entry is created with interval=Xm and NO start-time, the exact time of the FIRST execution is not stated in MikroTik's documentation. Community consensus is 'one interval from creation', and the scheduler print shows a next-run field, but I could not source an authoritative statement. Any rollback pattern relying on this MUST read `/system scheduler print detail` and confirm `next-run` before proceeding, rather than assuming. Whether `/system backup load` executed from a scheduler/script context auto-confirms the interactive 'Restore and reboot?' prompt, or silently hangs.
