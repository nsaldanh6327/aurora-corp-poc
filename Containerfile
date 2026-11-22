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

# Install openconnect, openconnect-sso, and Chrome SAML authenticator into /usr (bootc-compliant)
RUN dnf install -y \
      openconnect \
      python3-pip \
      python3-lxml \
      python3-requests \
      python3-keyring \
      python3-pysocks \
      python3-toml \
      python3-colorama \
      python3-prompt-toolkit \
      python3-pyxdg && \
    pip install --prefix=/usr --no-cache-dir \
      structlog attrs pyotp beautifulsoup4 signalrcore websockets aiohttp && \
    pip install --prefix=/usr --no-cache-dir --no-deps openconnect-sso && \
    csplit -s -z -f /etc/ssl/certs/ca- -b "%03d.pem" /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem '/-----BEGIN CERTIFICATE-----/' '{*}' && \
    openssl rehash /etc/ssl/certs && \
    dnf clean all

COPY system_files/usr/share/rexel-vpn/saml_authenticator.py /usr/share/rexel-vpn/saml_authenticator.py
COPY system_files/usr/bin/rexel-vpn /usr/bin/rexel-vpn
COPY system_files/usr/share/applications/rexel-vpn.desktop /usr/share/applications/rexel-vpn.desktop
RUN chmod 0755 /usr/bin/rexel-vpn && \
    cp /usr/share/rexel-vpn/saml_authenticator.py /usr/lib/python*/site-packages/openconnect_sso/saml_authenticator.py

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN bootc container lint
