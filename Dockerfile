# syntax=docker/dockerfile:1

# --- Base image ------------------------------------------------------------
FROM debian:12-slim

# --- Metadata --------------------------------------------------------------
LABEL maintainer="Max Hogan <max@maxhogan.dev>" \
      org.opencontainers.image.title="nextdns-lancache" \
      org.opencontainers.image.description="NextDNS lancache" \
      org.opencontainers.image.source="https://github.com/pmaxhogan/nextdns-lancache" \
      org.opencontainers.image.licenses="MIT"

# --- Timezone --------------------------------------------------------------
ENV TZ="America/Chicago"

# --- Packages --------------------------------------------------------------
# Add bash, curl, jq, git, envsubst, cron (busybox includes crond), tzdata for zone info
RUN apt-get update && apt-get install -y --no-install-recommends cron gettext-base ca-certificates \
      bash \
      curl \
      jq \
      git \
      tzdata unzip wget && \
    # Set the local timezone inside the image
    cp /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo "${TZ}" > /etc/timezone; \
# clean apt caches to keep the image small
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*;

# --- Application files -----------------------------------------------------
COPY script.sh /script.sh
COPY config.template.json /config.template.json

RUN chmod +x /script.sh && \
# Register the daily cron (02:00 container local time)
    echo "0 2 * * * root /bin/bash /script.sh" > /etc/cron.d/daily_script && \
    chmod 0644 /etc/cron.d/daily_script && \
    crontab /etc/cron.d/daily_script

# These will be overridden at deploy time in TrueNAS, but documenting them
ENV CACHE_IP="" \
    NEXTDNS_API_KEY=""

# 1. Run the script immediately (first‑run)                                
# 2. Launch cron in the foreground so the container stays healthy for TrueNAS
ENTRYPOINT ["/bin/sh", "-ec", "/script.sh && exec /usr/sbin/crond -f"]

# Default command (not strictly necessary; cron holds the PID)
CMD []
