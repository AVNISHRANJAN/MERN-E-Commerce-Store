# MERN E-Commerce Store Deployment Guide

This guide deploys the MERN application with Docker, MongoDB, host-level Nginx, and HTTPS on port `443`.

## Final Architecture

```text
Internet
   |
   | HTTPS :443
   v
Host Nginx + SSL certificate
   |
   | http://127.0.0.1:8080
   v
Frontend Docker container (Nginx :80)
   |
   | /api/* and /uploads/*
   v
Backend Docker container (:5000)
   |
   v
MongoDB Docker container (:27017)
```

Only host port `443` is public. Docker frontend port `8080` is bound to localhost, and ports `5000` and `27017` are not published.

## Requirements

- Ubuntu VPS or cloud server
- A domain name
- DNS access for the domain
- Docker Engine
- Docker Compose plugin
- SSH access to the server

## 1. Configure DNS

Create these DNS A records and point them to the server public IP:

```text
yourdomain.com     -> SERVER_PUBLIC_IP
www.yourdomain.com -> SERVER_PUBLIC_IP
```

Replace `yourdomain.com` everywhere in this guide with your real domain.

## 2. Connect to the Server

```bash
ssh root@SERVER_PUBLIC_IP
```

For a non-root user, use `sudo` with the commands below.

## 3. Install Docker and Git

```bash
apt update
apt install -y docker.io docker-compose-plugin git
systemctl enable --now docker
```

Verify the installation:

```bash
docker --version
docker compose version
```

## 4. Clone the Project

```bash
git clone <repository-url>
cd MERN-E-Commerce-Store
```

## 5. Create Production Environment Variables

Create a root `.env` file:

```bash
nano .env
```

Add production values:

```env
JWT_SECRET=replace-with-a-long-random-secret
PAYPAL_CLIENT_ID=your-paypal-client-id
```

Do not commit `.env` to Git. MongoDB is configured automatically by Docker Compose with this internal connection:

```text
mongodb://mongo:27017/huxnStore
```

## 6. Build and Start Docker Services

The Compose configuration uses this private port forwarding:

```yaml
ports:
  - "127.0.0.1:8080:80"
```

Start the services:

```bash
docker compose up -d --build
```

Check the service status:

```bash
docker compose ps
```

Test the frontend locally on the server:

```bash
curl http://127.0.0.1:8080
```

View logs if needed:

```bash
docker compose logs -f
docker compose logs -f backend
```

At this point the application is available only on the server at `http://127.0.0.1:8080`.

## 7. Install Host Nginx and Certbot

```bash
apt install -y nginx certbot python3-certbot-nginx
```

## 8. Allow Only Required Firewall Ports

Allow SSH and HTTPS:

```bash
ufw allow 22/tcp
ufw allow 443/tcp
ufw deny 80/tcp
ufw enable
ufw status
```

Port `80` is intentionally not public. Port `8080` is private because Docker binds it to `127.0.0.1`.

## 9. Create the SSL Certificate

Use the DNS challenge so port `80` does not need to be exposed:

```bash
certbot certonly --manual --preferred-challenges dns \
  -d yourdomain.com -d www.yourdomain.com
```

Certbot will show DNS TXT records. Add the requested TXT records at your DNS provider, wait for DNS propagation, and continue the Certbot prompt.

The certificates will normally be created under:

```text
/etc/letsencrypt/live/yourdomain.com/fullchain.pem
/etc/letsencrypt/live/yourdomain.com/privkey.pem
```

## 10. Configure Host Nginx for HTTPS

Copy the included example configuration:

```bash
cp deploy/nginx-ssl.conf.example /etc/nginx/sites-available/mern-store
```

Edit it and replace both occurrences of `yourdomain.com` with your real domain:

```bash
nano /etc/nginx/sites-available/mern-store
```

The important proxy target is:

```nginx
proxy_pass http://127.0.0.1:8080;
```

Enable the site:

```bash
ln -s /etc/nginx/sites-available/mern-store /etc/nginx/sites-enabled/mern-store
nginx -t
systemctl enable --now nginx
systemctl reload nginx
```

## 11. Test HTTPS

Open the application in a browser:

```text
https://yourdomain.com
```

Test from the server:

```bash
curl -I https://yourdomain.com
```

Check the certificate:

```bash
certbot certificates
```

## 12. Updating the Application

After pushing new code to the repository:

```bash
cd MERN-E-Commerce-Store
git pull
docker compose up -d --build
```

Check the updated services:

```bash
docker compose ps
docker compose logs -f --tail=100
```

## 12A. GitHub Actions CI/CD

The workflow at `.github/workflows/ci-cd.yml` runs CI for pushes and pull requests to `main`. It installs dependencies, lints and builds the frontend, and builds both Docker images. A push to `main` deploys automatically after CI passes.

Add these repository or production-environment secrets in GitHub:

```text
DEPLOY_HOST       Server public IP or hostname
DEPLOY_USER       SSH user, for example ubuntu
DEPLOY_SSH_KEY    Private SSH key for that server
DEPLOY_PORT       SSH port, usually 22
DEPLOY_PATH       Absolute project path, for example /opt/mern-store
```

Before the first automated deployment, prepare the server manually:

```bash
cd /opt/mern-store
git clone <repository-url> .
nano .env
docker compose up -d --build
```

The server's deployment user must be able to run Docker and read the repository. Keep `.env` only on the server; do not add it to GitHub Secrets unless the workflow explicitly needs to create it.

## 13. Stop and Restart

Stop the containers without deleting database data:

```bash
docker compose down
```

Start them again:

```bash
docker compose up -d
```

Do not use this unless you intentionally want to delete MongoDB and upload volumes:

```bash
docker compose down -v
```

## 14. Data Persistence

Docker Compose stores data in named volumes:

- `mongo_data`: MongoDB database data
- `uploads_data`: uploaded files from the backend

These volumes survive normal `docker compose down` and container rebuilds.

## Troubleshooting

### Check all containers

```bash
docker compose ps
```

### Backend logs

```bash
docker compose logs backend
```

### Nginx logs

```bash
tail -f /var/log/nginx/error.log
 tail -f /var/log/nginx/access.log
```

### Check which ports are listening

```bash
ss -tulpn
```

Expected public listener:

```text
443
```

The Docker frontend should be listening only on:

```text
127.0.0.1:8080
```

### Nginx configuration error

```bash
nginx -t
systemctl status nginx
```

Make sure the certificate files exist and the domain names in the Nginx config are correct.

### Frontend loads but API fails

Check that the backend is running and that the Docker frontend Nginx configuration contains:

```nginx
location /api/ {
    proxy_pass http://backend:5000;
}
```

Then rebuild the frontend image:

```bash
docker compose up -d --build
```

### SSL certificate renewal

The manual DNS certificate requires DNS verification during renewal. Check its expiry:

```bash
certbot certificates
```

Renew it before expiry using the same DNS challenge command, then reload Nginx:

```bash
systemctl reload nginx
```
