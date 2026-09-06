# MikroTik RouterOS — Scripting and the /tool fetch transport

Part of the `mikrotik-routeros` skill. Every claim below was researched against
MikroTik's own documentation and changelogs, then independently fact-checked; where
the check found an error the corrected form is inline as **Review correction** and
the correction wins over the paragraph above it.


### Variable scoping: :local, :global, :set and the scope rules

Three declarators: `:local <var> [<value>]`, `:global <var> [<value>]`, `:set <var> [<value>]`. Every variable except built-ins MUST be declared before use or you get a compilation error (`:set myVar "x"; :put $myVar` fails; `:local myVar; :set myVar "x"; :put $myVar` works). Local scopes are delimited by curly braces `{ }`; a variable declared in a block is visible only in that block and its nested blocks, and only after the declaration point.


**Versions.** Undefined-variable lookup and `:set` with no value to un-define are documented as new in v6.2 (archived v6 wiki). Behaviour is the same in RouterOS 7.


```routeros
:local myVar;
:global myVar 3;
:global myVar;
```


**Danger.** Declaring a `:global` inside a local block does NOT make it visible outside that block. `{ :local a 3; { :global b 4; } :put ($a+$b); }` prints 3, silently, with no error. You must re-declare `:global b;` in the outer scope to see it.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### Data types and :typeof; conversion failure yields nil silently

Types: `num` (64-bit signed integer, hex input allowed), `bool`, `str`, `ip`, `ip-prefix`, `ip6`, `ip6-prefix`, `id` (hex value prefixed with `*`), `time`, `array`, `nil`. `:typeof <var>` returns the type name. A variable declared with no value has type `nil`. Conversion commands: `:toarray :tobool :toid :toip :toip6 :tonum :tostr :totime :tonsec :tocrlf :tolf`. KEY TRAP, quoted from the manual: 'If a variable type conversion function cannot apply the new format to the provided data, the output will be empty.


**Versions.** `:tonsec` added in 7.12 ('console - improved ":totime" and ":tonum" commands and added ":tonsec" command for time value manipulation'). `:tolf`/`:tocrlf` added in 7.14. 7.22 'implemented string casting in :tobool command'.


```routeros
:put [:typeof $myVar];
:local n [:tonum $s]; :if ([:typeof $n] = "nil") do={ :log error "not a number: $s" }
:put [:tonsec value=10:00];
```


**Danger.** Never branch on a `:tonum` result without a `:typeof` nil check — a malformed value compares as nothing rather than erroring, so a comparison like `:if ($n > 100)` silently takes the false branch.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### Arrays and dictionaries: literal syntax, indexing, the empty-array workaround

Array literal: `{1;2;3}` or `{x=1; y=2}` or mixed `{2; "aX"=1; y=2; 5}`. Element access by key or index uses `->`: `($arr->"key")`, `($arr->1)`. 2-D access chains: `($test->1->1)`. Assignment to an element: `:set ($a->"x") 5` and `:set ($test->1->1) "22_changed"`. Array key names containing any character other than a lowercase character must be quoted: `{ "aX"=1; ay=2 }`. Concatenation: `.` joins strings, `,` joins arrays or appends an element (`:put ({1;2;3} , 5)`).


**Versions.** 7.24 added `in` and `has` operators for array types, comparison operators for array type, and `order-by` for print. 7.21 added a `delimiter` parameter to `:toarray`.


```routeros
:global array [:toarray ""];
:set ($array->"el0") "el0_val";
:foreach k,v in=$arr do={ :put "$k=$v" }
```


**Danger.** Appending an array to a string with `.` does NOT stringify it — it distributes: `:put ("array value is: " . $array)` where `$array={"cccc","ddddd"}` prints `array value is: cccc;array value is: ddddd`. Convert first: `:put ("array value is: " .


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/scripting-tips-and-tricks/


### print as-value: 1-D vs 2-D results, and how to tell which you got

`print as-value` is the only scripting-safe way to read a menu. It returns EITHER a 1-D array (a single dictionary of property=value) or a 2-D array (a list of dictionaries), and which one you get depends on the menu, not on the number of matches. Non-list / command-style menus give 1-D: `:put ([/interface/wireless/info/hw-info wlan1 as-value]->"tx-chains")` works directly.


**Versions.** 7.10: 'console - disable output when using "as-value" parameter' (before 7.10 as-value also echoed to the terminal). 7.20: 'console - include flags by default when printing to value' — as-value results gained flag fields in 7.20, so a script that iterates keys…


```routeros
/ip/route/print as-value where gateway="ether1"
:pick [/ip/route/print as-value where dst-address="0.0.0.0/0"] 0
:foreach r in=[/interface/print as-value] do={ :put ($r->"name") }
```


**Danger.** An inventory collector written against 7.19 and shipped to a 7.21 fleet will silently start returning fewer fields (sensitive hidden by default) and, on 7.20+, extra flag fields.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/scripting-tips-and-tricks/


### get vs print vs find, and why numeric item numbers are a production bug

`find <expression>` returns a list of internal IDs (`*1`, `*400ae12f`) matching the expression. `get <id> <param>` retrieves one property value and does not print it by default — combine with `:put`: `:put [/system/resource/get version]`. `print` renders items and, as a side effect, 'assigns numbers used by all commands that operate with items in this list'. Those small numbers (`0`, `1`, `2`) are a transient print-buffer artefact. From the manual: a script containing `/ip route set 1 gateway=3.3.3.3` 'does not know what "1" refers to and throws an error'.


**Versions.** 7.20: 'console - unified string representation of ID values'. 7.21: 'console - changed file id format'. 7.22: 'console - added comparison operators for ID values' and 'improved error tracing when using find command'.


```routeros
/ip/route/set [find dst-address="0.0.0.0/0"] gateway=3.3.3.3
:put [/ip/route/find where dst-address="10.0.0.0/8"]
:put [/system/resource/get version];
```


**Danger.** Generating `set 0 ...` / `remove 1 ...` from a print you did earlier is the classic way to reconfigure or delete the WRONG object on a remote router. Always `[find ...]` inline in the same command.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/scripting-tips-and-tricks/


### A menu's SHAPE can change between RouterOS lines, and `find` is not universal

`find` is a list-menu command. A settings menu — one that holds properties rather than items — does not have it, and a menu can be a settings menu on one RouterOS line and a list menu on the next. `/system health` is the documented case: RouterOS 7 prints it as rows with `NAME`, `VALUE` and `TYPE` columns, while RouterOS 6 prints it as flat properties (`voltage`, `temperature`, `cpu-temperature`, …) whose exact set is per-model.

`print` and `get` exist on every menu. `:foreach k,v in=[... print as-value]` then reads both shapes with one loop: on the list form the key is a row index and the value is that row's array, and on the settings form the key IS the property name — so no list of expected property names has to be maintained, which matters when the set differs per model.


```routeros
:local n 0
:do {
  :foreach k,v in=[/system health print as-value] do={
    :if ([:typeof $v] = "array") do={
      :put ("$n " . [:tostr ($v->"name")] . "=" . [:tostr ($v->"value")] . [:tostr ($v->"type")])
    } else={
      :put ("$n " . [:tostr $k] . "=" . [:tostr $v])
    }
    :set n ($n + 1)
  }
} on-error={ :do { :foreach k,v in=[/system health get] do={ :put ("$k=$v") } } on-error={} }
```


**Danger.** Calling a command a menu does not have fails the way referencing an absent menu does: it takes down the WHOLE script, not the one line, and wrapping it in `:do ... on-error` does not save you. So a `find` written against the RouterOS 7 shape stops every RouterOS 6 device in the fleet from running the script at all — and because that script is usually what reports in, the symptom is silence rather than an error. Reach a shape-varying menu only through `print` and `get`.


Source: https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/health


### where clauses fail silently on type mismatch (the ip-prefix trap)

The console converts types aggressively but not always successfully, and a failed comparison produces an EMPTY result set, not an error. Documented example: `/ip/address/print where address=111.111.1.1/24` returns nothing even though that address exists, because `[:typeof ([print as-value]->0->"address")]` is `str` and the literal `111.111.1.1/24` is parsed as `ip-prefix`. Two documented fixes: `print where address=[:tostr 111.111.1.1/24]` or quote the literal `print where address="111.111.1.1/24"`. When the value comes from a variable, either convert with `:tostr` or interpolate into a string: `"$myVar"`.


```routeros
/ip/address/print where address=[:tostr 111.111.1.1/24]
/ip/address/print where address="111.111.1.1/24"
/interface/print where (name~"ether")=false
```


**Danger.** A `remove [find where ...]` whose where-clause silently matches NOTHING is harmless; the same clause silently matching EVERYTHING is not. Verify with `print count-only as-value` before any destructive `[find]` on a live device.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/scripting-tips-and-tricks/


### Error handling: exact version gate for every mechanism

There are four distinct mechanisms and they were added at four different times. 1) `do={...} on-error={...}` — the original. Documented as 'Starting from v6.2 scripting has ability to catch run-time errors.' Still valid in RouterOS 7: `do { import test.rsc } on-error={ :put "Failure" }`. Gives you NO error detail, only control flow. This is the ONLY option on RouterOS 6. 2) `:error <output>` — raises an error and stops the script. Available in v6 and v7. 3) `:retry command=<expr> delay=[num] max=[num]` — added in RouterOS 7.4.


**Versions.** `:retry` = 7.4 ('console - added ":retry" command'). `:onerror` = 7.13 ('console - added ":onerror" command'), fixed in 7.14 ('fixed incorrect behavior of ":onerror" command in certain cases') and 7.15 ('fixed ":onerror" behavior when "do" block is missing').


```routeros
:onerror e in={ :resolve www.example.com } do={ :put "resolver failed: $e" }
:onerror e {:put [:resolve www.example.com]} do={:put "resolver failed"}
:onerror e {:retry command={/tool/fetch url=$u as-value output=user} delay=5 max=3} do={:log error "fetch failed: $e"}
```


**Danger.** If you target a mixed RouterOS 6/7 fleet, `:onerror` and `:retry` are SYNTAX errors on RouterOS 6 and on 7.0–7.12 / 7.0–7.3 respectively. A script using them will not run at all on those devices — not fail gracefully, fail to parse.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### String operations: :find, :pick, :len, :tostr, :tonum

`:len <expression>` returns string length or array element count. `:pick <var> <start> [<end>]` returns a substring or array range; the first index is 0 and the END INDEX IS EXCLUSIVE ('terminating index (element at this index is not included)'). `:put [:pick "abcde" 1 3]` → `bc`. If the end is omitted with an array, it returns only one element. `:find <arg> <arg> <start>` returns the position of a substring or array element; `:put [:find "abc" "a" -1]` returns 0 (start at -1 to include position 0). `:find` returns nothing/nil when not found — check with `:typeof`, do not compare to -1.


**Versions.** 7.20.6: 'console - improved service stability and memory allocation when using "regexp" operator' — heavy `~` use on pre-7.20.6 can destabilise the console service.


```routeros
:put [:len "length=8"];
:put [:pick "abcde" 1 3];
:put [:find "abc" "a" -1];
```


**Danger.** `[:find $s "x"]` returning nil (not found) fed straight into `:pick` produces an empty string rather than an error, so a parser silently returns "" for every malformed input.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### :convert — base64, url, hex and the transform list (7.11+)

`:convert from=[arg] to=[arg] transform=[arg]`. When `from` is omitted it uses an automatically parsed value ('001' becomes '1', '10.1' becomes '10.0.0.1'). `from`/`to` formats: `base32, base64, bit-array-lsb, bit-array-msb, byte-array, hex, num, raw, url`. `transform` values: `lc` (lowercase), `uc` (uppercase), `lcfirst`, `ucfirst`, `crlf`, `none`, `rot13`, `reverse`, `md5`, `sha512`, `ed25519-private-to-x25519-private`, `x25519-private-to-x25519-public`, `ed25519-private-to-ed25519-public`, `ed25519-public-to-x25519-public`.


**Versions.** `:convert` added in 7.11. `transform` property added in 7.12. `byte-array` added in 7.15 (plus 'additional byte-array option' in 7.16). `to=url` began converting spaces, CR and LF in 7.15. uppercase/lowercase transforms added in 7.16.


```routeros
:put [:convert "user:pass" to=base64];
:put [:convert $s to=url];
:put [:convert transform=sha512 $s];
```


**Danger.** `:convert` does not exist before 7.11. On RouterOS 6 there is no base64 and no URL encoding primitive, so an HTTP Basic header must be precomputed off-device or built with `user=`/`password=` on /tool fetch instead.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### :serialize / :deserialize JSON — and the silent string↔number coercion that corrupts wire formats

`:serialize [<value>] to=[json|dsv]` and `:deserialize [<value>] from=[json|dsv]`. Options: `json.pretty`, `json.no-string-conversion`, `dsv.wrap-strings`, `dsv.ignore-size`, `dsv.remap`, `dsv.plain`, `dsv.array`; `delimiter=` sets the separator, `order=` fixes column order, `file-name=` writes output to a file. CRITICAL, straight from the manual's own examples: `:global var ({ "string"="1234"; "number"=1234 }); :put [:serialize to=json value=$var]` emits `{"number":1234,"string":1234.000000}` — the console STRING "1234" was emitted as a JSON number, AND numbers are emitted with six decimal places.


**Versions.** `:serialize`/`:deserialize` added in 7.13 (JSON only). DSV support added in 7.16. `json.no-string-conversion` added in 7.17. `dsv.remap` and `file-name` added in 7.18; tab allowed as a DSV delimiter in 7.18.


```routeros
:put [:serialize to=json value=$payload options=json.no-string-conversion];
:put [:serialize to=json value=$payload options=json.pretty];
:local body [:deserialize from=json value=($res->"data") options=json.no-string-conversion];
```


**Danger.** ALWAYS pass `options=json.no-string-conversion` on both serialize and deserialize for any machine-to-machine payload. Without it a device serial number like "0012345" is transmitted as the number 12345.000000, and a server-sent string field silently changes co…


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### Loops: :for, :foreach, :while, :do..while and their pitfalls

`:for <var> from=<int> to=<int> step=<int> do={ <commands> }`; `:foreach <var> in=<array> do={ <commands> }`; `:foreach k,v in=<array> do={...}` iterates key,value; `:while (<conditions>) do={ <commands> }`; `:do { <commands> } while=( <conditions> )`. Whitespace is FORBIDDEN around `=` in `from=`, `to=`, `step=`, `in=`, `do=`, `else=` — `:for i from = 1 to = 2 do = {...}` is a syntax error, while `:for i from= 1 to= 2 do={...}` is legal (space is allowed AFTER the `=`, never before).


**Versions.** 6.43 'removed automatic swapping of "from=" and "to=" in "for" loops' — on RouterOS < 6.43 a descending `from=10 to=1` was silently swapped into an ascending loop; from 6.43 it iterates zero times.


```routeros
:for i from=1 to=10 step=1 do={ :put $i }
:foreach i in=[/interface/find] do={ :put [/interface/get $i name] }
:foreach k,v in=$arr do={ :put "$k=$v" }
```


**Danger.** There is no loop-abort primitive before 7.22. On 7.0–7.21 and all of RouterOS 6, a `:foreach` over an unbounded remote-supplied array cannot be short-circuited; bound the array size yourself with `:len` before looping, or a hostile/oversized server response be…


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### :execute — background jobs, the 64 kB limit, and how to reap them

`:execute <expression>` runs a script IN THE BACKGROUND and returns a job id. Verbatim: 'The result can be written in the file by setting a file parameter or printed to the CLI by setting as-string. When using the as-string parameter executed script is blocked (not executed in the background). Executed scripts cannot be larger than 64 kB.' Documented reap pattern: `{ :local j [:execute {/interface/print follow where [:log info ~Sname~]}]; :delay 10s; :onerror e {/system/script/job remove $j} }`.


**Versions.** `as-string` added to `:execute` in 7.8. `/system/script/job` gained a `parent` field, fixed in 7.11 ('fixed missing "parent" for script jobs (introduced in v7.9)'). `/task` submenu (CLI only) added in 7.9. 7.24.2 'fix a memory leak in background scripts'.


```routeros
:local j [:execute {/tool/fetch url=$u output=file dst-path=out.json}];
/system/script/job/print
:onerror e {/system/script/job remove $j}
```


**Danger.** A `:execute` job that is never reaped keeps running. A scheduler that fires every minute and starts an unreaped background fetch will accumulate jobs until the console service degrades.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### :parse of network data is remote code execution — use :deserialize instead

`:parse <expression>` 'parses the string and returns parsed console commands. Can be used as a function.' The documented idiom is exactly the dangerous one: `:global myFunc [:parse ":put hello!"]; $myFunc;` and `:global myFunc [:parse [/system/script/get myScript source]]`. That means: any string handed to `:parse` becomes executable console code, running with the calling script's policy set.


**Versions.** `:parse` exists in RouterOS 6 and 7 alike (present in the v6 command table). `:deserialize` — the safe alternative — only exists from 7.13. On RouterOS 6 there is no JSON parser, so a v6 agent must consume a fixed, strictly-validated field format, never `:pars…


```routeros
:local body [:deserialize from=json value=($res->"data") options=json.no-string-conversion];
:global myFunc [:parse ":put hello!"]; $myFunc;
```


**Danger.** NEVER call `:parse`, `:execute`, or `import` on any string that originated from `/tool fetch`, a file the server wrote, a DHCP option, a DNS TXT record, or any other remote input. This is unconditional remote code execution at the script's policy level.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### /tool fetch — complete property list (RouterOS 7.24 CLI reference)

Every argument, copy-exact from the CLI reference: `url` (string) — full URL; can replace `address`+`src-path`; supports `@vrf_name` appended to the IP. `output` (none|file|user|user-with-headers; Default: file). `http-method` (get|post|put|delete|head|patch; Default: get). `http-auth-scheme` (basic|digest; Default: basic). `http-data` (string) — POST/PUT body, max 64 KB. `http-header-field` (multi) — `"h1:fff,h2:yyy"`. `check-certificate` (no|yes|yes-without-crl; Default: no). `certificate` (enum) — from the certificate store, HTTPS only, only when check-certificate is enabled.


**Versions.** See the per-parameter version-gate entry for exact release numbers. The frozen Confluence table (https://help.mikrotik.com/docs/spaces/ROS/pages/8978514/Fetch) is the older wording and still lists `duration` and `keep-result` as live.


```routeros
/tool/fetch url="https://example.com/f.bin" dst-path=f.bin check-certificate=yes
/tool/fetch url="sftp://192.168.88.2" address=@test src-path=test.txt user=admin password="" upload=yes
```


**Danger.** `mode=` is deprecated and is NOT how the protocol is chosen when `url=` is present — the URL scheme wins. Setting `mode=http` alongside an `https://` URL (as one of MikroTik's own examples does) is confusing but harmless; setting `mode=https` and an `http://`…


> **Review correction.** Treat `duration` as read-only output, not an input bound. `idle-timeout` (1..604800 or `none`, default 10s, 7.15+) is the only documented settable bound on current RouterOS. This is not a harmless extra argument: 7.23 'console - treat non-existent command parameters as runtime errors' and 7.24 'console - produce runtime errors for bad com…


Source: https://manual.mikrotik.com/docs/cli-reference/tool/fetch/


### /tool fetch — read-only result fields returned by as-value

`as-value` (set|not-set; Default: not-set) 'Store the output in a variable, should be used with the output property.' The returned array carries these read-only fields: `status` (none|connecting|requesting|downloading|uploading|finished|failed), `code` (num, the HTTP status code), `downloaded` (num, bytes), `uploaded` (num, bytes), `total` (num, total transfer size in bytes), `duration` (time, total operation duration), `data` (string, present only when output=user or user-with-headers, 64 KB limit), `http-headers` (object, the server's response headers).


**Versions.** `as-value` output format added to fetch in 6.43. `output` (none/file/user) added in 6.42. Response headers made available in 7.13 ('fetch - allow to receive HTTP response headers'). 7.21 'fixed http headers appearance when received payload is empty'.


```routeros
:local r [/tool/fetch url=$u as-value output=user];
:if (($r->"status") = "finished") do={ :put ($r->"data") }
:put ($r->"code"); :put ($r->"total"); :put ($r->"duration");
```


**Danger.** `as-value` without `output=user` gives you `status`/`code`/`duration` but no `data`, and no error — a heartbeat that reads `$r->"data"` will just see nil. The two parameters must be set together.


Source: https://manual.mikrotik.com/docs/cli-reference/tool/fetch/


### /tool fetch — every 64 KB / 4 KB cap, exactly where it bites

Four separate size limits, all documented: 1) `http-data` — 'The data, that is going to be sent. Data limit is 64Kb.' This caps the request body a router can POST in one call. 2) `output=user` — 'store downloaded data in the data variable (variable limit is 64Kb)'. 3) `output=user-with-headers` — 'variable limit is 64Kb (20Kb for downloaded data, 44Kb for headers)'. So asking for headers cuts your usable response body from 64 KB to 20 KB. 4) When the body is loaded from a file, the frozen Fetch page says: 'Important note, since variable data comes from a file, a file can only be in size up to 4KB.


**Versions.** File content limit raised to 60 KB in 7.14: 'console - increased maximum file content length that can be managed through command line to 60 KB' (https://download.mikrotik.com/routeros/7.14/CHANGELOG).


```routeros
/tool/fetch ... output=user as-value
/tool/fetch ... output=user-with-headers as-value
/file/read file=big.json chunk-size=32768 offset=0
```


**Danger.** Design the telemetry protocol so a single upload body stays well under 64 KB and a single response body under 20 KB if you need headers. A config export from a busy router routinely exceeds both.


> **Review correction.** The archived RouterOS 6 scripting manual carries an explicit note: "Variable value size is limited to 4096bytes". So on RouterOS 6 a fetch response read via `output=user` is bounded at ~4 KB, not 64 KB, regardless of what the fetch documentation says.


Source: https://manual.mikrotik.com/docs/cli-reference/tool/fetch/


### /tool fetch — check-certificate DEFAULTS TO NO (unauthenticated TLS)

Verbatim from the summary: 'In HTTPS mode by default, no certificate checks are made, setting check-certificate to yes enables trust chain validation from the local certificate store (can be used only in HTTPS mode).' Values: `no` (default), `yes` (validate the trust chain against the local certificate store), `yes-without-crl` (validate without a CRL check). `certificate=<name>` names a specific certificate from the store for host verification and is only usable in HTTPS mode and only when check-certificate is enabled.


**Versions.** 7.14: 'fetch - allow to use certificate and check-certificate parameters only in HTTPS mode'. 7.17: 'fetch - fixed certificate check when provided hostname is IP address'. 7.19: 'certificate - added built-in root certificate authorities store'.


```routeros
/tool/fetch url="https://api.example.com/v1/x" check-certificate=yes output=user as-value
/certificate/settings/set builtin-trust-store=fetch
/certificate/settings/print
```


**Danger.** DEFAULT-INSECURE. Every `/tool fetch https://...` written without `check-certificate=yes` accepts any certificate from any MITM, and the router will happily send its bearer token / API key in the request.


> **Review correction.** (a) The SMIPS store did not exist until 7.23 and the five-CA list is only accurate from 7.23.3. Changelogs: 7.23 'certificate - added "ISRG Root X1" and "DigiCert Global Root G2" to SMIPS built-in root certificate authorities store'; 7.23.3 'certificate - added "ISRG Root X2", "Root YE" and "Root YR" to SMIPS built-in root certificate aut…


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/fetch/


### /tool fetch — http-header-field syntax and its two-backslash escape

Multiple headers are comma-separated inside one quoted string: `http-header-field="h1:fff,h2:yyy"`. To put a comma INSIDE a single header's value you must escape it with two backslashes: `http-header-field="h:fff\\,yyy"`. The manual's own wording: 'within a single header multiple values need to be "escaped" using two backlashes'. Because the whole thing is a RouterOS string literal, a value containing a double quote must also be escaped (`\"`), which is why the JSON POST example is written `http-data="{\"lat\":\"56.12\",\"lon\":\"25.12\"}"`.


**Versions.** `http-header-field` added in 6.44, together with 'option to specify multiple headers under "http-header-field", including content type'. The earlier `http-content-type` parameter was added in 6.42 and REMOVED in 6.44 — a script targeting 6.42/6.43 must use `ht…


```routeros
/tool/fetch url=$u http-method=post http-header-field="Content-Type:application/json,Authorization:Bearer $tok" http-data=$body output=user as-value
/tool/fetch url=$u http-header-field="Accept:application/json\\,text/plain"
```


**Danger.** A header value containing an unescaped comma silently splits into two malformed headers — the request goes out, the server sees garbage, and nothing on the router logs a problem.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/fetch/


### /tool fetch — http-method and http-data version gates

`http-method` accepts `get, post, put, delete, head, patch`, default `get`. `http-data` carries the POST/PUT body. Original RouterOS 6.39 wording: 'fetch - added "http-data" and "http-method" parameters to allow delete, get, post, put methods (content-type=application/x-www-form-urlencoded by default)'. So on 6.39–7.13 the implicit content type is `application/x-www-form-urlencoded`; set it explicitly with `http-header-field="Content-Type:..."` if you are sending JSON. `head` and `patch` were only added in 7.14.


**Versions.** http-data/http-method (delete,get,post,put) = 6.39. head+patch = 7.14. http-auth-scheme (basic|digest) = 7.13. http-content-encoding = 7.13. http-data on any method = 7.21. Sources: https://download.mikrotik.com/routeros/6.39/CHANGELOG , /7.13 , /7.14 , /7.21


```routeros
/tool/fetch url=$u http-method=post http-data=$json http-header-field="Content-Type:application/json"
/tool/fetch url=$u http-method=patch http-data=$json
/tool/fetch url=$u http-method=post http-content-encoding=gzip http-data=$json
```


**Danger.** Do not design the ingest API around PATCH or HEAD if any device may run below 7.14, and do not put a body on a GET or DELETE if any device may run below 7.21 — the router sends the request with the body silently dropped, which looks like an empty-payload bug o…


Source: https://manual.mikrotik.com/docs/cli-reference/tool/fetch/


### /tool fetch — redirects, HTTP/2, and IP family selection

`http-max-redirect-count` (num; Default: 2) — 'Maximum number of HTTP redirects the fetch will follow automatically.' Redirect following did not exist as a parameter before 7.18. `http-version` (http1_1|http2|http2-forced; Default: http1_1) — HTTP2 is supported ONLY on ARM64 and x86/CHR devices; on MIPS/SMIPS/PPC/ARM32 it is not available. `ip-type` (any|ipv4|ipv6; Default: any) controls the family preference when resolving a hostname. `src-address` pins the source IP and works only in HTTP, HTTPS and SFTP modes.


**Versions.** http-max-redirect-count added in 7.18 ('allows to follow redirects'); 7.22 'increased default maximum redirect count to 2' and 'fixed fetch treating relative paths from redirects as hostnames'.


```routeros
/tool/fetch url=$u http-max-redirect-count=0 check-certificate=yes
/tool/fetch url=$u ip-type=ipv4
/tool/fetch url="https://192.168.88.2@vrf1/x" output=user as-value
```


**Danger.** Redirect following is a credential-leak vector: an `Authorization` header set with `http-header-field` will be replayed to whatever host the redirect names. On 7.22+ the default is 2 hops.


Source: https://manual.mikrotik.com/docs/cli-reference/tool/fetch/


### /tool fetch — what counts as success, and how to read the failure

Fetch RAISES a script error on failure; it does not return a status code you can branch on unless you catch it. From 7.14, 'treat any 2xx HTTP return code as success' (6.41 already had 'accept all HTTP 2xx status codes'); from 7.22, 'treat HTTP 304 return code as success'. Everything else aborts the script. Since 7.22 the error carries structured attributes, reachable through `:onerror`'s two-variable form: ``` :onerror err,attr in={ /tool/fetch http://127.0.0.1/error as-value} do={:put $err;:put ($attr->"code");:put ($attr->"http-headers")} failure: Status 404, Not Found 404 Cache-Control: no-store;Connection: K…


**Versions.** 2xx accepted = 6.41 and reaffirmed 7.14. 304 = 7.22. Structured `code` + `http-headers` on the error = 7.22 ('fetch - return error code and HTTP headers to :onerror script'). 7.16 'fetch - handle HTTP 401 status correctly'.


```routeros
:onerror err,attr in={ /tool/fetch url=$u as-value output=user } do={ :log error ("fetch failed " . ($attr->"code") . ": " . $err) }
:onerror e {:retry command={/tool/fetch url=$u as-value output=user} delay=5 max=3} do={:log error "give up: $e"}
```


**Danger.** An UNCAUGHT fetch failure terminates the whole script at that line. In a scheduled heartbeat that also does cleanup, rotates a token, or re-arms a watchdog, everything after the fetch is skipped when the control plane is briefly down.


> **Review correction.** Treat `duration` as read-only output, not an input bound. `idle-timeout` (1..604800 or `none`, default 10s, 7.15+) is the only documented settable bound on current RouterOS. This is not a harmless extra argument: 7.23 'console - treat non-existent command parameters as runtime errors' and 7.24 'console - produce runtime errors for bad com…


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/fetch/


### /tool fetch — required user policies (the netwatch trap)

Two policies matter. The `test` policy 'grants rights to run ping, traceroute, bandwidth-test, wireless scan, snooper, fetch, email and other test commands'. Separately, RouterOS 7.13 changed fetch to 'require "ftp" user policy'. The `ftp` policy 'grants full rights to log in remotely via FTP. Allows reading/writing/erasing files and to transfer files from/to the router. Should be used together with read/write policies.' Contexts that run scripts have their own ceilings: Netwatch 'is limited to read,write,test,reboot script policies.


**Versions.** 'fetch - require "ftp" user policy' = 7.13 (https://download.mikrotik.com/routeros/7.13/CHANGELOG). 6.45.1 'fetch - improved user policy lookup'.


```routeros
/system/script/add name=heartbeat policy=read,write,test,ftp source="..."
/system/scheduler/add name=hb interval=5m on-event=heartbeat policy=read,write,test,ftp
```


**Danger.** Netwatch's ceiling is `read,write,test,reboot` — it does NOT include `ftp`. On 7.13+, where fetch requires `ftp`, a fetch driven from a netwatch up-script/down-script can be refused on policy.


Source: https://manual.mikrotik.com/docs/authentication-authorization-accounting/user/


### The complete user policy list and what each grants

Login policies: `local` (log in locally via console), `telnet`, `ssh`, `web` (WebFig), `winbox` (WinBox and bandwidth-test authentication), `password` (change own password), `api`, `rest-api`, `ftp` (full remote FTP: read/write/erase files and transfer files to and from the router — 'Should be used together with read/write policies'), `romon` (connect to the RoMon server).


**Versions.** `tikapp` policy removed in 7.2; `dude` policy removed in 7.6. `sensitive` policy required for SSH key and certificate export from 7.11. `policy` policy required to add an SSH public key from 7.14.2/7.15.


```routeros
/user/group/add name=dunmir policy=read,write,test,ftp,api,rest-api,!policy,!sensitive,!sniff
/user/group/print
```


**Danger.** Do not provision the control-plane user into the built-in `read` or `write` groups: both include `sensitive`, `reboot` and `sniff`. Build a custom group with only what the agent needs.


Source: https://manual.mikrotik.com/docs/authentication-authorization-accounting/user/


### /system script: properties, dont-require-permissions, owner

`/system/script` items carry: `name` (string), `owner` (string), `policy` (multi-valued policy list), `dont-require-permissions` (bool), `source` (string), plus read-only `last-started` (date) and `run-count` (num), and an `I - invalid` flag. Run it with `/system/script/run [id|name]` or `/system/script/run [id|name] use-script-permissions`. Documented permission semantics: 'Depending on how a script is called, it may: Use its own permissions.


**Versions.** `dont-require-permissions` added in 6.43. 6.46.4 'fixed script with "dont-require-permissions=yes" execution without sufficient permissions'. `use-script-permissions` when running from CLI added in 7.15; the same release made WinBox/WebFig 'use user permission…


```routeros
/system/script/add name=heartbeat policy=read,write,test,ftp dont-require-permissions=no source="..."
/system/script/run heartbeat
/system/script/run heartbeat use-script-permissions
```


**Danger.** `dont-require-permissions=yes` is a privilege-escalation switch. MikroTik's own guidance: 'be very careful granting unrestricted permissions to scripts...


> **Review correction.** The property list IS confirmed there verbatim (flag `I invalid`; arguments name, owner, policy, dont-require-permissions, source; read-only last-started, run-count). The permission prose comes from the legacy Confluence Scripting page.


Source: https://manual.mikrotik.com/docs/cli-reference/system/script/


### /system scheduler: interval vs start-time vs startup, and the exact semantics

Properties: `days` (always|sun|mon|tue|wed|thu|fri|sat, comma-separated; Default: always), `interval` (time; Default: 0s — 'When set to zero, the script runs only once at the start time'), `name`, `on-event` (script to execute), `policy` (ftp|reboot|read|write|policy|test|password|sniff|sensitive|romon), `start-date` (date), `start-time` (time or the literal `startup`), and read-only `run-count` and `next-run`. Exact `startup` semantics, verbatim: 'If a scheduler item has start-time set to startup, it behaves as if start-time and start-date were set to a time 3 seconds after console starts up.


**Versions.** `days` was added to the scheduler in 7.24 ('console - added "days" to scheduler') — do not emit `days=` in a scheduler entry destined for a device below 7.24. 7.10 'scheduler - fixed incorrectly started scheduler during reboot or shutdown'.


```routeros
/system/scheduler/add name=dunmir-heartbeat interval=5m on-event=heartbeat policy=read,write,test,ftp
/system/scheduler/add name=dunmir-boot start-time=startup interval=0 on-event=register policy=read,write,test,ftp
/system/scheduler/print detail
```


**Danger.** `start-time=startup` with a non-zero `interval` does NOT run at boot — the documented behaviour is that it will not run at startup at all. A boot-time registration and a periodic heartbeat therefore need TWO scheduler entries, not one.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/scheduler/


### Scheduler permission inheritance: three call forms, two of which fail

Documented experiment, with a full-permission user and a script whose `policy=""`: - `/system/script/run add-dhcp-no-perms use-script-permissions` → `not enough permissions (9)`. - `/system/script/run add-dhcp-no-perms` (as the user) → succeeds, inheriting the caller. From a scheduler, three forms behave differently: - `on-event="...run <script> use-script-permissions"` → FAILS (uses the script's own empty policy).


**Versions.** `use-script-permissions` became available from the CLI in 7.15; 7.15 also changed WinBox/WebFig to 'use user permissions when running scripts', so the same script can behave differently depending on which UI started it across that boundary.


```routeros
/system/scheduler/add name=hb interval=5m on-event="/system script run heartbeat" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon
/log/print where topics~"script"
```


**Danger.** Writing `on-event=heartbeat` (the bare script name) is the intuitive form and it is the one that silently fails on policy. The working form is `on-event="/system script run heartbeat"`.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### :log — the only reliable output channel for an unattended script

`:log <topic> <message>` writes to the system log; the manual lists the available topics as `debug`, `error`, `info` and `warning`. Example: `:log info "Hello from script"`. Background scripts have no terminal: `:execute`'s documentation says 'The result can be written in the file by setting a file parameter or printed to the CLI by setting as-string', i.e. output is not delivered anywhere unless you ask for it, and `/console/settings log-script-errors` is documented as 'write background script failures to log'. Every scheduler example in the official documentation uses `:log`, never `:put`.


**Versions.** 7.13 'log - added "fetch" topic' — from 7.13 you can subscribe to fetch-specific logging. 7.13 also added 'raw logging' to fetch, and 7.14.3/7.15 fixed 'slow throughput due to "raw" logging which occurred even when not listening to the topic (introduced in v7.…


```routeros
:log info "heartbeat sent";
:log error ("fetch failed: " . $err);
/console/settings/set log-script-errors=yes
```


**Danger.** Do not build a debugging story around `:put` for anything the scheduler runs — you will see nothing and conclude the script never ran. Use `:log`.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### monitor commands need once= and do={} — there is no as-value or get

Interactive `monitor` commands run indefinitely until a user interrupts them, which a script cannot do. The documented approach, verbatim: 'run them with the once parameter, which executes the command a single time and then stops. Another issue is retrieving the returned variables: there is no as-value and no get, but there is do. It allows you to access variables returned by the command.' Working example: `/interface/monitor-traffic ether1 once do={:global myBps $"rx-bits-per-second" }` then `:environment print` shows `myBps=71464`.


**Versions.** 6.43 'made "once" parameter mandatory when using "as-value" on "monitor" commands'. 6.48 'allow "once" parameter for bonding monitoring'. 7.19 'console - added proplist to monitor command'.


```routeros
/interface/monitor-traffic ether1 once do={:global myBps $"rx-bits-per-second"}
/interface/ethernet/monitor ether1 once do={:global lnk $"status"}
/system/resource/monitor once do={:global cpu $"cpu-used"}
```


**Danger.** A `monitor` without `once` from a script never returns. It becomes a permanent background job holding a console slot, and a scheduler that starts one every interval will exhaust the console service. Always `once`, and always inside `do={}`.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/scripting-tips-and-tricks/


### Writing a script that survives a missing or disabled package

`/system/package` is read-only in the running system and exposes `name`, `version`, `build-time`, `scheduled`, `bundle` and `size`, with flags `X - disabled` and `A - available`; its own note says 'Commands executed in this menu will take place only on the restart of the router.' The portable guard is therefore a `find` count before you touch the feature's menu: `:if ([:len [/system/package/find where name="wifi-qcom" disabled=no]] > 0) do={ ...


**Versions.** 7.13 'console - resolve "wifiwave2" directory to "wifi"' — a script written for `/interface/wifiwave2` still resolves on 7.13+, but a script written for `/interface/wifi` does not work on releases before that rename.


```routeros
:if ([:len [/system/package/find where name="wifi-qcom" disabled=no]] > 0) do={ :log info "wifi present" }
/system/package/print
:put [/system/resource/get version];
```


**Danger.** Do not use `:parse` on a string that mixes in remote data just to make it version-portable — that reintroduces the remote-code-execution problem.


Source: https://manual.mikrotik.com/docs/cli-reference/system/package/


### Date and time handling and its traps

`/system/clock` exposes `time` (HH:MM:SS), `date` (YYYY-MM-DD, year range 1970..2037), `time-zone-autodetect` (bool, Default: yes), `time-zone-name`, and read-only `gmt-offset` and `dst-active`. Key facts: 'Startup date and time is 1970-01-02 00:00:00 [+|-]gmt-offset.' 'Local time cannot be exported and is not stored with the rest of the configuration.' Time-zone autodetect uses the public IP and MikroTik's cloud (`cloud2.mikrotik.com`). And: 'the router's internal CPU clock is not a reliable time source for precise timing operations'.


**Versions.** 7.10 'console - changed time format according to ISO standard' — dates print as `2010-06-01 11:59:51` on 7.10+ and as `jun/01/2010 11:59:51` before. Any string parsing of a printed date breaks across 7.10.


```routeros
:put [:timestamp];
:put [:timestamp use-tz];
:put ([:tonsec [:timestamp]] / 1000000000);
```


**Danger.** THREE traps. (1) Before NTP sync the clock reads 1970-01-02, so `check-certificate=yes` fails 'not yet valid' and every timestamp you send is wrong — gate the agent's first report on `[/system/clock/get date] != "1970-01-02"`.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/clock/


### Functions: globals are invisible inside them, and nested calls must be declared

Functions are globals with a `do={...}` body: `:global myFunc do={:put "hello"}`, called as `$myFunc` or `[$myFunc a=1]`. Arguments are either named (`$a`) or positional (`$1`, `$2`, ... in call order). `:return` returns a value. TWO documented traps: 1) A global is NOT visible inside a function body. `:global myVar "test"; :global myFunc do={ :put "global var=$myVar" }; [$myFunc]` prints `global var=` (empty). You must re-declare it inside: `:global myFunc do={ :global myVar; :put "global var=$myVar" }`.


**Versions.** The `:global name do={}` function syntax was introduced in v6.2 ('Starting from v6.2 new syntax is added to easier define such functions and even pass parameters'). Before that only the `[:parse ...]` workaround existed.


```routeros
:global myFunc do={ :global myVar; :return ($myVar . $a) }
:put [$myFunc a="x"];
:global funcB do={ :global funcA; :return ([$funcA] + 4) }
```


**Danger.** Because functions live in the per-user global environment, they vanish on reboot and are not part of the exported configuration. An agent that defines helper functions at the top of a script and calls them later in the SAME script is fine; one that defines the…


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/scripting-tips-and-tricks/


### Reserved variable names collide with menu properties and silently break where clauses

Verbatim: 'All built-in RouterOS properties are reserved variables. Variables defined with the same names as RouterOS built-in properties can cause errors.' Documented failing example: `{ :local type "ether1"; /interface print where name=$type; }` does not work, while `{ :local customname "ether1"; /interface print where name=$customname; }` does. Same for `:global "dst-address" "0.0.0.0/0"; /ip route print where dst-address=$"dst-address"` — the where clause compares the property to itself and matches everything. Rule: prefix every variable in agent code (e.g.


```routeros
:local dmIfName "ether1"; /interface/print where name=$dmIfName
```


**Danger.** This does not error — it returns the WRONG rows. `/ip/route/remove [find where dst-address=$"dst-address"]` with a colliding name matches every route.


> **Review correction.** All three passages are on the main scripting page, https://manual.mikrotik.com/docs/developer-guides/scripting/ — the 'Reserved variable names' section with the `{ :local type "ether1"; /interface print where name=$type; }` vs `customname` example; the relational-operators section with `/interface/print where (name~"ether")=false` (and th…


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/scripting-tips-and-tricks/


### Parsing gotchas: whitespace, division, comments, line joining, escapes

- Whitespace is FORBIDDEN before `=` in `<parameter>=` and in `from=`, `to=`, `step=`, `in=`, `do=`, `else=`. `/ip route add gateway = 3.3.3.3` is invalid; `gateway=3.3.3.3` is valid. - Division needs braces or spaces so the expression is not read as an IP address: `:put (10 / 2)` or `:put ((10)/2)`. - Comments start with `#` and run to end of physical line; RouterOS has NO multiline comments; a `#` inside a string is not a comment.


**Versions.** 6.40.7 / 6.41.3 'console - do not allow variables that start with digit to be referenced without "$" sign'. 7.19 'console - disallow incomplete double-quoted arguments (allows multiline string pasting)'.


```routeros
:put ( "value is " . (4+5) );
:put " We have $[ :len [/ip route find] ] routes";
:put "\48\45\4C\4C\4F";
```


**Danger.** When you generate RouterOS script text from a server, the double-escaping is the usual source of production breakage: a JSON body embedded in `http-data="..."` inside a `source="..."` inside an API call needs three levels of quote escaping.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### Reading global variables set by another script, and /system/script/environment

A second script does not automatically see globals from the first. The documented pattern is to re-declare with no value: script1: `:global myVar "hello!"` script2: `:global myVar; :log info "value is: $myVar"` Without the bare `:global myVar;` line, script2 sees nothing. Globals live in `/system/script/environment` (readable via `:environment print`, or `/system/script/environment/print` which lists `name` and `value`). 'You can use /system script environment remove to delete unused variables; however, the preferred method is to unset the variable' with `:set myVar` (no value).


**Versions.** 6.47.10 / 6.48.3 'console - do not clear environment values if any global variable is set'. 7.18 'console - fixed issue with disappearing global variable'. Globals do not survive a reboot.


```routeros
:global dmToken;
/system/script/environment/print
:set dmToken;
```


**Danger.** Do not store a bearer token or device secret in a global — `/system/script/environment/print` exposes it to any user with the right policies, it is not covered by the `sensitive` hiding applied to config properties, and it is lost on reboot anyway.


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/scripting-tips-and-tricks/


### print parameters in full (what a collector can ask for)

`as-value` (output as an array of parameters and values), `where <expr>` (filter), `count-only`, `brief`, `detail`, `terse` ('Show details in a compact and machine-friendly format'), `value-list` ('Data is displayed in a table, where parameters are split by lines and available items are split by columns (can be used for parsing purposes)'), `file=` (write output to a file), `follow` (print current entries and track new ones until Ctrl-C), `follow-only` (only new entries), `from=` (only a specified item), `interval=` (continuously reprint), `without-paging`, `append`, `about` (entries carrying an `about` field, e.…


**Versions.** `group-by` added 7.17 (with an id-printing bug fixed in 7.20.1). `order-by` added 7.24. `proplist` on interactive commands added 7.15; on monitor commands 7.19. `about` filters for find/print-where added 7.16. `follow-strict` REMOVED in 7.16.


```routeros
/interface/print as-value proplist=name,type,running
/ip/route/print count-only as-value where dst-address="0.0.0.0/0"
/interface/print order-by=-link-downs proplist=name,link-downs
```


**Danger.** `follow` and `interval` never terminate. Using either from a scheduled script creates a permanent job, exactly like `monitor` without `once`. For collection always use a plain `print as-value` with an explicit `proplist=`; the proplist also freezes the schema…


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### Reading a fetched body back out of a file when it exceeds the variable cap

`/file` items expose `name`, `type` (file|directory), `contents` ('The actual content of the file. File size limit is 60 KB.'), plus read-only `size`, `last-modified`, and package metadata fields. Documented fetch-to-variable idiom for uploading a file body: `:global data [/file/get [/file/find name=export.rsc] contents];` then `/tool/fetch mode=https http-method=put http-data=$data url=$url`.


**Versions.** 'console - added "read" command under "file" menu' = 7.13. 'console - added option to create new files using "/file add" command (CLI only)' = 7.9. File content limit raised to 60 KB in 7.14.


```routeros
:global data [/file/get [/file/find name=export.rsc] contents];
/file/read file=big.json chunk-size=32768 offset=0
/file/print as-value where name="backup.backup"
```


**Danger.** Never assume `/file/get ... contents` returned the whole file. Compare `[:len $data]` against `[/file/get [find name=$f] size]` before you upload; a truncated backup that uploads with a 200 OK is the worst possible failure for this product.


Source: https://manual.mikrotik.com/docs/cli-reference/file/


### Fetch upload, SFTP and FTP specifics

`upload=yes` works only in FTP and SFTP modes and 'Requires src-path and dst-path parameters to be set'. `ascii=yes` applies only to FTP and TFTP. Documented FTP download and upload: `/tool/fetch address=192.168.88.2 src-path=conf.rsc user=admin mode=ftp password=123 dst-path=123.rsc port=21 host="" keep-result=yes` `/tool/fetch address=192.168.88.2 src-path=conf.rsc user=admin mode=ftp password=123 dst-path=123.rsc upload=yes` SFTP over a VRF must use the `address=@vrf` form, not the URL form: 'url="http://192.168.88.2@vrf1/..." - will not work for SFTP'; the documented working call is `/tool/fetch url="sftp://1…


**Versions.** SFTP support added in 6.45.1. 6.46.7/6.47.2 'fetch - show status "uploaded" instead of "downloaded" when uploading a file' — on older releases the status field is misleading for uploads. 6.46.8/6.47.4 'fixed "src-address" usage for SFTP'.


```routeros
/tool/fetch url="sftp://backup.example.com" src-path=backup.backup dst-path=/upload/backup.backup user=$u password=$p upload=yes
/tool/fetch address=192.168.88.2 src-path=conf.rsc user=admin mode=ftp password=123 dst-path=123.rsc upload=yes
```


**Danger.** On RouterOS < 7.19 an FTP upload could report success when it had not succeeded ('fixed false successful messages in FTP mode'). Do not treat `status=finished` from an FTP upload on older firmware as proof of delivery — verify server-side.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/fetch/


### Fetch timeouts and how to bound a hung transfer

`idle-timeout` (time 1..604800 seconds, or the literal `none`; Default: 10s) is the 'Idle timeout since last read/write action' — it bounds silence, not total duration. `duration` (time) on the frozen documentation is 'Time how long fetch should run', i.e. a wall-clock cap. Together these are the only built-in bounds; there is no separate connect timeout parameter.


**Versions.** `idle-timeout` added in 7.15. 7.23 'fetch - fixed non-working idle-timeout in some cases' — the parameter was unreliable between 7.15 and 7.22. 7.11 'fetch - improved timeout detection'. On RouterOS 6 and 7.0–7.14 there is no `idle-timeout` at all.


```routeros
/tool/fetch url=$u idle-timeout=10s output=user as-value
/tool/fetch url=$u duration=30s output=user as-value
```


**Danger.** A slowloris-ish server that dribbles a byte every 9 seconds keeps the fetch alive indefinitely under the default 10s idle timeout. Set BOTH `idle-timeout` and a wall-clock bound, and make the scheduler interval comfortably longer than that bound, or overlappin…


> **Review correction.** Treat `duration` as read-only output, not an input bound. `idle-timeout` (1..604800 or `none`, default 10s, 7.15+) is the only documented settable bound on current RouterOS. This is not a harmless extra argument: 7.23 'console - treat non-existent command parameters as runtime errors' and 7.24 'console - produce runtime errors for bad com…


Source: https://manual.mikrotik.com/docs/cli-reference/tool/fetch/


### RouterOS 6 vs RouterOS 7: what simply does not exist in v6

The RouterOS 6 console command set is: `:global :local :beep :delay :put :len :typeof :pick :log :time :set :find :environment :terminal :error :execute :parse :resolve :toarray :tobool :toid :toip :toip6 :tonum :tostr :totime`, plus `:if`, `:for`, `:foreach`, `:while`, `:do..while` and `do={}/on-error={}`. NOT present in RouterOS 6 (each was added in the release named): `:retry` (7.4), `:convert` (7.11), `:jobname` (7.12), `:tonsec` (7.12), `:grep` (7.13), `:onerror` (7.13), `:serialize` / `:deserialize` (7.13), `:tolf` / `:tocrlf` (7.14), `:lock` (7.16), `:range` (7.17), `:break` / `:continue` / `:exit` (7.22).…


**Versions.** Every 'added in' claim above is from the corresponding https://download.mikrotik.com/routeros/<version>/CHANGELOG entry under the `console` or `fetch` component.


```routeros
:global v [/system/resource/get version];
:if ([:pick $v 0 1] = "6") do={ ... } else={ ... }
```


**Danger.** A single script cannot use v7-only commands and still load on v6 — the failure is at parse time, so the script does not run at all rather than degrading.


> **Review correction.** The archived RouterOS 6 scripting manual carries an explicit note: "Variable value size is limited to 4096bytes". So on RouterOS 6 a fetch response read via `output=user` is bounded at ~4 KB, not 64 KB, regardless of what the fetch documentation says.


Source: https://web.archive.org/web/20190301000000/https://wiki.mikrotik.com/wiki/Manual:Scripting


### Changelog-documented scripting bugs an agent must route around

Concrete regressions with releases: - 7.13: fetch required `content-length` for HTTP; fixed in 7.13.1 and 7.14 ('do not require "content-length" for HTTP (introduced in v7.13)'). A chunked-encoding server breaks fetch on 7.13.0. - 7.13–7.14.2: fetch throughput degraded by raw logging that ran even when nobody listened to the topic; fixed 7.14.3/7.15. - 7.13: `src-path` broken with HTTP/HTTPS (fixed 7.13.1/7.14) and with SFTP (fixed 7.13.3/7.14); AAAA-only domains failed to resolve (fixed 7.13.1). - 7.14.0: do/while broken with variables; fixed 7.14.1/7.15.


**Versions.** Individual entries are in https://download.mikrotik.com/routeros/7.13.1/CHANGELOG , /7.13.3 , /7.14 , /7.14.1 , /7.14.3 , /7.15 , /7.17 , /7.18.1 , /7.18.2 , /7.19 , /7.20.1 , /7.20.6 , /7.24.1 , /7.24.2


```routeros
:put [/system/resource/get version];
/system/package/update/check-for-updates
```


**Danger.** Treat 7.13.0, 7.14.0, 7.18.0, 7.20.0 and 7.24.0 as known-bad for a fetch-based agent and require at least the first patch release of each line. Publish a minimum-supported-version check in the agent and log loudly rather than silently misbehaving on a known-br…


Source: https://download.mikrotik.com/routeros/7.14/CHANGELOG


### Safe heartbeat skeleton (composite of the verified rules)

Every element below is drawn from a documented rule elsewhere in this reference: one `{ }` block so locals survive across lines; a version guard; a clock guard before TLS validation; `check-certificate=yes`; zero redirects; both `as-value` and `output=user`; `:onerror` with the two-variable form; `:log` rather than `:put`; `:deserialize` with `json.no-string-conversion` rather than `:parse`; and a `nil` check on the decoded value.


**Versions.** This skeleton requires 7.22+ for the `:onerror err,attr` two-variable form with fetch attributes, 7.18+ for `http-max-redirect-count`, 7.17+ for `json.no-string-conversion`, 7.15+ for `idle-timeout`, and 7.13+ for `:onerror` and `:deserialize`.


```routeros
/system/script/add name=dunmir-heartbeat policy=read,write,test,ftp dont-require-permissions=no source="..."
/system/scheduler/add name=dunmir-heartbeat interval=5m on-event="/system script run dunmir-heartbeat" policy=read,write,test,ftp
```


**Danger.** Note the scheduler `on-event` uses the `"/system script run <name>"` form, not the bare script name — the bare name runs with the script's own (empty) policy and silently fails.


> **Review correction.** Move identity resolution inside the guarded region, or gate it: `:if ([/system/routerboard/get routerboard] = true) do={ ... } else={ ... }`, falling back to `/system/license get system-id`, `/system/identity get name`, or a provisioned identifier stored in the script source.


Source: https://manual.mikrotik.com/docs/system-information-and-utilities/fetch/


### Sending data with :serialize straight from print as-value (inventory collection)

The documented one-liner for turning a list menu into a flat table is `:serialize` with `dsv.remap`, which 'merges array of dictionaries into a single dictionary (useful when working with "print as-value")': ``` :put [:serialize to=dsv options=dsv.remap delimiter="#" [/ip/address/print as-value]] .id#address#comment#interface#network *1#192.168.88.1/24#defconf#bridge#192.168.88.0 *2#192.168.69.190/24##ether1#192.168.69.0 ``` For JSON, feed the 2-D as-value array directly to `:serialize to=json options=json.no-string-conversion` and post it.


**Versions.** `dsv.remap` and `file-name` added in 7.18; DSV format added in 7.16; `json.no-string-conversion` added in 7.17. On 7.13–7.15 only plain JSON serialize/deserialize exists. Sources: https://download.mikrotik.com/routeros/7.16/CHANGELOG , /7.17 , /7.18


```routeros
:put [:serialize to=json options=json.no-string-conversion [/ip/address/print as-value proplist=address,interface,network]];
:serialize to=json file-name=inventory.json value=[/interface/print as-value];
:put [:serialize to=dsv options=dsv.remap delimiter="#" [/ip/address/print as-value]];
```


**Danger.** Always pair this with an explicit `proplist=`. Without one, the serialized payload changes shape on upgrade (7.20 added flags to as-value output, 7.21 removed sensitive fields), and a server-side schema validator will start rejecting every device that upgrades…


Source: https://manual.mikrotik.com/docs/developer-guides/scripting/


### Could not verify

The exact default value of /tool fetch http-max-redirect-count between 7.18 (when it was introduced) and 7.21. The 7.22 CHANGELOG says only 'increased default maximum redirect count to 2'; the prior default is not stated in any MikroTik source I found. Set the parameter explicitly rather than relying on the default on 7.18-7.21. An explicit official statement that :put output from a script run by /system/scheduler is discarded. The claim is inferred from two documented facts: :execute's note that a background script's result must be captured with file= or as-string, and /console/settings log-script-errors being described as 'write background script failures to log'.
