# TLS Bootstrapping 使用的Token，可以使用命令 head -c 16 /dev/urandom | od -An -t x | tr -d ' ' 生成
BOOTSTRAP_TOKEN="7503a7e3d7505b940c662afba740d7bb"

# 建议使用未用的网段来定义服务网段和Pod 网段
# 服务网段(Service CIDR)，部署前路由不可达，部署后集群内部使用IP:Port可达
SERVICE_CIDR="10.254.0.0/16"
# Pod 网段(Cluster CIDR)，部署前路由不可达，部署后路由可达(flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围(NodePort Range)
NODE_PORT_RANGE="30000-32766"

# etcd集群服务地址列表
ETCD_ENDPOINTS="https://192.168.10.213:2379,https://192.168.10.214:2379,https://192.168.10.215:2379"

# flanneld 网络配置前缀
FLANNEL_ETCD_PREFIX="/kubernetes/network"

# kubernetes 服务IP(预先分配，一般为SERVICE_CIDR中的第一个IP)
CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务IP(从SERVICE_CIDR 中预先分配)
CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名
CLUSTER_DNS_DOMAIN="cluster.local."

# MASTER API Server 地址
MASTER_URL="k8s-api.virtual.local"

# 当前部署的机器名称(随便定义，只要能区分不同机器即可) etcd01
NODE_NAME=$HOSTNAME 

#直接获取eth0网卡地址
NODE_IP=$(ifconfig eth0 | grep 'inet'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $2}')

# etcd 集群所有机器 IP
NODE_IPS="192.168.10.213 192.168.10.214 192.168.10.215" 

# etcd 集群间通信的IP和端口
ETCD_NODES=vm-213=https://192.168.10.213:2380,vm-214=https://192.168.10.214:2380,vm-215=https://192.168.10.215:2380

#如果你没有安装`haproxy`的话，还是需要使用6443端口的哦
KUBE_APISERVER="https://${MASTER_URL}"