# ristory-k8s-cluster
### 基于Centos7.4的k8s v1.10集群，不同于kubeadm部署方式
##### 1.思路源自于[https://blog.qikqiak.com/post/manual-install-high-available-kubernetes-cluster/][1]
##### 2.优化部分环节并将分散命令集成为多个Shell，实现高可用生产集群的快速搭建
##### 3.目前脚本为集合，非一键部署
##### 4.文件夹内为过程中依赖的一些证书、配置等，按需使用
##### 5.2*master(apiserver+controller manager+shecheduler)+3*etcd+3*node(kubulet+proxy)+kubedns+fannel++2*(ha+keepalived)+dashboard+heapster+traefik+grafana+influxdb


[1]:	https://blog.qikqiak.com/post/manual-install-high-available-kubernetes-cluster/