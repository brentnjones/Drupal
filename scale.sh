#!/bin/bash

# scale.sh - Check resource utilization for Crunchy Data PostgreSQL pods in OpenShift
# and scale up/down horizontally
# Usage: ./scale.sh

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
CPU_DOWN_THRESHOLD=$(oc get configmap "$CONFIGMAP_NAME" -n "$CONFIGMAP_NAMESPACE" -o jsonpath='{.data.cpu-down-threshold}')
MEM_DOWN_THRESHOLD=$(oc get configmap "$CONFIGMAP_NAME" -n "$CONFIGMAP_NAMESPACE" -o jsonpath='{.data.mem-down-threshold}')
MIN_REPLICAS=$(oc get configmap "$CONFIGMAP_NAME" -n "$CONFIGMAP_NAMESPACE" -o jsonpath='{.data.min-replicas}')
MAX_REPLICAS=$(oc get configmap "$CONFIGMAP_NAME" -n "$CONFIGMAP_NAMESPACE" -o jsonpath='{.data.max-replicas}')

log "Checking resource utilization for PostgreSQL pods in namespace: $NAMESPACE"
METRICS=$(oc adm top pods -n "$NAMESPACE" --selector="$LABEL" | tail -n +2)

SCALE_UP=false
SCALE_DOWN=true

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

	# Memory calculation (convert to Mi if needed)
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

	log "Pod: $POD, CPU: $CPU, CPU_PCT: $CPU_PCT%, MEM: $MEM, MEM_PCT: $MEM_PCT%"
	if (( CPU_PCT > CPU_UP_THRESHOLD )) || (( MEM_PCT > MEM_UP_THRESHOLD )); then
		SCALE_UP=true
	fi
	if (( CPU_PCT > CPU_DOWN_THRESHOLD )) || (( MEM_PCT > MEM_DOWN_THRESHOLD )); then
		SCALE_DOWN=false
	fi
done <<< "$METRICS"

CURRENT_REPLICAS=$(oc get postgrescluster drupal-postgres -n "$NAMESPACE" -o jsonpath='{.spec.instances[0].replicas}')

if [ "$CURRENT_REPLICAS" -lt "$MIN_REPLICAS" ]; then
	NEW_REPLICAS="$MIN_REPLICAS"
	log "Current replicas ($CURRENT_REPLICAS) below minimum ($MIN_REPLICAS). Scaling up to $NEW_REPLICAS replicas."
	oc patch postgrescluster drupal-postgres -n "$NAMESPACE" --type='json' -p="[{\"op\":\"replace\",\"path\":\"/spec/instances/0/replicas\",\"value\":$NEW_REPLICAS}]"
elif [ "$CURRENT_REPLICAS" -gt "$MAX_REPLICAS" ]; then
	NEW_REPLICAS="$MAX_REPLICAS"
	log "Current replicas ($CURRENT_REPLICAS) above maximum ($MAX_REPLICAS). Scaling down to $NEW_REPLICAS replicas."
	oc patch postgrescluster drupal-postgres -n "$NAMESPACE" --type='json' -p="[{\"op\":\"replace\",\"path\":\"/spec/instances/0/replicas\",\"value\":$NEW_REPLICAS}]"
elif [ "$SCALE_UP" = true ] && [ "$CURRENT_REPLICAS" -lt "$MAX_REPLICAS" ]; then
	NEW_REPLICAS=$((CURRENT_REPLICAS + 1))
	log "Resource usage above threshold. Scaling up to $NEW_REPLICAS replicas."
	oc patch postgrescluster drupal-postgres -n "$NAMESPACE" --type='json' -p="[{\"op\":\"replace\",\"path\":\"/spec/instances/0/replicas\",\"value\":$NEW_REPLICAS}]"
elif [ "$SCALE_DOWN" = true ] && [ "$CURRENT_REPLICAS" -gt "$MIN_REPLICAS" ]; then
	NEW_REPLICAS=$((CURRENT_REPLICAS - 1))
	log "Resource usage below thresholds. Scaling down to $NEW_REPLICAS replicas."
	oc patch postgrescluster drupal-postgres -n "$NAMESPACE" --type='json' -p="[{\"op\":\"replace\",\"path\":\"/spec/instances/0/replicas\",\"value\":$NEW_REPLICAS}]"
else
	log "No scaling action taken."
fi
