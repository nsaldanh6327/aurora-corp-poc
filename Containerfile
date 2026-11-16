FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

FROM ghcr.io/ublue-os/aurora:stable

RUN mkdir -p /etc/opt/edge/policies/managed
COPY m365_pwas.json /etc/opt/edge/policies/managed/m365_pwas.json

RUN mkdir -p /usr/share/edge-policy
COPY m365_pwas.json /usr/share/edge-policy/m365_pwas.json
COPY edge-policy.service /usr/lib/systemd/system/edge-policy.service
RUN systemctl enable edge-policy.service


RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN bootc container lint
