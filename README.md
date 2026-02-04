# Drupal Installation with Crunchy Data PostgreSQL

Complete Kubernetes/OpenShift-based installation of Drupal with PostgreSQL via Crunchy Data operator.

## Prerequisites

- Kubernetes/OpenShift cluster running
- **Crunchy Data operator already installed** (operator handles all image management)
- `kubectl` or `oc` configured and available
- `openssl` installed (for certificate generation)
- Ingress controller available (automatic on OpenShift)
- Available storage class for PersistentVolumeClaims

## Quick Start

```bash
chmod +x *.sh
./install-drupal-crunchy.sh [namespace]
```

If no namespace is specified, it defaults to `default`.

## How It Works

The script leverages the **pre-installed Crunchy Data operator** to:
- Automatically pull and manage PostgreSQL images
- Create a 3-node PostgreSQL 15 cluster
- Handle replication and failover
- Manage backups with pgBackRest

You only need to specify the cluster configuration (replicas, storage, version) - the operator handles the rest.

## What Gets Created

### PostgreSQL Cluster
- **Name**: `drupal-postgres`
- **Nodes**: 3 replicas for high availability
- **Version**: PostgreSQL 15
- **Storage**: 10Gi per instance + 20Gi for backups
- **Database**: `drupal_db`
- **User**: `drupal_user` (auto-generated secure password)

### Drupal Deployment
- **Image**: `drupal:10-apache`
- **Storage**: 5Gi PVC for `/sites/default/files`
- **Service**: ClusterIP on ports 80 and 443
- **Ingress**: TLS-enabled ingress for `drupal.local` and `drupal` hostnames

### Security
- **TLS Certificate**: Self-signed certificate valid for 365 days
- **Secret**: `drupal-tls` - stores certificate and key
- **ConfigMap**: `drupal-settings` - Drupal database configuration
- **Database Password**: Generated securely with `openssl rand -base64 32`

## Access Drupal

### Option 1: Using Ingress (Recommended)

1. Get the Ingress IP:
```bash
kubectl get ingress drupal-ingress -n default
```

2. Add to your `/etc/hosts`:
```
<INGRESS_IP> drupal.local
```

3. Open in browser: `https://drupal.local`

### Option 2: Port Forwarding

```bash
./port-forward.sh [namespace]
```

Then access:
- HTTP: `http://localhost:8080`
- HTTPS: `https://localhost:8443`

## Drupal Web Installer Configuration

When you access Drupal for the first time, the web installer will guide you through setup:

1. **Language Selection**: Choose your language
2. **Database Configuration**:
   - **Driver**: PostgreSQL
   - **Host**: `drupal-postgres-primary.NAMESPACE.svc.cluster.local`
   - **Port**: `5432`
   - **Database name**: `drupal_db`
   - **Database username**: `drupal_user`
   - **Database password**: (displayed during installation)
3. **Site Information**: Configure site name, admin user, etc.

## Database Connection Details

```
Host:     drupal-postgres-primary.NAMESPACE.svc.cluster.local
Port:     5432
Database: drupal_db
User:     drupal_user
Password: (check installation output or: kubectl get secret drupal-postgres-secret -o jsonpath='{.data.password}' | base64 -d)
```

## Troubleshooting

### Check Status
```bash
./troubleshoot.sh [namespace]
```

This script will show:
- PostgreSQL cluster status
- Pod status and logs
- Service and Ingress configuration
- Network connectivity tests

### Common Issues

#### Drupal pod stuck in pending
- Check PVC creation: `kubectl get pvc -n NAMESPACE`
- Check node resources: `kubectl describe nodes`

#### Cannot connect to database
- Verify PostgreSQL cluster is ready: `kubectl get pgcluster -n NAMESPACE`
- Check service DNS: `kubectl get svc -n NAMESPACE`
- Verify credentials in ConfigMap: `kubectl get configmap drupal-settings -n NAMESPACE -o yaml`

#### SSL/TLS Certificate Warning
- This is expected with self-signed certificates
- For production, use proper certificates (Let's Encrypt, corporate CA, etc.)

#### Ingress not working
- Verify ingress controller is installed: `kubectl get ingressclass`
- Check ingress resource: `kubectl describe ingress drupal-ingress -n NAMESPACE`

## Scaling and Management

### Scale PostgreSQL Replicas
```bash
kubectl patch pgcluster drupal-postgres -n NAMESPACE -p '{"spec":{"instances":[{"name":"instance1","replicas":5}]}}'
```

### Monitor PostgreSQL
```bash
kubectl logs -l postgres-operator.crunchydata.com/cluster=drupal-postgres -n NAMESPACE -f
```

### Access PostgreSQL Console
```bash
# Find a postgres pod
POD=$(kubectl get pods -l postgres-operator.crunchydata.com/cluster=drupal-postgres -n NAMESPACE -o jsonpath='{.items[0].metadata.name}')

# Connect using psql
kubectl exec -it $POD -n NAMESPACE -- psql -U drupal_user -d drupal_db
```

## Backup and Restore

Crunchy Data includes pgBackRest for backups. Backups are stored in a PVC:

```bash
# List backups
kubectl exec -n NAMESPACE <postgres-pod> -- pgbackrest info

# Manual backup (optional)
kubectl exec -n NAMESPACE <postgres-pod> -- pgbackrest backup
```

## Cleanup

To remove all resources:

```bash
./cleanup.sh [namespace]
```

**Warning**: This will delete:
- Drupal deployment and services
- PostgreSQL cluster and data
- All PersistentVolumeClaims
- ConfigMaps and Secrets

## Production Considerations

1. **Certificates**: Replace self-signed certificates with proper TLS certificates
2. **Resource Limits**: Adjust CPU and memory requests/limits based on your workload
3. **Database Passwords**: Store passwords in a secrets management system (Vault, etc.)
4. **Backups**: Configure regular backups and test restoration
5. **Monitoring**: Set up monitoring and alerting for PostgreSQL and Drupal
6. **High Availability**: Ensure your storage backend supports HA for PVCs
7. **Network Policies**: Implement network policies for security
8. **Registry Secrets**: Use private image registries for production images

## Crunchy Data Operator

For more information on Crunchy Data PostgreSQL Operator, visit:
https://access.crunchydata.com/documentation/postgres-operator/latest/

## License

These scripts are provided as-is for Drupal and Kubernetes setup automation.
