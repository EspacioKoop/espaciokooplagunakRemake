FROM python:3.12-slim-bookworm AS build
WORKDIR /opt/lagunak
COPY tools/bootstrap.py tools/export_targets.py ./tools/
RUN python3 tools/bootstrap.py
COPY game/ ./game/
RUN .toolchain/godot --headless --editor --path game --quit

FROM python:3.12-slim-bookworm AS runtime
WORKDIR /opt/lagunak
COPY --from=build /opt/lagunak/.toolchain/godot /usr/local/bin/godot
COPY --from=build /opt/lagunak/game/ ./game/
COPY server/*.py server/*.gd ./server/
COPY LICENSE CREDITS.md ./
COPY third_party/ ./third_party/
RUN mkdir -p /var/lib/lagunak && chown 10001:10001 /var/lib/lagunak
ENV XDG_DATA_HOME=/var/lib/lagunak \
    LAGUNAK_RUNTIME_DIR=/tmp/lagunak-runtime \
    LAGUNAK_KEY_FILE=/run/secrets/session_key \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
USER 10001:10001
EXPOSE 27840/udp
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=5s --timeout=2s --start-period=15s --retries=3 CMD ["python3", "/opt/lagunak/server/healthcheck.py"]
ENTRYPOINT ["python3", "/opt/lagunak/server/launch.py"]
