#!/usr/bin/env bash
# Run once after first docker compose up to initialise Garage.
# Usage: ./scripts/setup-garage.sh

set -euo pipefail

CONTAINER="pree-it-garage-1"

echo "[1/4] Reading node ID..."
NODE_ID=$(docker exec "$CONTAINER" /garage node id -q | cut -d@ -f1)

echo "[2/4] Assigning layout (single node, zone=local, capacity=10G)..."
docker exec "$CONTAINER" /garage layout assign \
  -z local -c 10G "$NODE_ID"

echo "[3/4] Applying layout..."
docker exec "$CONTAINER" /garage layout apply --version 1

echo "[4/4] Creating bucket and access key..."
docker exec "$CONTAINER" /garage bucket create preeit-media
docker exec "$CONTAINER" /garage key create preeit-media-key
docker exec "$CONTAINER" /garage bucket allow preeit-media \
  --read --write --owner --key preeit-media-key

echo ""
echo "Garage S3 credentials:"
docker exec "$CONTAINER" /garage key info preeit-media-key