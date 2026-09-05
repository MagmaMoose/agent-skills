# MikroTik RouterOS — Networking subsystems worth monitoring

Part of the `mikrotik-routeros` skill. Every claim below was researched against
MikroTik's own documentation and changelogs, then independently fact-checked; where
the check found an error the corrected form is inline as **Review correction** and
the correction wins over the paragraph above it.


### Ethernet: the RouterOS 7.12 link-negotiation breaking change

7.12 is a hard breaking change (marked "!)" in the changelog) to how link speed is expressed. The exact line is: `!) ethernet - changed "advertise" and "speed" arguments, and removed "half-duplex" setting under "/interface ethernet" menu;` plus `!) sfp - convert configuration to support new link modes for SFP and QSFP type of interfaces;`. Before 7.12 `speed` took plain rates (10Mbps/100Mbps/1Gbps) and duplex was a separate `full-duplex` boolean.


**Versions.** Change lands in 7.12 (2023). RouterOS 6.x and RouterOS 7.0–7.11 use the old `speed`/`full-duplex` form. 7.12 also added `*) ethernet - added "supported" and "sfp-supported" values for "monitor" command;` so the monitor output gained capability lists in the sam…


```routeros
/interface/ethernet print detail
/interface/ethernet set ether1 auto-negotiation=yes advertise=1G-baseT-full,100M-baseT-full
/interface/ethernet set ether1 auto-negotiation=no speed=1G-baseT-full
```


**Danger.** Setting `auto-negotiation=no` on a remote copper link is a classic lockout: if the far end still autonegotiates, the link either drops or comes up half-duplex and the device is unreachable with no console.


> **Review correction.** Treat the list as non-exhaustive, or read the per-port capability set from `/interface/ethernet monitor` `supported`/`sfp-supported` (added in 7.12, which the entry correctly notes) rather than validating against a hardcoded list.


Source: https://download.mikrotik.com/routeros/7.12/CHANGELOG


### Ethernet: everything readable from /interface/ethernet monitor, including SFP DDM

`/interface/ethernet monitor` is the single richest per-port read for a fleet console and is entirely read-only. Fields: `status` (link-ok | no-link | unknown), `auto-negotiation` (disabled | done | failed | incomplete), `rate` (negotiated rate), `full-duplex`, `tx-flow-control`, `rx-flow-control`, `advertising`, `link-partner-advertising`. For optics/DACs the same command exposes digital diagnostic monitoring: `sfp-module-present`, `sfp-rx-loss`, `sfp-temperature` (C), `sfp-supply-voltage` (V), `sfp-tx-bias-current` (mA), `sfp-tx-power` (dBm), `sfp-rx-power` (dBm), `sfp-vendor-name`, `sfp-vendor-part-number`, `s…


**Versions.** 7.12 added `supported` and `sfp-supported` values to the monitor command output (per the 7.12 CHANGELOG), so capability enumeration is only available from 7.12 onward.


```routeros
/interface/ethernet monitor ether1 once
/interface/ethernet monitor [find] once
/interface/ethernet monitor sfp-sfpplus1 once
```


**Danger.** `monitor` without `once` is an interactive streaming command. Over the API or an SSH exec it never returns and will hang the collector. Always append `once`.


> **Review correction.** Identity field is `iccid`. For the pre-lock safety read use `primary-band` and `ca-band` (and `ul-ca-band`). Rewrite the danger note to name `primary-band`. All other listed fields are CONFIRMED present, and the monitor also exposes `roaming`, `psc`, `data-class`, `subscriber-number`, `frame-error-rate`, `dl-modulation`, `dl-mimo`, `mcs`,…


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8323191/Ethernet


### Ethernet: per-port error and frame counters

`/interface/ethernet print stats` returns hardware counters that the generic interface counters do not carry. Documented names include `driver-rx-byte`, `driver-rx-packet`, `driver-tx-byte`, `driver-tx-packet`, `rx-bytes`, `tx-bytes`, `rx-broadcast`, `rx-multicast`, `rx-unicast`, `tx-broadcast`, `tx-multicast`, `tx-unicast`, error counters `rx-fcs-error`, `rx-align-error`, `tx-collision`, `tx-underrun`, FEC counters `fc-fec-block-corrected`, `rs-fec-corrected`, `rs-fec-uncorrected`, and frame-size histograms `rx-64`, `rx-65-127`, ... `rx-1024-1518`.


**Versions.** Counter availability is chip-dependent; not every model populates every counter. Treat a missing key as "not supported", not as zero.


```routeros
/interface/ethernet print stats
/interface/ethernet print stats where name=ether1
/interface/ethernet cable-test ether1 once
```


**Danger.** `/interface/ethernet cable-test` takes the port down while it runs. Never run it against the port carrying your management session.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8323191/Ethernet


### Generic interface counters, link flap history and fast-path split

`/interface print stats` gives `RX-BYTE`, `TX-BYTE`, `RX-PACKET`, `TX-PACKET`, `TX-QUEUE-DROP` ("Packets dropped by the interface queue"). `/interface print stats-detail` adds `link-downs`, `last-link-down-time`, `last-link-up-time` and the fast-path counters `fp-rx-byte`, `fp-tx-byte`, `fp-rx-packet`, `fp-tx-packet`. `link-downs` plus `last-link-up-time` is the correct flap detector for a fleet console — it is a monotonic counter, so poll the delta rather than watching for a transient `running=no`.


**Versions.** `stats-detail` and the fp-* counters are RouterOS 7 constructs; RouterOS 6 exposes a smaller set.


```routeros
/interface print stats
/interface print stats-detail
/interface/monitor-traffic interface=ether1 once
```


**Danger.** `/interface/monitor-traffic` without `once` streams forever and will wedge a non-interactive session.


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/interface-stats-and-monitor-traffic/


### Bridge: what silently turns off the software fast path

`/interface/bridge` core properties: `vlan-filtering`, `protocol-mode` (none | stp | rstp | mstp), `igmp-snooping`, `dhcp-snooping`, `fast-forward`, `pvid` (1-4094), `frame-types` (admit-all | admit-only-untagged-and-priority-tagged | admit-only-vlan-tagged), `ingress-filtering`, `auto-mac`, `admin-mac`, `priority`, `forward-delay`, `max-learned-entries`, `forward-reserved-addresses`. Enabling `vlan-filtering`, `igmp-snooping` or `dhcp-snooping`, or setting `use-ip-firewall=yes` under `/interface/bridge/settings`, prevents software fast-path operation.


**Versions.** 7.16 added `max-learned-entries`, `forward-reserved-addresses`, MVRP for bridge VLANs and L2 MDB for IGMP snooping (see the 7.16 CHANGELOG).


```routeros
/interface/bridge print detail
/interface/bridge/settings print
/interface/bridge set bridge1 auto-mac=no admin-mac=CC:2D:E0:00:00:01
```


**Danger.** Turning on `vlan-filtering` on a live bridge before the bridge VLAN table is complete drops every frame that is not covered by a VLAN entry, including your own management traffic.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328068/Bridging+and+Switching


### Bridge ports: hardware offload and what disables it

`/interface/bridge/port` properties: `hw` (enable hardware offload), `horizon`, `pvid`, `frame-types`, `ingress-filtering`, `learn` (auto | yes | no), `edge` (auto | no | no-discover | yes | yes-discover), `point-to-point`, `path-cost`, `internal-path-cost`, `priority`, `bpdu-guard`, `restricted-role`, `restricted-tcn`. Offload is silently disabled by: `hw=no` on the port, any non-zero `horizon`, `tag-stacking=yes`, a non-0x8100 `ether-type` on non-Prestera chips, enabling a feature the chip does not implement, and VLAN filtering on hardware that cannot do VLAN filtering plus offload together.


**Versions.** The RTL8367/88E639x/MT76xx/EN7523 combination of VLAN filtering + offload is a RouterOS v7 capability; on v6 those devices lose the switch chip when VLAN filtering is on.


```routeros
/interface/bridge/port print detail
/interface/bridge/port/monitor [find] once
/interface/bridge/port print where hw-offload=no
```


**Danger.** Losing offload does not error — it silently moves forwarding to the CPU. On a CRS or CCR carrying real traffic, that is an instant throughput collapse and a CPU-pegged, unmanageable device.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328068/Bridging+and+Switching


### Bridge: changing certain properties resets the switch chip

Some bridge and Ethernet properties map directly onto switch-chip registers, and writing them triggers a switch chip reset that temporarily disables every Ethernet port on that chip while the setting takes effect. Documented triggers: DHCP Snooping, IGMP Snooping, VLAN filtering, L2MTU and Flow Control.


**Versions.** Applies to both RouterOS 6 and 7 on switch-chip devices.


```routeros
/interface/bridge set bridge1 vlan-filtering=yes
/interface/bridge set bridge1 igmp-snooping=yes
/interface/ethernet set ether1 l2mtu=9000
```


**Danger.** This is an all-ports outage of several seconds on a production switch, including the management port. Never apply these from an unattended job during business hours; queue them into a maintenance window, and expect the device's own session to drop and reconnec…


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328068/Bridging+and+Switching


### Bridge VLAN table and monitoring reads

`/interface/bridge/vlan` holds `bridge`, `vlan-ids` (single, list or range, e.g. `100-115,120,122`), `tagged`, `untagged`, and the read-only resolved sets `current-tagged` / `current-untagged`. `current-*` is what the bridge is actually doing and is the field to monitor; `tagged`/`untagged` is only what was configured. For the router itself to terminate a VLAN, the bridge interface must appear in the `tagged` list of that VLAN. `/interface/bridge/monitor` read-only: `root-bridge`, `root-path-cost`, `root-port`, `bridge-id`, `designated-port-count`, `fast-forward`, `port-count`.


**Versions.** From 7.16 a dynamic tagged bridge-VLAN entry is created automatically when a `/interface/vlan` interface is built on a vlan-filtering bridge: `*) bridge - added dynamic tagged entry when VLAN interface is created on vlan-filtering bridge` (7.16 CHANGELOG).


```routeros
/interface/bridge/vlan print detail
/interface/bridge/monitor bridge1 once
/interface/bridge/port/monitor [find bridge=bridge1] once
```


**Danger.** Read-only menus, safe to poll. The write side (`tagged`/`untagged`) is the dangerous one: removing the bridge itself from a VLAN's tagged list cuts the router off that VLAN instantly.


> **Review correction.** `role` enum: disabled-port | root-port | designated-port | alternate-port | backup-port. Note the whole rest of this entry verified cleanly and unusually well: `current-tagged`/`current-untagged` are read-only as claimed; `/interface/bridge/monitor` does expose root-bridge, root-path-cost, root-port, bridge-id, designated-port-count, fast…


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328068/Bridging+and+Switching


### /interface/vlan and its interaction with a vlan-filtering bridge

`/interface/vlan` properties: `name`, `vlan-id`, `interface`, `use-service-tag` (802.1ad service tag), `mvrp`, `mtu`, `arp`, `arp-timeout`, `disabled`. Documented note: MTU should be 1500 like Ethernet, but the parent must be able to carry 1500 data + 4 bytes VLAN header + 14 bytes Ethernet header, i.e. the parent's `l2mtu` must be at least 1504 or tagged full-size frames are dropped with no error anywhere. Documented note on bridges: "Adding a VLAN interface to a bridge with vlan-filtering enabled will automatically tag the bridge interface as a member port.


**Versions.** The automatic dynamic bridge-VLAN entry is 7.16+. `mvrp` on bridge VLANs also arrives in 7.16 (`*) bridge - added MVRP support for VLANs assigned to bridge`).


```routeros
/interface/vlan add name=vlan100 vlan-id=100 interface=bridge1
/interface/vlan print detail
/interface/bridge/vlan print where dynamic
```


**Danger.** Silent failure mode: a parent interface whose `l2mtu` is exactly 1500 will pass untagged 1500-byte frames and drop tagged ones. Nothing logs. Check `l2mtu` on the parent before creating the VLAN.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/88014957/VLAN


### Wireless: which package a device runs, and why it matters before you issue any command

There are two mutually exclusive wireless stacks. Legacy `wireless` package -> `/interface/wireless`. New stack -> `/interface/wifi` (called `/interface/wifiwave2` before 7.13). Driver packages for the new stack: `wifi-qcom` (Wi-Fi 6/6E Qualcomm), `wifi-qcom-ac` (Wi-Fi 5 / 802.11ac Qualcomm), `wifi-qcom-be` (Wi-Fi 7 Qualcomm), `wifi-mediatek` (MediaTek Wi-Fi 6/7). Documented constraints: "MIPS type devices have no choice of driver, only legacy drivers are supported." 802.11 a/b/g/n devices require the `wireless` package; 802.11ac ARM devices may use either `wifi-qcom-ac` or `wireless`.


**Versions.** 7.13 split the stack: `!) wifi - split existing "wifiwave2" package into separate packages "wifi-qcom", "wifi-qcom-ac", and include required utilities for WiFi management into bundle;` and `!) wireless - separate "wireless" package from bundle and build as a s…


```routeros
/system/package print
/interface/wireless print detail
/interface/wifi print detail
```


**Danger.** Upgrading a device past 7.13 changes which packages exist. `wireless` left the bundle, so an upgrade that does not also install the standalone `wireless` package leaves an 802.11n AP with no radio at all — a total service outage on that site, recoverable only…


Source: https://manual.mikrotik.com/docs/wireless/


### Wireless: legacy /interface/wireless registration table (per-client monitoring)

`/interface/wireless/registration-table` is read-only and only populated on APs. Exact field names: `signal-strength`, `signal-strength-ch0`, `signal-strength-ch1`, `signal-strength-ch2`, `signal-to-noise`, `tx-rate`, `rx-rate`, `tx-ccq`, `rx-ccq`, `p-throughput`, `uptime`, `last-activity`, `bytes`, `packets`, `frames`, `hw-frames`, `tx-signal-strength`, `distance`, `ap`, `wds`, `bridge`, `comment`, `authentication-type`, `encryption`.


**Versions.** Legacy package only. RouterOS 6 and RouterOS 7 with the `wireless` package share this schema.


```routeros
/interface/wireless/registration-table print detail
/interface/wireless/registration-table print stats
/interface/wireless/monitor wlan1 once
```


**Danger.** Read-only, safe to poll at any interval. Removing an entry (`/interface/wireless/registration-table remove`) deauthenticates that client.


> **Review correction.** Drop `band` from the monitor output list; use `channel` (which encodes the band/width) or `frequency`. `current-tx-powers` is CONFIRMED correct including the plural. `noise-floor`, `overall-tx-ccq`, `registered-clients`, `authenticated-clients`, `notify-external-fdb`, `status`, `wireless-protocol` all CONFIRMED, and the `status` enum is (…


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8978446/Wireless+Interface


### Wireless: legacy /interface/wireless/monitor radio-level reads

`/interface/wireless/monitor <iface> once` returns read-only `status`, `band`, `channel`, `frequency`, `wireless-protocol`, `noise-floor`, `overall-tx-ccq`, `registered-clients`, `authenticated-clients`, `current-tx-powers`, `notify-external-fdb`. `noise-floor` in dBm is the interference indicator — a noise floor that rises from about -100 to -80 explains a client-signal drop that is not actually a signal drop. `overall-tx-ccq` is the AP-wide health percentage.


**Versions.** Legacy package only.


```routeros
/interface/wireless/monitor wlan1 once
/interface/wireless/security-profiles print detail
/interface/wireless/snooper/snoop wlan1 duration=10
```


**Danger.** `/interface/wireless/snooper` and `scan` put the radio into scanning mode and drop every associated client for the duration. Never run either on a production AP without a maintenance window; use `registration-table` and `monitor` for passive health instead.


> **Review correction.** Drop `band` from the monitor output list; use `channel` (which encodes the band/width) or `frequency`. `current-tx-powers` is CONFIRMED correct including the plural. `noise-floor`, `overall-tx-ccq`, `registered-clients`, `authenticated-clients`, `notify-external-fdb`, `status`, `wireless-protocol` all CONFIRMED, and the `status` enum is (…


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8978446/Wireless+Interface


### WiFi (new stack): menus and the exact registration-table fields

Submenus: `/interface/wifi`, `/interface/wifi/network`, `/interface/wifi/security`, `/interface/wifi/channel`, `/interface/wifi/configuration`, `/interface/wifi/datapath`, `/interface/wifi/aaa`, `/interface/wifi/interworking`, `/interface/wifi/access-list`, `/interface/wifi/registration-table`, `/interface/wifi/radio`, `/interface/wifi/capsman`, `/interface/wifi/cap`, `/interface/wifi/provisioning`, `/interface/wifi/monitor`.


**Versions.** Menu is `/interface/wifi` from 7.13; `/interface/wifiwave2` before that. "The configuration menu used to be called 'wifiwave2' in RouterOS versions before 7.13, where it was a part of the 'wifiwave2' software package."


```routeros
/interface/wifi/registration-table print detail
/interface/wifi/radio print detail
/interface/wifi/monitor [find] once
```


**Danger.** Read-only, safe to poll. Do not assume legacy field names exist here — a collector that reads `signal-strength` gets nothing and will report every client as 0 dBm.


Source: https://manual.mikrotik.com/docs/wireless/wifi/


### CAPsMAN: the two implementations do not interoperate

MikroTik states it plainly: "WiFi CAPsMAN can only control WiFi interfaces, and WiFi CAPs can join only WiFi CAPsMAN, similarly, regular CAPsMAN only supports non-WiFi caps." And for data path: "The 'wifi' station-bridge mode, is incompatible with APs running the older 'wireless' package and vice versa." New-stack controller/CAP menus: `/interface/wifi/capsman` (`enabled`, `interfaces` (default all), `certificate`, `ca-certificate`, `package-path`, `require-peer-certificate`, `upgrade-policy` = none | require-same-version | suggest-same-version) and `/interface/wifi/cap` (`enabled`, `discovery-interfaces`, `caps-…


**Versions.** Legacy CAPsMAN (`/caps-man`) exists in RouterOS 6 and 7 with the `wireless` package. WiFi CAPsMAN (`/interface/wifi/capsman`) is 7.13+ (7.12 and earlier: `/interface/wifiwave2/capsman`).


```routeros
/interface/wifi/capsman print
/interface/wifi/radio print detail
/caps-man/remote-cap print detail
```


**Danger.** Pointing an AP's `/interface/wifi/cap caps-man-addresses` at a legacy `/caps-man` controller produces a permanent "no connection to CAPsMAN" with the radio down — the AP stops serving clients and the failure looks like a network problem, not a version mismatch…


Source: https://manual.mikrotik.com/docs/wireless/wifi/capsman/


### LTE/5G: configuration menus and the passthrough switch

Menus: `/interface/lte`, `/interface/lte/apn`, `/interface/lte/settings`, `/interface/lte/monitor`, `/interface/lte/cell-monitor`, `/interface/lte/at-chat`, `/interface/lte/firmware-upgrade`, `/interface/lte/esim`. Interface properties: `apn-profiles`, `band` (lock LTE bands), `nr-band` (lock 5G NR bands), `network-mode` (3g | gsm | lte | 5g), `modem-init` (AT commands at startup), `pin`. `/interface/lte/apn` properties: `apn`, `authentication` (pap | chap | none), `ip-type` (ipv4 | ipv4-ipv6 | ipv6), `add-default-route`, `use-peer-dns`, `passthrough-interface`, `passthrough-mac`.


**Versions.** eSIM provisioning via `/interface/lte/esim` is 7.18+. RouterOS 7 renamed `ignore-direct-modem` to `mode` under `/interface/lte/settings`. SIM-slot command syntax changed in 6.45.1 and again in v7 — do not reuse a v6 sim-slot command on v7.


```routeros
/interface/lte print detail
/interface/lte/apn print detail
/interface/lte set lte1 band=3,7,20
```


**Danger.** Locking `band` or `nr-band` to a set the tower does not offer takes the modem permanently off the network. On a router whose only WAN is that modem, this is an unrecoverable remote outage.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/30146563/LTE+5G


### LTE/5G: everything readable from /interface/lte/monitor

`/interface/lte/monitor <iface> once` returns, read-only: state — `status`, `registration-status`, `functionality`, `access-technology`, `session-uptime`, `pin-status`; identity — `manufacturer`, `model`, `revision`, `imei`, `imsi`, `uicc`; network/cell — `current-operator`, `current-cellid`, `lac`, `enb-id`, `sector-id`, `phy-cellid`, `earfcn`; signal — `rssi`, `rsrp`, `rsrq`, `sinr`, `cqi`, `ri`, `band`, `primary-band`, `ca-band`.


**Versions.** Field availability is modem-firmware dependent; not every modem populates `sinr`, `cqi`, `ri` or `ca-band`. Treat absent keys as unsupported, not zero.


```routeros
/interface/lte/monitor lte1 once
/interface/lte/cell-monitor lte1 once
/interface/lte/at-chat lte1 input="AT+CSQ"
```


**Danger.** `/interface/lte/at-chat` sends raw AT commands to the modem. Write-type AT commands can reconfigure or brick the modem's NV settings and are not covered by RouterOS config backup. Restrict a fleet console to read-only AT strings.


> **Review correction.** Identity field is `iccid`. For the pre-lock safety read use `primary-band` and `ca-band` (and `ul-ca-band`). Rewrite the danger note to name `primary-band`. All other listed fields are CONFIRMED present, and the monitor also exposes `roaming`, `psc`, `data-class`, `subscriber-number`, `frame-error-rate`, `dl-modulation`, `dl-mimo`, `mcs`,…


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/30146563/LTE+5G


### IP addresses: /ip/address schema and flags

`/ip/address` properties: `address` (ipAddr with netmask), `network` (calculated), `netmask`, `broadcast`, `interface` (mandatory), plus `comment`/`disabled`. Read-only: `actual-interface` — the interface the address really lives on, which differs from `interface` when the configured interface is a bridge port; and `vrf`. Flags: `X` disabled, `I` invalid, `D` dynamic, `S` slave ("Whether address belongs to an interface which is a slave port to some other master interface"). A console must read `actual-interface`, not `interface`, when mapping addresses to the forwarding topology.


**Versions.** `vrf` as a read-only field on an address is RouterOS 7.


```routeros
/ip/address print detail
/ip/address print where dynamic
/ip/address print where invalid
```


**Danger.** Adding an address on the management interface without removing the old one is safe; replacing it with `set` is not — the session drops at the moment the old address disappears. Use `add`, verify, then `remove`, inside Safe Mode.


Source: https://manual.mikrotik.com/docs/cli-reference/ip/address/


### IP routing: route flags, RIB vs FIB, and the distance rule

RouterOS keeps a RIB (everything learned) and a FIB (what forwards). `/ip/route` properties: `dst-address`, `gateway`, `distance`, `scope`, `target-scope`, `routing-table`, `pref-src`, `check-gateway`, `blackhole`, `suppress-hw-offload`, `vrf-interface`. Flags: `A` active, `D` dynamic, `X` disabled, `I` inactive, `C` connect, `S` static, `H` hardware-offloaded, `+` ECMP. Only routes that are not disabled, have at least one reachable next-hop and are not synthetic take part in selection; the lowest `distance` wins, and among equal distances the choice is arbitrary unless the route is ECMP.


**Versions.** `/routing/route`, `/routing/table` and named routing tables are RouterOS 7. In RouterOS 6 the equivalent is `routing-mark` on `/ip/route` and there is no `/routing/table` menu.


```routeros
/ip/route print detail where active
/routing/route print detail
/ip/route print count-only where !active
```


**Danger.** Adding or editing a default route on a remote device is the single most common way to lose it. Do it in Safe Mode, or add the new route at a higher `distance` first, confirm it is `I` (inactive but valid), and only then lower the distance.


> **Review correction.** Full v7 flag set: D dynamic, X disabled, I inactive, A active, c connect, s static, r rip, b bgp, o ospf, i is-is, d dhcp, v vpn, m modem, y bgp-mpls-vpn, H hw-offloaded, + ecmp. The entry omits the six protocol-origin flags entirely.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328084/IP+Routing


### IP routing: ECMP and recursive next-hop resolution

ECMP routes carry multiple gateways; all reachable next-hops are copied into the FIB and used to forward. Default ECMP hashing is Layer3 (source/destination IP); Layer4 (adds ports) and Layer3-Inner are the alternatives. Recursive routes (iBGP, multihop eBGP, a static route pointing at a gateway several hops away) are installed only after next-hop lookup resolves an immediate directly-reachable gateway.


**Versions.** The v7 nexthop-lookup implementation is part of the rewritten routing stack (7.1: "completely new BGP implementation", "completely new OSPF implementation").


```routeros
/ip/route print detail where dst-address=0.0.0.0/0
/ip/route add dst-address=10.0.0.0/8 gateway=192.0.2.1 target-scope=30
/routing/route print detail
```


**Danger.** Raising `target-scope` to make a recursive route resolve can make it resolve through a route you did not intend (including through the default route), silently blackholing or looping traffic. Prefer an explicit /32 host route to the recursive gateway.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328084/IP+Routing


### IP routing: check-gateway semantics and its failure timing

`check-gateway` on `/ip/route` actively probes the next hop by ARP request, ICMP echo, or an active BFD session (`arp` | `ping` | `bfd` | `none`). The router probes every 10 seconds; a probe with no response times out after 10 seconds, and after two consecutive timeouts the gateway is considered unreachable and the route goes inactive. A reply resets the counter. Worst-case detection time is therefore on the order of 20-30 seconds, which is why `check-gateway` alone is not a sub-second failover mechanism.


**Versions.** `bfd` as a `check-gateway` value belongs to the v7 BFD implementation (`/routing/bfd`); RouterOS 6 offers only `arp` and `ping`.


```routeros
/ip/route set [find dst-address=0.0.0.0/0 gateway=192.0.2.1] check-gateway=ping
/ip/route print detail where check-gateway!=none
```


**Danger.** `check-gateway=ping` against a gateway that rate-limits or drops ICMP will flap the route every ~20 seconds forever, taking the link down repeatedly with no fault on the link.


> **Review correction.** Interval 10s, timeout 1s, count 2. Worst-case detection is ~21s, not 20-30s. The entry also fails to mention that these are tunable in `/routing/settings` via `check-gateway-ping-interval`, `check-gateway-ping-timeout` and `check-gateway-ping-count` — which is the actual answer to "can I make failover faster".


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328084/IP+Routing


### DHCP server: leases and what each read-only field means

Menus: `/ip/dhcp-server`, `/ip/dhcp-server/network`, `/ip/dhcp-server/lease`, `/ip/dhcp-server/config`, `/ip/dhcp-server/option`, `/ip/dhcp-server/option/sets`, `/ip/dhcp-server/alert`, `/ip/dhcp-server/matcher`. Server properties: `name`, `interface`, `address-pool`, `lease-time`, `use-radius`, `authoritative`, `conflict-detection`, `add-arp`, `relay`. Lease read-only fields: `address`, `mac-address`, `client-id`, `server`, `status`, `expires-after`, `last-seen`, `active-address`, `active-mac-address`, `active-server`, `host-name`, `blocked`, `dynamic`, `radius`, `rate-limit`.


**Versions.** 7.16 added `class-id` on leases, `comment` on matchers/options/option sets, raised the lease offer timeout to 120 seconds, and made dynamic leases be removed when their address-pool is removed (7.16 CHANGELOG).


```routeros
/ip/dhcp-server print detail
/ip/dhcp-server/lease print detail where status=bound
/ip/dhcp-server/lease print count-only where status=conflict
```


**Danger.** Removing a DHCP server or its pool removes the dynamic leases with it (explicitly so from 7.16). Every client on that segment loses its address at next renewal. Never remove a pool to "tidy up" on a live device.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/24805500/DHCP


### DHCP client and relay: readable status

`/ip/dhcp-client` configurable: `interface`, `disabled`, `host-name`, `client-id`, `add-default-route`, `use-peer-dns`, `use-peer-ntp`, `script`, `comment`. Read-only: `address` (IP/netmask), `gateway`, `dhcp-server`, `primary-dns`, `secondary-dns`, `primary-ntp`, `secondary-ntp`, `expires-after`, `status`, `netmask`, `invalid`. `status` values: `bound` | `error` | `rebinding` | `requesting` | `searching` | `stopped`. For a WAN-health check, `status=bound` plus a non-empty `gateway` is the correct signal; `searching` persisting past one lease interval is an upstream fault.


**Versions.** `dhcp-server-vrf` on the relay is 7.15+.


```routeros
/ip/dhcp-client print detail
/ip/dhcp-client print where status!=bound
/ip/dhcp-client release [find interface=ether1]
```


**Danger.** `/ip/dhcp-client release` drops the current WAN address immediately. If the upstream server is down or has moved the pool, the device does not come back. Prefer `renew` over `release`, and never issue either against the interface carrying your management path.


> **Review correction.** Values are: stopped, `searching...`, `requesting...`, bound, `renewing...`, `rebinding...`, error. Prefer the negative test the entry already recommends (`print where status!=bound`), which is unaffected.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/24805500/DHCP


### IP pools: pool exhaustion is directly readable

`/ip/pool` properties: `name`, `ranges` ("IP address list of non-overlapping IP address ranges in the form of: from1-to1,from2-to2,...,fromN-toN"), `next-pool` (fallback when exhausted), `comment`. The CLI reference documents read-only statistics on the pool itself: `total` (complete pool size), `used` (currently allocated), `available` (remaining). That triple is the correct, cheap pool-utilisation metric for a console — no need to count leases. `/ip/pool/used` is the per-address view, read-only: `address`, `owner` (the service holding it), `info` (DHCP MAC address or PPP username), `pool`.


**Versions.** The `total`/`used`/`available` read-only fields are documented in the current manual's CLI reference; the exact release that introduced them is not stated in MikroTik's documentation — a console should feature-detect (fall back to counting `/ip/pool/used` rows…


```routeros
/ip/pool print detail
/ip/pool/used print
/ip/pool/used print count-only where pool=dhcp_pool0
```


**Danger.** Editing `ranges` on a pool that is in use does not renumber existing leases; shrinking a range below the addresses already handed out leaves clients holding addresses the pool no longer owns, and they are not reclaimed until lease expiry.


Source: https://manual.mikrotik.com/docs/cli-reference/ip/pool/


### DNS: resolver config, cache pressure and static record types

`/ip/dns` properties: `servers`, read-only `dynamic-servers` (learned from DHCP/VPN/IPv6 RA), `allow-remote-requests` (default no), `cache-size` (KiB, 64..4294967295, default 2048), `cache-max-ttl` (default 1w), read-only `cache-used`, `max-concurrent-queries` (default 100), `max-concurrent-tcp-sessions` (default 20), `max-udp-packet-size` (50..65507, default 4096), `query-server-timeout` (default 2s), `query-total-timeout` (default 10s), `vrf`, `mdns-repeat-ifaces`; DoH: `use-doh-server`, `verify-doh-cert` (default no), `doh-max-server-connections` (default 5), `doh-max-concurrent-queries` (default 50), `doh-tim…


**Versions.** DoH properties, `/ip/dns/adlist` and `/ip/dns/forwarders` are RouterOS 7 features; `verify-doh-cert=yes` requires a valid CA certificate store and a correct clock on the device.


```routeros
/ip/dns print
/ip/dns/cache print count-only
/ip/dns/static print detail
```


**Danger.** `allow-remote-requests=yes` without a firewall rule blocking UDP/TCP 53 from WAN turns the router into an open DNS resolver and a DDoS amplifier. If a console enables it, it must also verify an input-chain drop for 53 on untrusted interfaces.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS


### ARP: modes, flags and the lockout mode

`/ip/arp` entry properties: `address`, `mac-address` (default 00:00:00:00:00:00), `interface`, `published` (static proxy-arp for an individual IP), `comment`, `disabled`. Flags: `D` dynamic, `I` invalid, `H` DHCP (created by the DHCP server with `add-arp=yes`), `P` published, `C` complete. Per-interface `arp` property values: `enabled` (default, learns dynamically), `disabled`, `proxy-arp`, `local-proxy-arp`, `reply-only`. `reply-only` means the router answers ARP but resolves neighbours only from static `/ip/arp` entries — combined with DHCP `add-arp=yes` this is a legitimate anti-spoofing design.


**Versions.** Same in RouterOS 6 and 7.


```routeros
/ip/arp print detail
/ip/arp print where dynamic
/interface/ethernet set ether2 arp=reply-only
```


**Danger.** `arp=disabled` on an interface means the router will not answer ARP requests from clients on it — every host on that segment, including your management station, loses the router unless it has a static ARP entry.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/100892687/ARP


### PPP: secrets, profiles and the active-session view

`/ppp/secret`: `name`, `password`, `service` (any | async | isdn | l2tp | pppoe | pptp | ovpn | sstp), `profile`, `local-address`, `remote-address`, `routes` ("dst-address gateway metric"), `caller-id`, `limit-bytes-in`, `limit-bytes-out`, `disabled`. `/ppp/profile`: `name`, `local-address`, `remote-address`, `bridge`, `rate-limit`, `only-one`, `use-mpls`, `use-compression`, `use-encryption`, `session-timeout`, `idle-timeout`, `dns-server`, `address-list`, `incoming-filter`, `outgoing-filter`, `change-tcp-mss`.


**Versions.** Same shape in RouterOS 6 and 7.


```routeros
/ppp/active print detail
/ppp/active print count-only
/ppp/secret print detail where !disabled
```


**Danger.** `/ppp/active remove` disconnects a live subscriber immediately. Removing or disabling a `/ppp/secret` does not by itself drop the current session, so a console that suspends a user must do both — and must not do the first as a side effect of a bulk edit.


> **Review correction.** Drop `isdn`. Valid values: any | async | pptp | pppoe | l2tp | ovpn | sstp — identical on `/ppp/active`. The rest of the entry is CONFIRMED, and this also resolves its own couldNotVerify item on `/ppp/aaa`: the real property set is `use-radius`, `accounting`, `use-circuit-id-in-nas-port-id`, `interim-update`, `enable-ipv6-accounting` — so…


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/132350049/PPP+AAA


### PPPoE: client and server, and the client monitor fields

`/interface/pppoe-client` properties: `interface`, `user`, `password`, `service-name`, `ac-name`, `add-default-route`, `use-peer-dns`, `dial-on-demand`, `max-mtu` / `max-mru` (default 1460), `keepalive-timeout` (default 60), `allow` (pap, chap, mschap1, mschap2). `/interface/pppoe-client monitor` reports `status`, `uptime`, `encoding`, `service-name`, `ac-name`, `ac-mac`, `local-address`, `remote-address`, `mru`, `mtu` — `ac-mac` changing is a BNG failover on the ISP side and explains a session reset with no local cause.


**Versions.** `pppoe-over-vlan-range` on the server is a RouterOS 7 addition.


```routeros
/interface/pppoe-client monitor pppoe-out1 once
/interface/pppoe-client print detail
/interface/pppoe-server/server print detail
```


**Danger.** Changing `interface` or `service-name` on a live `/interface/pppoe-server server` drops every session on it at once. On a BNG that is a full customer outage; treat it as a maintenance-window change.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/2031625/PPPoE


### Firewall: tables, chains and where RAW sits

Menus: `/ip/firewall/filter`, `/ip/firewall/nat`, `/ip/firewall/mangle`, `/ip/firewall/raw`, `/ip/firewall/address-list`, `/ip/firewall/connection`, `/ip/firewall/service-port`. Chains — raw: `prerouting`, `output`; filter: `input`, `forward`, `output`; mangle: `prerouting`, `input`, `forward`, `output`, `postrouting`; nat: `srcnat`, `dstnat` plus (RouterOS 7 only) `input` and `output`. `connection-state` matcher values: `new`, `established`, `related`, `invalid`, `untracked`.


**Versions.** The NAT `input` and `output` chains are RouterOS 7 only: "Since RouterOS v7 the firewall NAT has two new INPUT and OUTPUT chains which are traversed for packets delivered to and sent from applications running on the local machine." A v6 config generator must n…


```routeros
/ip/firewall/filter print stats
/ip/firewall/filter print where bytes=0
/ip/firewall/raw print stats
```


**Danger.** Adding a rule to the filter `input` chain on a remote device is the fastest way to lock yourself out — rule order matters and an `action=drop` placed above your management accept applies instantly to the existing session.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/250708066/Firewall


### NAT: masquerade vs src-nat, and the conntrack flush requirement

`/ip/firewall/nat` NAT-specific actions: `src-nat`, `dst-nat`, `masquerade`, `netmap`, `redirect`, `same`, `endpoint-independent-nat`, `socksify` (plus the generic actions shared with filter). Documented behaviour: masquerade chooses the source address from the IP bound to the outgoing interface, which is what makes it correct for DHCP/PPPoE WANs whose address changes. Documented tradeoff, quoted: "If srcnat is used instead of masquerade, connection tracking entries remain and connections can simply resume after a link failure.


**Versions.** `endpoint-independent-nat` is RouterOS 7. NAT `input`/`output` chains are RouterOS 7.


```routeros
/ip/firewall/nat print stats
/ip/firewall/nat add chain=srcnat out-interface=ether1 action=masquerade
/ip/firewall/connection remove [find]
```


**Danger.** `/ip/firewall/connection remove [find]` clears the whole connection table — every established session on the device, including SSH/API/Winbox, is torn down. It is the documented fix after a NAT change, but on a busy router it is a visible outage.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/3211299/NAT


### Connection tracking: settings, capacity and the readable connection table

`/ip/firewall/connection/tracking` properties: `enabled` (yes | no | auto — `auto` means tracking runs only if a filter/NAT/mangle rule needs it), `loose-tcp-tracking` (default yes), `liberal-tcp-tracking` (default no), `tcp-syn-sent-timeout` (5s), `tcp-syn-received-timeout` (5s), `tcp-established-timeout` (1d), `tcp-fin-wait-timeout` (10s), `tcp-close-wait-timeout` (10s), `tcp-last-ack-timeout` (10s), `tcp-time-wait-timeout` (10s), `tcp-close-timeout` (10s), `udp-timeout` (30s), `udp-stream-timeout` (3m), `icmp-timeout` (10s), `generic-timeout` (10m).


**Versions.** `enabled=auto` is the RouterOS 7 default behaviour; RouterOS 6 defaults to tracking on.


```routeros
/ip/firewall/connection/tracking print
/ip/firewall/connection print count-only
/ip/firewall/connection print detail where fasttrack
```


**Danger.** Setting `enabled=no` instantly invalidates every stateful firewall rule (`connection-state=established` stops matching) and every NAT rule stops working.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/130220087/Connection+tracking


### FastTrack: the reason your queue and mangle counters read zero

`action=fasttrack-connection` (available in firewall filter and mangle) marks a connection for the fast path; the connection table entry then shows the `fasttrack` flag. Documented bypass list, quoted: FastTrack packets bypass "firewall, connection tracking, simple queues, queue tree with parent=global, ip traffic-flow, IP accounting, IPSec, hotspot universal client, VRF assignment." "Only TCP and UDP connections can be fast-tracked" and "to maintain connection tracking entries some random packets will still be sent to a slow path." Consequences a fleet console must encode: (1) simple queues and `parent=global` q…


**Versions.** FastTrack exists from RouterOS 6.29 onward and is present in the RouterOS 7 default configuration.


```routeros
/ip/firewall/filter print where action=fasttrack-connection
/ip/firewall/connection print count-only where fasttrack
/ip/firewall/filter disable [find action=fasttrack-connection]
```


**Danger.** Disabling the default FastTrack rule to make queues work moves all forwarding to the slow path. On a low-end device (hEX, hAP) that can cut routed throughput by a large factor and peg the CPU, making the device unmanageable under load.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328227/Packet+Flow+in+RouterOS


### Firewall address lists: dynamic entries and where they live

`/ip/firewall/address-list` properties: `list`, `address` (a single IP, a range `IP-IP`, a CIDR, or a DNS name), `timeout`, `comment`, `disabled`, plus read-only `dynamic` and `creation-time`. Entries are populated dynamically by `action=add-src-to-address-list` / `action=add-dst-to-address-list` with `address-list=` and `address-list-timeout=`. Storage rule that matters for a console: entries with no `timeout` are stored permanently in configuration; entries with a `timeout` live in RAM and are gone after a reboot. So a blocklist built by firewall rules is not durable state and must not be treated as inventory.


**Versions.** Same in RouterOS 6 and 7.


```routeros
/ip/firewall/address-list print detail
/ip/firewall/address-list print count-only where list=blocked
/ip/firewall/address-list print where dynamic
```


**Danger.** A dynamic address list can grow without bound under attack and consume RAM on a small device. Always pair `add-src-to-address-list` with an `address-list-timeout`; never leave it unset on an internet-facing rule.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/130220135/Address-lists


### Queues: simple queues, queue trees and their monitoring counters

`/queue/simple`: `name`, `target`, `dst-address`, `packet-marks`, `parent`, `priority` (1-8), `queue`, `limit-at` (upload/download), `max-limit`, `burst-limit`, `burst-time`, `burst-threshold`, plus the `total-*` variants (`total-queue`, `total-limit-at`, `total-max-limit`, `total-burst-limit`, `total-burst-time`, `total-burst-threshold`). `/queue/tree`: `name`, `parent` (a queue name or an interface), `packet-mark`, `queue`, `priority`, `limit-at`, `max-limit`, `burst-limit`, `burst-time`, `burst-threshold`.


**Versions.** Same menu shape in RouterOS 6 and 7.


```routeros
/queue/simple print stats
/queue/simple/monitor [find name="cust-1"] once
/queue/tree print stats
```


**Danger.** `/queue/simple` matches top-down and a queue with `target=0.0.0.0/0` placed above the specific ones swallows all traffic. Adding a queue at the wrong position silently rate-limits the whole site, including management traffic, to that queue's `max-limit`.


> **Review correction.** RouterOS 7 `/queue/tree` read-only: bytes, packets, dropped, rate, packet-rate, queued-packets, queued-bytes, pcq-queues. `/queue/simple` read-only: the same set as upload/download composites, each with a `total-` scalar (total-bytes, total-packets, total-dropped, total-rate, total-packet-rate, total-queued-packets, total-queued-bytes).


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328088/Queues


### Queue types: PCQ, CAKE and fq-codel

`/queue/type` `kind` values: `pfifo`, `bfifo`, `mq-pfifo`, `sfq`, `pcq`, `red`, `none`, `codel`, `cake`, `fq-codel`. PCQ properties: `pcq-classifier` (dst-address | src-address | dst-port | src-port), `pcq-rate`, `pcq-limit` (KiB, per sub-stream), `pcq-total-limit` (KiB, all sub-streams), `pcq-burst-rate`, `pcq-burst-threshold`, `pcq-burst-time`, `pcq-src-address-mask`, `pcq-dst-address-mask`, `pcq-src-address6-mask`, `pcq-dst-address6-mask`.


**Versions.** MikroTik's Queues documentation marks `cake` and `fq-codel` as available from RouterOS 7.1beta3; they do not exist on RouterOS 6.


```routeros
/queue/type print detail
/queue/type add name=pcq-down kind=pcq pcq-classifier=dst-address pcq-rate=10M
/queue/simple print stats
```


**Danger.** CAKE and fq-codel are CPU-heavy relative to pfifo. Applying CAKE at a high `cake-bandwidth` on a small device can saturate the CPU and cause packet loss that looks like an upstream fault.


> **Review correction.** `cake-flowmode` enum is exactly (flowblind | srchost | dsthost | hosts | flows | dual-srchost | dual-dsthost | triple-isolate). NAT awareness is the separate `cake-nat` bool. Everything else in this entry is CONFIRMED verbatim: the `kind` enum is exactly the ten listed, and all PCQ/fq-codel/CAKE property names check out.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328088/Queues


### WireGuard: config and the four fields that tell you a tunnel is alive

`/interface/wireguard`: `name`, `listen-port` (default 13231), `private-key` (auto-generated if omitted), `mtu` (default 1420), `disabled`, `comment`, `vrf` (routing table for the encrypted UDP), plus read-only `public-key` and `running`. `/interface/wireguard/peers`: `interface`, `public-key`, `endpoint-address`, `endpoint-port`, `allowed-address`, `preshared-key`, `persistent-keepalive` (default 0), `responder`, `name`, `disabled`, and the client-config helpers `client-address`, `client-endpoint`, `client-dns`, `client-keepalive`, `client-listen-port`, `client-allowed-address`.


**Versions.** WireGuard is a RouterOS 7 feature and is listed as a headline item of 7.1 in the 7.1 CHANGELOG: `!) support for WireGuard;`. It does not exist in RouterOS 6 at all — a console must gate the whole menu on major version 7.


```routeros
/interface/wireguard print detail
/interface/wireguard/peers print detail
/interface/wireguard/peers print where last-handshake>3m
```


**Danger.** Changing `listen-port`, `private-key`, or a peer's `allowed-address` on a device reachable only through that tunnel drops the tunnel instantly and, in the `private-key` case, unrecoverably (the far side now has the wrong public key).


> **Review correction.** `ph2-state` enum: spawning | starting | ready-to-send | getspi-sent | getspi-done | msg1-sent | ready-to-establish | commiting | adding-sa | established | expired | no-phase2. Alert only on `expired`/`no-phase2` persisting, and treat the negotiation states as transient.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/69664792/WireGuard


### IPsec: the read-only menus that actually tell you if a tunnel is up

Config menus: `/ip/ipsec/peer` (IKE peer), `/ip/ipsec/profile` (phase 1 parameters), `/ip/ipsec/identity` (auth + peer-specific settings), `/ip/ipsec/proposal` (phase 2 algorithms), `/ip/ipsec/policy` (what traffic is protected), `/ip/ipsec/settings`. Monitoring: `/ip/ipsec/policy` read-only `ph2-state` (`no-phase2` | `expired` | `established`), `ph2-count`, `sa-src-address`, `sa-dst-address`, `active`, `invalid`, with flags `T` template, `D` dynamic, `X` disabled, `I` invalid, `A` active.


**Versions.** The `/ip/ipsec/profile` + `/ip/ipsec/identity` split is the modern layout used from RouterOS 6.43 onward and throughout v7; much older configs used a flat `/ip/ipsec/peer`.


```routeros
/ip/ipsec/active-peers print detail
/ip/ipsec/policy print detail where !template
/ip/ipsec/installed-sa print detail
```


**Danger.** `/ip/ipsec/installed-sa flush` tears down every SA on the device, dropping all IPsec tunnels simultaneously until they renegotiate. It is a legitimate recovery step for a stuck SA but is a multi-site outage if issued blind.


> **Review correction.** `ph2-state` enum: spawning | starting | ready-to-send | getspi-sent | getspi-done | msg1-sent | ready-to-establish | commiting | adding-sa | established | expired | no-phase2. Alert only on `expired`/`no-phase2` persisting, and treat the negotiation states as transient.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/11993097/IPsec


### EoIP and the meaning of the 'running' flag on tunnels

`/interface/eoip` properties: `tunnel-id` ("Unique tunnel identifier, which must match other side of the tunnel"), `remote-address`, `local-address`, `keepalive` (format `KeepaliveInterval,KeepaliveRetries`, default `10s,10` — "Sets the time interval in which the tunnel running flag will remain even if remote end goes down"), `dscp` (default inherit), `dont-fragment`, `allow-fast-path` (default yes; "Must be disabled if IPsec tunneling is used"), `ipsec-secret` (adds a dynamic IPsec peer with that PSK), `mac-address` (auto-assigned from the IANA range 00:00:5E:80:00:00 - 00:00:5E:FF:FF:FF).


**Versions.** Same in RouterOS 6 and 7.


```routeros
/interface/eoip print detail
/interface/eoip print where !running
/interface/eoip set eoip-tunnel1 keepalive=5s,3
```


**Danger.** Setting `ipsec-secret` without also setting `allow-fast-path=no` leaves fast path on, which the documentation says must be disabled with IPsec — the result is traffic that bypasses encryption or is silently dropped.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/24805521/EoIP


### OSPF in RouterOS 7: the menus are not the v6 menus

RouterOS 7 menus: `/routing/ospf/instance` (`name`, `version` (2 or 3), `router-id`, `vrf`, `redistribute`, `originate-default` (never | always | if-installed), `in-filter-chain`, `out-filter-chain`, `out-filter-select`), `/routing/ospf/area` (`name`, `area-id` (0.0.0.0 = backbone), `instance`, `type` (default | stub | nssa), `no-summaries`), `/routing/ospf/interface-template` (`interfaces`, `networks`, `area`, `type` (broadcast | ptmp | nbma | point-to-point | virtual-link), `cost`, `priority`, `passive`, `auth`, `auth-id`, `auth-key`, `hello-interval` (default 10s), `dead-interval` (default 40s)), plus read-onl…


**Versions.** RouterOS 7 shipped a "completely new OSPF implementation with performance improvements" (7.1 CHANGELOG). The v6 menus `/routing/ospf/network` and the v6 instance model do not exist in v7 — `interface-template` replaces `network`.


```routeros
/routing/ospf/neighbor print detail
/routing/ospf/interface print detail
/routing/ospf/instance print detail
```


**Danger.** Changing `router-id` on a live OSPF speaker tears down every adjacency on that router and re-floods the LSDB across the area. On a backbone router that is a network-wide reconvergence.


> **Review correction.** RouterOS 7 `/routing/ospf/neighbor` read-only fields are: instance, area, interface, address, priority, router-id, `dr`, `bdr`, state, state-changes, ls-retransmits, ls-requests, db-summaries, adjacency, timeout. Flags: V virtual, D dynamic. The entry also omits `interface`, `ls-retransmits`, `ls-requests`, `db-summaries`.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/9863229/OSPF


### BGP in RouterOS 7: the rewrite, and the 7.20 instance menu

RouterOS 7 menus: `/routing/bgp/connection` (`name`, `remote.address`, `remote.as`, `local.role` (ebgp/ibgp), `local.address`, `router-id`, `address-families`, `multihop`, `nexthop-choice`, `templates`, `vrf`, `hold-time`, `keepalive-time`, `input.filter`, `output.filter`, `routing-table`), `/routing/bgp/template`, read-only `/routing/bgp/session`, `/routing/bgp/advertisements`, `/routing/bgp/vpls`, and from 7.20 `/routing/bgp/instance`.


**Versions.** RouterOS 7.1: "completely new BGP implementation with performance improvements". The v6 menus `/routing/bgp/instance` and `/routing/bgp/peer` are gone in v7 — `connection` + `template` replace them. 7.4 moved `/interface bgp vpls` to `/routing bgp vpls`.


```routeros
/routing/bgp/session print detail
/routing/bgp/session print where !established
/routing/bgp/connection print detail
```


**Danger.** Editing a `/routing/bgp/connection` resets that session. Editing a `/routing/bgp/template` resets every connection referencing it — a template edit on a route reflector drops all clients at once.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328220/BGP


### Netwatch: the 7.4 rewrite is what makes it useful for a console

`/tool/netwatch` `type` values: `simple` (default, backwards-compatible), `icmp`, `tcp-conn`, `http-get`, `https-get`, `dns`. Common properties: `host`, `type`, `interval` (10s), `timeout` (3s), `src-address`, `start-delay` (3s), `startup-delay` (5m), `up-script`, `down-script`, `test-script`, `ignore-initial-up`, `ignore-initial-down`. ICMP-type: `packet-interval` (50ms), `packet-count` (10), `packet-size` (54), `thr-max` (1s), `thr-avg` (100ms), `thr-stdev` (250ms), `thr-jitter` (1s), `thr-loss-percent` (85%), `thr-loss-count`, `ttl` (255), `accept-icmp-time-exceeded`, `early-failure-detection`, `early-success-…


**Versions.** RouterOS 6 and RouterOS 7.0-7.3 only have the simple ICMP probe with `host`, `interval`, `timeout`, `up-script`, `down-script` — none of the `type`, threshold or statistic fields exist.


```routeros
/tool/netwatch print detail
/tool/netwatch print where status=down
/tool/netwatch add host=1.1.1.1 type=icmp interval=30s packet-count=10 thr-loss-percent=20
```


**Danger.** `up-script` and `down-script` execute arbitrary RouterOS script with full privileges on every state transition. A netwatch entry pushed by a console is a remote-code-execution primitive on the whole fleet — treat script bodies as privileged config, never templ…


> **Review correction.** The property is `http-codes`, a multi range type `range [100 .. 599]`, default 100-299. Correct syntax: `/tool/netwatch add host=x type=http-get http-codes=200-299`. Also in the same entry: `packet-size` default is **50**, not 54.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8323208/Netwatch


### Diagnostic tools: ping and traceroute

`/tool/ping` (also reachable as `/ping`): `address`, `src-address`, `count`, `interval`, `size`, `ttl`, `arp-ping`, `nd-ping`, `dscp`, `interface`, `routing-table`, `do-not-fragment`. Per-reply output columns: `SEQ`, `HOST`, `SIZE`, `TTL`, `TIME`, `STATUS`; summary fields: `sent`, `received`, `packet-loss`, `min-rtt`, `avg-rtt`, `max-rtt`. `do-not-fragment` with a sweep of `size` is the correct way to find path MTU from the device. `/tool/traceroute` traces the path using TTL expiry and ICMP time-exceeded replies.


**Versions.** `routing-table` as a ping parameter is RouterOS 7 (v6 used `routing-mark`).


```routeros
/ping 1.1.1.1 count=5 interval=200ms
/ping 1.1.1.1 count=1 size=1472 do-not-fragment
/tool/traceroute 1.1.1.1 count=1
```


**Danger.** `/ping` without `count=` runs until interrupted and never returns over an API or non-interactive SSH call. Always set `count=`. The same applies to `/tool/traceroute`.


> **Review correction.** Prefer `vrf` on current RouterOS 7 and feature-detect rather than hardcoding either name; flag the two MikroTik pages as inconsistent. Everything else is CONFIRMED against the CLI reference: address, src-address, count, interval, size, ttl, arp-ping, nd-ping, dscp, do-not-fragment, interface; per-reply seq/host/size/ttl/time/status; summa…


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/ping/


### Diagnostic tools: Torch and its blind spots

`/tool/torch` shows live per-flow traffic on an interface, filtered by `interface`, `src-address`, `dst-address` (IPv4 or IPv6), `port`, and classified by MAC protocol, MAC address, VLAN ID and DSCP; it displays the selected protocols with TX/RX data rate per entry. Two documented blind spots a console must not paper over: "Traffic captured by Torch is seen before it is filtered by the Firewall" — so a flow appearing in Torch does not mean it was accepted; and unicast wireless client-to-client traffic and hardware-offloaded bridge packets are not visible to Torch at all, because they never reach the CPU.


**Versions.** Present in RouterOS 6 and 7.


```routeros
/tool/torch interface=ether1 src-address=0.0.0.0/0 duration=10
/tool/torch interface=ether1 port=any ip-protocol=any duration=5
```


**Danger.** Torch pulls every matching packet to the CPU for inspection. On a busy uplink of a low-end router it will spike CPU and can affect forwarding. Always bound it with `duration=` and a narrow filter, never run it unfiltered on a gigabit uplink.


> **Review correction.** Remove `duration=` from both commands and from the danger note. Torch is an unbounded interactive streaming command with no self-limiting parameter; over API or one-shot SSH it never returns. Either avoid it in a collector entirely, or wrap it in a script with `:delay` plus an explicit stop.


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/torch/


### Diagnostic tools: packet sniffer

`/tool/sniffer` settings: `filter-interface` (default all), `filter-direction` (rx | tx | any), `filter-ip-address` / `filter-src-ip-address` / `filter-dst-ip-address` (up to 16 entries each), `filter-mac-address` / `filter-src-mac-address` / `filter-dst-mac-address`, `filter-port` / `filter-src-port` / `filter-dst-port`, `filter-ip-protocol`, `filter-mac-protocol`, `filter-vlan` (0-4095), `filter-size`, `filter-cpu`, `filter-operator-between-entries` (and | or, default or), `filter-stream` (default yes), `file-name`, `file-limit` (default 1000KiB), `memory-limit` (default 100KiB), `memory-scroll` (default yes),…


**Versions.** Present in RouterOS 6 and 7.


```routeros
/tool/sniffer set filter-interface=ether1 filter-ip-protocol=tcp file-name=cap.pcap file-limit=500
/tool/sniffer start
/tool/sniffer stop
```


**Danger.** An unfiltered sniffer with a `file-limit` at or above free RAM will exhaust memory on a small device — MikroTik states the file-size limit should not exceed available free memory. A sniffer left running is also a privacy exposure: captures contain payloads.


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/packet-sniffer/


### Diagnostic tools: bandwidth test is a production hazard

`/tool/bandwidth-server`: `enabled` (default yes), `authenticate` (default yes), `allocate-udp-ports-from` (1000..64000, default 2000), `max-sessions` (1..1000, default 100). `/tool/bandwidth-test`: `address`, `direction` (both | receive | transmit, default receive), `duration`, `protocol` (udp | tcp, default udp), `local-udp-tx-size` / `remote-udp-tx-size` (28..64000), `user`, `password`.


**Versions.** Present in RouterOS 6 and 7.


```routeros
/tool/bandwidth-server print
/tool/bandwidth-test address=192.0.2.2 duration=10s direction=both user=btest password=***
```


**Danger.** This is the most destructive tool in the list. It deliberately saturates the link and the CPU; on a customer uplink it is an outage for everyone behind it, and on a low-end device it can make the router itself unresponsive so the test cannot even be stopped.


> **Review correction.** Remove that couldNotVerify item. Emit `local-tx-speed`/`remote-tx-speed` as the throttle whenever running a test at all, plus `connection-count` and `random-data` as needed. Separately, the claim that MikroTik "advises...


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/bandwidth-test/


### Safe Mode: the only real rollback, and why it does not protect API calls

Safe Mode is entered in the console with [Ctrl]+[X] (or F4). While a session is in safe mode, all configuration changes made during it — including changes made from other login sessions — are automatically undone if the safe mode session terminates abnormally; if the connection is cut, the undo happens after the TCP timeout (about 9 minutes). Exiting with [Ctrl]+[D] also undoes the safe mode changes, while `/quit` keeps them. Pressing [Ctrl]+[X] again empties the safe mode action list (commits).


**Versions.** Present in RouterOS 6 and 7; the 100-action history limit and the ~9 minute TCP-timeout undo are documented behaviour in both.


```routeros
/export file=pre-change
/system/backup save name=pre-change
/system/scheduler add name=revert start-time=startup interval=5m on-event="/system/reboot"
```


**Danger.** Relying on Safe Mode from an automated agent is a false sense of safety — it does not apply to non-interactive API or single-command SSH execution.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/8978498/Console


### Could not verify

The exact RouterOS release that introduced the read-only `total` / `used` / `available` statistics fields on `/ip/pool`. They are documented in the current CLI reference (https://manual.mikrotik.com/docs/cli-reference/ip/pool/) but no MikroTik page or CHANGELOG line I could reach names the release. A console must feature-detect and fall back to counting `/ip/pool/used` rows. The exact beta/RC that introduced WireGuard. The 7.1 CHANGELOG lists `!) support for WireGuard;` as a 7.1 headline feature; the widely repeated '7.1beta2' figure is not confirmed by any MikroTik page I could fetch.
