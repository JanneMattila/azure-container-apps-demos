# Queue-triggered PowerShell job

[queue.ps1](queue.ps1) adapts the [event-driven jobs tutorial](https://learn.microsoft.com/en-us/azure/container-apps/tutorial-event-driven-jobs).
It creates an **Azure Container Apps Job**, not an always-running container app.
Each execution receives one queue message, runs the bundled [timer1.ps1](timer1.ps1),
and deletes the message only after successful completion. Message content is data,
never executed as PowerShell. The worker exposes it as `QUEUE_MESSAGE_TEXT` (as stored,
without Base64 decoding) and `QUEUE_MESSAGE_ID`.

Prerequisites: PowerShell 7.4+, Azure CLI, an authenticated and explicitly selected
subscription, and the existing resource group, VNet, VNet-integrated Container Apps
environment and ACR from [deploy.ps1](deploy.ps1). The caller needs resource creation,
ACR build and role-assignment permissions. Review the variables, then run:

```powershell
./queue.ps1
```

The image build includes the local timer script; rebuild/redeploy after editing it.
The queue image uses the current Azure PowerShell image; pin a tested tag or digest
for production. The job uses managed identity for the scaler, queue operations,
registry pull and Azure PowerShell. Reader access is scoped to this demo resource
group, so `Get-AzResourceGroup` is limited to resources the identity can read.
Role assignments may take several minutes to propagate before scaling or pulling works.

### Long-running work

| Setting | Value | Purpose |
| --- | --- | --- |
| Expected run time | 32,400 seconds (9 hours) | Workload budget |
| Replica timeout | 36,000 seconds (10 hours) | Workload plus headroom |
| Queue visibility timeout | 39,600 seconds (11 hours) | Keeps the message hidden beyond the replica deadline |
| Replica retry limit | 0 | Queue redelivery handles retries, not an immediate replacement replica |
| Parallelism / completion count | 1 / 1 | One message per execution |
| Min / max executions | 0 / 1 | Conservative event scaling configuration |
| Polling interval | 60 seconds | Queue check interval, not a work timeout |

Keep visibility timeout greater than replica timeout when increasing the budget
(Queue Storage supports up to seven days). A fresh storage token is requested
before acknowledgement, so the initial token is not reused after nine hours.
The sample timer still sleeps only ten seconds; no nine-hour wait is added to it.

Failure or termination leaves the message for redelivery after its visibility
timeout, potentially 11 hours after receipt. This demo has no poison-message cutoff:
repeatedly failing messages must be investigated and removed or quarantined.
Queue delivery is at least once, so real work must be idempotent, preferably using a
durable business operation ID. A long timeout does not prevent infrastructure
interruptions; checkpoint long-running work. `max-executions` is a scaler setting,
not a global serialization lock. The scaler counts queued messages including hidden
ones; an execution finding no visible message exits without running the timer.

### Private queue access

The script creates a **queue** private endpoint in `pe-subnet`, a
`privatelink.queue.core.windows.net` private DNS zone, its VNet link and the endpoint's
DNS zone group. Both the worker and scaler use the normal storage hostname, which
resolves privately within that VNet. Custom DNS must forward this zone appropriately.
Allow HTTPS traffic from the Container Apps subnet to the private endpoint.

Public network access is left unchanged because the storage account is shared by
other demos. Set `$disablePublicNetworkAccess = $true` for private-only access.
This disables public access for **all storage services** in that account; blob/file
consumers need their own private endpoints. Queue creation uses the management plane,
so deployment does not require data-plane connectivity from your workstation.

To trigger the job, run the following from a host with queue connectivity and
`Storage Queue Data Message Sender` (or `Storage Queue Data Contributor`) access.
For private-only storage this requires VNet/VPN connectivity and private DNS:

```powershell
az storage message put --account-name academos00000101 --queue-name queue01 --auth-mode login --content "run-timer1" --time-to-live -1
az containerapp job execution list --name queue-timer1 --resource-group rg-containerapps-demos -o table
az containerapp job logs show --name queue-timer1 --resource-group rg-containerapps-demos --follow
```

The message TTL is unlimited (`-1`) so backlog and retry delays do not expire the work.
Check execution status after the next polling interval and container startup; logs
should show processing followed by successful deletion. A failed script must leave
the message for redelivery, not acknowledge it.
