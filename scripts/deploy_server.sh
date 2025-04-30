
#!/bin/bash

set -e  # Exit immediately if a command fails

# Change to script directory to ensure relative paths work
cd "$(dirname "$0")"

# Restart docker
./restart_server.sh

# Copy any files in volumes/ to the container
CONTAINER_NAME=flexit-analytics

cd ..

# Recursively copy the contents of volumes/ to the same folder the container
find volumes/ -type f | while read -r file; do
    # Remove the 'volumes/' prefix
    target_path="/${file#volumes/}"

    # Create target directory inside the container if needed
    dir_path=$(dirname "$target_path")
    sudo docker exec "$CONTAINER_NAME" mkdir -p "$dir_path"

    # Copy file to container
    sudo docker cp "$file" "$CONTAINER_NAME:$target_path"
done

# restart FlexIt after copying files
echo 'Restarting FlexIt Service'
sudo docker exec flexit-analytics /bin/bash -c "/opt/flexit/bin/start_flexit &"
echo 'FlexIt Service Restarted'
