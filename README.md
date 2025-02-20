
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
