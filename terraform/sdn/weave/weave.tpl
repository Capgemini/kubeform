- name: 10-weave.network
  runtime: false
  content: |
    [Match]
    Type=bridge
    Name=weave*
    [Network]
- name: install-weave.service
  enable: true
  content: |
    [Unit]
    After=network-online.target
    After=docker.service
    Before=weave.service
    Description=Install Weave
    Documentation=http://docs.weave.works/
    Requires=network-online.target
    [Service]
    EnvironmentFile=-/etc/weave.%H.env
    EnvironmentFile=-/etc/weave.env
    Type=oneshot
    RemainAfterExit=yes
    TimeoutStartSec=0
    ExecStartPre=/bin/mkdir -p /opt/bin/
    ExecStartPre=/usr/bin/curl \
      --silent \
      --location \
      git.io/weave \
      --output /opt/bin/weave
    ExecStartPre=/usr/bin/chmod +x /opt/bin/weave
    ExecStart=/opt/bin/weave setup
    [Install]
    WantedBy=weave-network.target
    WantedBy=weave.service
- name: weaveproxy.service
  enable: true
  content: |
    [Unit]
    After=install-weave.service
    After=docker.service
    Description=Weave proxy for Docker API
    Documentation=http://docs.weave.works/
    Requires=docker.service
    Requires=install-weave.service
    [Service]
    EnvironmentFile=-/etc/weave.%H.env
    EnvironmentFile=-/etc/weave.env
    ExecStartPre=/opt/bin/weave launch-proxy --rewrite-inspect --without-dns
    ExecStart=/usr/bin/docker attach weaveproxy
    Restart=on-failure
    ExecStop=/opt/bin/weave stop-proxy
    [Install]
    WantedBy=weave-network.target
- name: weave.service
  enable: true
  content: |
    [Unit]
    After=install-weave.service
    After=docker.service
    Description=Weave Network Router
    Documentation=http://docs.weave.works/
    Requires=docker.service
    Requires=install-weave.service
    [Service]
    TimeoutStartSec=0
    EnvironmentFile=-/etc/weave.%H.env
    EnvironmentFile=-/etc/weave.env
    ExecStartPre=/opt/bin/weave launch-router "${peers}"
    ExecStart=/usr/bin/docker attach weave
    Restart=on-failure
    ExecStop=/opt/bin/weave stop-router
    [Install]
    WantedBy=weave-network.target
- name: weave-expose.service
  enable: true
  content: |
    [Unit]
    After=install-weave.service
    After=weave.service
    After=docker.service
    Documentation=http://docs.weave.works/
    Requires=docker.service
    Requires=install-weave.service
    Requires=weave.service
    [Service]
    Type=oneshot
    RemainAfterExit=yes
    TimeoutStartSec=0
    EnvironmentFile=-/etc/weave.%H.env
    EnvironmentFile=-/etc/weave.env
    ExecStart=/opt/bin/weave expose
    ExecStop=/opt/bin/weave hide
    [Install]
    WantedBy=weave-network.target
