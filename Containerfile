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

COPY system_files/usr/libexec/rexel-set-icons.sh /usr/libexec/rexel-set-icons.sh
COPY system_files/usr/lib/systemd/user/rexel-icons.service /usr/lib/systemd/user/rexel-icons.service
RUN chmod 0755 /usr/libexec/rexel-set-icons.sh && \
    mkdir -p /usr/lib/systemd/user/default.target.wants && \
    ln -sf ../rexel-icons.service /usr/lib/systemd/user/default.target.wants/rexel-icons.service

COPY system_files/usr/share/rexel-vpn/saml_authenticator.py /usr/share/rexel-vpn/saml_authenticator.py
COPY system_files/usr/bin/rexel-vpn /usr/bin/rexel-vpn
COPY system_files/usr/share/applications/rexel-vpn.desktop /usr/share/applications/rexel-vpn.desktop
RUN chmod 0755 /usr/bin/rexel-vpn

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN bootc container lint
