#!/bin/bash
#author: ristory
#基础准备(ALL-NODE)
sed -i '$a export PATH=/usr/k8s/bin:$PATH' /etc/profile
sed -i '$a 192.168.10.213 k8s-api.virtual.local k8s-api' /etc/hosts
mkdir -p /usr/k8s/bin
cd /usr/k8s/bin
wget http://ftp.netty.cc/k8s/env.sh
sed -i '$a source /usr/k8s/bin/env.sh' /etc/profile
source /etc/profile
#下载cfssl(ALL-NODE)
cd /usr/k8s/bin
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
chmod a+x cfssl_linux-amd64
mv cfssl_linux-amd64 /usr/k8s/bin/cfssl
wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x cfssljson_linux-amd64
mv cfssljson_linux-amd64 /usr/k8s/bin/cfssljson
wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
chmod +x cfssl-certinfo_linux-amd64
mv cfssl-certinfo_linux-amd64 /usr/k8s/bin/cfssl-certinfo
wget http://ftp.netty.cc/k8s/ca-config.json
wget http://ftp.netty.cc/k8s/ca-csr.json
#CA证书cfssl(ONE-NODE),上传到ftp备用
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
#证书分发(ALL-NODE)
mkdir -p /etc/kubernetes/ssl
cd /etc/kubernetes/ssl
wget http://ftp.netty.cc/k8s/ca-config.json
wget http://ftp.netty.cc/k8s/ca-csr.json
wget http://ftp.netty.cc/k8s/ca-key.pem
wget http://ftp.netty.cc/k8s/ca.csr
wget http://ftp.netty.cc/k8s/ca.pem
#部署etcd集群(ALL-ETCD)
wget https://github.com/coreos/etcd/releases/download/v3.3.4/etcd-v3.3.4-linux-amd64.tar.gz
tar -zxvf etcd-v3.3.4-linux-amd64.tar.gz
mv etcd-v3.3.4-linux-amd64/etcd* /usr/k8s/bin/
mkdir -p /etc/etcd/ssl
cd /etc/etcd/ssl
cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "${NODE_IP}"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
mkdir -p /var/lib/etcd
cd /var/lib/etcd
cat > etcd.service <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
ExecStart=/usr/k8s/bin/etcd \\
  --name=${NODE_NAME} \\
  --cert-file=/etc/etcd/ssl/etcd.pem \\
  --key-file=/etc/etcd/ssl/etcd-key.pem \\
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \\
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \\
  --trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --initial-advertise-peer-urls=https://${NODE_IP}:2380 \\
  --listen-peer-urls=https://${NODE_IP}:2380 \\
  --listen-client-urls=https://${NODE_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://${NODE_IP}:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
mv etcd.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable etcd
systemctl start etcd
systemctl status etcd
#etcd集群健康检查(ONE-ETCD)(非必须)
for ip in ${NODE_IPS}; do
  ETCDCTL_API=3 /usr/k8s/bin/etcdctl \
  --endpoints=https://${ip}:2379  \
  --cacert=/etc/kubernetes/ssl/ca.pem \
  --cert=/etc/etcd/ssl/etcd.pem \
  --key=/etc/etcd/ssl/etcd-key.pem \
  endpoint health; done

#安装kubctl
export KUBE_APISERVER="https://${MASTER_URL}" 
#还没有安装haproxy:6443
wget https://dl.k8s.io/v1.10.0/kubernetes-client-linux-amd64.tar.gz
tar -xzvf kubernetes-client-linux-amd64.tar.gz
cp kubernetes/client/bin/kube* /usr/k8s/bin/
chmod a+x /usr/k8s/bin/kube*


#ONE NODE
mkdir -p /etc/kubectl/ssl
cd /etc/kubectl/ssl

cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes admin-csr.json | cfssljson -bare admin
mv admin*.pem /etc/kubernetes/ssl/
kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER}
kubectl config set-credentials admin \
  --client-certificate=/etc/kubernetes/ssl/admin.pem \
  --embed-certs=true \
  --client-key=/etc/kubernetes/ssl/admin-key.pem \
  --token=${BOOTSTRAP_TOKEN}
kubectl config use-context kubernetes
##分发kubeconfig 文件
##将~/.kube/config文件拷贝到运行kubectl命令的机器的~/.kube/目录下去。
mkdir -p ~/.kube/
cd ~/.kube/
wget http://ftp.netty.cc/k8s/config
#Flannel SSL (ALL-NODE) 
mkdir -p /etc/flanneld/ssl
cd /etc/flanneld/ssl
cat > flanneld-csr.json <<EOF
{
  "CN": "flanneld",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes flanneld-csr.json | cfssljson -bare flanneld
#仅一次(ONLY ONE TIME)
etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'
#安装flannel(ALL-NODE) 
cd ~
mkdir -p flannel
wget https://github.com/coreos/flannel/releases/download/v0.10.0/flannel-v0.10.0-linux-amd64.tar.gz
tar -zxvf flannel-v0.10.0-linux-amd64.tar.gz -C flannel
cp flannel/{flanneld,mk-docker-opts.sh} /usr/k8s/bin

cat > flanneld.service <<EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
ExecStart=/usr/k8s/bin/flanneld \\
  -etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  -etcd-certfile=/etc/flanneld/ssl/flanneld.pem \\
  -etcd-keyfile=/etc/flanneld/ssl/flanneld-key.pem \\
  -etcd-endpoints=${ETCD_ENDPOINTS} \\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX}
ExecStartPost=/usr/k8s/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF
cp flanneld.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable flanneld
systemctl start flanneld
systemctl status flanneld

#检查flanneld 服务
#ifconfig flannel.1

#部署Master
wget https://dl.k8s.io/v1.10.0/kubernetes-server-linux-amd64.tar.gz
tar -xzvf kubernetes-server-linux-amd64.tar.gz
cp kubernetes/server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler} /usr/k8s/bin/
cd /etc/kubernetes/ssl
cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "${NODE_IP}",
    "${MASTER_URL}",
    "${CLUSTER_KUBERNETES_SVC_IP}",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes

#创建kube-apiserver 使用的客户端token 文件
cd /etc/kubernetes/
wget http://ftp.netty.cc/k8s/audit-policy.yaml
cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

cat  > kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=/usr/k8s/bin/kube-apiserver \\
  --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --advertise-address=${NODE_IP} \\
  --bind-address=0.0.0.0 \\
  --insecure-bind-address=${NODE_IP} \\
  --authorization-mode=Node,RBAC \\
  --runtime-config=rbac.authorization.k8s.io/v1alpha1 \\
  --kubelet-https=true \\
  --enable-bootstrap-token-auth \\
  --token-auth-file=/etc/kubernetes/token.csv \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --service-node-port-range=${NODE_PORT_RANGE} \\
  --tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem \\
  --tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --client-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  --etcd-certfile=/etc/kubernetes/ssl/kubernetes.pem \\
  --etcd-keyfile=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --etcd-servers=${ETCD_ENDPOINTS} \\
  --enable-swagger-ui=true \\
  --allow-privileged=true \\
  --apiserver-count=2 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/lib/audit.log \\
  --audit-policy-file=/etc/kubernetes/audit-policy.yaml \\
  --event-ttl=1h \\
  --logtostderr=true \\
  --v=6
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
cp kube-apiserver.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable kube-apiserver
systemctl start kube-apiserver
systemctl status kube-apiserver

cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/k8s/bin/kube-controller-manager \\
  --address=127.0.0.1 \\
  --master=http://${MASTER_URL}:8080 \\
  --allocate-node-cidrs=true \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --root-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


cp kube-controller-manager.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable kube-controller-manager
systemctl start kube-controller-manager
systemctl status kube-controller-manager


cat > kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/k8s/bin/kube-scheduler \\
  --address=127.0.0.1 \\
  --master=http://${MASTER_URL}:8080 \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


cp kube-scheduler.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable kube-scheduler
systemctl start kube-scheduler
systemctl status kube-scheduler


#kubeApiServer高可用(LB-NODE)
yum install -y haproxy
cd /etc/haproxy
rm -rf /etc/haproxy/haproxy.cfg
cat > haproxy.cfg <<EOF
listen stats
  bind    *:9000
  mode    http
  stats   enable
  stats   hide-version
  stats   uri       /stats
  stats   refresh   30s
  stats   realm     Haproxy\ Statistics
  stats   auth      Admin:Password

frontend k8s-https-api
    bind ${NODE_IP}:443
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    default_backend k8s-https-api

backend k8s-https-api
    mode tcp
    option tcplog
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
    server k8s-api-1 192.168.10.213:6443 check
    server k8s-api-2 192.168.10.214:6443 check

frontend k8s-http-api
    bind ${NODE_IP}:80
    mode tcp
    option tcplog
    default_backend k8s-http-api

backend k8s-http-api
    mode tcp
    option tcplog
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
    server k8s-http-api-1 192.168.10.213:8080 check
    server k8s-http-api-2 192.168.10.214:8080 check
EOF
systemctl daemon-reload
systemctl start haproxy
systemctl enable haproxy
systemctl status haproxy
#开启路由转发
sed -i '$a net.ipv4.ip_forward = 1' /etc/sysctl.conf
sed -i '$a net.ipv4.ip_nonlocal_bind = 1' /etc/sysctl.conf
sysctl -p

yum install -y keepalived
yum install -y psmisc
cd /etc/keepalived
rm -rf /etc/keepalived/keepalived.conf
#192.168.10.219
cat > keepalived.conf <<EOF
! Configuration File for keepalived

global_defs {
   notification_email {
   }
   router_id kube_api
}

vrrp_script check_haproxy {
    # 自身状态检测
    script "killall -0 haproxy"
    interval 3
    weight 5
}

vrrp_instance haproxy-vip {
    # 使用单播通信，默认是组播通信
    unicast_src_ip 192.168.10.219
    unicast_peer {
        192.168.10.220
    }
    # 初始化状态
    state MASTER
    # 虚拟ip 绑定的网卡 （这里根据你自己的实际情况选择网卡）
    interface eth0
    # 此ID 要与Backup 配置一致
    virtual_router_id 51
    # 默认启动优先级，要比Backup 大点，但要控制量，保证自身状态检测生效
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        # 虚拟ip 地址
        192.168.10.221
    }
    track_script {
        check_k8s
    }
}

virtual_server 192.168.10.221 80 {
  delay_loop 5
  lvs_sched wlc
  lvs_method NAT
  persistence_timeout 1800
  protocol TCP

  real_server 192.168.10.219 80 {
    weight 1
    TCP_CHECK {
      connect_port 80
      connect_timeout 3
    }
  }
}

virtual_server 192.168.10.221 443 {
  delay_loop 5
  lvs_sched wlc
  lvs_method NAT
  persistence_timeout 1800
  protocol TCP

  real_server 192.168.10.219 443 {
    weight 1
    TCP_CHECK {
      connect_port 443
      connect_timeout 3
    }
  }
}
EOF

#192.168.10.220
cat > keepalived.conf <<EOF
! Configuration File for keepalived

global_defs {
   notification_email {
   }
   router_id kube_api
}

vrrp_script check_haproxy {
    # 自身状态检测
    script "killall -0 haproxy"
    interval 3
    weight 5
}

vrrp_instance haproxy-vip {
    # 使用单播通信，默认是组播通信
    unicast_src_ip 192.168.10.220
    unicast_peer {
        192.168.10.219
    }
    # 初始化状态
    state MASTER
    # 虚拟ip 绑定的网卡 （这里根据你自己的实际情况选择网卡）
    interface eth0
    # 此ID 要与Backup 配置一致
    virtual_router_id 51
    # 默认启动优先级，要比Backup 大点，但要控制量，保证自身状态检测生效
    priority 99
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        # 虚拟ip 地址
        192.168.10.221
    }
    track_script {
        check_k8s
    }
}

virtual_server 192.168.10.221 80 {
  delay_loop 5
  lvs_sched wlc
  lvs_method NAT
  persistence_timeout 1800
  protocol TCP

  real_server 192.168.10.220 80 {
    weight 1
    TCP_CHECK {
      connect_port 80
      connect_timeout 3
    }
  }
}

virtual_server 192.168.10.221 443 {
  delay_loop 5
  lvs_sched wlc
  lvs_method NAT
  persistence_timeout 1800
  protocol TCP

  real_server 192.168.10.220 443 {
    weight 1
    TCP_CHECK {
      connect_port 443
      connect_timeout 3
    }
  }
}
EOF

systemctl daemon-reload
systemctl enable keepalived
systemctl start keepalived
systemctl status keepalived

#部署Node节点
#安装flanneld
#开启路由转发
sed -i '$a net.ipv4.ip_forward = 1' /etc/sysctl.conf
sed -i '$a net.bridge.bridge-nf-call-iptables=1' /etc/sysctl.conf
sed -i '$a net.bridge.bridge-nf-call-ip6tables=1' /etc/sysctl.conf
sysctl -p

#修改docker配置
source /run/flannel/docker
cd /usr/lib/systemd/system
rm -rf docker.service
cat > docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
EnvironmentFile=-/run/flannel/docker
ExecStart=/usr/bin/dockerd --log-level=info $DOCKER_NETWORK_OPTIONS
ExecReload=/bin/kill -s HUP $MAINPID
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process
# restart the docker process if it exits prematurely
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable docker
systemctl restart docker
systemctl status docker

#重新安装docker (可选) 如果要用overlay2存储，需要升级centos7内核到3.16+
yum remove docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-selinux \
                  docker-engine-selinux \
                  docker-engine -y
yum install -y yum-utils \
  device-mapper-persistent-data \
  lvm2
yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
yum install docker-ce -y

#加快pullimage的速度
cat > /etc/docker/daemon.json <<EOF
{
  "max-concurrent-downloads": 10
}
EOF
cat /etc/docker/daemon.json

#配置kubelet(执行一次)
kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap
kubectl create clusterrolebinding kubelet-nodes --clusterrole=system:node --group=system:nodes

#安装kubelet proxy
cd ~
wget https://dl.k8s.io/v1.10.0/kubernetes-server-linux-amd64.tar.gz
tar -xzvf kubernetes-server-linux-amd64.tar.gz
cd kubernetes
tar -xzvf  kubernetes-src.tar.gz
cp -r server/bin/{kube-proxy,kubelet} /usr/k8s/bin/

#生成bootstrap.kubeconfig (执行一次)
cd ~
kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig
kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig
kubectl config use-context default --kubeconfig=bootstrap.kubeconfig
mv bootstrap.kubeconfig /etc/kubernetes/

#node分发
cd /etc/kubernetes/
wget http://ftp.netty.cc/k8s/bootstrap.kubeconfig


# kubelet service
mkdir /var/lib/kubelet 
cd /var/lib/kubelet
cat > kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=/usr/k8s/bin/kubelet \\
  --fail-swap-on=false \\
  --cgroup-driver=cgroupfs \\
  --address=${NODE_IP} \\
  --hostname-override=${NODE_IP} \\
  --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --cert-dir=/etc/kubernetes/ssl \\
  --cluster-dns=${CLUSTER_DNS_SVC_IP} \\
  --cluster-domain=${CLUSTER_DNS_DOMAIN} \\
  --hairpin-mode promiscuous-bridge \\
  --allow-privileged=true \\
  --serialize-image-pulls=false \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cp kubelet.service /etc/systemd/system/kubelet.service
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet
systemctl status kubelet


#解决HA后端口问题
sed -i "/213/s/213/221/"   /etc/hosts #ALL NODE
sed -i "/:8080/s/:8080//"   /etc/systemd/system/kube-controller-manager.service #MASTER NODE
sed -i "/:8080/s/:8080//"   /etc/systemd/system/kube-scheduler.service #MASTER NODE
sed -i "/:6443/s/:6443//"  ~/.kube/config
#重启各节点
systemctl daemon-reload
systemctl restart kube-controller-manager
systemctl restart kube-scheduler
systemctl status kube-controller-manager
systemctl status kube-scheduler
systemctl restart kubelet
systemctl status kubelet

##手工查看csr并激活
kubectl get csr
kubectl certificate approve node-csr-GGnRUnLb7gxqD78abPkDE8bDXRs51E5GXn_YnujwdhI
kubectl certificate approve node-csr-WQ5T7y2qV1prY4qlmntV6oLydakeQSo2jdOhxS4Zc2w
kubectl certificate approve node-csr-yPEBEcSzDGgQ8SLh1Y2TuY02Dy85oyN8-JmUI2CVos4
kubectl get nodes

#配置kube-proxy 执行一次
cd /etc/kubernetes/ssl
cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cd /etc/kubernetes/
cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy

kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-credentials kube-proxy \
  --client-certificate=/etc/kubernetes/ssl/kube-proxy.pem \
  --client-key=/etc/kubernetes/ssl/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

#其他node节点直接分发kube-proxy.kubeconfig
cd /etc/kubernetes/
wget http://ftp.netty.cc/k8s/kube-proxy.kubeconfig

#kube-proxy service
mkdir -p /var/lib/kube-proxy 
cd /var/lib/kube-proxy 
cat > kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/usr/k8s/bin/kube-proxy \\
  --bind-address=${NODE_IP} \\
  --hostname-override=${NODE_IP} \\
  --cluster-cidr=${SERVICE_CIDR} \\
  --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
cp kube-proxy.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy
systemctl status kube-proxy

#集群验证
cd ~
wget http://ftp.netty.cc/k8s/nginx-ds.yml
kubectl create -f nginx-ds.yml
kubectl get pods -o wide
kubectl get svc

#部署kube-dns
cd ~
wget http://ftp.netty.cc/k8s/kube-dns.yaml
kubectl create -f kube-dns.yaml 
kubectl get pods -n kube-system
kubectl describe pod kube-dns-6954bd9cf4-28wpg -n kube-system
kubectl get svc -n kube-system

#检查kubedns 功能
cd ~
wget http://ftp.netty.cc/k8s/my-nginx.yaml
kubectl create -f my-nginx.yaml 
kubectl get pods -o wide
kubectl expose deploy my-nginx
kubectl get svc

cd ~
wget http://ftp.netty.cc/k8s/pod-nginx.yaml
kubectl create -f pod-nginx.yaml
kubectl exec  nginx -i -t -- /bin/bash
root@nginx:/# cat /etc/resolv.conf
root@nginx:/# ping my-nginx
root@nginx:/# ping kubernetes
root@nginx:/# ping kube-dns.kube-system.svc.cluster.local

#部署dashboard
cd ~
wget http://ftp.netty.cc/k8s/kubernetes-dashboard.yaml
kubectl create -f kubernetes-dashboard.yaml
kubectl get pods -n kube-system
kubectl get svc -n kube-system

#高级账号和token
cd ~
wget http://ftp.netty.cc/k8s/admin-sa.yaml
kubectl create -f admin-sa.yaml
kubectl get secret -n kube-system|grep admin-token
kubectl get secret admin-token-lw6tk -o jsonpath={.data.token} -n kube-system |base64 -d

#heapster插件
cd ~
wget https://github.com/kubernetes/heapster/archive/v1.5.2.tar.gz
tar -xzvf v1.5.2.tar.gz
cd heapster-1.5.2/deploy/kube-config
kubectl create -f rbac/heapster-rbac.yaml
sed -i "/# type: NodePort/s/# type: NodePort/type: NodePort/"   ~/heapster-1.5.2/deploy/kube-config/influxdb/grafana.yaml
kubectl create -f influxdb
#更新dashboard yaml
cd ~
rm -rf kubernetes-dashboard.yaml
wget http://ftp.netty.cc/k8s/kubernetes-dashboard.yaml
kubectl apply -f kubernetes-dashboard.yaml


#Ingress traefik
cd ~
wget http://ftp.netty.cc/k8s/ingress-rbac.yaml
wget http://ftp.netty.cc/k8s/traefik-daemonset.yaml
wget http://ftp.netty.cc/k8s/traefik-ingress.yaml
wget http://ftp.netty.cc/k8s/traefik-ui.yaml
kubectl create -f ingress-rbac.yaml
kubectl create -f traefik-daemonset.yaml
kubectl create -f traefik-ingress.yaml
kubectl create -f traefik-ui.yaml