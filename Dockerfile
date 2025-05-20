FROM ubuntu:24.04

ENV NGINX_VERSION=1.24.0
ENV WORKDIR=/opt/modsec-build

# نصب پیش‌نیازها
RUN apt-get update && apt-get install -y \
    git g++ build-essential autoconf automake libtool \
    libpcre2-dev libxml2 libxml2-dev libyajl-dev pkgconf libgeoip-dev zlib1g-dev curl wget ca-certificates \
    libssl-dev

# ساخت دایرکتوری کاری
RUN mkdir -p $WORKDIR
RUN mkdir -p /var/log/nginx

WORKDIR $WORKDIR

# کلون ModSecurity
RUN git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity ModSecurity && \
    cd ModSecurity && \
    git submodule init && git submodule update && \
    ./build.sh && ./configure && make -j$(nproc) && make install

# کلون ModSecurity-nginx connector
RUN git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git ModSecurity-nginx

# دانلود سورس Nginx
RUN wget http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz && \
    tar zxvf nginx-$NGINX_VERSION.tar.gz

# ساخت ماژول ModSecurity-nginx به صورت داینامیک
RUN cd nginx-$NGINX_VERSION && \
    ./configure --with-compat --add-dynamic-module=$WORKDIR/ModSecurity-nginx && \
    make && make install && \
    mkdir -p /etc/nginx/modules && \
    cp /usr/local/nginx/modules/ngx_http_modsecurity_module.so /etc/nginx/modules/

RUN git clone https://github.com/coreruleset/coreruleset.git /etc/nginx/owasp-crs && \
    cp /etc/nginx/owasp-crs/crs-setup.conf.example /etc/nginx/owasp-crs/crs-setup.conf


# کپی فایل تنظیمات modsecurity (باید کنار Dockerfile باشه)
COPY modsecurity.conf /etc/nginx/modsecurity.conf

# ایجاد پوشه پیش‌فرض html برای nginx
RUN mkdir -p /usr/local/nginx/html && \
    echo "ModSecurity is OFF. Use 'modsecurity on;' in nginx.conf to enable it." > /usr/local/nginx/html/index.html

# ساخت فایل ماژول nginx.conf
RUN echo "load_module modules/ngx_http_modsecurity_module.so;" > /etc/nginx/modules.conf

# کپی فایل کانفیگ nginx (می‌تونی این فایل رو خودت بسازی یا همون زیر رو کپی کنی)
RUN echo ' \
worker_processes 1; \n\
events { worker_connections 1024; } \n\
http { \n\
    include       mime.types; \n\
    default_type  application/octet-stream; \n\
    modsecurity off; \n\
    modsecurity_rules_file /etc/nginx/modsecurity.conf; \n\
    server { \n\
        listen 80; \n\
        server_name localhost; \n\
        location / { \n\
            root   /usr/local/nginx/html; \n\
            index  index.html index.htm; \n\
        } \n\
        error_page 403 /403.html; \n\
        location = /403.html { \n\
            root /usr/local/nginx/html; \n\
            internal; \n\
        } \n\
    } \n\
} \n' > /etc/nginx/nginx.conf

EXPOSE 80

CMD ["/usr/local/nginx/sbin/nginx", "-g", "daemon off;"]
