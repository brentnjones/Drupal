#!/bin/bash

################################################################################
# Quick Reference - Useful oc (OpenShift) commands for Drupal/PostgreSQL
################################################################################

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Drupal with Crunchy Data PostgreSQL - Quick Reference ===${NC}\n"

# Get namespace
NAMESPACE="${1:-default}"

echo -e "${GREEN}Status Checks:${NC}"
echo "1. Check PostgreSQL cluster status:"
echo "   oc get postgrescluster -n $NAMESPACE"
echo ""

echo "2. Check Drupal deployment:"
echo "   oc get deployment drupal -n $NAMESPACE"
echo ""

echo "3. Check all pods:"
echo "   oc get pods -n $NAMESPACE"
echo ""

echo "4. Check services:"
echo "   oc get svc -n $NAMESPACE"
echo ""

echo "5. Check routes (OpenShift):"
echo "   oc get route -n $NAMESPACE"
echo ""

echo -e "${GREEN}Pod Management:${NC}"
echo "1. Get Drupal pod name:"
echo "   oc get pods -n $NAMESPACE -l app=drupal -o name"
echo ""

echo "2. Get PostgreSQL pod names:"
echo "   oc get pods -n $NAMESPACE -l postgres-operator.crunchydata.com/cluster=drupal-postgres"
echo ""

echo "3. Restart Drupal:"
echo "   oc rollout restart deployment/drupal -n $NAMESPACE"
echo ""

echo "4. View Drupal logs:"
echo "   oc logs -l app=drupal -n $NAMESPACE -f"
echo ""

echo "5. View PostgreSQL logs:"
echo "   oc logs -l postgres-operator.crunchydata.com/cluster=drupal-postgres -n $NAMESPACE -f"
echo ""

echo -e "${GREEN}Database Access:${NC}"
echo "1. Get PostgreSQL password:"
echo "   oc get secret drupal-postgres-secret -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d"
echo ""

echo "2. Connect to PostgreSQL pod:"
echo "   oc exec -it <pod-name> -n $NAMESPACE -- psql -U drupal_user -d drupal_db"
echo ""

echo "3. Quick SQL query:"
echo "   oc exec -it <pod-name> -n $NAMESPACE -- psql -U drupal_user -d drupal_db -c 'SELECT version();'"
echo ""

echo -e "${GREEN}Drupal Configuration:${NC}"
echo "1. View Drupal settings ConfigMap:"
echo "   oc get configmap drupal-settings -n $NAMESPACE -o yaml"
echo ""

echo "2. Edit Drupal settings ConfigMap:"
echo "   oc edit configmap drupal-settings -n $NAMESPACE"
echo ""

echo "3. View Drupal environment variables:"
echo "   oc exec -it <drupal-pod> -n $NAMESPACE -- env | grep POSTGRES"
echo ""

echo -e "${GREEN}Storage:${NC}"
echo "1. Check PVC status:"
echo "   oc get pvc -n $NAMESPACE"
echo ""

echo "2. Check PV (Persistent Volumes):"
echo "   oc get pv"
echo ""

echo "3. Check storage classes:"
echo "   oc get storageclass"
echo ""

echo -e "${GREEN}Network & Routes (OpenShift):${NC}"
echo "1. Get route details:"
echo "   oc describe route drupal-ingress -n $NAMESPACE"
echo ""

echo "2. Get route URL:"
echo "   oc get route drupal-ingress -n $NAMESPACE -o wide"
echo ""

echo "3. Test internal DNS (from pod):"
echo "   oc run -it --rm debug --image=alpine --restart=Never -- nslookup drupal-postgres-primary.$NAMESPACE.svc.cluster.local"
echo ""

echo -e "${GREEN}Debugging:${NC}"
echo "1. Describe a pod (see events and status):"
echo "   oc describe pod <pod-name> -n $NAMESPACE"
echo ""

echo "2. Get pod logs with timestamps:"
echo "   oc logs <pod-name> -n $NAMESPACE --timestamps=true"
echo ""

echo "3. Stream logs from multiple pods:"
echo "   oc logs -l app=drupal -n $NAMESPACE -f --all-containers=true"
echo ""

echo "4. Execute command in pod:"
echo "   oc exec -it <pod-name> -n $NAMESPACE -- <command>"
echo ""

echo "5. Get into pod shell:"
echo "   oc exec -it <pod-name> -n $NAMESPACE -- bash"
echo ""

echo -e "${GREEN}Scaling:${NC}"
echo "1. Scale Drupal replicas:"
echo "   oc scale deployment drupal --replicas=3 -n $NAMESPACE"
echo ""

echo "2. Scale PostgreSQL replicas:"
echo "   oc patch postgrescluster drupal-postgres -n $NAMESPACE -p '{\"spec\":{\"instances\":[{\"name\":\"instance1\",\"replicas\":5}]}}'"
echo ""

echo -e "${GREEN}Advanced Troubleshooting:${NC}"
echo "1. Check resource usage:"
echo "   oc top pods -n $NAMESPACE"
echo "   oc top nodes"
echo ""

echo "2. Check node status:"
echo "   oc get nodes -o wide"
echo "   oc describe node <node-name>"
echo ""

echo "3. View cluster events:"
echo "   oc get events -n $NAMESPACE --sort-by='.lastTimestamp'"
echo ""

echo "4. Port forward for local access:"
echo "   oc port-forward svc/drupal 8080:80 -n $NAMESPACE"
echo ""

echo "5. Copy files from pod:"
echo "   oc cp $NAMESPACE/<pod-name>:/path/in/pod /local/path"
echo ""

echo "6. Copy files to pod:"
echo "   oc cp /local/path $NAMESPACE/<pod-name>:/path/in/pod"
echo ""

echo -e "${GREEN}Useful Aliases (add to ~/.bashrc):${NC}"
echo "alias o=oc"
echo "alias ogp='oc get pods'"
echo "alias ogs='oc get svc'"
echo "alias ogr='oc get route'"
echo "alias ol='oc logs'"
echo "alias oe='oc exec -it'"
echo "alias od='oc describe'"
echo ""
