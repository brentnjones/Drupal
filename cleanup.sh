#!/bin/bash

################################################################################
# Cleanup script to remove all Drupal and PostgreSQL resources
################################################################################

set -e

NAMESPACE="${1:-default}"
CLUSTER_NAME="drupal-postgres"
DRUPAL_SERVICE="drupal"

echo "=== Cleaning up Drupal Installation ==="
echo "Namespace: $NAMESPACE"
echo ""
read -p "Are you sure you want to delete all resources? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo "Deleting Drupal deployment..."
oc delete deployment $DRUPAL_SERVICE -n "$NAMESPACE" --ignore-not-found

echo "Deleting Drupal service..."
oc delete service $DRUPAL_SERVICE -n "$NAMESPACE" --ignore-not-found

echo "Deleting Drupal ingress..."
oc delete ingress drupal-ingress -n "$NAMESPACE" --ignore-not-found

echo "Deleting PostgreSQL cluster..."
oc delete postgrescluster $CLUSTER_NAME -n "$NAMESPACE" --ignore-not-found

echo "Deleting PVCs..."
oc delete pvc drupal-files -n "$NAMESPACE" --ignore-not-found
oc delete pvc -l postgres-operator.crunchydata.com/cluster=$CLUSTER_NAME -n "$NAMESPACE" --ignore-not-found

echo "Deleting ConfigMaps..."
oc delete configmap drupal-settings -n "$NAMESPACE" --ignore-not-found

echo "Deleting Secrets..."
oc delete secret drupal-tls drupal-postgres-secret -n "$NAMESPACE" --ignore-not-found

echo ""
echo "=== Cleanup Complete ==="
