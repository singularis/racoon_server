FROM alpine:3.18

RUN apk add --no-cache openssh bash
RUN adduser -D -s /bin/bash proxyuser

# Create directory for sshd
RUN mkdir -p /var/run/sshd

# Create directory for client keys (to be mounted) and host keys
RUN mkdir -p /etc/ssh/client_keys /etc/ssh/server_keys

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose port
EXPOSE 3141

ENTRYPOINT ["/entrypoint.sh"]
