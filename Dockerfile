# Credits
# https://github.com/hetznercloud/ceph-s3-box
# https://github.com/ceph/ceph-container

FROM fedora:40 AS ceph
ENV TZ=Etc/UTC
RUN curl -JL "https://dl.filippo.io/mkcert/v1.4.4?for=linux/$(uname -m | sed s/aarch64/arm64/ | sed s/x86_64/amd64/)"\
 -o mkcert \
 && chmod +x mkcert \
 && mv mkcert /usr/local/bin/mkcert \
 && mkcert -install
RUN cat <<-EOF | tee /etc/dnf/dnf.conf
[main]
max_parallel_downloads=10
fastestmirror=True 
EOF
RUN dnf -y upgrade --refresh \
--best \
--enhancement \
--newpackage \
--security \
--secseverity Critical \
--secseverity Important \
--secseverity Moderate \
--secseverity Low \
--bugfix \
--nodocs \
--allowerasing \
--setopt=install_weak_deps=False \
--verbose
RUN dnf -y install \
hostname \
ceph-mon \
ceph-mgr \
ceph-osd \
ceph-radosgw \
s3cmd \
--best \
--nodocs \
--allowerasing \
--setopt=install_weak_deps=False \
--verbose
RUN dnf -y autoremove
RUN dnf clean all

FROM ceph as radosgw
ENV ACCESS_KEY="demo-key"
ENV SECRET_KEY="demo-secret"
ENV BUCKET_NAME="demo-bucket"

EXPOSE 7480 7443

COPY ./entrypoint.sh /entrypoint
ENTRYPOINT /entrypoint
