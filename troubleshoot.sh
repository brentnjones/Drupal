#!/bin/bash

################################################################################
# Helper script to troubleshoot Drupal and PostgreSQL setup
################################################################################

NAMESPACE="${1:-default}"
CLUSTER_NAME="drupal-postgres"

echo "=== Drupal & PostgreSQL Status Check ==="
echo ""

echo "1. PostgreSQL Cluster Status:"
oc get postgrescluster -n "$NAMESPACE"
echo ""

echo "2. PostgreSQL Instance Pods:"
oc get pods -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster=$CLUSTER_NAME
echo ""

echo "3. Drupal Deployment Status:"
oc get deployment drupal -n "$NAMESPACE"
echo ""

echo "4. Drupal Pod Status:"
oc get pods -n "$NAMESPACE" -l app=drupal
echo ""

echo "5. Services:"
oc get svc -n "$NAMESPACE"
echo ""

echo "6. Routes/Ingress:"
oc get route -n "$NAMESPACE"
echo ""

echo "7. PersistentVolumeClaims:"
oc get pvc -n "$NAMESPACE"
echo ""

echo "8. PostgreSQL Secrets:"
oc get secret -n "$NAMESPACE" | grep -E "drupal|postgres"
echo ""

echo "9. Recent Events:"
oc get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
echo ""

echo "=== Pod Logs ==="
echo ""

DRUPAL_POD=$(oc get pods -n "$NAMESPACE" -l app=drupal -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$DRUPAL_POD" ]; then
    echo "Drupal Pod Logs ($DRUPAL_POD):"
    oc logs -n "$NAMESPACE" "$DRUPAL_POD" --tail=20
    echo ""
else
    echo "No Drupal pod found"
    echo ""
fi

PG_POD=$(oc get pods -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster=$CLUSTER_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$PG_POD" ]; then
    echo "PostgreSQL Pod Logs ($PG_POD):"
    oc logs -n "$NAMESPACE" "$PG_POD" --tail=20
    echo ""
else
    echo "No PostgreSQL pod found"
    echo ""
fi

echo "=== Connectivity Test ==="
echo ""
echo "PostgreSQL Service DNS:"
echo "  $CLUSTER_NAME-primary.$NAMESPACE.svc.cluster.local"
echo ""

# Test if we can reach PostgreSQL from Drupal
if [ ! -z "$DRUPAL_POD" ]; then
    echo "Testing database connectivity from Drupal pod:"
    oc exec -n "$NAMESPACE" "$DRUPAL_POD" -- bash -c "curl -v telnet://$CLUSTER_NAME-primary.$NAMESPACE.svc.cluster.local:5432" 2>&1 | head -20 || echo "Connection test output above"
    echo ""
fi
