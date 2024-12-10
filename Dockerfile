# Use an official lightweight base image
FROM alpine:latest

# Set the working directory to root
WORKDIR /

# Copy the script to /usr/bin and rename it
COPY foobar.sh /usr/bin/tyk-sync-foobar

# Make the script executable
RUN chmod +x /usr/bin/tyk-sync-foobar

# Set the entrypoint
ENTRYPOINT ["/usr/bin/tyk-sync-foobar"]