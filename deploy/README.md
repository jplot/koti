# Running koti on the NAS

koti runs in Docker: `web` (the Rails app, which also serves the front) and `db` (PostgreSQL 18). Run these commands from the repository root on the NAS.

## First start

1. Copy `deploy/.env.example` to `deploy/.env`, then fill it:
   - `POSTGRES_PASSWORD`: a long random password, for example from `openssl rand -hex 24`;
   - `SECRET_KEY_BASE`: from `openssl rand -hex 64`.
2. Build and start:

   ```sh
   docker compose -f deploy/compose.yml up -d --build
   ```

3. Create the first account from the Rails console, so the password stays out of the shell history:

   ```sh
   docker compose -f deploy/compose.yml exec web bin/rails console
   ```

   ```ruby
   User.create!(email_address: "ana@example.com", password: "…")
   ```

4. Open `http://<nas>:3000`, sign in, and import the plan.

## Upgrade

```sh
git pull
docker compose -f deploy/compose.yml up -d --build
```

The image migrates the database before the server starts. The data lives in the `koti-db` volume.

## Notes

- koti answers plain HTTP on the LAN. Behind a TLS proxy, set `KOTI_TLS=1`: koti then forces HTTPS and marks its session cookie Secure.
- Behind Docker's port mapping, every browser reaches koti from the same address. The sign-in limit by address (10 tries in 3 minutes) then counts for the whole home; the limit by account still applies.
