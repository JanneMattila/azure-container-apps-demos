# Queue-triggered PowerShell job

[queue.ps1](queue.ps1) adapts the [event-driven jobs tutorial](https://learn.microsoft.com/en-us/azure/container-apps/tutorial-event-driven-jobs).
It creates an **Azure Container Apps Job**, not an always-running container app.
Each execution receives one queue message, deletes it, then runs the bundled
[timer1.ps1](queue-app/timer1.ps1) synchronously. Deletion must succeed before the script
starts. Failure after deletion requires manual resubmission. Message content is data,
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
| Queue visibility timeout | 39,600 seconds (11 hours) | Hides the received message until deletion; only matters if deletion is not completed |
| Replica retry limit | 0 | No automatic replica retry; deleted work requires manual resubmission |
| Parallelism / completion count | 1 / 1 | One message per execution |
| Min / max executions | 0 / 1 | Conservative event scaling configuration |
| Polling interval | 60 seconds | Queue check interval, not a work timeout |

The worker retains its visibility-timeout validation: greater than replica timeout
and at most seven days. Once deletion succeeds, visibility no longer affects the
running script. Both receive and delete happen before the long-running work.
The sample timer still sleeps only ten seconds; no nine-hour wait is added to it.

Failure or termination after deletion does not return the message to the queue,
even if the script has not started yet. Monitor failed executions and resubmit work
manually. If the worker fails before deletion, the message can become visible again
up to 11 hours after receipt. A delete request can also succeed at the service while
its response is lost, leaving no message and no processing. This is an intentional
trade-off, not a reliable exactly-once workflow.

A long timeout does not prevent infrastructure interruptions; checkpoint important
work and make resubmissions idempotent. `max-executions` is a scaler setting, not a
global serialization lock. The scaler still checks every 60 seconds, but an empty
queue does not request new executions. Deleting the message does not stop its running
job. An execution already requested may find no visible message and exit without
running the timer.

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

The message TTL is unlimited (`-1`) so backlog delays do not expire the work.
Check execution status after the next polling interval and container startup; logs
should show deletion before processing, then completion when the script finishes.
A failed script leaves the message deleted; it must be resubmitted manually.
