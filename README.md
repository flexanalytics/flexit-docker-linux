
# FlexIt Docker Deployment

This repository provides everything needed to deploy [FlexIt](https://flexitanalytics.com/) using Docker.
FlexIt is a highly powerful and flexible business intelligence and data transformation tool.

---

## Installation Instructions

### 1. Clone this repository

On your linux server, clone this repository to your selected folder:
```bash
git clone https://github.com/flexanalytics/flexit-docker-linux.git
```

> If `git` is not installed, then run `sudo apt update` and `sudo apt install git -y` to install git, then retry the clone.

### 2. Configure Environment Variables

Configuration lives in `.env`, which is not tracked by git. Create it from the template and fill it in deliberately before the first deploy:

```bash
cp .env.template .env
chmod 600 .env
```

At minimum, set:

- `DB_USER`, `DB_PASSWORD`, `DB_NAME` — credentials for the content database. The template password is rejected.
- `FLEXIT_ENCRYPTION_KEY` — a 32-character key that encrypts stored datasource and integration secrets. Generate one with `openssl rand -hex 16`. Keep it somewhere safe and never change it: losing it makes saved secrets unrecoverable.
- `FLEXIT_VERSION` — the FlexIt release to install, or `latest`.
- `DBT_ADAPTERS` — the dbt adapters this install needs, comma-separated with no spaces. Supported: `snowflake`, `redshift`, `postgres`, `oracle`. Installs that leave it unset get `snowflake,redshift`.
- `DLT_DEFAULT_DESTINATION` — the dlt destination: `snowflake`, `redshift`, `postgres`, or `sqlalchemy`. dlt has no native Oracle destination; Oracle installs use `sqlalchemy`. This is only where dlt loads data to: SQL database sources (Oracle, Postgres, MySQL, SQL Server, Snowflake) are always available, whatever destination you pick.
- `DLT_VERIFIED_SOURCES` — dlt verified API sources to pre-install, space-separated, e.g. `filesystem salesforce hubspot`. Defaults to `filesystem`.

These dbt and dlt settings are baked into the image at build time, so changing any of them takes effect on the next restart, which rebuilds. Every supported combination installs the same package versions from `constraints.txt`. To change a version or add an adapter, edit `requirements.in` and regenerate the constraints with the command at the top of `constraints.txt`.

If you're serving over HTTPS through the bundled nginx, also set `USE_NGINX`, `PUBLIC_DNS` and `CERT_PATH` (see [Configure SSL](#configure-ssl)), plus `CERT_EMAIL` and `AUTO_MANAGE_CERTS` for Let's Encrypt.

Every install and restart runs `scripts/check_env.sh` first, and refuses to continue while required values are missing or still set to template placeholders. Run it yourself any time to check a `.env`:

```bash
./scripts/check_env.sh
```

> [!NOTE]
> When `.env.template` gains new keys in a later release, copy them into your `.env` by hand. The template is never applied automatically.

### 3. Install The Software

To install the software, run the below script:
```bash
sudo ./install.sh
```

This installs Docker if needed and starts FlexIt using the values in `.env`. If `.env` doesn't exist yet, the script creates it from the template and walks you through each setting (press Enter to keep the default), then continues with the install. When run without a terminal, it creates `.env` and exits so you can fill it in, then you rerun it.

When `DB_PASSWORD` is still the template default or `FLEXIT_ENCRYPTION_KEY` is empty, the script offers to generate a random value for each. It never replaces a key that is already set. If you generate a new encryption key, back it up right away.

The application will automatically start after this script is complete.
You may need to reboot the server if docker was not previously installed.

### 4. Access FlexIt
Visit the application at:
- **First Install**: `http://localhost:<FLEXIT_PORT>`
- **After Optionally Configuring SSL**: `https://DNS_NAME`

## Configuring the application for production use

### Configure SSL

There are 2 ways to configure SSL for the application:

### 1. Use FlexIt as the reverse proxy

1. Provide a certificate and key file. These files should be placed in a `certs` folder in the `flex_config` directory.
- The files should be named `certificate.pem` and `privatekey.pem`.

> [!NOTE]
> You will have to restart the application after adding the certificate and key files.

```sh
sudo ./scripts/restart_server.sh
# or
docker compose down
docker compose up -d
```

After restarting the server, an administrator can navigate to Configuration > Server Settings and add the Host Name, as well as change the port to 443 and enable ssl.

![Server Settings](https://github.com/user-attachments/assets/1b2399d6-2a88-4fd4-b125-d531654ab08a)


![SSL Settings](https://github.com/user-attachments/assets/3fe63d24-f5f0-40d9-b817-c8e21eb16d21)

2. Update the `FLEXIT_PORT` in `.env` to use port 443.

```dotenv
## -- frontend app setup -- ##
FLEXIT_PORT=443
```
3. Restart the application again.

```sh
sudo ./scripts/restart_server.sh
# or
docker compose down
docker compose up -d
```

4. Access the application at `https://<dns_name_in_settings>`.

### 2. Use the provided Nginx reverse proxy with your own certificate

1. Change the `USE_NGINX` flag from `false` to `true` in the `.env` file.

```dotenv
USE_NGINX=true
```
2. Provide a certificate and key file. These files should be placed in the `certificates` subfolder of the `$CERT_PATH` configured in the `.env` file. For example, with `CERT_PATH=/opt/nginx/certs`, create the folder with `sudo mkdir -p /opt/nginx/certs/certificates` and put the files there.

> [!NOTE]
> The certificate and key files will need to have the naming convention of `PUBLIC_DNS.crt` and `PUBLIC_DNS.key` i.e. `flexit.myserver.com.crt`.
More information can be found in the nginx proxy containers documentation [here](https://github.com/nginx-proxy/nginx-proxy/tree/main/docs#ssl-support)

3. Change the `PUBLIC_DNS` in the `.env` file to the domain name you want to use.

```dotenv
PUBLIC_DNS=your_domain_name
```

4. Restart the application. The `restart_server` script will detect the USE_NGINX flag and start a new container running nginx.

```sh
sudo ./scripts/restart_server.sh
```

### 3. Use the provided Nginx reverse proxy with a Let's Encrypt certificate

1. Change the `USE_NGINX` flag from `false` to `true` in the `.env` file.

```dotenv
USE_NGINX=true
```
2. Change the `PUBLIC_DNS` in the `.env` file to the domain name you want to use.

```dotenv
PUBLIC_DNS=your_domain_name
```

3. Change the `CERT_EMAIL` in the `.env` file to your email address.

```dotenv
CERT_EMAIL=your_email_address
```

4. Change the `AUTO_MANAGE_CERTS` in the `.env` file to `true`.

```dotenv
AUTO_MANAGE_CERTS=true
```

Issued certificates are stored under `$CERT_PATH/certificates`, the same folder nginx reads from.

5. Restart the application. The `restart_server` script will detect the USE_NGINX and AUTO_MANAGE_CERTS flags and start a new container running nginx and the companion container.

```sh
sudo ./scripts/restart_server.sh
```

#### Renewal failures

Renewal runs on every restart, but the ACME client only acts inside its own 30-day window and exits cleanly otherwise. A renewal that *fails* therefore means the certificate is already inside that window.

A single failure is usually transient, and aborting the restart there would leave the stack down. Instead the failure is logged and the restart continues on the existing certificate. Consecutive failures are counted, and once they reach `CERT_RENEW_MAX_FAILURES` the restart aborts loudly — spending the 30-day buffer deliberately instead of either failing on every transient error or staying quiet until the certificate expires.

```dotenv
## -- [optional] certificate renewal -- ##
# Consecutive renewal failures tolerated before a restart aborts.
CERT_RENEW_MAX_FAILURES=3
```

The counter lives at `$CERT_PATH/.renew_failures` and is deleted on the first clean run.

## Auto-Deploy

FlexIt can trigger its own redeploy from the in-app **Configuration → Deployment** view. When an admin clicks "Deploy", the running container writes a marker file at `/opt/flexit/webcontent/.deploy_request`; a cron job on the host watches for that marker and runs `deploy_server.sh` when it's present.

This lets admins update versions, pull new images, or apply config changes from the UI without SSHing into the box.

### Enable on a fresh install

1. Install the cron entry. The repo ships an example at `scripts/crontab.example`:

   ```bash
   sudo crontab -e
   # paste the contents of scripts/crontab.example, adjusting the path
   ```

   The default polls once per minute. The script no-ops silently when there's nothing to deploy, so the load is negligible.

2. Make sure the log file is writable by whichever user owns the crontab. For `sudo crontab -e` (root), `/var/log/flexit-deploy.log` is created on first write.

3. (Optional) Tune behavior via `.env`:

   ```dotenv
   ## -- [optional] auto-deploy behavior -- ##
   # What to do if a deploy fails. "retry" (default) leaves the marker
   # in place so the next cron tick tries again. "clear" removes it
   # after a failure so a misconfigured deploy doesn't loop forever.
   AUTO_DEPLOY_FAIL_BEHAVIOR=retry

   # How many times a failed deploy is retried before the script gives up
   # and logs for manual intervention. Ignored when FAIL_BEHAVIOR=clear.
   AUTO_DEPLOY_MAX_ATTEMPTS=5

   # Where host-side deploy state is kept. Created on first run.
   AUTO_DEPLOY_STATE_DIR=/var/lib/flexit

   # Override the docker invocation (e.g., for rootless or custom binaries).
   # Leave unset to use plain `docker`, falling back to `sudo -n docker`.
   # DOCKER=docker
   ```

### How it works

* The cron script (`scripts/auto_deploy_server.sh`) is **lock-protected** — only one deploy can run at a time even if cron ticks during a long deploy.
* On a successful deploy, the marker is **not** cleared by the host. The newly-booted FlexIt clears it during its own boot-reconcile so it can audit the deploy request first. Don't delete the marker manually.
* On a failed deploy, the marker is left in place by default (so the next tick retries). Set `AUTO_DEPLOY_FAIL_BEHAVIOR=clear` in `.env` to remove it instead.
* A deploy tears the stack down before rebuilding it, so a failure partway through leaves the marker sealed inside a container that no longer exists. The script records the owed retry on the host instead, and will retry with the stack down. After `AUTO_DEPLOY_MAX_ATTEMPTS` consecutive failures it stops and logs a `giving up` line rather than rebuilding every minute forever.

### Deploying by git push

The UI marker requires a healthy container. As a second, out-of-band trigger, the cron script can also watch a branch and deploy whenever it advances — useful when the box is unreachable by SSH, or when FlexIt itself isn't running.

It is off unless `GIT_DEPLOY_BRANCH` is set.

The branch is a **signal, not a payload**. The host stays checked out on its normal branch and deploys that as always; it only watches the named branch for its tip to move. The branch's contents are never checked out or merged.

1. Set the branch in `.env`:

   ```dotenv
   ## -- [optional] git deploy trigger -- ##
   # Branch the host watches. Moving its tip triggers a deploy. Empty disables.
   GIT_DEPLOY_BRANCH=deploy
   ```

2. Nothing else changes — the same cron entry serves both triggers, with the same lock, log, and retry accounting.

Polling uses `git ls-remote`, a single ref query with no object negotiation, so the per-minute cost is one short SSH round trip. Objects are only transferred by the `git pull` that runs as part of an actual deploy.

To force a restart, push a commit to the branch. The next tick (within a minute) sees the tip has moved and redeploys:

```bash
git checkout deploy && git commit --allow-empty -m "restart" && git push
git checkout main
```

The commit's contents are irrelevant — an empty commit is the normal case, since the usual reason to reach for this is restarting a wedged stack rather than shipping code. The host pulls `main` on the way through, so if `main` has advanced you get those changes too; if it hasn't, the pull is a no-op and you get a clean restart.

The revision the host last acted on is recorded in `$AUTO_DEPLOY_STATE_DIR/last_handled_sha`. It's written on success **and** on give-up, so a commit that can't deploy won't retry forever — push a new commit to try again. On the very first tick after enabling, the current tip is recorded without deploying, so arming the trigger doesn't itself cause a deploy.

The host only needs read access to the repo. It never writes back.

### Verify it's working

After installing the cron, trigger a deploy from the FlexIt UI and watch the log:

```bash
sudo tail -f /var/log/flexit-deploy.log
```

You should see the marker payload, the deploy steps, and a `auto-deploy: success` line within a minute.

If you see `cannot access docker` errors in the log, the user running the cron doesn't have docker access. Three fixes:
- Install via `sudo crontab -e` so it runs as root (simplest).
- Add the user to the docker group: `sudo usermod -aG docker $USER` and log out/in.
- Configure passwordless sudo for the docker binary.

## Installing a patch

The standard deployment pulls versions from the repo to deploy standard versions of FlexIt. If a patch is issued and you need to apply a non-standard FlexIt version, then you can follow these instructions to build the new image:

```bash
scp -i /path/to/flexitserver-privatekey.pem "/path/to/flexit/install/installers/flexit-linux-x64-installer.run" ubuntu@1.1.1.1:~/flexit-docker-deploy
ssh -i /path/to/flexitserver-privatekey.pem ubuntu@1.1.1.1
cd flexit-docker-deploy
sudo docker compose down
sudo docker rmi $(sudo docker images -q) #removes all docker images to clear up space
sudo docker compose build
sudo docker compose up --pull missing -d
```

---

## Additional Notes

### Viewing Logs
To view logs for the FlexIt Frontend:
```bash
docker logs <container_name>
```

### Stopping the Application
To stop the application:

```bash
./scripts/stop_server.sh
```

### Restarting the Application
To restart the application:

```bash
sudo ./scripts/restart_server.sh
```

### Health and Automatic Restart
The container's entrypoint watches FlexIt on port 3030. Once FlexIt has answered, or after a startup grace period, consecutive failed checks are counted, and the container exits after too many so Docker's restart policy brings it back. `docker stop` shuts FlexIt down cleanly.

Check status and restart count:

```bash
sudo docker inspect -f '{{.State.Health.Status}} restarts={{.RestartCount}}' flexit-analytics
```

The watchdog can be tuned in `.env`:

```dotenv
## -- [optional] health watchdog -- ##
# Seconds between checks.
HEALTH_INTERVAL=30
# Consecutive failures before the container restarts.
HEALTH_MAX_FAILURES=5
# Seconds before failures count if FlexIt never came up.
HEALTH_START_GRACE=600
```

---

## Troubleshooting
### 1. FlexIt Frontend Not Starting
- Ensure docker is running:
  ```bash
  docker ps
  ```
- Review logs:
  ```bash
  docker logs flexit-analytics
  ```
- Look for watchdog restarts. `FlexIt health check failed (n/5)` lines followed by `FlexIt unresponsive` mean FlexIt stopped answering and the container restarted itself:
  ```bash
  docker logs flexit-analytics 2>&1 | grep -E "health check failed|unresponsive"
  ```

### 2. Auto-Deploy Not Firing
- Confirm the cron is installed: `sudo crontab -l`
- Check the deploy log: `sudo tail -100 /var/log/flexit-deploy.log`
- Trigger a deploy from the UI, then within ~60s check whether the marker appears:
  ```bash
  sudo docker exec flexit-analytics cat /opt/flexit/webcontent/.deploy_request
  ```
  If the marker is missing, the UI deploy action didn't write it — check the FlexIt container logs.
- If the marker is present but cron isn't picking it up, the cron user likely can't access docker (see [Verify it's working](#verify-its-working)).

### 3. Deploy Failed and the Site Is Down
- Check the tail of `/var/log/flexit-deploy.log` for the failing step.
- A retry is owed automatically. If the log ends in `giving up after N failed attempts`, the retries are exhausted and the cause needs fixing before anything else will run.
- To recover by hand: `sudo ./scripts/restart_server.sh`

### 4. Git Push Doesn't Trigger a Deploy
- Confirm the trigger is armed: `GIT_DEPLOY_BRANCH` must be set in `.env`.
- The host stays on its normal branch; it never checks the signal branch out. `git branch --show-current` on the host should show `main`, not the signal branch.
- Compare what the host has acted on against the branch tip:
  ```bash
  cat /var/lib/flexit/last_handled_sha
  git ls-remote origin deploy
  ```
  Matching values mean the host considers that revision handled — either it deployed, or it gave up on it. Push a new commit to retry.
- A failed ref query disables the trigger silently for that tick. Check that the host can reach the remote and that `.git` isn't owned by root:
  ```bash
  sudo -u <repo-owner> git ls-remote origin refs/heads/deploy
  ```

### 5. Saved Credentials Show Garbage or Stop Working
Symptoms: a stored token or password displays as random characters, connections fail with authentication errors, or requests fail with `Invalid character in header content ["Authorization"]`.

The secret was encrypted under a different `FLEXIT_ENCRYPTION_KEY` than the one the container has now. Confirm the container has the key from `.env`:

```bash
sudo docker exec flexit-analytics printenv FLEXIT_ENCRYPTION_KEY | tr -d '\n' | sha256sum
grep '^FLEXIT_ENCRYPTION_KEY=' .env | cut -d= -f2- | tr -d '\n' | sha256sum
```

If the hashes match, the affected secrets were saved under another key, for example copied in from another instance. Re-enter them and save. If you have the original key, restoring it in `.env` recovers every secret saved under it.
