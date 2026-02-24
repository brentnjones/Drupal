# Drupal Troubleshooting: Cache Clearing & Permissions Fix

## Clearing Drupal Cache via PostgreSQL (pgAdmin)

If you cannot access Drush or the Drupal admin UI, you can clear all Drupal cache tables directly in PostgreSQL using pgAdmin:

1. Open pgAdmin and connect to your `drupal-postgres` database.
2. Open a Query Tool window for the database.
3. Run the following SQL command:

```sql
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'cache%')
    LOOP
        EXECUTE 'TRUNCATE TABLE ' || quote_ident(r.tablename) || ' RESTART IDENTITY CASCADE';
    END LOOP;
END $$;
```

This will safely clear all Drupal cache tables.

---

## Fixing File and Directory Permissions

If you encounter errors related to file permissions (such as during install or configuration), ensure the following permissions are set in your Drupal pod:

```sh
oc exec deployment/drupal -n drupal -- chmod u+w /var/www/html/sites/default
oc exec deployment/drupal -n drupal -- chmod u+w /var/www/html/sites/default/settings.php

oc exec deployment/drupal -n drupal -- chmod -R u+w /var/www/html/sites/default/files
```

- `sites/default` should be writable by the web server user during install/configuration.
- `settings.php` should be writable during install/configuration, then set back to read-only for security:


After installation, for security, set settings.php back to read-only:

```sh
oc exec deployment/drupal -n drupal -- chmod u-w /var/www/html/sites/default/settings.php
```

---

Always restore secure permissions after installation is complete.
