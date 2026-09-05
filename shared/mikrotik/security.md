# MikroTik RouterOS — Security: hardening, CVEs, incidents and IoCs

Part of the `mikrotik-routeros` skill. Every claim below was researched against
MikroTik's own documentation and changelogs, then independently fact-checked; where
the check found an error the corrected form is inline as **Review correction** and
the correction wins over the paragraph above it.


### Canonical sources and the docs-site migration (read this first)

There are now TWO MikroTik doc sites and the old one is frozen. help.mikrotik.com/docs/spaces/ROS/... displays the banner 'This documentation site has been frozen, no further edits will be made here!' and points to manual.mikrotik.com. The current canonical manual is https://manual.mikrotik.com/docs/ (Docusaurus, versioned - 'current' and '7.24' selectors). Security advisories live at https://mikrotik.com/supportsec, which is a Livewire SPA that only renders ONE year at a time; the year is a URL query parameter, so https://mikrotik.com/supportsec?year=2018 etc.


**Versions.** help.mikrotik.com ROS space last updated Jan 06 2025 and is frozen; manual.mikrotik.com is current as of RouterOS 7.24/7.25beta (Sept 2026).


```routeros
/system/resource/print
/system/package/print
/system/routerboard/print
```


**Danger.** None. But an agent that reads only the frozen help.mikrotik.com pages will emit stale property names (e.g. allow-none-crypto, always-allow-password-login) that no longer exist on RouterOS >= 7.17/7.21.


Source: https://help.mikrotik.com/docs/spaces/ROS/pages/328353/Securing+your+router ; https://manual.mikrotik.com/docs/ ; https://mikrotik…


### Securing your router - RouterOS version and update channel

MikroTik's first hardening item is to upgrade. Release chains are Long term (rare, critical fixes only), Stable (every few months), Testing (every few weeks, not for production), Development. The 'Check for Updates' feature connects FROM THE ROUTER to the MikroTik download server over HTTPS - the router itself needs egress. Upgrade server is upgrade.mikrotik.com and MikroTik documents its address as 159.148.147.251 for troubleshooting.


**Versions.** v6 -> v7 intermediate hop is v7.12.1. RouterOS cannot be upgraded over a serial cable (only RouterBOOT can).


```routeros
/system/package/update/set channel=stable mode=https ip-version=auto check-certificate=yes
/system/package/update/check-for-updates
/system/package/update/print
```


**Danger.** An unattended /system/package/update/install reboots the device. On a remote site with no out-of-band access, a bad upgrade plus a bootloader mismatch is a truck roll.


> **Review correction.** State the CLI value as 'ros' wherever a mode is named as something an agent might emit, and keep 'ROSE' only as the human label for the device class. Also worth adding: the danger note on this entry correctly says device-mode changes need physical confirmation, and that is confirmed - the change is not applied until a button press or a po…


Source: https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/upgrade ; https://manual.mikrotik.com/docs/getting-start…


### Securing your router - replace the admin account

MikroTik's guidance is to create a new full-rights user and DISABLE (not delete) admin. RouterOS enforces that at least one full-access user exists; if it is the only one it cannot be removed. Modern devices ship with a unique per-device factory password printed on the serial-number sticker, the box, and the Quick Guide - it exists only on physical media and is not stored in any online system; distributors hold a database keyed by serial number. Older models shipped as username 'admin' with an empty password.


**Versions.** Same on v6 and v7. Slash-path form shown is v7 manual style.


```routeros
/user/add name=myname password=mypassword group=full
/user/disable admin
/user/print detail
```


**Danger.** HIGH LOCKOUT RISK. Disabling admin before you have PROVEN the new account can log in over the same transport you are using will lock you out permanently on a remote device.


> **Review correction.** State the CLI value as 'ros' wherever a mode is named as something an agent might emit, and keep 'ROSE' only as the human label for the device class. Also worth adding: the danger note on this entry correctly says device-mode changes need physical confirmation, and that is confirmed - the change is not applied until a button press or a po…


Source: https://manual.mikrotik.com/docs/getting-started/securing-your-router ; https://manual.mikrotik.com/docs/authentication-authorizat…


### Securing your router - password policy and complexity enforcement

MikroTik's stated minimum: at least 12 characters; mixed digits, symbols, upper and lower case; not a dictionary word or combination of them. Quote characters in a password must be escaped in the CLI. RouterOS can enforce this centrally via /user/settings with minimum-password-length (integer 0..4294967295) and minimum-categories (integer 0..4, categories being uppercase, lowercase, digit, symbol). Individual passwords can be force-expired with the expire-password action, which prompts the user to change it at next login.


**Versions.** /user/settings minimum-password-length and minimum-categories are documented in the current (v7) manual.


```routeros
/user/set myname password="!={Ba3N!40TуX+GvKBz?jTLIUcx/,"
/user/settings/set minimum-password-length=12 minimum-categories=4
/user/settings/print
```


**Danger.** Setting minimum-categories=4 does not retro-invalidate existing weak passwords, so it gives false assurance unless you also expire them. Escaping errors in a password string set over an automated channel produce a password you cannot reproduce - lockout.


> **Review correction.** State the CLI value as 'ros' wherever a mode is named as something an agent might emit, and keep 'ROSE' only as the human label for the device class. Also worth adding: the danger note on this entry correctly says device-mode changes need physical confirmation, and that is confirmed - the change is not applied until a button press or a po…


Source: https://manual.mikrotik.com/docs/getting-started/securing-your-router ; https://manual.mikrotik.com/docs/authentication-authorizat…


### Securing your router - the WAN management ruleset MikroTik publishes (exact rules, exact order)

MikroTik publishes this ONLY as a last-resort pattern for cases where direct internet-facing management is unavoidable (ISP-managed kit, sites with no VPN gateway) and explicitly says not to apply it otherwise. It allows ICMP, WinBox (8291) and SSH (22) from ether1 and drops everything else inbound. The published order is: accept established/related/untracked; drop invalid; accept ICMP; accept tcp/8291; accept tcp/22; drop everything from that interface. MikroTik's own recommended alternative is a VPN (WireGuard) so management never touches the public internet at all.


**Versions.** Published on the current v7 manual. Same semantics apply to v6 with space-separated paths.


```routeros
/ip/firewall/filter
add chain=input action=accept connection-state=established,related,untracked comment="accept established,related,untracked"
add chain=input action=drop connection-state=invalid comment="drop invalid"
```


**Danger.** EXTREME LOCKOUT RISK, and MikroTik flags it itself: 'If the public interface is PPPoE, LTE, or another interface type, in-interface should be set accordingly.


> **Review correction.** Reword to 'MikroTik's documentation example shows only www-ssl disabled; actual shipped state depends on the device's default configuration, so always read /ip/service/print where !dynamic on the target rather than assuming.' The command to enumerate the applied defconf is /system/default-configuration/print, which the knowledge base does…


Source: https://manual.mikrotik.com/docs/getting-started/securing-your-router


### Securing your router - MAC-Telnet, MAC-WinBox and MAC-Ping (the single highest-lockout hardening ite…

RouterOS exposes layer-2 management that works with no IP address at all: MAC-Telnet, MAC-WinBox and MAC-Ping. MikroTik says these should be shut down on production networks. MAC-Telnet only works between two MikroTik RouterOS devices. Sessions are visible with /tool/mac-server/sessions/print. The scoping mechanism is an interface list, not a boolean: set allowed-interface-list to a trusted list name, or to none to disable entirely. The 2025 CVE-2024-54772 advisory recommends the same control as a WinBox mitigation: restrict MAC-WinBox to a trusted interface list.


**Versions.** Since RouterOS v7.22 the mac-telnet CLIENT accepts an interface property (/tool/mac-telnet 00:11:22:33:44:55 interface=ether1) to stop it broadcasting on every interface.


```routeros
/tool/mac-server/set allowed-interface-list=none
/tool/mac-server/mac-winbox/set allowed-interface-list=none
/tool/mac-server/ping/set enabled=no
```


**Danger.** CRITICAL. MAC-WinBox is the ONLY recovery path into a device whose IP configuration you have just broken, short of physical console or Netinstall. Disabling it removes the safety net.


> **Review correction.** State the CLI value as 'ros' wherever a mode is named as something an agent might emit, and keep 'ROSE' only as the human label for the device class. Also worth adding: the danger note on this entry correctly says device-mode changes need physical confirmation, and that is confirmed - the change is not applied until a button press or a po…


Source: https://manual.mikrotik.com/docs/getting-started/securing-your-router ; https://manual.mikrotik.com/docs/management-tools/mac-serv…


### Securing your router - Neighbor discovery (MNDP/CDP/LLDP) and the discover port

MikroTik Neighbor Discovery Protocol advertises the device to other MikroTik routers. MikroTik's hardening step is to disable it on all interfaces by setting the interface list to none. The discovery service runs on UDP/5678 (RouterOS lists '5678/udp Mikrotik Neighbor Discovery Protocol' and shows a dynamic /ip/service entry named 'discover' on port 5678). Scanners fingerprint MikroTik brand devices with this and with the WinBox port. A safer middle ground than none is a trusted-LAN interface list.


**Versions.** Property is discover-interface-list on both v6 and v7. LLDP settings are under /ip/neighbor/lldp in v7.


```routeros
/ip/neighbor/discovery-settings/set discover-interface-list=none
/ip/neighbor/discovery-settings/print
/ip/neighbor/print
```


**Danger.** Low-to-moderate. Disabling discovery removes the device from WinBox's Neighbors tab and from RoMON/CAPsMAN neighbour views. If your management tooling or a CAPsMAN/controller relationship relies on neighbour discovery, this breaks it.


> **Review correction.** State the CLI value as 'ros' wherever a mode is named as something an agent might emit, and keep 'ROSE' only as the human label for the device class. Also worth adding: the danger note on this entry correctly says device-mode changes need physical confirmation, and that is confirmed - the change is not applied until a button press or a po…


Source: https://manual.mikrotik.com/docs/getting-started/securing-your-router ; https://manual.mikrotik.com/docs/system-information-and-ut…


### Securing your router - bandwidth server (TCP/UDP 2000)

The bandwidth server answers throughput tests from other MikroTik routers on TCP/UDP port 2000 and MikroTik says to disable it in production. It is a documented DDoS/resource-abuse surface: Qrator's Meris analysis found '90-95% have Bandwidth Test on port 2000' among the attacking devices. RouterOS shows it as a dynamic /ip/service entry named 'btest' on port 2000. It is separately gated by device-mode: bandwidth-test is No in home and basic modes, Yes in advanced and ROSE.


**Versions.** device-mode gating of bandwidth-test covers /tool/bandwidth-test, /tool/bandwidth-server and /tool/speed-test.


```routeros
/tool/bandwidth-server/set enabled=no
/tool/bandwidth-server/print
/system/device-mode/update bandwidth-test=no
```


**Danger.** No lockout risk to management. Note the device-mode route (bandwidth-test=no) REQUIRES physical presence to confirm - do not issue it on a remote device unless someone is standing at it.


> **Review correction.** State the CLI value as 'ros' wherever a mode is named as something an agent might emit, and keep 'ROSE' only as the human label for the device class. Also worth adding: the danger note on this entry correctly says device-mode changes need physical confirmation, and that is confirmed - the change is not applied until a button press or a po…


Source: https://manual.mikrotik.com/docs/getting-started/securing-your-router ; https://manual.mikrotik.com/docs/system-information-and-ut…


### Securing your router - DNS cache / open resolver

allow-remote-requests defaults to no, but MikroTik's factory default configurations for home/AP-router and CPE profiles enable DNS for the LAN, so a shipped device commonly has it on. Left reachable from a WAN it is an open resolver and a reflection/amplification source. MikroTik's own note: 'When the DNS server allow-remote-requests is used make sure that you limit access to your server over TCP and UDP protocol port 53 only for known hosts.' The DNS resolver appears as dynamic /ip/service entries 'resolver' on 53/tcp and 53/udp.


**Versions.** Default allow-remote-requests=no documented in the current v7 manual property table. Same property name on v6.


```routeros
/ip/dns/set allow-remote-requests=no
/ip/dns/print
/ip/dns/static/print detail
```


**Danger.** MODERATE OUTAGE RISK, not lockout. If LAN clients were handed the router's own address as their DNS server by its DHCP server, setting allow-remote-requests=no breaks name resolution for the entire LAN instantly.


> **Review correction.** State the CLI value as 'ros' wherever a mode is named as something an agent might emit, and keep 'ROSE' only as the human label for the device class. Also worth adding: the danger note on this entry correctly says device-mode changes need physical confirmation, and that is confirmed - the change is not applied until a button press or a po…


Source: https://manual.mikrotik.com/docs/network-management/dns ; https://manual.mikrotik.com/docs/getting-started/securing-your-router ;…


### Securing your router - caching proxy, SOCKS, UPnP and MikroTik Cloud

MikroTik names exactly four 'additional services' to disable in production: caching proxy, SOCKS, UPnP, and MikroTik Cloud services. The published commands differ between the frozen and current pages for /ip/cloud: the frozen ROS page says ddns-enabled=no, the current manual says ddns-enabled=auto. Both set update-time=no. SOCKS is the single most important of these for incident response - it is the service the 2018/2021 MikroTik botnets turned on (Netlab 360 confirmed 239,000 devices with SOCKS enabled maliciously, mostly on TCP/4153; MikroTik's own Meris advisory says 'IP -> Socks proxy.


**Versions.** Current v7 manual: /ip/cloud/set ddns-enabled=auto update-time=no. Frozen v6/v7 page: /ip cloud set ddns-enabled=no update-time=no. device-mode gates socks (No in home and basic) and proxy (No in home and basic).


```routeros
/ip/proxy/set enabled=no
/ip/socks/set enabled=no
/ip/upnp/set enabled=no
```


**Danger.** Disabling /ip/cloud kills the <serial>.sn.mynetname.net DDNS name and the Back To Home VPN. If your ONLY route to a dynamic-IP device is that DDNS name, disabling it is an immediate, unrecoverable remote lockout.


> **Review correction.** State the CLI value as 'ros' wherever a mode is named as something an agent might emit, and keep 'ROSE' only as the human label for the device class. Also worth adding: the danger note on this entry correctly says device-mode changes need physical confirmation, and that is confirmed - the change is not applied until a button press or a po…


Source: https://manual.mikrotik.com/docs/getting-started/securing-your-router ; https://help.mikrotik.com/docs/spaces/ROS/pages/328353/Sec…


### Securing your router - management services (/ip/service): which are on by default and how to lock th…

MikroTik's documented /ip/service inventory: telnet (23), ftp (21), www (80), ssh (22), www-ssl (443), api (8728), winbox (8291), api-ssl (8729), reverse-proxy. In MikroTik's own published print output, only www-ssl carries the X (disabled) flag - ftp, ssh, telnet, www, winbox, api and api-ssl are all listed enabled. Services cannot be added, only modified. Per-service properties: address (source prefixes), certificate (www-ssl / api-ssl only), max-sessions (1..1000, default 20), port, tls-version (any | only-1.2), vrf.


**Versions.** tls-version=only-1.2 and the /ip/service/webserver sub-menu are v7. The v7 CLI reference also shows an available-from property alongside address on /ip/service.


```routeros
/ip/service/disable telnet,ftp,www,api
/ip/service/set ssh port=2200
/ip/service/set winbox address=192.168.88.0/24
```


**Danger.** SEVERE LOCKOUT RISK, several ways. (1) Disabling the service you are currently connected over (ssh, www, api) drops you instantly. (2) Changing ssh port=2200 while your firewall only accepts tcp/22 locks you out - change the firewall first, verify, then move t…


> **Review correction.** Reword to 'MikroTik's documentation example shows only www-ssl disabled; actual shipped state depends on the device's default configuration, so always read /ip/service/print where !dynamic on the target rather than assuming.' The command to enumerate the applied defconf is /system/default-configuration/print, which the knowledge base does…


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/services ; https://manual.mikrotik.com/docs/cli-reference/ip/ser…


### Securing your router - SSH crypto (strong-crypto, ciphers, key-exchange) with exact version gates

/ip/ssh/set strong-crypto=yes is MikroTik's documented hardening switch. What it actually changes, per the CLI reference: 'use 256 and 192 bit encryption instead of 128 bits, disable null encryption, use sha256 for hashing instead of sha1, disable md5, use 2048bit prime for Diffie-Hellman exchange instead of 1024bit.' The prose on the Securing page adds that it enables aes-128-ctr and disallows hmac-sha1 and sha1-based groups.


**Versions.** On RouterOS < 7.17 use allow-none-crypto, NOT ciphers. On RouterOS < 7.21 use always-allow-password-login, NOT password-authentication. Writing the new names to an older box fails with an unknown-parameter error; writing the old names to 7.21+ also fails.


```routeros
/ip/ssh/set strong-crypto=yes
/ip/ssh/print
/ip/ssh/set host-key-type=ed25519
```


**Danger.** HIGH. (1) /ip/ssh/regenerate-host-key changes the host key and every client with a pinned known_hosts entry refuses to connect - an automation fleet will fail closed.


> **Review correction.** State the CLI value as 'ros' wherever a mode is named as something an agent might emit, and keep 'ROSE' only as the human label for the device class. Also worth adding: the danger note on this entry correctly says device-mode changes need physical confirmation, and that is confirmed - the change is not applied until a button press or a po…


Source: https://manual.mikrotik.com/docs/cli-reference/ip/ssh/ ; https://manual.mikrotik.com/docs/getting-started/securing-your-router ; h…


### Securing your router - unused interfaces and the LCD

MikroTik recommends disabling every unused Ethernet/SFP interface to reduce unauthorized physical access. Some RouterBOARDs have an LCD module; set a PIN or disable it. LCD PIN example uses pin-number=3659 hide-pin-number=yes.


**Versions.** Same on v6 and v7; v6 form is /interface set X disabled=yes and /lcd set enabled=no.


```routeros
/interface/print
/interface/set X disabled=yes
/lcd/pin/set pin-number=3659 hide-pin-number=yes
```


**Danger.** HIGH LOCKOUT RISK if you disable interfaces by index. /interface/print indices shift; disabling the wrong index kills your uplink or your bridge port.


> **Review correction.** State the CLI value as 'ros' wherever a mode is named as something an agent might emit, and keep 'ROSE' only as the human label for the device class. Also worth adding: the danger note on this entry correctly says device-mode changes need physical confirmation, and that is confirmed - the change is not applied until a button press or a po…


Source: https://manual.mikrotik.com/docs/getting-started/securing-your-router


### MikroTik's recommended input chain - IPv4, exact rules in exact order (defconf)

MikroTik's published advanced firewall puts most filtering in the RAW table and keeps the filter INPUT chain minimal. The published IPv4 input chain, in order, is: (1) accept protocol=icmp with comment 'defconf: accept ICMP after RAW'; (2) accept connection-state=established,related,untracked; (3) drop in-interface-list=!LAN. Note the ICMP accept is FIRST in this ruleset, because RAW has already dropped bad ICMP. It depends on two interface lists, WAN and LAN, which MikroTik creates with comment=defconf and populates with bridge->LAN and ether1->WAN.


**Versions.** Published on the current v7 manual. The same defconf comments are what MikroTik's factory default configurations use.


```routeros
/interface/list
  add comment=defconf name=WAN
  add comment=defconf name=LAN
```


**Danger.** EXTREME. The final rule drops every input packet that did not arrive on a LAN-list interface. If the LAN interface list is empty, or does not contain the interface your management session arrives on, you are cut off the moment that rule is added.


Source: https://manual.mikrotik.com/docs/firewall-and-quality-of-service/user-guides/building-advanced-firewall


### MikroTik's recommended input chain - IPv6, exact rules in exact order (defconf)

The IPv6 input chain is longer than IPv4 because RFC-recommended traffic must be admitted explicitly. Published order: accept icmpv6; accept established,related,untracked; accept UDP dst-port=33434-33534 (UDP traceroute); accept udp dst-port=546 src-address=fe80::/10 (DHCPv6-client prefix delegation); accept udp dst-port=500,4500 (IKE); accept protocol=ipsec-ah; accept protocol=ipsec-esp; drop in-interface-list=!LAN. MikroTik warns that with a DHCPv6 relay the source address may not be link-local, in which case the src-address=fe80::/10 constraint on the DHCPv6 rule must be removed or set to the relay address.


**Versions.** CVE-2023-47310 (default-config IPv6 firewall bypass for UDP) fixed in RouterOS 6.49.13, 7.14 or later.


```routeros
/ipv6/firewall/filter
add action=accept chain=input comment="defconf: accept ICMPv6 after RAW" protocol=icmpv6
add action=accept chain=input comment="defconf: accept established,related,untracked" connection-state=established,related,untracked
```


**Danger.** EXTREME if you manage the device over IPv6. Dropping ICMPv6 or the neighbour-discovery path breaks IPv6 outright (this is why icmpv6 is accepted wholesale here and filtered in RAW instead).


Source: https://manual.mikrotik.com/docs/firewall-and-quality-of-service/user-guides/building-advanced-firewall ; https://mikrotik.com/sup…


### MikroTik's recommended forward chain - IPv4 and IPv6, with the FastTrack/IPsec trap

IPv4 forward chain order as published: accept ipsec-policy=in,ipsec (DISABLED by default); fasttrack-connection for established,related; accept established,related,untracked; drop invalid; drop connection-nat-state=!dstnat connection-state=new in-interface-list=WAN; drop src-address-list=no_forward_ipv4; drop dst-address-list=no_forward_ipv4.


**Versions.** Published on the current v7 manual as the defconf ruleset.


```routeros
/ip/firewall/filter
  add action=accept chain=forward comment="defconf: accept all that matches IPSec policy" ipsec-policy=in,ipsec disabled=yes
  add action=fasttrack-connection chain=forward comment="defconf: fasttrack" connection-state=established,related
```


**Danger.** TRANSIT OUTAGE, not lockout (these are forward-chain rules and do not touch your management session). Two specific traps: (1) enabling fasttrack-connection on a router with IPsec tunnels and leaving the ipsec-policy accept rule disabled silently breaks the tun…


Source: https://manual.mikrotik.com/docs/firewall-and-quality-of-service/user-guides/building-advanced-firewall


### MikroTik's RAW filtering ruleset - IPv4 (bogons, bad TCP flags, ICMP chain)

MikroTik does the bulk of filtering in /ip/firewall/raw prerouting, before connection tracking, which is why it is cheap. Four address lists: bad_ipv4 (127.0.0.0/8, 192.0.0.0/24, 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, 240.0.0.0/4); not_global_ipv4 (0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/29, 192.168.0.0/16, 198.18.0.0/15, 255.255.255.255/32); bad_src_ipv4 (224.0.0.0/4, 255.255.255.255/32); bad_dst_ipv4 (0.0.0.0/8, 224.0.0.0/4).


**Versions.** /ip/firewall/raw exists in RouterOS 6.36+ and v7. The rule set as published is the current v7 defconf.


```routeros
/ip/firewall/raw
add action=accept chain=prerouting comment="defconf: enable for transparent firewall" disabled=yes
add action=accept chain=prerouting comment="defconf: accept DHCP discover" dst-address=255.255.255.255 dst-port=67 in-interface-list=LAN protocol=udp src-address=0.0.0.0 src-port=68
```


**Danger.** EXTREME, and worse than the filter chain because RAW runs before connection tracking so 'established' does not save you. Two rules are hardcoded to the factory LAN subnet: 'drop local if not from default IP range ...


Source: https://manual.mikrotik.com/docs/firewall-and-quality-of-service/user-guides/building-advanced-firewall


### MikroTik's RAW filtering ruleset - IPv6 (bogons and the RFC4890 icmp6 chain)

IPv6 RAW address lists: bad_ipv6 (::1/128, ::ffff:0:0/96, 2001::/23, 2001:db8::/32, 2001:10::/28, ::/96); not_global_ipv6 (100::/64, 2001::/32, 2001:2::/48, fc00::/7); bad_dst_ipv6 (::/128); bad_src_ipv6 (::/128, ff00::/8). The RAW chain begins with an RFC4291 sec 2.7.1 exception for DAD neighbour solicitations (src-address=::/128 dst-address=ff02:0:0:0:0:1:ff00::/104 icmp-options=135), then the bogon drops, then a jump to an icmp6 chain, then accept ff02::/16 local multicast, drop other ff00::/8, accept from WAN and LAN, drop the rest.


**Versions.** Current v7 manual defconf.


```routeros
/ipv6/firewall/raw
add action=accept chain=prerouting comment="defconf: enable for transparent firewall" disabled=yes
add action=accept chain=prerouting comment="defconf: RFC4291, section 2.7.1" src-address=::/128 dst-address=ff02:0:0:0:0:1:ff00::/104 icmp-options=135 protocol=icmpv6
```


**Danger.** EXTREME on any IPv6-managed device, and it fails in a delayed, confusing way. The ND accepts are constrained to in-interface-list=LAN, so on a WAN-side or non-LAN-listed interface neighbour discovery dies and IPv6 connectivity drops seconds to minutes later wh…


Source: https://manual.mikrotik.com/docs/firewall-and-quality-of-service/user-guides/building-advanced-firewall


### MikroTik's published brute-force prevention chain (and how it locks YOU out)

MikroTik's SSH brute-force example builds a 4-stage escalating address list. Note the rule ORDER on the page is written blacklist-first then third/second/first attempt then the accept - because RouterOS evaluates top-down, the blacklist promotion rule must sit above the rules that create the lower-tier lists so a source is promoted before it is re-added at tier 1. Timeouts: connection1=5m, connection2=15m, connection3=1h, bruteforce_blacklist=1d. MikroTik's own arithmetic: with 1-minute timeouts an attacker gets 9 guesses a minute; with these values the maximum is 3 guesses per 5 minutes.


**Versions.** Same technique on v6 and v7. The 2025 CVE-2024-54772 advisory recommends this page plus port knocking as WinBox mitigations for devices that cannot be updated.


```routeros
/ip/firewall/filter/add action=add-src-to-address-list address-list=connection1 address-list-timeout=5m chain=input comment="First attempt" connection-state=new dst-port=22 protocol=tcp
/ip/firewall/filter/add action=accept chain=input dst-port=22 protocol=tcp src-address-list=!bruteforce_blacklist
/ip/firewall/address-list/print where list=bruteforce_blacklist
```


**Danger.** HIGH SELF-LOCKOUT RISK, stated by MikroTik. Any automation that opens more than three SSH connections in a short window (a poller, a retrying agent, a CI job) will blacklist its own source for 24 hours, and success does not clear the lists.


Source: https://manual.mikrotik.com/docs/firewall-and-quality-of-service/user-guides/bruteforce-prevention ; https://manual.mikrotik.com/d…


### The mikrotik.com/supportsec advisory list, as published (complete index)

As published on 2026-09-05, the year tabs are: all, 2026, 2025, 2024, 2023, 2021, 2020, 2019, 2018. There is NO 2022 tab - MikroTik published no security announcement in 2022. Full list by year, newest first. 2026: 'September 2026 vulnerability' (Sep 3, 2026). 2025: CVE-2025-10948 (Sep 25), CVE-2025-6563 (Jul 3), CVE-2023-47310 (Jun 30), CVE-2025-6443 (Jun 25), CVE-2024-54952 (May 29), CVE-2024-54772 (Feb 18). 2024: CVE-2024-27686 (Apr 2). 2023: CVE-2023-41570 (Nov 14), CVE-2023-30800 (Sep 7), CVE-2023-30799 (Jul 27), CVE-2023-32154 (May 19).


**Versions.** MikroTik does NOT publish an advisory for every RouterOS CVE. NVD holds 82 CVEs matching cpe:2.3:o:mikrotik:routeros; supportsec lists 22 announcements. Notably CVE-2018-7445 (pre-auth SMB RCE) has no supportsec entry despite being in CISA KEV.


**Danger.** Do not treat supportsec as a complete vulnerability inventory. Cross-check NVD (virtualMatchString=cpe:2.3:o:mikrotik:routeros) and the per-release CHANGELOGs, which carry '!) ... (CVE-xxxx-xxxx)' lines that sometimes predate or replace an advisory.


> **Review correction.** Change to 'supportsec lists 26 announcements.' Everything else in this entry is verbatim correct: I fetched all eight year tabs and every advisory slug and date matched exactly, including the absence of a 2022 tab and the exact permalink slugs.


Source: https://mikrotik.com/supportsec ; https://mikrotik.com/supportsec?year=2025 ; https://mikrotik.com/supportsec?year=2024 ; https://…


### September 2026 vulnerability - the current live advisory

Published Sep 3, 2026. MikroTik found the issue itself and is deliberately withholding details: 'To give time to update your systems, we are not currently publishing detailed information.' No CVE has been assigned publicly. Described as 'an important security update. Most configurations are not at risk, but upgrading is highly recommended.' Fix is in 7.25 beta 3, 7.24.2, 7.23.4, and 6.49.21. Crucially: 'RouterOS will check if your device has been compromised, and set it to "Flagged" status if it is.


**Versions.** Fixed versions: 7.25beta3, 7.24.2, 7.23.4, 6.49.21 (all released 2026-09-03).


```routeros
/system/package/update/check-for-updates
/system/device-mode/print
/log/print where topics~"critical"
```


**Danger.** After upgrading to one of these builds a compromised device may enter Flagged state, which disables suspicious config and blocks creating new scheduler/SOCKS/PPTP/L2TP/IPsec/proxy/SMB entries and blocks bandwidth-test/traffic-gen/sniffer.


> **Review correction.** Drop the discovery attribution and say only that MikroTik is withholding details. Everything else in the entry is confirmed verbatim against all three changelogs and the advisory: fixed in 7.25beta3 / 7.24.2 / 7.23.4 / 6.49.21 all dated 2026-09-03; the Flagged-status text; the five shared changelog lines including 'ssh - refactor SSH inte…


Source: https://mikrotik.com/supportsec/september-2026-vulnerability/ ; https://download.mikrotik.com/routeros/7.24.2/CHANGELOG ; https://…


### CVE-2025-10948 - REST API libjson buffer overflow (publicly exploited PoC)

Advisory Sep 25, 2025. Buffer overflow in parse_json_element inside libjson.so, triggered through the /rest/ip/address/print endpoint, exploitable remotely. MikroTik states 'The exploit for this issue has been publicly disclosed and may be actively used.' Upgrading to RouterOS 7.20.1 or 7.21beta2 mitigates it. The 7.20.1 CHANGELOG (2025-Oct-10) contains exactly '*) www - improved stability (CVE-2025-10948);'. NVD: CVSS 3.1 8.8 HIGH (AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H) and CVSS 4.0 7.4 HIGH with E:P (proof-of-concept exploit maturity). PR:L means it requires some authentication. RouterOS 7 only.


**Versions.** Affects RouterOS 7. Fixed in 7.20.1 / 7.21beta2. Not applicable to RouterOS 6 (no REST API).


```routeros
/ip/service/webserver/set rest-plain=no rest-secure=no
/ip/service/webserver/print
/ip/service/print where !dynamic
```


**Danger.** Killing rest-plain/rest-secure disables the REST API. If your own management tooling drives the router over /rest, that is an immediate loss of control-plane access - switch the tooling to the binary API (8728/8729) or SSH first.


Source: https://mikrotik.com/supportsec/cve-2025-10948/ ; https://download.mikrotik.com/routeros/7.20.1/CHANGELOG ; https://services.nvd.n…


### CVE-2025-6563 - hotspot XSS via the dst parameter

Advisory Jul 3, 2025. Cross-site scripting in the RouterOS hotspot, affecting versions below 7.19.2. An attacker injects the javascript: protocol via the dst parameter of a crafted URL; when the victim browses to it and logs in through the hotspot page, the payload executes. Worse, the login POST can be converted to a GET, so a single crafted URL both logs the victim into the ATTACKER's account and fires the payload with no interaction beyond the click. MikroTik advises upgrading to 7.20 or later. The 7.19.2 CHANGELOG (2025-Jun-20) contains '*) hotspot - allow only "http:" and "https:" schemas in dst field;'.


**Versions.** Advisory says 'below 7.19.2'; the fix commit is in 7.19.2 and MikroTik recommends 7.20+.


```routeros
/ip/hotspot/print
/ip/hotspot/servers/print
/system/device-mode/update hotspot=no
```


**Danger.** Only relevant where hotspot is actually deployed. Disabling hotspot on a guest-wifi site cuts every guest off the network. The device-mode route (hotspot=no) needs physical confirmation.


Source: https://mikrotik.com/supportsec/cve-2025-6563/ ; https://download.mikrotik.com/routeros/7.19.2/CHANGELOG ; https://download.mikrot…


### CVE-2023-47310 - default IPv6 firewall config allows inbound UDP traceroute

Published as an advisory on Jun 30, 2025 although the CVE id is 2023. 'A misconfiguration in the default settings of MikroTik RouterOS 7 allows incoming IPv6 UDP traceroute packets, which could permit unauthorized network reconnaissance from external sources.' Fixed in RouterOS 6.49.13, 7.14 or later. NVD CVSS 3.1 6.5 MEDIUM (AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:N). This is the reason MikroTik's current published IPv6 input chain accepts dst-port=33434-33534 explicitly rather than leaving a broad UDP hole.


**Versions.** Fixed in 6.49.13 and 7.14. RouterOS 7 default configs before 7.14 are affected.


```routeros
/ipv6/firewall/filter/print
/ipv6/firewall/filter/print where chain=input
/ipv6/firewall/raw/print
```


**Danger.** None from auditing. Fixing it means adding a drop to the IPv6 input chain - see the IPv6 input-chain entry for the lockout warning.


Source: https://mikrotik.com/supportsec/cve-2023-47310/ ; https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2023-47310 ; https://…


### CVE-2025-6443 - VXLAN source-IP improper access control (unauthenticated)

Advisory Jun 25, 2025. RouterOS fails to validate the remote IP address against configured values when processing VXLAN traffic before allowing ingress into the internal network. Remote, UNAUTHENTICATED attackers can bypass access restrictions and reach internal network resources. Tracked as ZDI-CAN-26415 / ZDI-25-424. Fixed in RouterOS 7.20 or later. NVD CVSS 3.0 7.2 HIGH (AV:N/AC:L/PR:N/UI:N/S:C/C:L/I:L/A:N) - note Scope:Changed, because the impact lands on the internal network rather than the router.


**Versions.** Fixed in RouterOS 7.20+. Only affects devices with VXLAN configured (v7 feature; VXLAN does not exist in RouterOS 6).


```routeros
/interface/vxlan/print
/interface/vxlan/vteps/print
/ip/firewall/filter/print where chain=input
```


**Danger.** Mitigation without upgrading means firewalling the VXLAN UDP endpoint to known peers only. Doing that wrong drops the overlay and every service riding it.


Source: https://mikrotik.com/supportsec/cve-2025-6443/ ; https://www.zerodayinitiative.com/advisories/ZDI-25-424/ ; https://services.nvd.n…


### CVE-2024-54952 - SMB null-pointer dereference, remote unauthenticated DoS

Advisory May 29, 2025. Memory corruption in the RouterOS SMB service: remote, unauthenticated attackers send specially crafted packets triggering a null pointer dereference, making the SMB service unavailable. MikroTik's remediation is simply 'upgrade to the latest RouterOS 7.x stable release' - no specific fixed version is named in the advisory. NVD describes it against RouterOS 6.40.5 with CVSS 3.1 7.5 HIGH (AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H).


**Versions.** RouterOS 7.14 replaced the legacy SMB service with the ROSE SMB service ('!) smb - removed legacy SMB service (replaced with newer and faster ROSE SMB service, compatible with SMB 2.1, SMB 3.0 and SMB 3.1.1)'), so 7.14+ runs a different implementation.


```routeros
/ip/smb/print
/ip/smb/set enabled=no
/ip/smb/shares/print
```


**Danger.** SMB is enabled=yes in EVERY device-mode (home, basic, advanced, ROSE), so device-mode gives you no protection by default - you must turn it off explicitly. Disabling SMB kills any file share the site depends on.


Source: https://mikrotik.com/supportsec/cve-2024-54952/ ; https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2024-54952


### CVE-2024-54772 - WinBox username enumeration by response-size oracle

Advisory Feb 18, 2025. A discrepancy in the WinBox service's response size between valid and invalid usernames lets an attacker enumerate which accounts exist. Password still has to be guessed separately. Affected: RouterOS prior to 6.49.18 and 7.18. NVD gives the precise ranges: 'long-term release v6.43.13 through v6.49.13 and stable v6.43 through v7.17.2', patch in stable release v6.49.18. CVSS 3.1 5.4 MEDIUM (AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:L/A:N). MikroTik's recommended actions: upgrade to 6.49.18 / 7.18 or newer; review router logs for suspicious authentication activity.


**Versions.** Fixed in 6.49.18 and 7.18. Affected long-term 6.43.13-6.49.13 and stable 6.43-7.17.2.


```routeros
/ip/service/set winbox address=192.168.88.0/24
/ip/service/print where !dynamic
/tool/mac-server/mac-winbox/set allowed-interface-list=<trusted-interface-list>
```


**Danger.** See the /ip/service entry - setting winbox address= to a prefix that excludes you disconnects you and, if WinBox was your only transport, permanently.


> **Review correction.** Qualify the guidance in entry 1: changelogs confirm a fix when MikroTik chose to annotate it (they did for CVE-2025-10948, CVE-2023-32154, CVE-2019-3976/3977/3978/3979), but MikroTik frequently ships a security fix with no CVE reference or no matching line at all.


Source: https://mikrotik.com/supportsec/cve-2024-54772/ ; https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2024-54772 ; https://…


### CVE-2024-27686 - SMB session-setup packet disrupts transfers (RouterOS 6 only)

Advisory Apr 2, 2024 - MikroTik's only security announcement in the whole of 2024. 'The SMB service in RouterOS 6 could be affected by a specially crafted SMB session setup packet. In the reported scenario, this could interrupt the active SMB session, which may also interrupt an ongoing file transfer that depends on that session.' Fixed in RouterOS 6.49.14; RouterOS 7 is not affected. The 6.49.14 CHANGELOG (2024-Apr-03) shows '*) smb - improved service stability when receiving bogus packets;'.


**Versions.** RouterOS 6 only, fixed in 6.49.14. RouterOS 7 unaffected.


```routeros
/ip/smb/print
/ip/smb/set enabled=no
/ip/firewall/filter/add chain=input action=drop protocol=tcp dst-port=445 in-interface-list=WAN comment="drop SMB from WAN"
```


**Danger.** Note MikroTik's advisory downplays this ('interrupt the active SMB session') while NVD says device crash. Treat it as a device-crash DoS. Blocking 445 inbound from WAN has no management-plane lockout risk.


Source: https://mikrotik.com/supportsec/cve-2024-27686/ ; https://download.mikrotik.com/routeros/6.49.14/CHANGELOG ; https://services.nvd.…


### CVE-2023-41570 - REST API incorrect access control

Advisory Nov 14, 2023. 'MikroTik RouterOS versions 7.1 through 7.11 contained an access control issue in the REST API. The issue applied to installations where the REST API was enabled and reachable, and could allow requests to be handled with incorrect access control.' Fixed in RouterOS 7.12 and newer. RouterOS 6 has no REST API and is unaffected. The 7.12 CHANGELOG is dated 2023-Nov-09.


**Versions.** Affects RouterOS 7.1-7.11. Fixed in 7.12.


```routeros
/ip/service/webserver/set rest-plain=no rest-secure=no
/ip/service/print where !dynamic
/user/active/print
```


**Danger.** Same as CVE-2025-10948: disabling REST cuts any tooling that drives the router over /rest. Both REST CVEs argue for putting the REST API behind a VPN and never on a WAN-facing listener.


Source: https://mikrotik.com/supportsec/cve-2023-41570/ ; https://download.mikrotik.com/routeros/7.12/CHANGELOG ; https://services.nvd.nis…


### CVE-2023-30800 - RouterOS 6 web server heap corruption (unauthenticated)

Advisory Sep 7, 2023. 'The web server used by MikroTik RouterOS version 6 was affected by a heap memory corruption issue. In specific conditions, a crafted HTTP request could cause the web interface service to crash and restart.' Fixed in RouterOS 6.49.10 stable; RouterOS 7 is not affected. The 6.49.10 CHANGELOG (2023-Sep-15) shows '*) www - improved service stability when receiving malformed packets;'. NVD confirms remote AND unauthenticated: CVSS 3.1 7.5 HIGH (AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H). Researcher writeup: vulncheck.com/advisories/mikrotik-jsproxy-dos.


**Versions.** RouterOS 6 only, fixed in 6.49.10. RouterOS 7 unaffected.


```routeros
/ip/service/disable www
/ip/service/print where !dynamic
```


**Danger.** Disabling www removes WebFig. If WebFig is the operator's only interface (common on customer-managed home routers) this is a support call. Prefer firewalling tcp/80 from WAN over disabling the service.


Source: https://mikrotik.com/supportsec/cve-2023-30800/ ; https://download.mikrotik.com/routeros/6.49.10/CHANGELOG ; https://services.nvd.…


### CVE-2023-30799 - policy-to-superadmin privilege escalation (FOISted)

Advisory Jul 27, 2023. A logged-in administrator holding the 'policy' permission (which lets them grant additional permissions to any user) can send crafted configuration commands that are normally only exchanged internally between RouterOS software components and rejected when sent by a user - a stepping stone to arbitrary code execution on the underlying OS. Requires a known username and password AND network reachability.


**Versions.** Fixed in v7.7 and v6.49.7 and newer. Affected stable before 6.49.7 and long-term through 6.48.6.


```routeros
/user/group/print detail
/user/print detail
/user/active/print
```


**Danger.** The remediation that matters operationally is not a firewall rule - it is not handing out the 'policy' permission. Audit every custom group for 'policy' in its policy list.


> **Review correction.** Requote or de-quote. The load-bearing facts all verify: fixed "in all RouterOS releases available on our download page (v7.7 and v6.49.7 and newer)", and "if the malicious party has full admin login to a router, this exploit provides little additional advantage" is genuine.


Source: https://mikrotik.com/supportsec/cve-2023-30799/ ; https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2023-30799 ; https://…


### CVE-2023-32154 - IPv6 router-advertisement RCE, network-adjacent, unauthenticated

Advisory May 19, 2023. Affects RouterOS v6.xx and v7.xx WITH the IPv6 advertisement receiver enabled. You are only affected if one of these exact settings is applied: 'ipv6/settings/ set accept-router-advertisements=yes' OR 'ipv6/settings/set forward=no accept-router-advertisements=yes-if-forwarding-disabled'. MikroTik notes this combination 'is not normally found in routers and is rarely used'. Impact: network-adjacent attackers execute arbitrary code; authentication not required. Fixed in 7.9.1, 6.49.8, 6.48.7, 7.10beta8 and newer.


**Versions.** Fixed in 7.9.1, 6.49.8, 6.48.7, 7.10beta8. Affects both v6 and v7 when the RA receiver is enabled.


```routeros
/ipv6/settings/print
/ipv6/settings/set accept-router-advertisements=no
/ipv6/settings/set forward=yes
```


**Danger.** HIGH OUTAGE RISK. On a CPE whose IPv6 uplink is configured by SLAAC/RA from the ISP, accept-router-advertisements=no removes the default route and the delegated addressing - the device loses IPv6 upstream.


Source: https://mikrotik.com/supportsec/cve-2023-32154/ ; https://download.mikrotik.com/routeros/7.9.1/CHANGELOG ; https://download.mikrot…


### 2021 advisories - Meris, FragAttacks and the package-signing upgrade

Three announcements. (1) 'Mēris botnet' Sep 15, 2021 - see the dedicated Meris entry. (2) 'Fragattacks' Jun 2, 2021 - the Belgian fragmentation-attack set against Wi-Fi security protocols; the entries found to potentially affect RouterOS are CVE-2020-24587, CVE-2020-24588, CVE-2020-26144, CVE-2020-26146, CVE-2020-26147, all fixed in v6.47.10 [long-term], v6.48.3 [stable], v7.1beta6 [beta].


**Versions.** Package signing upgrade from 6.47.9 / 6.48.1 / 6.49beta11 / 7.1beta4. FragAttacks fixed in 6.47.10 / 6.48.3 / 7.1beta6.


```routeros
/system/package/print
/system/check-installation
```


**Danger.** 'Use Netinstall whenever there is doubt about previous history of software installed on the router' is MikroTik's own remediation standard for a suspect device.


> **Review correction.** Drop '/system/check-installation' or mark it explicitly as undocumented-by-MikroTik. Do not let an agent present it to an operator as the vendor-sanctioned integrity check for a suspected-compromised device; the vendor-sanctioned remediation in that advisory is Netinstall, which the entry already states correctly.


Source: https://mikrotik.com/supportsec/meris-botnet/ ; https://mikrotik.com/supportsec/fragattacks/ ; https://mikrotik.com/supportsec/upg…


### 2019-2020 advisories - Winbox MITM, DNS cache poisoning, package validation, TCP SACK, IPv6 exhausti…

CVE-2019-3981 (Jan 15, 2020): a MITM on port 8291 could retrieve a RouterOS user's password hash by intercepting a legitimate login; only affects RouterOS versions released before June 2019, because 'MikroTik has already forced the use of Winbox encryption since RouterOS v6.45.x (June 2019)'. DNS cache poisoning (Oct 28, 2019): RouterOS 6.45.6 and below vulnerable to unauthenticated remote DNS cache poisoning via WinBox on port 8291 - 'The router is impacted even when DNS is not enabled'; the resolver is reachable via WinBox by sending messages to the system resolver.


**Versions.** WinBox encryption forced from v6.45.x (June 2019). DNS/package fixes in 6.45.7 / 6.44.6 / 6.46beta59. Dude-agent fix in 6.42.12 / 6.43.12 / 6.44beta75.


```routeros
/ip/service/set winbox address=<trusted-prefix>
/ip/dns/cache/flush
/ip/dns/print
```


**Danger.** The recurring lesson: WinBox on 8291 open to the internet has been the pivot for a directory traversal (2018-14847), a DNS-cache-poisoning oracle (2019-3978/3979), a TCP/UDP proxy (2019-3924) and a hash-stealing MITM (2019-3981).


Source: https://mikrotik.com/supportsec/cve-2019-3981/ ; https://mikrotik.com/supportsec/dns-cache-poisoning-vulnerability/ ; https://mikr…


### 2018 advisories - the year of CVE-2018-14847 and Chimay-Red

Five advisories. 'Winbox vulnerability' (Jul 12, 2018) summarises the April 23, 2018 fix later assigned CVE-2018-14847: 'The vulnerability allowed a special tool to connect to the Winbox port, and request the system user database file.' Affected all bugfix releases 6.30.1-6.40.7 (fixed 6.40.8), all current releases 6.29-6.42 (fixed 6.42.1), all RC releases 6.29rc1-6.43rc3 (fixed 6.43rc4), all on 2018-Apr-23. MikroTik: 'Currently there is no sure way to see if you were affected.


**Versions.** CVE-2018-14847 fixed 2018-Apr-23 in 6.40.8 / 6.42.1 / 6.43rc4. Chimay-Red (CVE-2017-20149) fixed 2017-Mar-09 in 6.37.5 / 6.38.5. CVE-2018-1156..1159 fixed in 6.40.9 / 6.42.7 / 6.43.


```routeros
/log/print where topics~"system" && topics~"info"
/user/print detail
/ip/socks/print
```


**Danger.** MikroTik's own instruction after CVE-2018-14847 is the model incident-response sequence and it is still correct: upgrade, THEN change every password (an upgrade alone does not help if the credential was already stolen), THEN firewall the WinBox port, THEN /exp…


> **Review correction.** Attribute the licence-upgrade mechanism to Tenable, or drop it. All other 2018 facts verified verbatim: CVE-2018-14847 fixed 2018-Apr-23 in 6.40.8 / 6.42.1 / 6.43rc4 with the 'Currently there is no sure way to see if you were affected' quote and the four-step remediation order; Chimay-Red fixed 2017-Mar-09 in 6.37.5 / 6.38.5 with the VPNF…


Source: https://mikrotik.com/supportsec/winbox-vulnerability/ ; https://mikrotik.com/supportsec/new-exploit-for-mikrotik-router-winbox-vul…


### CISA KEV - exactly two MikroTik entries, and what that means for prioritisation

As of catalogVersion 2026.09.04 (1695 entries), the CISA Known Exploited Vulnerabilities catalog contains exactly TWO MikroTik RouterOS entries. (1) CVE-2018-14847, 'MikroTik Router OS Directory Traversal Vulnerability', dateAdded 2021-12-01, dueDate 2022-06-01, knownRansomwareCampaignUse Unknown, CWE-22. (2) CVE-2018-7445, 'MikroTik RouterOS Stack-Based Buffer Overflow Vulnerability', dateAdded 2022-09-08, dueDate 2022-09-29, knownRansomwareCampaignUse Unknown, CWE-119. No 2023, 2024, 2025 or 2026 MikroTik CVE is in KEV.


**Versions.** CVE-2018-14847: MikroTik RouterOS through 6.42. CVE-2018-7445: all architectures and all devices running RouterOS before 6.41.3 / 6.42rc27.


**Danger.** Do not tell an operator a MikroTik CVE is 'exploited in the wild' unless it is in KEV or MikroTik says so. For everything else, say 'public PoC exists' or 'no public exploitation evidence' and cite which.


Source: https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json ; https://services.nvd.nist.gov/rest/json/cves…


### CVE-2018-7445 - pre-authentication SMB stack overflow with no MikroTik advisory

'A buffer overflow was found in the MikroTik RouterOS SMB service when processing NetBIOS session request messages. Remote attackers with access to the service can exploit this vulnerability and gain code execution on the system. The overflow occurs before authentication takes place, so it is possible for an unauthenticated remote attacker to exploit it. All architectures and all devices running RouterOS before versions 6.41.3/6.42rc27 are vulnerable.' CVSS 3.1 9.8 CRITICAL (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H), CVSS 2 10.0. Published 2018-03-19, discovered by Core Security; Exploit-DB 44290.


**Versions.** Fixed in RouterOS 6.41.3 and 6.42rc27.


```routeros
/ip/smb/print
/ip/smb/set enabled=no
/system/resource/get version
```


**Danger.** SMB is allowed in every device-mode, so an unpatched pre-6.41.3 device with SMB on and reachable is a pre-auth RCE. Any device still on RouterOS below 6.41.3 should be treated as compromised until proven otherwise, not merely patched.


Source: https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2018-7445 ; https://www.cisa.gov/sites/default/files/feeds/known_exploi…


### CVE-2026-14227 - API session does not expire after a permission downgrade

Published 2026-07-30, carried by CISA ICS advisory ICSA-26-211-01 rather than by mikrotik.com/supportsec. 'An API session-management flaw in products with the MikroTik RouterOS API enabled are vulnerable to a Insufficient Session Expiration vulnerability. This could allow active sessions to retain their previous permission set after inactivity timeouts or user-group changes. As a result, an authenticated user whose permissions have been reduced may continue accessing information.' CVSS 4.0 6.9 MEDIUM (AV:N/AC:L/AT:N/PR:H/UI:N/VC:H/VI:N/VA:N), CVSS 3.1 4.9 MEDIUM.


**Versions.** No fixed version published as of 2026-09-05. Affects every RouterOS version with the API enabled.


```routeros
/user/active/print
/user/active/request-logout <session-number>
/user/group/print detail
```


**Danger.** Operationally this means: any workflow that revokes or downgrades a RouterOS account is INCOMPLETE without an explicit request-logout of that user's active sessions. Automation that only changes /user group= leaves a live session with the old rights.


Source: https://www.cisa.gov/news-events/ics-advisories/icsa-26-211-01 ; https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-1…


### CVE-2018-14847 and the Winbox campaigns - mechanism and scale

The bug: unauthenticated directory traversal in the WinBox interface (TCP/8291) that let an attacker read arbitrary files - specifically the system user database - and let an authenticated attacker write arbitrary files. NVD: 'MikroTik RouterOS through 6.42', CVSS 3.1 9.1 CRITICAL (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N). Public exploit tooling: BigNerd95/WinboxExploit, BasuCert/WinboxPoC, tenable/routeros (cve_2018_14847 and 'bytheway' PoCs), Exploit-DB 45578. Scale per Qihoo 360 Netlab (Sep 2018): of ~1.2 million MikroTik devices with TCP/8291 open, '370k (30.83%)' were still vulnerable months after the patch.


**Versions.** Fixed 2018-Apr-23 in 6.40.8 (bugfix), 6.42.1 (current), 6.43rc4 (RC).


```routeros
/ip/service/print where !dynamic
/user/print detail
/user/active/print
```


**Danger.** The single most important remediation fact in this whole domain: patching does NOT remediate CVE-2018-14847, because the credential was already exfiltrated.


> **Review correction.** Attribute the licence-upgrade mechanism to Tenable, or drop it. All other 2018 facts verified verbatim: CVE-2018-14847 fixed 2018-Apr-23 in 6.40.8 / 6.42.1 / 6.43rc4 with the 'Currently there is no sure way to see if you were affected' quote and the four-step remediation order; Chimay-Red fixed 2017-Mar-09 in 6.37.5 / 6.38.5 with the VPNF…


Source: https://mikrotik.com/supportsec/winbox-vulnerability/ ; https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2018-14847 ; ht…


### Coinhive cryptojacking campaign - mechanism and IoCs

Discovered by Simon Kenin (Trustwave SpiderLabs) on July 31, 2018 after noticing a surge of Coinhive activity in Brazil. Entry point was CVE-2018-14847 in WinBox. Mechanism: the attacker enabled the router's WEB PROXY and replaced its custom error page (error.html) with one containing the Coinhive miner, then arranged for user web traffic to be served that page - initially injecting the script into every page served through the router, later narrowing to error pages only to reduce detection.


**Versions.** Preconditions: RouterOS at or below 6.42 / 6.40.7 with WinBox 8291 reachable. Coinhive itself shut down in March 2019, so the injected miner no longer earns - but the underlying router compromise and the backdoor account persist.


```routeros
/ip/proxy/print
/ip/proxy/set enabled=no
/file/print
```


**Danger.** Hunt specifically for: /ip/proxy enabled=yes on a device that has no business proxying, an error.html or *.rsc in /file, a scheduler entry whose on-event calls /tool/fetch, a user named ftu or any account you did not create, and a dst-nat rule redirecting clie…


Source: https://www.levelblue.com/en-us/resources/blogs/spiderlabs-blog/mass-mikrotik-router-infection-first-we-cryptojack-brazil-then-we-…


### Traffic-interception campaign (Netlab 360) - SOCKS4 proxy and TZSP eavesdropping IoCs

Qihoo 360 Netlab, Sept 2018. Of ~1.2M MikroTik devices with 8291 open, 370k (30.83%) vulnerable; '239K IPs are confirmed to have Socks4 proxy enabled maliciously', mostly on TCP/4153, with SOCKS access restricted to 95.154.216.128/25 (primarily 95.154.216.167) so only the attacker could use it. Separately '7.5k MikroTik RouterOS device IPs have been compromised' to forward traffic to attacker collectors via RouterOS's built-in TZSP sniffing.


**Versions.** sniff-tzsp / sniff-pc mangle actions and /tool/sniffer streaming exist in both v6 and v7 - this is abuse of documented functionality, not a bug.


```routeros
/tool/sniffer/print
/ip/firewall/mangle/print detail where action=sniff-tzsp
/ip/firewall/mangle/print detail where action=sniff-pc
```


**Danger.** These are the two highest-value hunt queries on any suspected MikroTik. A non-zero streaming-server on /tool/sniffer, or any sniff-tzsp/sniff-pc mangle rule pointing off-box, is exfiltration until proven otherwise.


Source: https://blog.netlab.360.com/7500-mikrotik-routers-are-forwarding-owners-traffic-to-the-attackers-how-is-yours-en/ ; https://manual…


### Meris botnet - what MikroTik published, the exact config to remove, and the domain IoC list

Advisory Sep 15, 2021. MikroTik's position: 'There is no new vulnerability in RouterOS and there is no malware hiding inside the RouterOS filesystem even on the affected devices. The attacker is reconfiguring RouterOS devices for remote access, using commands and features of RouterOS itself.' Same devices as the 2018 CVE-2018-14847 compromise.


**Versions.** MikroTik's direct product response was device-mode: '!) device-mode - added feature locking mechanism;' shipped in 6.49.1 (2021-Nov-17) and 6.48.6 (2021-Dec-03), with '*) device-mode - improved flagged router configuration detection;' in 6.49.2 (2021-Dec-03).


```routeros
/system/scheduler/print detail
/system/scheduler/print detail where on-event~"fetch"
/system/script/print detail where source~"fetch"
```


**Danger.** Port 5678/udp is ALSO MikroTik's legitimate neighbour-discovery port, so a rule referencing 5678 is not automatically malicious - read the rule (chain, action, src/dst) before removing it.


> **Review correction.** Use an equality match or a broader print with external filtering, e.g. '/ip/firewall/filter/print detail where dst-port=5678' or '/ip/firewall/filter/export' then grep. Keep the entry's existing and correct caveat that 5678/udp is MikroTik's own MNDP port, so a rule referencing 5678 must be read (chain, action, protocol, src/dst) before r…


Source: https://mikrotik.com/supportsec/meris-botnet/ ; https://blog.qrator.net/en/meris-botnet-climbing-to-the-record_142/


### VPNFilter - mechanism, MikroTik models, and full IoC set

Cisco Talos, May 23 2018: 'at least 500,000 in at least 54 countries'. MikroTik devices named are the Cloud Core Router 1016, 1036 and 1072. MikroTik's own position, from the 'Web service vulnerability' advisory: 'We are highly certain that this malware was installed on these devices through the above mentioned vulnerability in the www service' - i.e. the Chimay-Red webfig bug fixed 2017-Mar-09 in 6.37.5/6.38.5 - and 'Simply upgrading RouterOS software deletes the malware, any other 3rd party files and closes the vulnerability.' MikroTik also notes 'The name VPNfilter is only a code name of the malware ...


**Versions.** Entry vector fixed 2017-Mar-09 in RouterOS 6.37.5 (Bugfix) and 6.38.5 (Current), i.e. CVE-2017-20149 'Chimay-Red'. Any RouterOS released after March 2017 closes it.


```routeros
/system/resource/print
/file/print
/system/scheduler/print detail
```


**Danger.** The Linux paths (/var/run/...) and crontab are NOT reachable from the RouterOS CLI - you cannot grep for them from a RouterOS session. Detection from RouterOS is indirect (unexpected config, unknown users, unknown files) and MikroTik's stated remediation is to…


Source: https://blog.talosintelligence.com/vpnfilter/ ; https://mikrotik.com/supportsec/web-service-vulnerability/


### device-mode - the four modes and the complete gated-feature matrix

device-mode sets hard limits on which subsystems a device may use, so a compromised admin session cannot turn the router into a proxy/tunnel/scanner. Modes: advanced (default; previously called enterprise), home, basic, ros (ROSE). Factory assignment on RouterOS 7.17+: advanced for CCR and 1100 series, home for home routers, basic for everything else. Devices on versions before 7.17 all use advanced/enterprise. ROSE mirrors advanced but enables container for RDS-style disk devices.


**Versions.** Feature-locking mechanism added in RouterOS 6.49.1 (2021-Nov-17) and 6.48.6 (2021-Dec-03). RouterOS 7.17 renamed enterprise->advanced, added basic mode, added the routerboard/install-any-version/partitions features and the allowed-versions list, and disabled t…


```routeros
/system/device-mode/print
/system/device-mode/print config
/system/device-mode/update mode=home
```


**Danger.** CRITICAL BEHAVIOURAL TRAP, stated by MikroTik: 'If the update command specifies any of the mode parameters, this update replaces the entire device-mode configuration.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/device-mode ; https://manual.mikrotik.com/docs/cli-reference/sys…


### device-mode - the change protocol, physical presence, and the three-attempt counter

Any device-mode change must be confirmed by physical presence: press the reset or mode button on the device, or perform a cold reboot (unplug the power / hard-reboot the VM). On confirmation the device REBOOTS. If no confirmation happens within the window the change is cancelled; if a second update command is issued in parallel, both are cancelled. The window is the activation-timeout argument, range 00:00:10 to 1d00:00:00, default 5m.


**Versions.** attempt-count limiting added in 7.17 ('*) device-mode - limit device-mode update maximum allowed attempt count which can be reset only with reboot or button press;'). Netinstall saves and restores device-mode configuration on format from 7.17.


```routeros
/system/device-mode/print
/system/device-mode/update mode=home activation-timeout=10m
/system/device-mode/update flagged=no
```


**Danger.** NEVER issue a /system/device-mode/update from an unattended remote agent. It is not a config write - it arms a pending change that (a) blocks on physical confirmation, (b) REBOOTS the device when confirmed, and (c) burns one of only three attempts if it is not…


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/device-mode ; https://manual.mikrotik.com/docs/cli-reference/sys…


### device-mode - allowed-versions (anti-downgrade)

allowed-versions is a list of RouterOS versions MikroTik considers free of serious exploitable vulnerabilities; the documented print example shows 'allowed-versions: 7.13+,6.49.8+'. Its purpose is to stop an attacker downgrading a device step-by-step to reach a known-vulnerable release. Key properties: it does NOT depend on the installed RouterOS version and works as a separate protection layer; upgrading RouterOS to a release carrying a newer allowed-versions list OVERWRITES the older list; downgrading RouterOS does NOT revert the list, which stays at the newest one seen.


**Versions.** allowed-versions added in RouterOS 7.17 ('*) device-mode - added "allowed-versions" list which are allowed to be installed without "install-any-version" mode enabled;').


```routeros
/system/device-mode/print
/system/device-mode/update install-any-version=yes
```


**Danger.** If you legitimately need to roll back to an older RouterOS after a bad upgrade, allowed-versions will BLOCK the install and enabling install-any-version needs physical presence at the device.


> **Review correction.** The enum value is `ros`. Prose: "Available device-modes are advanced, home, basic and ros." Both CLI reference pages agree: `/system/device-mode` read-only `mode enum — Current device mode: basic, home, advanced, or ros`, and `/system/device-mode/update` `mode enum — Device mode to apply: basic, home, advanced, or ros`.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/device-mode


### device-mode - Flagged status, what it disables, and how to exit it

RouterOS analyses the whole configuration at system startup for signs of unauthorized access. If suspicious configuration is found it is DISABLED and the flagged parameter is set to yes; flagging-enabled (default yes) controls whether that analysis runs at all. In flagged state the current configuration keeps working but you cannot: run bandwidth-test, traffic-generator or sniffer; or create/enable new entries (disable and delete still work) for system scheduler, SOCKS proxy, PPTP, L2TP, IPsec, proxy and SMB.


**Versions.** Flagged detection improved in 6.49.2 ('*) device-mode - improved flagged router configuration detection;'). Present in both v6 (6.49.x) and v7.


```routeros
/system/device-mode/print
/log/print where topics~"critical"
/export terse file=flagged-audit
```


**Danger.** Two failure modes for automation. (1) A flagged device silently rejects legitimate config pushes that add scheduler/IPsec/L2TP/SMB entries - a provisioning run will fail with 'configuration flagged' and an agent that does not check /system/device-mode/print fl…


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/device-mode ; https://mikrotik.com/supportsec/september-2026-vul…


### User groups and policies - what every policy actually grants

Full policy list on /user/group: local, telnet, ssh, ftp, reboot, read, write, policy, test, winbox, password, web, sniff, sensitive, api, rest-api, romon (default none). Login policies: local (console login), telnet, ssh, web (WebFig), winbox (WinBox login AND bandwidth-test authentication), password (change own password), api, rest-api, ftp ('policy that grants full rights to log in remotely via FTP. Allows reading/writing/erasing files and to transfer files from/to the router. Should be used together with read/write policies'), romon (connect to the RoMON server).


**Versions.** rest-api policy is v7-only (no REST API in v6). romon policy exists in both.


```routeros
/user/group/print detail
/user/group/add name=monitor policy=ssh,read,test,!ftp,!write,!policy,!sensitive,!sniff,!password,!telnet,!winbox,!web,!api,!rest-api,!romon,!local,!reboot
/user/print detail
```


**Danger.** Three escalation primitives to check for in any custom group: (1) 'policy' - the holder can grant themselves or anyone else any permission, and it is the precondition for CVE-2023-30799; (2) 'ftp' - grants read/write/erase on the router filesystem, which means…


Source: https://manual.mikrotik.com/docs/authentication-authorization-accounting/user


### Default user groups - exact policy strings, and the RADIUS escalation guard

Three undeletable system groups, with exactly these policy strings: read = local,telnet,ssh,reboot,read,test,winbox,password,web,sniff,sensitive,api,romon,rest-api,!ftp,!write,!policy ; write = local,telnet,ssh,reboot,read,write,test,winbox,password,web,sniff,sensitive,api,romon,rest-api,!ftp,!policy ; full = local,telnet,ssh,ftp,reboot,read,write,policy,test,winbox,password,web,sniff,sensitive,api,romon,rest-api. The 'read' group is therefore NOT read-only in any security sense: it carries reboot, sniff and sensitive. There is one predefined user, admin, group=full, address=0.0.0.0/0.


**Versions.** Same three groups on v6 and v7; rest-api appears in the v7 strings only.


```routeros
/user/group/print detail
/user/set myname inactivity-policy=logout inactivity-timeout=10m
/user/set myname address=10.0.0.0/24
```


**Danger.** If you enable use-radius=yes and do NOT set exclude-groups, a user who can edit the RADIUS server list can point the router at a RADIUS server they control and return group=full for themselves.


Source: https://manual.mikrotik.com/docs/authentication-authorization-accounting/user


### SSH keys on RouterOS - import, the password-login interaction, and the 'policy' requirement

Public keys go in /user/ssh-keys (import from a file with public-key-file=, or add a pasted key with key=). RSA, Ed25519 and Ed25519-sk are supported for public keys in PEM, PKCS#8 or OpenSSH format; pasted keys must be OpenSSH format. Private keys (for the router acting as an SSH CLIENT) go in /user/ssh-keys/private and support RSA and Ed25519 in PEM or PKCS#8. RouterOS cannot generate an SSH key pair; you export the device's host key instead with /ip/ssh/export-host-key key-file-prefix=admin, which produces admin_rsa and admin_rsa.pub.


**Versions.** 7.15 added user Ed25519 private keys AND '*) ssh - require "policy" user policy when adding public key;'. 7.19 fixed authorization when multiple user public keys are imported. 7.20 added showing the user public key fingerprint under /user/ssh-keys.


```routeros
/user/ssh-keys/import public-key-file=id_rsa.pub user=admin
/user/ssh-keys/print
/user/ssh-keys/private/import user=admin private-key-file=admin_rsa
```


**Danger.** HIGH LOCKOUT RISK, and it is silent. Importing a public key for a user immediately stops that user logging in with a password by default - if the key you imported is wrong, malformed, or bound to the wrong user, you have locked that account out of SSH in a sin…


Source: https://manual.mikrotik.com/docs/authentication-authorization-accounting/user ; https://manual.mikrotik.com/docs/management-tools/…


### Certificate handling and the trust store

Workflow: create a template under /certificate (the template is deleted as soon as it is signed or a request is generated), then /certificate/sign. Key sizes: 1024|1536|2048|4096|8192|prime256v1|secp384r1|secp521r1, default 2048. digest-algorithm md5|sha1|sha256|sha384|sha512, default sha256. days-valid default 365. Flags in print: K private-key, L crl, C smart-card-key, A authority, I issued, R revoked, E expired, T trusted. Removing a CA certificate REMOVES all issued certificates in its chain.


**Versions.** trust-store, /certificate/settings builtin-trust-store, ACME client and /certificate/builtin are v7. RouterOS 7.24.2 and 7.23.4 both carry '*) certificate - fix changing the built-in trust store setting (introduced in 7.22.2);'.


```routeros
/certificate/print detail
/certificate/add name=Server common-name=server key-size=4096 days-valid=365
/certificate/sign Server ca-crl-host=192.168.88.1 name=ServerCA
```


**Danger.** Two real hazards. (1) Deleting a CA silently deletes every certificate it issued - if that CA signed the certificate bound to www-ssl or api-ssl or an IPsec/SSTP tunnel, those services fail at once.


> **Review correction.** (a) The SMIPS store did not exist until 7.23 and the five-CA list is only accurate from 7.23.3. Changelogs: 7.23 'certificate - added "ISRG Root X1" and "DigiCert Global Root G2" to SMIPS built-in root certificate authorities store'; 7.23.3 'certificate - added "ISRG Root X2", "Root YE" and "Root YR" to SMIPS built-in root certificate aut…


Source: https://manual.mikrotik.com/docs/authentication-authorization-accounting/certificates ; https://manual.mikrotik.com/docs/system-in…


### API and API-SSL - the anonymous-Diffie-Hellman trap

The API listens on TCP/8728 and API-SSL on TCP/8729. The security-critical sentence from MikroTik: 'The API-SSL service can operate in two modes: with or without a certificate. Without a certificate provided in the /ip service settings, the client must use an anonymous Diffie-Hellman cipher to establish a connection. If the service uses a certificate, the client can establish a TLS session.' Anonymous DH gives you encryption with NO server authentication - it is fully MITM-able, and MikroTik ships api-ssl with certificate=none. So an api-ssl connection with no certificate configured is confidentiality theatre.


**Versions.** tls-version=only-1.2 on /ip/service is v7. CVE-2026-14227 (API sessions retaining stale permissions) has no fixed version as of 2026-09-05.


```routeros
/ip/service/print where !dynamic
/ip/service/set api-ssl certificate=ServerCA tls-version=only-1.2
/ip/service/set api-ssl address=10.5.101.0/24
```


**Danger.** Never build an integration on api-ssl without setting certificate= and pinning it on the client - anonymous DH means any on-path device can read and modify your management traffic.


Source: https://manual.mikrotik.com/docs/developer-guides/api/ ; https://manual.mikrotik.com/docs/system-information-and-utilities/service…


### Attacker persistence on RouterOS - the complete artifact list and the exact detection command for ea…

RouterOS has no shell for an attacker to drop a binary into (that is why VPNFilter needed the www RCE), so persistence is almost always legitimate configuration. The full hunt list, each with the command that surfaces it. (1) Scheduler jobs, especially ones calling /tool/fetch - /system/scheduler/print detail ; MikroTik's Meris advisory names this first. (2) Scripts - /system/script/print detail ; check source and note dont-require-permissions=yes, which lets a script run with more than the invoking user's rights. (3) SOCKS proxy - /ip/socks/print and /ip/socks/access/print.


**Versions.** /export properties: compact (default since 6rc1), file, path, show-sensitive, terse, verbose. By default sensitive information is HIDDEN and MikroTik states the export never contains system user passwords, installed certificates, SSH keys, Dude or User Manager…


```routeros
/export terse file=audit
/export terse
/system/scheduler/print detail
```


**Danger.** Two collection caveats. /export show-sensitive writes passwords, PSKs and keys in cleartext into a file on the router and requires the sensitive policy - do not use it on a suspect device and do not leave the file behind.


Source: https://mikrotik.com/supportsec/meris-botnet/ ; https://mikrotik.com/supportsec/winbox-vulnerability/ ; https://manual.mikrotik.co…


### Dangerous defaults and the one-shot audit script

The defaults worth flagging on a shipped device, each with the detection command and the safe fix. Enabled by default per MikroTik's own /ip/service print: ftp/21, telnet/23, www/80, api/8728, api-ssl/8729 (with certificate=none, i.e. anonymous DH), ssh/22, winbox/8291; only www-ssl/443 ships disabled. MAC-Telnet / MAC-WinBox / MAC-Ping are on. Neighbor discovery is on (5678/udp). Bandwidth server is on (2000/tcp+udp). DNS allow-remote-requests defaults to no but the factory configs enable DNS for LAN. IPv6 is disabled by default (which is why the IPv6 exhaustion CVEs did not hit default devices).


**Versions.** /system/default-configuration/print shows the exact factory default commands that were applied to this specific board.


```routeros
/ip/service/print where !dynamic
/ip/service/print where dynamic
/tool/mac-server/print
```


**Danger.** Every command in this list is read-only and safe to run on a production device. The corresponding remediations are not - see the per-item entries for lockout risk. Run the audit first, produce a diff, and stage the changes with safe mode engaged.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/services ; https://manual.mikrotik.com/docs/getting-started/secu…


### Safe mode - the anti-lockout mechanism, and its exact limits

Safe mode is RouterOS's built-in rollback for exactly the scenario where a firewall or addressing change cuts your own session. Take it with Ctrl+X (or F4) in the CLI, or the Safe Mode button in WinBox; the prompt changes to show <SAFE> and the router prints '[Safe Mode taken]'. All configuration changes made while safe mode is held - including changes made from OTHER login sessions - are automatically undone if the safe-mode session terminates abnormally. They appear in /system/history flagged F (floating-undo). If the connection is cut, the undo happens after the TCP timeout, documented as 9 minutes.


**Versions.** Safe mode is a CLI/WinBox-terminal feature and is documented for those transports. History depth is 100 actions.


```routeros
/safe-mode/print
/system/history/print
/system/history/print detail
```


**Danger.** Safe mode is NOT unlimited insurance. Pushing a 60-rule firewall in one batch can exceed the 100-action history and silently drop you OUT of safe mode with nothing undone - exactly when you most need it. Batch changes into small groups.


Source: https://manual.mikrotik.com/docs/getting-started/configuration-management/ ; https://manual.mikrotik.com/docs/management-tools/con…


### RoMON - unencrypted layer-2 management that bypasses your IP firewall

RoMON builds an independent MAC-layer peer-discovery and forwarding network. Packets use EtherType 0x88bf and DST-MAC 01:80:c2:00:88:bf and operate independently of L2 or L3 forwarding configuration - meaning your IP firewall does not filter them. Two facts that matter for security. First: 'The RoMON protocol does not provide encryption services. Encryption is provided at the "application" level, for example, by using ssh or by using a secure WinBox.' Second: 'When RoMON is enabled, any received RoMON packets are not displayed by sniffer or torch tools' - so RoMON traffic is invisible to your own on-box capture.


**Versions.** Since RouterOS 7.17 the switch chip auto-creates ACL rules to redirect RoMON frames to the CPU where supported. RB5009 (88E6393X) does not support this path: 'The chip's frame-types=admit-only-vlan-tagged filter drops RoMON frames before any ACL rule can be ap…


```routeros
/tool/romon/print
/tool/romon/set enabled=yes secrets=testing
/tool/romon/port/print
```


**Danger.** HIGH BOTH WAYS. Enabling RoMON with no secret hands layer-2 management reachability to anything on the same broadcast domain, and your IP firewall will not stop it - and hardware-offloaded bridges flood these frames like ordinary multicast.


> **Review correction.** Reword to 'MikroTik's documentation example shows only www-ssl disabled; actual shipped state depends on the device's default configuration, so always read /ip/service/print where !dynamic on the target rather than assuming.' The command to enumerate the applied defconf is /system/default-configuration/print, which the knowledge base does…


Source: https://manual.mikrotik.com/docs/management-tools/romon ; https://manual.mikrotik.com/docs/cli-reference/tool/romon/ ; https://man…


### protected-routerboot and Netinstall - the last line of defence and the only clean recovery

/system/routerboard/settings protected-routerboot (enum disabled|enabled) 'Disables access to the RouterBOOT configuration over the serial console and prevents the reset button from changing boot mode (Netinstall is disabled). You can access RouterOS only with a known RouterOS user account with administrative privileges. You can disable this setting only from within RouterOS.


**Versions.** protected-routerboot is unavailable on i386 (the settings menu carries 'Conditions: !i386'). From RouterOS 7.24beta1 the Netinstall package is available for all MikroTik architectures except SMIPS.


```routeros
/system/routerboard/settings/print
/system/routerboard/settings/set protected-routerboot=enabled
/system/routerboard/print
```


**Danger.** protected-routerboot=enabled is the strongest anti-physical-tamper control RouterOS has AND the easiest way to permanently brick your own access.


Source: https://manual.mikrotik.com/docs/cli-reference/system/routerboard/settings ; https://manual.mikrotik.com/docs/getting-started/inst…


### Could not verify

Whether the RouterOS 6 console accepts slash-separated menu paths (/ip/firewall/filter/print) as RouterOS 7 does. MikroTik's v6-era documentation uses space-separated paths exclusively and the current v7 manual uses slash-separated ones, but I could not source an explicit statement about v6 parser behaviour. Emit space-separated menu paths for any target that may be RouterOS 6. The exact RouterOS 7.x release in which device-mode first appeared. I confirmed the v6 introduction precisely ('!) device-mode - added feature locking mechanism;' in 6.49.1, 2021-Nov-17, and 6.48.6, 2021-Dec-03), and the 7.17/7.19/7.22 changes, but found no v7 changelog line announcing its introduction.
