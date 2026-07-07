#!/bin/bash

# check-resources.sh - Report resource utilization for Crunchy Data PostgreSQL pods in OpenShift
# Usage: ./check-resources.sh

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Load configuration from ConfigMap
CONFIGMAP_NAME="postgres-autoscaler-config"
CONFIGMAP_NAMESPACE="drupal"

log "Loading configuration from ConfigMap: $CONFIGMAP_NAME"

NAMESPACE=$(oc get configmap "$CONFIGMAP_NAME" -n "$CONFIGMAP_NAMESPACE" -o jsonpath='{.data.namespace}')
LABEL=$(oc get configmap "$CONFIGMAP_NAME" -n "$CONFIGMAP_NAMESPACE" -o jsonpath='{.data.label}')
CPU_UP_THRESHOLD=$(oc get configmap "$CONFIGMAP_NAME" -n "$CONFIGMAP_NAMESPACE" -o jsonpath='{.data.cpu-up-threshold}')
MEM_UP_THRESHOLD=$(oc get configmap "$CONFIGMAP_NAME" -n "$CONFIGMAP_NAMESPACE" -o jsonpath='{.data.mem-up-threshold}')

log "Checking resource utilization for PostgreSQL pods in namespace: $NAMESPACE"
METRICS=$(oc adm top pods -n "$NAMESPACE" --selector="$LABEL" | tail -n +2)

if [[ -z "$METRICS" ]]; then
    log "No pods found matching selector: $LABEL"
    exit 1
fi

printf "\n%-50s %10s %10s %10s %10s %10s\n" "POD" "CPU" "CPU%" "MEM" "MEM%" "STATUS"
printf '%s\n' "$(printf '%-55s' | tr ' ' '-')$(printf '%10s' | tr ' ' '-')$(printf '%10s' | tr ' ' '-')$(printf '%10s' | tr ' ' '-')$(printf '%10s' | tr ' ' '-')$(printf '%10s' | tr ' ' '-')"

WARN_COUNT=0
CRIT_COUNT=0

while read -r line; do
    POD=$(echo "$line" | awk '{print $1}')
    CPU=$(echo "$line" | awk '{print $2}')
    MEM=$(echo "$line" | awk '{print $3}')

    # CPU calculation
    CPU_VAL=${CPU%m}
    if [[ "$CPU" == *m ]]; then
        CPU_PCT=$((CPU_VAL / 10))
    else
        CPU_PCT=$CPU
    fi

    # Memory calculation (convert to Mi)
    if [[ "$MEM" == *Mi ]]; then
        MEM_VAL=${MEM%Mi}
    elif [[ "$MEM" == *Gi ]]; then
        MEM_VAL=$(( ${MEM%Gi} * 1024 ))
    else
        MEM_VAL=$MEM
    fi

    # Get pod memory request (in Mi) for percent calculation
    MEM_REQUEST=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.requests.memory}')
    if [[ "$MEM_REQUEST" == *Mi ]]; then
        MEM_REQ_VAL=${MEM_REQUEST%Mi}
    elif [[ "$MEM_REQUEST" == *Gi ]]; then
        MEM_REQ_VAL=$(( ${MEM_REQUEST%Gi} * 1024 ))
    else
        MEM_REQ_VAL=$MEM_REQUEST
    fi

    if [[ -n "$MEM_REQ_VAL" && "$MEM_REQ_VAL" -gt 0 ]]; then
        MEM_PCT=$(( 100 * MEM_VAL / MEM_REQ_VAL ))
    else
        MEM_PCT=0
    fi

    # Status label based on thresholds
    if (( CPU_PCT >= CPU_UP_THRESHOLD )) || (( MEM_PCT >= MEM_UP_THRESHOLD )); then
        STATUS="HIGH"
        (( CRIT_COUNT++ ))
    elif (( CPU_PCT >= CPU_UP_THRESHOLD * 75 / 100 )) || (( MEM_PCT >= MEM_UP_THRESHOLD * 75 / 100 )); then
        STATUS="WARN"
        (( WARN_COUNT++ ))
    else
        STATUS="OK"
    fi

    printf "%-50s %10s %9s%% %10s %9s%% %10s\n" "$POD" "$CPU" "$CPU_PCT" "$MEM" "$MEM_PCT" "$STATUS"
done <<< "$METRICS"

printf '\n'
log "Summary: $(echo "$METRICS" | wc -l) pod(s) checked — ${CRIT_COUNT} HIGH, ${WARN_COUNT} WARN"
log "Thresholds: CPU scale-up=${CPU_UP_THRESHOLD}%, MEM scale-up=${MEM_UP_THRESHOLD}%"
