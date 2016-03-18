- name: flanneld.service
  command: start
  drop-ins:
    - name: 50-network-config.conf
      content: |
        [Unit]
        Requires=etcd2.service
        [Service]
        ExecStartPre=/usr/bin/etcdctl set /coreos.com/network/config '{"Network": "10.2.0.0/16", "Backend": {"Type": "vxlan"}}'
