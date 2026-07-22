# Scenario: Control Plane Alerts

## Overview

Two independent faults are introduced into the OpenShift control plane, each causing a different set of alerts to fire:

1. **Insights Operator** — The `insights-config` ConfigMap is applied with an incorrect upload endpoint, causing the operator to become degraded when it fails to report data.
2. **NTP (chronyd)** — The `chronyd` service is disabled on a master node, causing clock drift and triggering time-synchronization alerts.

No applications are deployed — this scenario operates entirely on existing cluster components.

## Usage

```bash
oc login ...                # required

make break                  # introduce both faults
make fix                    # revert all changes
```

## The Faults

### Insights Operator

A ConfigMap override is applied to `openshift-insights` that points the upload endpoint to a wrong (but realistic-looking) URL. The Insights Operator picks up the change and fails to upload, becoming degraded.

### NTP

`chronyd` is disabled on the first master node via `oc debug` and the clock is shifted forward by 2 minutes. The immediate offset triggers clock-related alerts within ~10 minutes (the `for:` duration).

## Expected Alerts

| Alert | Severity | Fires after | Triggered by |
|-------|----------|-------------|--------------|
| `ClusterOperatorDegraded` | warning | ~30m | `clusteroperator/insights` reports Degraded=True |
| `NodeClockNotSynchronising` | critical | ~10m | NTP sync lost + clock shifted by 2 minutes pushes max error past 16s immediately |

## Components

| Fault | Namespace / Node | What changes | How it's fixed |
|-------|-----------------|--------------|----------------|
| Insights upload endpoint | `openshift-insights` | ConfigMap `insights-config` with wrong `uploadEndpoint` | Delete the ConfigMap |
| NTP disabled + clock shift | First master node | `systemctl disable --now chronyd` + `date -s '+2 minutes'` | `systemctl enable --now chronyd` (NTP syncs clock back) |
