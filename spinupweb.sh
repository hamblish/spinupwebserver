#!/bin/bash

# Step 1: Check prerequisites and confirm with the user
echo "Before running this script, please ensure that you have docker-compose installed,"
echo "are executing this script from the desired directory, have port forwarding set up,"
echo "and have a DNS pointing to your server's public IP."
echo "You also need to provide an email address for updates."
read -p "Do you want to proceed? (y/n): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Script aborted."
    exit 0
fi

# Step 2: Ask for DNS name
read -p "Enter your preconfigured DNS name: " userdns

# Step 3: Ask for email address
read -p "Enter your email address: " useremail

# Step 4: Ask for container name
read -p "Enter the name for the container: " containername

# Step 5: Create nginx-ssl directory
mkdir nginx-ssl

# Step 6: Create docker-compose.yml file
cat <<EOF >nginx-ssl/docker-compose.yml
version: '3.4'

services:
  web:
    image: nginx:1.14.2-alpine
    container_name: $containername-web
    restart: always
    volumes:
      - ./public_html:/public_html
      - ./conf.d:/etc/nginx/conf.d/
      - ./dhparam:/etc/nginx/dhparam
      - ./certbot/conf/:/etc/nginx/ssl/
      - ./certbot/data:/usr/share/nginx/html/letsencrypt
    ports:
      - 80:80
      - 443:443

  certbot:
     image: certbot/certbot:latest
     container_name: $containername-certbot
     command: certonly --webroot --webroot-path=/usr/share/nginx/html/letsencrypt --email $useremail --agree-tos --no-eff-email -d $userdns
     volumes:
       - ./certbot/conf/:/etc/letsencrypt
       - ./certbot/logs/:/var/log/letsencrypt
       - ./certbot/data:/usr/share/nginx/html/letsencrypt
EOF

# Step 7: Create public_html directory and index.html file
mkdir nginx-ssl/public_html
cat <<EOF >nginx-ssl/public_html/index.html
<!DOCTYPE html>
<html>
<head>
  <link rel="stylesheet" type="text/css" href="styles.css">
</head>
<body>
  <div class="container">
    <h1>Hello, World!</h1>
    <p>Welcome to my website.</p>
  </div>
</body>
</html>
EOF

# Step 8: Create dhparam directory and generate dhparam key
mkdir nginx-ssl/dhparam
openssl dhparam -out nginx-ssl/dhparam/dhparam-2048.pem 2048

# Step 9: Create conf.d directory and default.conf file
mkdir nginx-ssl/conf.d
cat <<EOF >nginx-ssl/conf.d/default.conf
server {
    listen 80;
    server_name $userdns;
    root /public_html/;

    # Letsencrypt validation
    location ~ /.well-known/acme-challenge {
        allow all;
        root /usr/share/nginx/html/letsencrypt;
    }
}
EOF

# Step 10: Start the containers
cd nginx-ssl
sudo docker-compose up -d

# Step 11: Delay for 1 minute
echo "Waiting for 10 seconds..."
sleep 10

# Step 12: Modify default.conf for HTTPS redirection
cat <<EOF >conf.d/default.conf
server {
    listen 80;
    server_name $userdns;
    root /public_html/;

    location ~ /.well-known/acme-challenge {
        allow all;
        root /usr/share/nginx/html/letsencrypt;
    }

    location / {
        return 301 https://$userdns\$request_uri;
    }
}

server {
     listen 443 ssl http2;
     server_name $userdns;
     root /public_html/;

     ssl on;
     server_tokens off;
     ssl_certificate /etc/nginx/ssl/live/$userdns/fullchain.pem;
     ssl_certificate_key /etc/nginx/ssl/live/$userdns/privkey.pem;
     ssl_dhparam /etc/nginx/dhparam/dhparam-2048.pem;
     
     ssl_buffer_size 8k;
     ssl_protocols TLSv1.2 TLSv1.1 TLSv1;
     ssl_prefer_server_ciphers on;
     ssl_ciphers ECDH+AESGCM:ECDH+AES256:ECDH+AES128:DH+3DES:!ADH:!AECDH:!MD5;

    location / {
        index index.html;
    }
}
EOF

# Step 13: Restart containers
sudo docker-compose down
sudo docker-compose up -d

# Step 14: Success message
echo "Hooray! Your Secure Web Server has been created successfully. Enjoy!"
