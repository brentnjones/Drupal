# Scaling Crunchy Data PostgreSQL Cluster on OpenShift

To scale your PostgreSQL cluster up or down, use the following `oc patch` commands. Replace `drupal-postgres` and `drupal` with your actual cluster and namespace names if different.

## Scale Up (Increase Nodes)

To scale to 5 nodes:

```sh
oc patch postgrescluster drupal-postgres -n drupal --type='json' -p='[{"op":"replace","path":"/spec/instances/0/replicas","value":5}]'
```

## Scale Down (Decrease Nodes)

To scale down to 2 nodes:

```sh
oc patch postgrescluster drupal-postgres -n drupal --type='json' -p='[{"op":"replace","path":"/spec/instances/0/replicas","value":2}]'
```

## Notes
- The Crunchy Data operator will automatically adjust the number of PostgreSQL pods.
- Scaling up increases high availability and capacity; scaling down reduces resource usage.
- Always monitor pod status after scaling:

```sh
oc get pods -n drupal | grep drupal-postgres
```
