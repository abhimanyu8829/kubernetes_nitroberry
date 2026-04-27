#!/bin/bash
# Configuration script for Nitroberry deployment

# Set your values here
YOUR_DOMAIN="yourdomain.com"
YOUR_IP_RANGE="10.0.0.100-10.0.0.150"
YOUR_EMAIL="admin@yourdomain.com"
YOUR_DB_PASSWORD="YourSecurePass123!"
YOUR_REGISTRY="yourregistry.com"
IMAGE_TAG="v1.0.0"

# Update MetalLB IP range
sed -i "s/192\.168\.49\.200-192\.168\.49\.250/$YOUR_IP_RANGE/" 01-metallb.yaml

# Update domain in all YAML files
find . -name "*.yaml" -exec sed -i "s/nitroberry\.com/$YOUR_DOMAIN/g" {} \;

# Update Let's Encrypt email
sed -i "s/admin@nitroberry\.com/$YOUR_EMAIL/" 04-traefik-install.yaml

# Update database password
find . -name "*.yaml" -exec sed -i "s/nitroberry-secret-password/$YOUR_DB_PASSWORD/" {} \;

# Update container images
find . -name "*.yaml" -exec sed -i "s|nitroberry/|$YOUR_REGISTRY/|g" {} \;
find . -name "*.yaml" -exec sed -i "s/:latest/:$IMAGE_TAG/" {} \;

echo "Configuration updated successfully!"
echo "Domain: $YOUR_DOMAIN"
echo "IP Range: $YOUR_IP_RANGE"
echo "Email: $YOUR_EMAIL"
echo "Registry: $YOUR_REGISTRY"
echo "Image Tag: $IMAGE_TAG"