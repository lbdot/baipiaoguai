#!/bin/bash
#Thanks for atrandys !
function blue(){
    echo -e "\033[34m\033[01m $1 \033[0m"
}
function green(){
    echo -e "\033[32m\033[01m $1 \033[0m"
}
function red(){
    echo -e "\033[31m\033[01m $1 \033[0m"
}
function yellow(){
    echo -e "\033[33m\033[01m $1 \033[0m"
}

#自定义项目

    green " 输入解析到此VPS的域名"
    read domain
    
    green "输入自定义UUID，[回车]随机UUID"
    read v2uuid
        if [ -z "$v2uuid" ]; then
                v2uuid=$(cat /proc/sys/kernel/random/uuid)
        fi
    
    green "输入自定义路径，不需要斜杠，[回车]随机路径"
    read newpath
        if [ -z "$newpath" ]; then
                newpath=$(head -n 50 /dev/urandom | sed 's/[^a-z]//g' | strings -n 4 | tr '[:upper:]' '[:lower:]' | head -1)
        fi
    
#安装nginx
install_nginx(){

    systemctl stop firewalld
    systemctl disable firewalld
    apt update -y
    apt install -y wget build-essential libpcre3 libpcre3-dev zlib1g-dev liblua5.1-dev libluajit-5.1-dev libgeoip-dev google-perftools libgoogle-perftools-dev gcc autoconf automake make cron sysv-rc-conf
    wget --no-check-certificate https://www.openssl.org/source/openssl-1.1.1n.tar.gz
    tar xzvf openssl-1.1.1n.tar.gz && rm openssl-1.1.1n.tar.gz
    mkdir /etc/nginx
    mkdir /etc/nginx/ssl
    mkdir /etc/nginx/conf.d
    wget --no-check-certificate https://nginx.org/download/nginx-1.20.2.tar.gz
    tar xf nginx-1.20.2.tar.gz && rm nginx-1.20.2.tar.gz
    cd nginx-1.20.2
    ./configure --prefix=/etc/nginx --with-openssl=../openssl-1.1.1n --with-openssl-opt='enable-tls1_3' --with-http_v2_module --with-http_ssl_module --with-http_gzip_static_module --with-http_stub_status_module --with-http_sub_module --with-stream --with-stream_ssl_module
    make && make install

cat > /etc/nginx/conf/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /etc/nginx/logs/error.log warn;
pid        /etc/nginx/logs/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/conf/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /etc/nginx/logs/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF

cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen       80;
    server_name  $domain;
    root /etc/nginx/html;
    index index.php index.html index.htm;
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /etc/nginx/html;
    }
}
EOF

    /etc/nginx/sbin/nginx

    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh --register-account -m me@$domain
    ~/.acme.sh/acme.sh  --issue  -d $domain  --webroot /etc/nginx/html/
    ~/.acme.sh/acme.sh  --installcert  -d  $domain   \
        --key-file   /etc/nginx/ssl/$domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer \
        --reloadcmd  "/etc/nginx/sbin/nginx -s reload"

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt -subj "/C=GB/ST=London/L=London/O=Global Security/OU=IT Department/CN=example.com"

cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen 80 default_server;
    listen 443 ssl default_server;
    ssl_certificate        /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key    /etc/nginx/ssl/nginx.key;
    server_name _;
    return 444;
}
server { 
    listen       80;
    server_name  $domain;
    rewrite ^(.*)$  https://\$host\$1 permanent; 
}
server {
    listen 443 ssl http2;
    server_name $domain;
    root /etc/nginx/html;
    index index.php index.html;
    ssl_certificate /etc/nginx/ssl/fullchain.cer; 
    ssl_certificate_key /etc/nginx/ssl/$domain.key;
    #TLS 版本控制
    ssl_protocols   TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers     'TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5';
    ssl_prefer_server_ciphers   on;
    # 开启 1.3 0-RTT
    ssl_early_data  on;
    ssl_stapling on;
    ssl_stapling_verify on;
    #add_header Strict-Transport-Security "max-age=31536000";
    #access_log /var/log/nginx/access.log combined;
    location /mypath {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:11234; 
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    location / {
       try_files \$uri \$uri/ /index.php?\$args;
    }
    # 反代
    # include /etc/nginx/proxy.conf;
}
EOF
}

# 反代
# wget -P /etc/nginx/ https://raw.githubusercontent.com/lbdot/baipiaoguai/master/proxy.conf

#安装v2ray
install_v2ray(){
    
    cd ~
    bash <(curl -s https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)  
    cd /usr/local/etc/v2ray/
    rm -f config.json
    wget --no-check-certificate https://raw.githubusercontent.com/lbdot/baipiaoguai/master/config.json
#    v2uuid=$(cat /proc/sys/kernel/random/uuid)
    sed -i "s/aaaa/$v2uuid/;" config.json
#    newpath=$(cat /dev/urandom | head -1 | md5sum | head -c 4)
    sed -i "s/mypath/$newpath/;" config.json
    sed -i "s/mypath/$newpath/;" /etc/nginx/conf.d/default.conf
    cd /etc/nginx/html
    rm -f /etc/nginx/html/*
    wget --no-check-certificate https://github.com/lbdot/baipiaoguai/raw/master/web.zip
    unzip web.zip
    /etc/nginx/sbin/nginx -s stop
    /etc/nginx/sbin/nginx
    
    #增加自启动脚本
cat > /etc/systemd/system/nginx.service <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/etc/nginx/logs/nginx.pid
ExecStartPre=/etc/nginx/sbin/nginx -t
ExecStart=/etc/nginx/sbin/nginx
ExecReload=/etc/nginx/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    #添加 nginx 自启动
    systemctl enable nginx
    
    #添加 v2ray 自启动
    systemctl enable v2ray
    systemctl restart v2ray

cat > /usr/local/etc/v2ray/myconfig.json<<-EOF
{
===========配置参数=============
地址：${domain}
端口：443
uuid：${v2uuid}
额外id：64
加密方式：aes-128-gcm
传输协议：ws
别名：myws
路径：${newpath}
底层传输：tls
}
EOF

clear
green
green "安装已经完成"
green 
green "===========配置参数============"
green "地址：${domain}"
green "端口：443"
green "uuid：${v2uuid}"
green "额外id：64"
green "加密方式：aes-128-gcm"
green "传输协议：ws"
green "别名：myws"
green "路径：${newpath}"
green "底层传输：tls"
green 
}

remove_v2ray(){

    systemctl stop nginx
    systemctl disable nginx
    systemctl stop v2ray
    systemctl disable v2ray
    
    rm -rf /usr/bin/v2ray /usr/local/etc/v2ray
    rm -rf /usr/local/etc/v2ray
    rm -rf /etc/nginx
    
    green "nginx、v2ray已删除"
    
}

start_menu(){
    clear
    green " 1. 安装 v2ray+ws+tls "
    green " 2. 升级 v2ray "
    red " 3. 卸载 v2ray 与 nginx "
    red " 4. 仅卸载 v2ray "
    yellow " 0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    install_nginx
    install_v2ray
    ;;
    2)
    bash <(curl -O https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
    ;;
    3)
    remove_v2ray 
    ;;
    4)
    bash <(curl -O https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --remove
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    red "请输入正确数字"
    sleep 2s
    start_menu
    ;;
    esac
}
# Thanks for atrandys !

start_menu
