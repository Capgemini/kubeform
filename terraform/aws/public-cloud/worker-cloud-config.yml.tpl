#cloud-config
coreos:
  etcd2:
    proxy: on
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    discovery: ${etcd_discovery_url}
  fleet:
    metadata: "role=worker,region=${region}"
    public-ip: "$public_ipv4"
    etcd_servers: "http://localhost:2379"
  locksmith:
    endpoint: "http://localhost:2379"
  units:
    - name: setup-network-environment.service
      command: start
      content: |
        [Unit]
        Description=Setup Network Environment
        Documentation=https://github.com/kelseyhightower/setup-network-environment
        Requires=network-online.target
        After=network-online.target

        [Service]
        ExecStartPre=-/usr/bin/mkdir -p /opt/bin
        ExecStartPre=/usr/bin/curl -L -o /opt/bin/setup-network-environment -z /opt/bin/setup-network-environment https://github.com/kelseyhightower/setup-network-environment/releases/download/1.0.1/setup-network-environment
        ExecStartPre=/usr/bin/chmod +x /opt/bin/setup-network-environment
        ExecStart=/opt/bin/setup-network-environment
        RemainAfterExit=yes
        Type=oneshot
    - name: flanneld.service
      command: start
      drop-ins:
        - name: 50-network-config.conf
          content: |
            [Unit]
            Requires=etcd2.service
            [Service]
            ExecStartPre=/usr/bin/etcdctl set /coreos.com/network/config '{"Network": "10.2.0.0/16", "Backend": {"Type": "vxlan"}}'
    - name: format-ebs-volume.service
      command: start
      content: |
        [Unit]
        Description=Formats the ebs volume if needed
        Before=docker.service
        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/bin/bash -c '(/usr/sbin/blkid -t TYPE=ext4 | grep /dev/xvdb) || (/usr/sbin/wipefs -fa /dev/xvdb && /usr/sbin/mkfs.ext4 /dev/xvdb)'
    - name: var-lib-docker.mount
      command: start
      content: |
        [Unit]
        Description=Mount ephemeral to /var/lib/docker
        Requires=format-ebs-volume.service
        After=format-ebs-volume.service
        [Mount]
        What=/dev/xvdb
        Where=/var/lib/docker
        Type=ext4
    - name: docker.service
      command: start
      drop-ins:
        - name: 10-wait-docker.conf
          content: |
            [Unit]
            After=var-lib-docker.mount
            After=flanneld.service
            Requires=flanneld.Service
            Requires=var-lib-docker.mount
            Restart=always
    - name: etcd2.service
      command: start
  update:
    reboot-strategy: best-effort
write_files:
  - path: /run/systemd/system/etcd.service.d/30-certificates.conf
    permissions: 0644
    content: |
      [Service]
      Environment=ETCD_CA_FILE=/etc/ssl/etcd/certs/ca.pem
      Environment=ETCD_CERT_FILE=/etc/ssl/etcd/certs/etcd.pem
      Environment=ETCD_KEY_FILE=/etc/ssl/etcd/private/etcd.pem
      Environment=ETCD_PEER_CA_FILE=/etc/ssl/etcd/certs/ca.pem
      Environment=ETCD_PEER_CERT_FILE=/etc/ssl/etcd/certs/etcd.pem
      Environment=ETCD_PEER_KEY_FILE=/etc/ssl/etcd/private/etcd.pem
  - path: /etc/ssl/etcd/certs/ca.pem
    permissions: 0644
    content: "${etcd_ca}"
  - path: /etc/ssl/etcd/certs/etcd.pem
    permissions: 0644
    content: "${etcd_cert}"
  - path: /etc/ssl/etcd/private/etcd.pem
    permissions: 0644
    content: "${etcd_key}"
manage_etc_hosts: localhost
