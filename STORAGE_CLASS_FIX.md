## Storage Class PVC Binding Fix

### Problem
Getting error: `0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims`

### Root Cause
The storage class wasn't being properly selected for the PersistentVolumeClaims, or a storage class with `WaitForFirstConsumer` binding mode was being used instead of `Immediate`.

### Solution Implemented

Updated `install-drupal-crunchy.sh` with intelligent storage class selection logic:

1. **Primary check**: Look for default storage class with `Immediate` binding mode
2. **Secondary check**: Use any default storage class
3. **Tertiary check**: Find any storage class with `Immediate` binding
4. **Last resort**: Use first available storage class
5. **Error handling**: If no storage class found, display available options and allow manual specification

### Storage Class Selection Strategy

```bash
# Prefers Immediate binding storage classes
# Tries to find default storage class first
# Falls back to any available storage class
# Shows error with available options if none found
```

### How to Use

**Automatic (default):**
```bash
./install-drupal-crunchy.sh msu
```
Script will auto-detect and use `ocs-storagecluster-ceph-rbd` (or equivalent default)

**Manual override:**
```bash
STORAGE_CLASS=ocs-storagecluster-ceph-rbd ./install-drupal-crunchy.sh msu
```

### OpenShift Storage Classes

Common storage classes on OpenShift:
- `ocs-storagecluster-ceph-rbd` (default, Immediate binding) ✓
- `ocs-storagecluster-cephfs` (Immediate binding) ✓
- `local-block` (WaitForFirstConsumer binding) ✗

The script now automatically selects classes with `Immediate` binding to avoid scheduling delays.

### Verification

All PersistentVolumeClaims should now show as `Bound`:

```bash
oc get pvc -n msu
NAME                                    STATUS   VOLUME                                     ...
drupal-postgres-instance1-kqtj-pgdata   Bound    pvc-44879aa6-de73-444f-9244-31b74f230959   ...
drupal-postgres-instance1-mxwc-pgdata   Bound    pvc-63757895-77c9-4f91-b227-a9ae413643cc   ...
drupal-postgres-instance1-snhn-pgdata   Bound    pvc-c71a64f7-9cbd-4d12-a8f8-be28f49597bc   ...
drupal-postgres-repo1                   Bound    pvc-8e645559-c51f-4277-b43d-fd990cd3c6ec   ...
```
