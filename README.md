
# Datadog DHCP Monitor

<div align="center">

<img src="https://media.licdn.com/dms/image/v2/C510BAQEaNQXhD4EVaQ/company-logo_200_200/company-logo_200_200/0/1631395395675/zoos_logo?e=2147483647&v=beta&t=OR7jdri2KV5dJZuY7I8bt0U5wOFT6-ElaMb_0Kydvj8" alt="Zoos Global" width="90" height="90"/>

<br/>

![Version](https://img.shields.io/badge/version-1.0.0-blue?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-Windows%20Server-0078D4?style=for-the-badge&logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Datadog](https://img.shields.io/badge/Datadog-DogStatsD-632CA6?style=for-the-badge&logo=datadog&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)
![Status](https://img.shields.io/badge/status-Production%20Ready-brightgreen?style=for-the-badge)

<br/>

**PowerShell → Windows DHCP Server → DogStatsD → Datadog Metrics → Dashboards & Alerts**

*Monitors IPv4 & IPv6 DHCP server health, scope utilization, traffic counters, and failover metrics via a single lightweight PowerShell script submitted every minute to Datadog.*

<br/>

![Metrics](https://img.shields.io/badge/metrics-35%20per%20run-blue?style=flat-square)
![Unique](https://img.shields.io/badge/unique%20metric%20names-26-blue?style=flat-square)
![Runs](https://img.shields.io/badge/runs%2Fday-1440-blue?style=flat-square)
![Coverage](https://img.shields.io/badge/coverage-IPv4%20%2B%20IPv6-blue?style=flat-square)

</div>

---

## 📁 Directory Structure

```text
C:\Scripts\
└── dhcp-metrics.ps1       # Main metric collection & submission script
```

---

## 📊 Metrics Reference

### `dhcp.server.*` — Server Level

> Tags: `version:v4` / `version:v6`

| Metric | Description |
|--------|-------------|
| `dhcp.server.total_addresses` | Total IP addresses across all scopes |
| `dhcp.server.addresses_in_use` | Currently leased addresses |
| `dhcp.server.addresses_free` | Available addresses *(calculated)* |
| `dhcp.server.pending_offers` | Offers awaiting client confirmation |
| `dhcp.server.percent_in_use` | Overall pool utilization % |
| `dhcp.server.percent_available` | Overall pool available % |
| `dhcp.server.total_scopes` | Total number of scopes on server |
| `dhcp.server.discovers` | DHCPDISCOVER (v4) / Solicits (v6) received |
| `dhcp.server.offers` | DHCPOFFER (v4) / Advertises (v6) sent |
| `dhcp.server.requests` | DHCPREQUEST messages received |
| `dhcp.server.acks` | DHCPACK (v4) / Replies (v6) sent |
| `dhcp.server.naks` | DHCPNAK messages — high value = IP conflicts ⚠️ |
| `dhcp.server.declines` | DHCPDECLINE messages — high value = address conflicts ⚠️ |
| `dhcp.server.releases` | DHCPRELEASE messages received |
| `dhcp.server.delayed_offers` | Delayed DHCPOFFER messages sent |
| `dhcp.server.uptime_seconds` | Seconds since DHCP service started |

### `dhcp.scope.*` — Scope Level

> Tags: `scope`, `scopename`, `subnetmask`, `version`, `superscope` *(if applicable)*

| Metric | Description |
|--------|-------------|
| `dhcp.scope.total_addresses` | Total IPs in scope *(calculated: free + in_use)* |
| `dhcp.scope.addresses_free` | Free IPs in scope *(IPv4 only)* |
| `dhcp.scope.addresses_in_use` | Leased IPs in scope |
| `dhcp.scope.percent_in_use` | Scope utilization % — **primary alert metric** 🎯 |
| `dhcp.scope.pending_offers` | Pending unconfirmed offers in scope |
| `dhcp.scope.reserved_address` | Static reservation count |
| `dhcp.scope.free_this_server` | Failover: free addresses on this node |
| `dhcp.scope.free_partner_server` | Failover: free addresses on partner node |
| `dhcp.scope.inuse_this_server` | Failover: leases held by this node |
| `dhcp.scope.inuse_partner_server` | Failover: leases held by partner node |

> **⚠️ IPv6 Note:** `total_addresses` and `addresses_free` are intentionally **skipped** for IPv6 scopes.  
> A `/64` prefix = 2^64 addresses → overflows `UInt64` → meaningless for capacity monitoring.  
> IPv6 tracks: `addresses_in_use`, `percent_in_use`, `pending_offers`, `reserved_address` only.

---

## ⚙️ System Requirements

| Requirement | Version |
|-------------|---------|
| Windows Server | 2019 / 2022 / 2025 |
| DHCP Server Role | Installed & Running |
| Datadog Agent | v7+ (DogStatsD on `127.0.0.1:8125`) |
| PowerShell | 5.1+ |
| Privileges | Admin / SYSTEM |

---

## 1️⃣ Install Datadog Agent

```powershell
# Download installer
Invoke-WebRequest -Uri "https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi" `
                  -OutFile "C:\ddagent.msi"

# Install with your API key
Start-Process -Wait msiexec -ArgumentList '/qn /i C:\ddagent.msi APIKEY="<your_api_key>"'
```

**Verify Agent is running:**

```powershell
Get-Service -Name "datadog-agent"
# Expected: Status = Running
```

**Verify DogStatsD is listening:**

```powershell
netstat -an | findstr 8125
# Expected: UDP    127.0.0.1:8125    *:*
```

---

## 2️⃣ Deploy the Script

```powershell
New-Item -ItemType Directory -Path "C:\Scripts" -Force
Copy-Item dhcp-metrics.ps1 C:\Scripts\dhcp-metrics.ps1
```

---

## 3️⃣ Manual Validation (MANDATORY)

> Always test manually **before** scheduling.

```powershell
cd C:\Scripts
.\dhcp-metrics.ps1
```

**Expected output:**

```text
Sent: dhcp.server.total_addresses:254      | Tags: version:v4
Sent: dhcp.server.addresses_in_use:0       | Tags: version:v4
Sent: dhcp.server.addresses_free:254       | Tags: version:v4
Sent: dhcp.server.pending_offers:0         | Tags: version:v4
Sent: dhcp.server.percent_in_use:0         | Tags: version:v4
Sent: dhcp.server.percent_available:100    | Tags: version:v4
Sent: dhcp.server.total_scopes:1           | Tags: version:v4
Sent: dhcp.server.discovers:0              | Tags: version:v4
Sent: dhcp.server.offers:0                 | Tags: version:v4
Sent: dhcp.server.requests:0               | Tags: version:v4
Sent: dhcp.server.acks:0                   | Tags: version:v4
Sent: dhcp.server.naks:0                   | Tags: version:v4
Sent: dhcp.server.declines:0               | Tags: version:v4
Sent: dhcp.server.releases:0               | Tags: version:v4
Sent: dhcp.server.delayed_offers:0         | Tags: version:v4
Sent: dhcp.server.uptime_seconds:5492      | Tags: version:v4
Sent: dhcp.scope.total_addresses:254       | Tags: scope:192.168.1.0,scopename:Office,subnetmask:255.255.255.0,version:v4
...
Done! Check Datadog Metrics Explorer for dhcp.*
```

**Verify in Datadog:**  
Metrics → Explorer → search `dhcp.scope.percent_in_use`

---

## 4️⃣ Windows Task Scheduler Setup

### Command Line

```cmd
schtasks /create /tn "DHCP-Datadog-Metrics" /sc minute /mo 1 /st 00:00 ^
  /tr "powershell.exe -NonInteractive -ExecutionPolicy Bypass -File C:\Scripts\dhcp-metrics.ps1" ^
  /ru SYSTEM /rl HIGHEST /f
```

### PowerShell Method

<details>
<summary>Click to expand</summary>

```powershell
$action  = New-ScheduledTaskAction -Execute "PowerShell.exe" `
           -Argument "-NonInteractive -ExecutionPolicy Bypass -File C:\Scripts\dhcp-metrics.ps1"
$trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 1) `
           -Once -At (Get-Date)
Register-ScheduledTask -TaskName "DHCP-Datadog-Metrics" `
           -Action $action -Trigger $trigger -RunLevel Highest
```

</details>

---

## 5️⃣ Execution Timeline

```text
00:00 → dhcp-metrics.ps1 runs
  ├── IPv4 server stats     → 16 metrics
  ├── IPv4 scope stats      → 10 metrics per scope
  ├── IPv6 server stats     → 6 metrics
  └── IPv6 scope stats      → 4 metrics per scope

00:01 → Repeats
00:02 → Repeats
...
1,440 runs/day
```

---

## 6️⃣ Datadog Monitor — Scope Exhaustion

```text
Query  : max:dhcp.scope.percent_in_use{version:v4} by {scopename}
Warning: > 70
Alert  : > 80
Message: DHCP scope {{scopename.name}} is {{value}}% utilized — free IPs may run out soon.
```

---

## 7️⃣ Datadog Dashboard Queries

| Widget | Query |
|--------|-------|
| Scope utilization % | `avg:dhcp.scope.percent_in_use{version:v4} by {scopename}` |
| Free addresses per scope | `avg:dhcp.scope.addresses_free{version:v4} by {scopename}` |
| Server NAKs | `avg:dhcp.server.naks{version:v4}` |
| Server Declines | `avg:dhcp.server.declines{version:v4}` |
| Server uptime | `avg:dhcp.server.uptime_seconds{*} by {version}` |
| IPv6 active leases | `avg:dhcp.scope.addresses_in_use{version:v6} by {scopename}` |

---

## 🛡️ Production Features

| Feature | Status |
|---------|--------|
| IPv4 server & scope metrics | ✅ |
| IPv4 failover metrics | ✅ |
| IPv6 server metrics | ✅ |
| IPv6 scope & reservation metrics | ✅ |
| Null / empty → 0 conversion | ✅ |
| IPv6 overflow protection | ✅ |
| Per-scope error handling | ✅ |
| Superscope auto-tagging | ✅ |
| SYSTEM scheduler compatible | ✅ |
| DogStatsD UDP submission | ✅ |

---

## ✅ Production Checklist

- [ ] Datadog Agent installed and running
- [ ] DogStatsD listening on `127.0.0.1:8125`
- [ ] Script deployed to `C:\Scripts\dhcp-metrics.ps1`
- [ ] Script validated manually
- [ ] Metrics visible in Datadog Metrics Explorer
- [ ] Task Scheduler task created
- [ ] Scope exhaustion monitor created
- [ ] Dashboard created

---

## 🚨 Troubleshooting

| Issue | Fix |
|-------|-----|
| Metrics not appearing | Verify `netstat -an \| findstr 8125` |
| `1` printed at top | Use `$null = $udpClient.Connect(...)` |
| Blank values | Convert null/empty to `0` |
| IPv6 `1.8e19` | Stale data from old version |
| Cmdlets not found | Install DHCP tools / role |

---

## 👤 Author

| | |
|--|--|
| **Name** | Shivam Anand |
| **Title** | Sr. DevOps Engineer \| Engineering |
| **Organisation** | Zoos Global |
| **Email** | shivam.anand@zoosglobal.com |
| **Web** | [www.zoosglobal.com](https://www.zoosglobal.com) |
| **Address** | Violena, Pali Hill, Bandra West, Mumbai - 400050 |

---

<div align="center">

**Version 1.0.0 · Last Updated: April 01, 2026**
© 2026 Zoos Global · <a href="LICENSE">MIT License</a>

</div>