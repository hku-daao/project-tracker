Place HKU test server TLS files here (not committed to git):

  nginx.crt
  nginx.key

First-time setup on 147.8.203.132 (copy from IT POC, then stop the POC stack):

  mkdir -p docker/nginx/ssl
  cp /var/www/my-fullstack-app/nginx/ssl/nginx.crt docker/nginx/ssl/
  cp /var/www/my-fullstack-app/nginx/ssl/nginx.key docker/nginx/ssl/
  chmod 600 docker/nginx/ssl/nginx.key

Or run: ./scripts/setup_hku_test_ssl.sh
