#!/bin/bash

################################################################################
# Drupal Installation Script with Crunchy Data PostgreSQL
# 
# Prerequisites:
# - Kubernetes/OpenShift cluster running
# - Crunchy Data operator already installed
# - oc (OpenShift CLI) configured
# - openssl installed (for self-signed certificates)
#
# Usage: ./install-drupal-crunchy.sh [namespace]
################################################################################

set -e

NAMESPACE="${1:-default}"
CLUSTER_NAME="drupal-postgres"
DRUPAL_SERVICE="drupal"
DRUPAL_IMAGE="drupal:10-apache"
# Note: Crunchy Data operator creates user and database with cluster name
POSTGRES_USER="$CLUSTER_NAME"
POSTGRES_DB="$CLUSTER_NAME"
HASH_SALT=$(openssl rand -base64 32)

# Check if oc is logged in
if ! oc whoami &>/dev/null; then
    echo "ERROR: Not authenticated to OpenShift cluster."
    echo ""
    echo "Please run the following command with your token and server URL:"
    echo "  oc login --token=<your-token> --server=<your-server-url>"
    echo ""
    echo "Example:"
    echo "  oc login --token=sha256~a4XQPmmQF0XaqMYnPd-25VtzJ5Su44p7K1S2ZtR_Q1o --server=https://api.cluster-rhbdl.rhbdl.sandbox3514.opentlc.com:6443"
    exit 1
fi

echo "Authenticated as: $(oc whoami)"
echo "Connected to: $(oc cluster-info | head -1 | sed 's/.*is running at //')"
echo ""

# Get storage class with proper binding mode (prefer Immediate binding)
# First try to find default storage class with Immediate binding
DEFAULT_STORAGE_CLASS=$(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true" && @.volumeBindingMode=="Immediate")].metadata.name}' 2>/dev/null | head -1)

if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
    # Fall back to any default storage class
    DEFAULT_STORAGE_CLASS=$(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null | head -1)
fi

if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
    # Try to find any Immediate binding storage class (preferring RBD)
    DEFAULT_STORAGE_CLASS=$(oc get storageclass -o jsonpath='{.items[?(@.volumeBindingMode=="Immediate" && @.provisioner=="openshift-storage.rbd.csi.ceph.com")].metadata.name}' 2>/dev/null | head -1)
fi

if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
    # Use first available with Immediate binding
    DEFAULT_STORAGE_CLASS=$(oc get storageclass -o jsonpath='{.items[?(@.volumeBindingMode=="Immediate")].metadata.name}' 2>/dev/null | head -1)
fi

if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
    # Last resort: use first available
    DEFAULT_STORAGE_CLASS=$(oc get storageclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi

STORAGE_CLASS="${STORAGE_CLASS:-$DEFAULT_STORAGE_CLASS}"

if [ -z "$STORAGE_CLASS" ]; then
    echo "ERROR: Could not determine storage class. Available options:"
    oc get storageclass
    echo ""
    echo "Usage: STORAGE_CLASS=<classname> ./install-drupal-crunchy.sh $NAMESPACE"
    exit 1
fi

echo "=== Drupal Installation with Crunchy Data PostgreSQL ==="
echo "Namespace: $NAMESPACE"
echo "PostgreSQL Cluster: $CLUSTER_NAME"
echo "Storage Class: $STORAGE_CLASS"
echo "PostgreSQL Password: $POSTGRES_PASSWORD"
echo ""

# Create namespace if it doesn't exist
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    echo "[1/6] Creating namespace: $NAMESPACE"
    oc create namespace "$NAMESPACE"
else
    echo "[1/6] Namespace $NAMESPACE already exists"
fi

# Create Crunchy Data PostgreSQL Cluster
# The operator will handle all image management and deployment
echo "[2/6] Creating PostgreSQL cluster (3 nodes) with Crunchy Data..."
EXISTING_CLUSTER=$(oc get postgrescluster "$CLUSTER_NAME" -n "$NAMESPACE" --ignore-not-found -o name 2>/dev/null)
oc apply -f - <<EOF
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: $CLUSTER_NAME
  namespace: $NAMESPACE
spec:
  postgresVersion: 15
  
  # PostgreSQL configuration for pod connectivity
  patroni:
    dynamicConfiguration:
      postgresql:
        pg_hba:
          - "local   all             all                                     trust"
          - "host    all             all             127.0.0.1/32            trust"
          - "host    all             all             ::1/128                 trust"
          - "host    all             all             0.0.0.0/0               md5"
          - "host    all             all             ::/0                    md5"
  
  # Instance replicas (3-node cluster)
  instances:
    - name: instance1
      replicas: 3
      resources:
        requests:
          cpu: 500m
          memory: 512Mi
        limits:
          cpu: 1000m
          memory: 1Gi
      dataVolumeClaimSpec:
        accessModes:
          - ReadWriteOnce
        storageClassName: $STORAGE_CLASS
        resources:
          requests:
            storage: 10Gi
  
  # Backups with pgBackRest
  backups:
    pgbackrest:
      repos:
        - name: repo1
          volume:
            volumeClaimSpec:
              accessModes:
                - ReadWriteOnce
              storageClassName: $STORAGE_CLASS
              resources:
                requests:
                  storage: 20Gi
EOF

if [ -z "$EXISTING_CLUSTER" ]; then
    echo "Waiting for PostgreSQL cluster to be ready..."
    oc wait --for=condition=PG.Ready postgrescluster/$CLUSTER_NAME -n "$NAMESPACE" --timeout=300s 2>/dev/null || true
    sleep 15
else
    echo "PostgreSQL cluster already exists; skipping long wait."
fi

PG_POD=$(oc get pods -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster=$CLUSTER_NAME -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==true)].metadata.name}' 2>/dev/null | awk '{print $1}')

if [ ! -z "$PG_POD" ]; then
    # Wait for pod to be fully ready
    oc wait --for=condition=Ready pod/$PG_POD -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
    sleep 5
    
    # Grant necessary permissions to the Crunchy-generated database user
    # The operator creates user "drupal-postgres" and database "drupal-postgres"
    echo "Configuring database permissions..."
    
    # Get the primary pod for permission grants
    PRIMARY_POD=$(oc get pods -n "$NAMESPACE" -l postgres-operator.crunchydata.com/cluster=$CLUSTER_NAME,postgres-operator.crunchydata.com/role=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ ! -z "$PRIMARY_POD" ]; then
        oc exec -n "$NAMESPACE" "$PRIMARY_POD" -- psql -U postgres -d "$CLUSTER_NAME" -c "GRANT ALL ON SCHEMA public TO \"$CLUSTER_NAME\";" 2>/dev/null && echo "Schema permissions granted" || echo "Note: Schema permissions may need manual configuration"
        oc exec -n "$NAMESPACE" "$PRIMARY_POD" -- psql -U postgres -c "ALTER DATABASE \"$CLUSTER_NAME\" OWNER TO \"$CLUSTER_NAME\";" 2>/dev/null && echo "Database ownership set" || echo "Note: Database ownership may need manual configuration"
        echo "Database configuration complete"
    else
        echo "Warning: Could not find primary PostgreSQL pod for permission grants"
    fi
else
    echo "Warning: Could not find PostgreSQL pod to initialize database"
fi

# Generate Self-Signed Certificate
echo "[3/6] Creating self-signed certificate..."
CERT_DIR=$(mktemp -d)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$CERT_DIR/tls.key" \
    -out "$CERT_DIR/tls.crt" \
    -subj "/CN=drupal.local/O=Drupal"

# Create TLS secret
oc create secret tls drupal-tls \
    --cert="$CERT_DIR/tls.crt" \
    --key="$CERT_DIR/tls.key" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | oc apply -f -

echo "Certificate and key stored in secret: drupal-tls"

# Prepare Drupal settings and permissions via initContainer
echo "[4/6] Preparing Drupal settings and permissions..."

# Create PersistentVolumeClaim for Drupal files
echo "[5/6] Creating storage for Drupal..."
oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drupal-sites-default
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $STORAGE_CLASS
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drupal-files
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $STORAGE_CLASS
  resources:
    requests:
      storage: 5Gi
EOF

# Create ServiceAccount and assign SCC to allow Apache to bind to port 80
echo "Configuring ServiceAccount and SCC for Drupal..."
oc create serviceaccount drupal-sa -n "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -
oc adm policy add-scc-to-user anyuid -z drupal-sa -n "$NAMESPACE" 2>/dev/null || true

# Deploy Drupal
echo "[6/6] Deploying Drupal..."
oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DRUPAL_SERVICE
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DRUPAL_SERVICE
  template:
    metadata:
      labels:
        app: $DRUPAL_SERVICE
    spec:
      serviceAccountName: drupal-sa
      initContainers:
      - name: init-drupal-settings
        image: $DRUPAL_IMAGE
        command:
        - /bin/sh
        - -c
        - |
          set -e
          # Copy default site files to persistent volume if not already there
          if [ ! -f /mnt/sites-default/settings.php ]; then
            echo "Initializing sites/default on persistent volume..."
            cp -a /var/www/html/sites/default/. /mnt/sites-default/
            {
              echo '<?php'
              echo '// Crunchy Data PostgreSQL Configuration'
              echo '$'"databases"'["default"]["default"] = ['
              echo "  'driver' => 'pgsql',"
              echo "  'database' => getenv('POSTGRES_DB'),"
              echo "  'username' => getenv('POSTGRES_USER'),"
              echo "  'password' => getenv('POSTGRES_PASSWORD'),"
              echo "  'host' => getenv('POSTGRES_HOST'),"
              echo "  'port' => (getenv('POSTGRES_PORT') ?: '5432'),"
              echo "  'prefix' => '',"
              echo "  'options' => ["
              echo "    'sslmode' => 'prefer',"
              echo "  ],"
              echo '];'
              echo
              echo '// Trusted hosts for SSL/TLS'
              echo '$'"settings"'["trusted_host_patterns"] = ['
              echo "  '^.+$',"
              echo '];'
              echo
              echo '// Hash salt'
              echo '$'"settings"'["hash_salt"] = getenv("HASH_SALT");'
            } > /mnt/sites-default/settings.php
            chmod 666 /mnt/sites-default/settings.php
            chmod 777 /mnt/sites-default
            mkdir -p /mnt/sites-default/files
            chmod 775 /mnt/sites-default/files
            chown -R 33:33 /mnt/sites-default
            echo "Initialization complete"
          else
            echo "sites/default already initialized on persistent volume"
          fi
        env:
        - name: POSTGRES_HOST
          valueFrom:
            secretKeyRef:
              name: $CLUSTER_NAME-pguser-$CLUSTER_NAME
              key: host
        - name: POSTGRES_PORT
          valueFrom:
            secretKeyRef:
              name: $CLUSTER_NAME-pguser-$CLUSTER_NAME
              key: port
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: $CLUSTER_NAME-pguser-$CLUSTER_NAME
              key: dbname
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: $CLUSTER_NAME-pguser-$CLUSTER_NAME
              key: user
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: $CLUSTER_NAME-pguser-$CLUSTER_NAME
              key: password
        - name: HASH_SALT
          value: "$HASH_SALT"
        volumeMounts:
        - name: drupal-sites-default
          mountPath: /mnt/sites-default
      containers:
      - name: drupal
        image: $DRUPAL_IMAGE
        ports:
        - containerPort: 80
          name: http
        - containerPort: 443
          name: https
        securityContext:
          runAsUser: 0
        env:
        - name: POSTGRES_HOST
          valueFrom:
            secretKeyRef:
              name: $CLUSTER_NAME-pguser-$CLUSTER_NAME
              key: host
        - name: POSTGRES_PORT
          valueFrom:
            secretKeyRef:
              name: $CLUSTER_NAME-pguser-$CLUSTER_NAME
              key: port
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: $CLUSTER_NAME-pguser-$CLUSTER_NAME
              key: dbname
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: $CLUSTER_NAME-pguser-$CLUSTER_NAME
              key: user
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: $CLUSTER_NAME-pguser-$CLUSTER_NAME
              key: password
        volumeMounts:
        - name: drupal-sites-default
          mountPath: /var/www/html/sites/default
        livenessProbe:
          httpGet:
            path: /user/login
            port: 80
          initialDelaySeconds: 60
          periodSeconds: 30
          failureThreshold: 5
        readinessProbe:
          tcpSocket:
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
      volumes:
      - name: drupal-sites-default
        persistentVolumeClaim:
          claimName: drupal-sites-default
      - name: drupal-files
        persistentVolumeClaim:
          claimName: drupal-files
---
apiVersion: v1
kind: Service
metadata:
  name: $DRUPAL_SERVICE
  namespace: $NAMESPACE
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  - port: 443
    targetPort: 443
    protocol: TCP
    name: https
  selector:
    app: $DRUPAL_SERVICE
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: drupal
  namespace: $NAMESPACE
spec:
  to:
    kind: Service
    name: $DRUPAL_SERVICE
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

# Wait for Drupal deployment
echo ""
echo "Waiting for Drupal deployment to be ready..."
oc rollout status deployment/$DRUPAL_SERVICE -n "$NAMESPACE" --timeout=300s

# Deploy pgAdmin for PostgreSQL management
echo "[7/6] Deploying pgAdmin..."
PGADMIN_PASSWORD=$(openssl rand -base64 32)

# Create pgAdmin ServiceAccount
oc create serviceaccount pgadmin-sa -n "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -
oc adm policy add-scc-to-user anyuid -z pgadmin-sa -n "$NAMESPACE" 2>/dev/null || true

oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: pgadmin-secret
  namespace: $NAMESPACE
type: Opaque
stringData:
  PGADMIN_DEFAULT_EMAIL: brentjon@redhat.com
  PGADMIN_DEFAULT_PASSWORD: $PGADMIN_PASSWORD
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pgadmin
  template:
    metadata:
      labels:
        app: pgadmin
    spec:
      serviceAccountName: pgadmin-sa
      containers:
      - name: pgadmin
        image: dpage/pgadmin4:latest
        ports:
        - containerPort: 80
          name: http
        env:
        - name: PGADMIN_DEFAULT_EMAIL
          valueFrom:
            secretKeyRef:
              name: pgadmin-secret
              key: PGADMIN_DEFAULT_EMAIL
        - name: PGADMIN_DEFAULT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pgadmin-secret
              key: PGADMIN_DEFAULT_PASSWORD
        - name: SCRIPT_NAME
          value: /pgadmin4
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: $NAMESPACE
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: pgadmin
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: pgadmin
  namespace: $NAMESPACE
spec:
  to:
    kind: Service
    name: pgadmin
  port:
    targetPort: http
  path: /pgadmin4
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

echo "Waiting for pgAdmin deployment to be ready..."
oc rollout status deployment/pgadmin -n "$NAMESPACE" --timeout=300s || true

# Output access information
echo ""
echo "=== Installation Complete ==="
echo ""
echo "PostgreSQL Cluster Info:"
echo "  Host: $CLUSTER_NAME-primary.$NAMESPACE.svc.cluster.local"
echo "  Port: 5432"
echo "  Database: $POSTGRES_DB"
echo "  Username: $POSTGRES_USER"
echo ""
echo "Drupal Access:"
echo "  Service: $DRUPAL_SERVICE.$NAMESPACE.svc.cluster.local"
echo "  Route: use 'oc get route drupal -n $NAMESPACE'"
echo ""
echo "pgAdmin Access:"
echo "  Email: admin@example.com"
echo "  Password: $PGADMIN_PASSWORD"
echo "  Route: use 'oc get route pgadmin -n $NAMESPACE'"
echo ""
echo "Next Steps:"
echo "1. Get Drupal route URL (OpenShift):"
echo "   oc get route drupal -n $NAMESPACE"
echo ""
echo "2. Get pgAdmin route URL (OpenShift):"
echo "   oc get route pgadmin -n $NAMESPACE"
echo ""
echo "3. Access pgAdmin:"
echo "   - Go to the pgAdmin route URL"
echo "   - Login with: admin@example.com / $PGADMIN_PASSWORD"
echo "   - Add server connection:"
echo "     Host: $CLUSTER_NAME-primary.$NAMESPACE.svc.cluster.local"
echo "     Port: 5432"
echo "     Username: $POSTGRES_USER"
echo "     Password: (see PostgreSQL password above)"
echo ""
echo "4. Forward ports to access locally (optional):"
echo "   oc port-forward svc/$DRUPAL_SERVICE 8443:443 -n $NAMESPACE"
echo "   oc port-forward svc/pgadmin 8080:80 -n $NAMESPACE"
echo ""
echo "5. Open browser:"
echo "   Drupal: https://drupal.local (or https://localhost:8443)"
echo "   pgAdmin: http://localhost:8080/pgadmin4"
echo ""
echo "6. Run Drupal web installer and configure:"
echo "   - Database: PostgreSQL"
echo "   - Host: $CLUSTER_NAME-primary.$NAMESPACE.svc.cluster.local"
echo "   - Database: $POSTGRES_DB"
echo "   - User: $POSTGRES_USER"
echo "   - Password: (see above)"
echo ""
echo "Note: Self-signed certificate will show security warning - this is expected."
echo ""

# Cleanup
rm -rf "$CERT_DIR"
