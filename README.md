
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

The repo's `.env` file defines project-level variables. Should you need to update ports or install versions, you can edit them there. Otherwise keep the defaults.

```dotenv
## -- frontend app setup -- ##
FLEXIT_PORT=3030
FLEXIT_VERSION=latest

## -- backend db setup -- ##
CONTENT_DB_VERSION=latest
DB_PORT=5432

## -- Optional nginx setup -- ##
USE_NGINX=false
CERT_PATH=/etc/nginx/certs
PUBLIC_DNS=myserver.mydomain.com
NGINX_HTTPS_PORT=443
NGINX_HTTP_PORT=80
```

See the [Configure SSL](#configure-ssl) section below for details on how to enable HTTPS/SSL. The above configuration uses the [Nginx with your certs](#2-use-the-provided-nginx-reverse-proxy-with-your-own-certificate) configuration, which would require you to set `USE_NGINX=true` and then the following:
1. The `/etc/nginx/certs` folder
2. The `myserver.mydomain.com.crt` certificate file under that folder
3. The `myserver.mydomain.com.key` private key file under that folder

### 3. Install The Software

To install the software, run the below script:
```bash
sudo ./install.sh
```

This will install the needed software and allow you to configure the backend credentials.

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
2. Provide a certificate and key file. These files should be placed in the `$CERT_PATH` folder that's configured in the `.env` file. If you're not sure where to put the certs folder, you can put them in `/etc/nginx/certs`, which may need to be created with the `sudo mkdir -p /etc/nginx/certs/` command.

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

5. Restart the application. The `restart_server` script will detect the USE_NGINX and AUTO_MANAGE_CERTS flags and start a new container running nginx and the companion container.

```sh
sudo ./scripts/restart_server.sh
```

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

   # Override the docker invocation (e.g., for rootless or custom binaries).
   # Leave unset to use plain `docker`, falling back to `sudo -n docker`.
   # DOCKER=docker
   ```

### How it works

* The cron script (`scripts/auto_deploy_server.sh`) is **lock-protected** — only one deploy can run at a time even if cron ticks during a long deploy.
* On a successful deploy, the marker is **not** cleared by the host. The newly-booted FlexIt clears it during its own boot-reconcile so it can audit the deploy request first. Don't delete the marker manually.
* On a failed deploy, the marker is left in place by default (so the next tick retries). Set `AUTO_DEPLOY_FAIL_BEHAVIOR=clear` in `.env` to remove it instead.

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

### 2. Auto-Deploy Not Firing
- Confirm the cron is installed: `sudo crontab -l`
- Check the deploy log: `sudo tail -100 /var/log/flexit-deploy.log`
- Trigger a deploy from the UI, then within ~60s check whether the marker appears:
  ```bash
  sudo docker exec flexit-analytics cat /opt/flexit/webcontent/.deploy_request
  ```
  If the marker is missing, the UI deploy action didn't write it — check the FlexIt container logs.
- If the marker is present but cron isn't picking it up, the cron user likely can't access docker (see [Verify it's working](#verify-its-working)).
