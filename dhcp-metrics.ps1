# ==============================================================================
#
#   ███████╗ ██████╗  ██████╗███████╗     ██████╗ ██╗      ██████╗ ██████╗  █████╗ ██╗
#   ╚══███╔╝██╔═══██╗██╔═══██╗██╔════╝    ██╔════╝ ██║     ██╔═══██╗██╔══██╗██╔══██╗██║
#     ███╔╝ ██║   ██║██║   ██║███████╗    ██║  ███╗██║     ██║   ██║██████╔╝███████║██║
#    ███╔╝  ██║   ██║██║   ██║╚════██║    ██║   ██║██║     ██║   ██║██╔══██╗██╔══██║██║
#   ███████╗╚██████╔╝╚██████╔╝███████║    ╚██████╔╝███████╗╚██████╔╝██████╔╝██║  ██║███████╗
#   ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝     ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝
#
# ==============================================================================
#  Script    : DHCP Services Health - Datadog Metrics Submission
#  Version   : 2.0.0
#  Purpose   : Collects IPv4 & IPv6 DHCP server/scope metrics and submits
#              them to the local Datadog Agent via DogStatsD (UDP 8125)
#  Schedule  : Every 1 minute via Windows Task Scheduler
#  Namespaces: zg.dhcp.server.* | zg.dhcp.scope.*
# ------------------------------------------------------------------------------
#  CHANGE LOG:
#  v2.0.0  2026-05-14  Renamed all metrics to zg.dhcp.* namespace to align with
#                      commercial integration naming conventions (rapdev.*, etc.)
#                      and avoid conflicts with any built-in Datadog dhcp.* metrics.
#                      Added server_role tag (primary / secondary / standalone / loadbalance)
#                      via Get-DhcpServerv4Failover — fixes scope utilization alerts
#                      firing on secondary servers (reported by Shobhit Gupta).
#                      Datadog scope monitors should now filter on server_role:primary.
#  v1.0.0  Initial release
# ------------------------------------------------------------------------------
#  Author    : Shivam Anand
#  Title     : Sr. DevOps Engineer | Engineering
#  Org       : Zoos Global
#  Email     : shivam.anand@zoosglobal.com
#  Web       : www.zoosglobal.com
#  Address   : Violena, Pali Hill, Bandra West, Mumbai - 400050
# ------------------------------------------------------------------------------
#  Platform  : Windows Server 2019 / 2022 / 2025
#  Requires  : Datadog Agent  (DogStatsD listening on 127.0.0.1:8125)
#              DHCP Server Role (for PowerShell cmdlet availability)
#              PowerShell 5.1+
# ==============================================================================

$dogstatsdHost   = "127.0.0.1"
$dogstatsdPort   = 8125
$METRIC_PREFIX   = "zg.dhcp"
$INTEGRATION     = "zg_dhcp_monitor"
$VERSION         = "2.0.0"

$udpClient = New-Object System.Net.Sockets.UdpClient
$null = $udpClient.Connect($dogstatsdHost, $dogstatsdPort)

# ==============================================================================
# Helper : Send-Metric
# Sends a DogStatsD gauge metric over UDP to the local Datadog Agent.
# Converts null/empty to 0 so Datadog never shows gaps in dashboards/monitors.
# ==============================================================================
function Send-Metric($name, $value, $tags) {
    if ($null -eq $value -or "$value".Trim() -eq "") { $value = 0 }
    $tagStr = $tags -join ","
    $msg = [System.Text.Encoding]::UTF8.GetBytes("${name}:${value}|g|#${tagStr}")
    $udpClient.Send($msg, $msg.Length) | Out-Null
    Write-Host "Sent: ${name}:${value} | Tags: ${tagStr}"
}

# ==============================================================================
# SECTION 0 : Detect Failover Role
# Cmdlet    : Get-DhcpServerv4Failover
# Purpose   : Tags all scope metrics with server_role so Datadog monitors
#             can be scoped to primary only — resolves dual-alert issue.
#
# server_role values:
#   primary      — HotStandby mode, this server is the active node
#   secondary    — HotStandby mode, this server is the standby node
#   loadbalance  — LoadBalance mode (both nodes are peers; no single primary)
#   standalone   — No failover relationship configured
#
# FIX : Update Datadog scope utilization monitor query to:
#       avg:zg.dhcp.scope.percent_in_use{server_role:primary} by {scope,scopename}
# ==============================================================================
$serverRole = "standalone"

try {
    $failover = Get-DhcpServerv4Failover -ErrorAction Stop | Select-Object -First 1
    if ($failover) {
        $mode = $failover.Mode.ToString()
        if ($mode -eq "HotStandby") {
            $serverRole = $failover.ServerRole.ToString().ToLower()  # "primary" or "secondary"
        } elseif ($mode -eq "LoadBalance") {
            $serverRole = "loadbalance"
        }
    }
} catch {
    Write-Warning "[$INTEGRATION] Could not determine failover role. Defaulting to 'standalone': $_"
}

Write-Host "[$INTEGRATION] Server role detected: $serverRole"

# Base tags applied to every metric emitted by this script
$baseTags = @(
    "host:$($env:COMPUTERNAME)",
    "integration:$INTEGRATION",
    "integration_version:$VERSION",
    "server_role:$serverRole"
)

# ==============================================================================
# SECTION 1 : IPv4 - Server Level Statistics
# Cmdlet    : Get-DhcpServerv4Statistics
# Tags      : version:v4, server_role
# ==============================================================================
try {
    $v4Stats = Get-DhcpServerv4Statistics
    $v4Tags  = $baseTags + @("version:v4")

    # Address pool metrics
    Send-Metric "$METRIC_PREFIX.server.total_addresses"   $v4Stats.TotalAddresses                              $v4Tags
    Send-Metric "$METRIC_PREFIX.server.addresses_in_use"  $v4Stats.AddressesInUse                              $v4Tags
    Send-Metric "$METRIC_PREFIX.server.addresses_free"    ($v4Stats.TotalAddresses - $v4Stats.AddressesInUse)  $v4Tags
    Send-Metric "$METRIC_PREFIX.server.pending_offers"    $v4Stats.PendingOffers                               $v4Tags
    Send-Metric "$METRIC_PREFIX.server.percent_in_use"    $v4Stats.PercentageInUse                             $v4Tags
    Send-Metric "$METRIC_PREFIX.server.percent_available" $v4Stats.PercentageAvailable                         $v4Tags
    Send-Metric "$METRIC_PREFIX.server.total_scopes"      $v4Stats.TotalScopes                                 $v4Tags

    # DHCP message/traffic counters
    # High naks/declines = IP conflicts | High discovers + low acks = scope exhaustion
    Send-Metric "$METRIC_PREFIX.server.discovers"         $v4Stats.Discovers                                   $v4Tags
    Send-Metric "$METRIC_PREFIX.server.offers"            $v4Stats.Offers                                      $v4Tags
    Send-Metric "$METRIC_PREFIX.server.requests"          $v4Stats.Requests                                    $v4Tags
    Send-Metric "$METRIC_PREFIX.server.acks"              $v4Stats.Acks                                        $v4Tags
    Send-Metric "$METRIC_PREFIX.server.naks"              $v4Stats.Naks                                        $v4Tags
    Send-Metric "$METRIC_PREFIX.server.declines"          $v4Stats.Declines                                    $v4Tags
    Send-Metric "$METRIC_PREFIX.server.releases"          $v4Stats.Releases                                    $v4Tags
    Send-Metric "$METRIC_PREFIX.server.delayed_offers"    $v4Stats.DelayedOffers                               $v4Tags

    # Uptime in seconds — alert if this resets unexpectedly (service restart)
    $uptime = [int](((Get-Date) - $v4Stats.ServerStartTime).TotalSeconds)
    Send-Metric "$METRIC_PREFIX.server.uptime_seconds"    $uptime                                              $v4Tags

} catch {
    Write-Warning "[$INTEGRATION] Failed to collect IPv4 server stats: $_"
}

# ==============================================================================
# SECTION 2 : IPv4 - Scope Level Statistics
# Cmdlet    : Get-DhcpServerv4Scope + Get-DhcpServerv4ScopeStatistics
# Tags      : scope, scopename, subnetmask, version, server_role,
#             superscope (if applicable)
#
# KEY FIX   : server_role tag added here so Datadog monitors can filter
#             scope utilization alerts to server_role:primary only.
# ==============================================================================
try {
    $v4Scopes = Get-DhcpServerv4Scope | Select-Object ScopeId, Name, SubnetMask

    foreach ($scope in $v4Scopes) {
        try {
            $stats = Get-DhcpServerv4ScopeStatistics -ScopeId $scope.ScopeId
            $total = $stats.AddressesFree + $stats.AddressesInUse

            $tags = $baseTags + @(
                "scope:$($scope.ScopeId)",
                "scopename:$($scope.Name)",
                "subnetmask:$($scope.SubnetMask)",
                "version:v4"
            )

            # Dynamically add superscope tag if this scope belongs to one
            if ($stats.SuperscopeName) { $tags += "superscope:$($stats.SuperscopeName)" }

            # Address pool metrics
            Send-Metric "$METRIC_PREFIX.scope.total_addresses"  $total                       $tags
            Send-Metric "$METRIC_PREFIX.scope.addresses_free"   $stats.AddressesFree         $tags
            Send-Metric "$METRIC_PREFIX.scope.addresses_in_use" $stats.AddressesInUse        $tags
            Send-Metric "$METRIC_PREFIX.scope.percent_in_use"   $stats.PercentageInUse       $tags
            Send-Metric "$METRIC_PREFIX.scope.pending_offers"   $stats.PendingOffers         $tags
            Send-Metric "$METRIC_PREFIX.scope.reserved_address" $stats.ReservedAddress       $tags

            # Failover metrics — only populated if scope has a failover relationship.
            # Use to detect imbalance between primary and partner node.
            Send-Metric "$METRIC_PREFIX.scope.free_this_server"      $stats.AddressesFreeOnThisServer     $tags
            Send-Metric "$METRIC_PREFIX.scope.free_partner_server"   $stats.AddressesFreeOnPartnerServer  $tags
            Send-Metric "$METRIC_PREFIX.scope.inuse_this_server"     $stats.AddressesInUseOnThisServer    $tags
            Send-Metric "$METRIC_PREFIX.scope.inuse_partner_server"  $stats.AddressesInUseOnPartnerServer $tags

        } catch {
            Write-Warning "[$INTEGRATION] Failed to collect IPv4 scope stats for $($scope.ScopeId): $_"
        }
    }
} catch {
    Write-Warning "[$INTEGRATION] Failed to enumerate IPv4 scopes: $_"
}

# ==============================================================================
# SECTION 3 : IPv6 - Server Level Statistics
# Cmdlet    : Get-DhcpServerv6Statistics
# Tags      : version:v6, server_role
# NOTE      : total_addresses / addresses_free intentionally skipped.
#             IPv6 /64 = 2^64 addresses -> overflows UInt64 (1.8e19),
#             meaningless for capacity monitoring.
# ==============================================================================
try {
    $v6Stats = Get-DhcpServerv6Statistics
    $v6Tags  = $baseTags + @("version:v6")

    # Address metrics (InUse only — free/total overflow for IPv6)
    Send-Metric "$METRIC_PREFIX.server.addresses_in_use"  $v6Stats.AddressesInUse   $v6Tags

    # IPv6 protocol message equivalents:
    # Discover -> Solicit | Offer -> Advertise | Ack -> Reply
    Send-Metric "$METRIC_PREFIX.server.discovers"         $v6Stats.Solicts           $v6Tags
    Send-Metric "$METRIC_PREFIX.server.offers"            $v6Stats.Advertises        $v6Tags
    Send-Metric "$METRIC_PREFIX.server.acks"              $v6Stats.Replies           $v6Tags
    Send-Metric "$METRIC_PREFIX.server.releases"          $v6Stats.Releases          $v6Tags

    # Uptime in seconds
    $v6Uptime = [int](((Get-Date) - $v6Stats.ServerStartTime).TotalSeconds)
    Send-Metric "$METRIC_PREFIX.server.uptime_seconds"    $v6Uptime                  $v6Tags

} catch {
    Write-Warning "[$INTEGRATION] Failed to collect IPv6 server stats: $_"
}

# ==============================================================================
# SECTION 4 : IPv6 - Scope Level Statistics
# Cmdlet    : Get-DhcpServerv6Scope + Get-DhcpServerv6ScopeStatistics
#             Get-DhcpServerv6Reservation (for reservation count)
# Tags      : scope (prefix), scopename, version, server_role
# NOTE      : total_addresses / addresses_free intentionally skipped.
#             IPv6 /64 ranges are too large to be operationally meaningful.
#
# KEY FIX   : server_role tag added here so Datadog monitors can filter
#             scope utilization alerts to server_role:primary only.
# ==============================================================================
try {
    $v6Scopes = Get-DhcpServerv6Scope | Select-Object Prefix, Name

    foreach ($scope in $v6Scopes) {
        try {
            $stats = Get-DhcpServerv6ScopeStatistics -Prefix $scope.Prefix

            $tags = $baseTags + @(
                "scope:$($scope.Prefix)",
                "scopename:$($scope.Name)",
                "version:v6"
            )

            # Core utilization metrics
            Send-Metric "$METRIC_PREFIX.scope.addresses_in_use" $stats.AddressesInUse   $tags
            Send-Metric "$METRIC_PREFIX.scope.percent_in_use"   $stats.PercentageInUse  $tags
            Send-Metric "$METRIC_PREFIX.scope.pending_offers"   $stats.PendingOffers    $tags

            # Static reservation count per IPv6 scope
            $v6Reservations = (Get-DhcpServerv6Reservation -Prefix $scope.Prefix `
                               -ErrorAction SilentlyContinue | Measure-Object).Count
            Send-Metric "$METRIC_PREFIX.scope.reserved_address" $v6Reservations $tags

        } catch {
            Write-Warning "[$INTEGRATION] Failed to collect IPv6 scope stats for $($scope.Prefix): $_"
        }
    }
} catch {
    Write-Warning "[$INTEGRATION] Failed to enumerate IPv6 scopes: $_"
}

# ==============================================================================
$udpClient.Close()
Write-Host "`n[$INTEGRATION] Done! Check Datadog Metrics Explorer for $METRIC_PREFIX.*"
Write-Host "[$INTEGRATION] Scope utilization monitor query should filter on: server_role:primary"
# ==============================================================================
#  © Zoos Global | www.zoosglobal.com | shivam.anand@zoosglobal.com
# ==============================================================================