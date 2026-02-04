#!/bin/bash

################################################################################
# Forward ports to access Drupal locally
################################################################################

NAMESPACE="${1:-default}"
DRUPAL_SERVICE="drupal"

echo "=== Setting up port forwarding ==="
echo "Namespace: $NAMESPACE"
echo ""

# Get Drupal pod
DRUPAL_POD=$(oc get pods -n "$NAMESPACE" -l app=$DRUPAL_SERVICE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$DRUPAL_POD" ]; then
    echo "Error: No Drupal pod found in namespace $NAMESPACE"
    exit 1
fi

echo "Drupal Pod: $DRUPAL_POD"
echo ""
echo "Forwarding ports:"
echo "  HTTP:  localhost:8080 -> pod:80"
echo "  HTTPS: localhost:8443 -> pod:443"
echo ""
echo "Press Ctrl+C to stop"
echo ""

oc port-forward -n "$NAMESPACE" "pod/$DRUPAL_POD" 8080:80 8443:443
