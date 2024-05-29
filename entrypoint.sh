#!/usr/bin/env bash

# Credits
# https://github.com/hetznercloud/ceph-s3-box
# https://github.com/ceph/ceph-container

set -eux
set -o pipefail

##
# Configure s3cmd
##

cat <<-EOF | tee /root/.s3cfg
[default]
access_key = $ACCESS_KEY
secret_key = $SECRET_KEY
check_ssl_certificate = False
guess_mime_type = False
host_base = localhost:7480
host_bucket = localhost:7480/$BUCKET_NAME
use_https = False
EOF

##
# Create SSL for radosgw
##

mkcert -cert-file /etc/ssl/ceph.cert -key-file /etc/ssl/ceph.key localhost

##
# Configure ceph.conf
##

cat <<- EOF > /etc/ceph/ceph.conf
[global]
fsid = $(uuidgen)
mon_host = $(hostname -i)
auth_allow_insecure_global_id_reclaim = false
mon_warn_on_pool_no_redundancy = false
mon_osd_down_out_interval = 60
mon_osd_report_timeout = 300
mon_osd_down_out_subtree_limit = host
mon_osd_reporter_subtree_level = rack
osd_scrub_auto_repair = true
osd_pool_default_size = 1
osd_pool_default_min_size = 1
osd_pool_default_pg_num = 1
osd_pool_default_pg_autoscale_mode = 1
osd_crush_chooseleaf_type = 0
osd_objectstore = memstore
mgr_initial_modules = diskprediction_local stats
mgr_standby_modules = 0
rgw_dns_name = localhost
rgw_enable_usage_log = 1
[client.rgw.localhost]
rgw_frontends ="beast port=7480 ssl_port=7443 ssl_certificate=/etc/ssl/ceph.cert ssl_private_key=/etc/ssl/ceph.key tcp_nodelay=0"
EOF

##
# Create mon
##

ceph-authtool \
    --create-keyring /tmp/ceph.mon.keyring \
    --gen-key -n mon. \
    --cap mon 'allow *'
ceph-authtool \
    --create-keyring /etc/ceph/ceph.client.admin.keyring \
    --gen-key -n client.admin \
    --cap mon 'allow *' \
    --cap osd 'allow *' \
    --cap mds 'allow *' \
    --cap mgr 'allow *'
ceph-authtool /tmp/ceph.mon.keyring \
    --import-keyring /etc/ceph/ceph.client.admin.keyring

monmaptool \
    --create \
    --add "localhost" "$(hostname -i)" \
    --fsid "$(grep -oP '(?<=^fsid = )[0-9a-z-]*' /etc/ceph/ceph.conf)" \
    --set-min-mon-release pacific \
    --enable-all-features \
    --clobber \
    /tmp/monmap

mkdir -p "/var/lib/ceph/mon/ceph-localhost"
rm -rf "/var/lib/ceph/mon/ceph-localhost/*"
ceph-mon --mkfs -i "localhost" --monmap /tmp/monmap --keyring /tmp/ceph.mon.keyring
chown -R ceph:ceph /var/lib/ceph/mon/
ceph-mon --cluster ceph --id "localhost" --setuser ceph --setgroup ceph

##
# Create mgr
##

mkdir -p "/var/lib/ceph/mgr/ceph-localhost"
ceph auth get-or-create "mgr.localhost" mon 'allow profile mgr' osd 'allow *' mds 'allow *' \
    > "/var/lib/ceph/mgr/ceph-localhost/keyring"
chown -R ceph:ceph /var/lib/ceph/mgr/
ceph-mgr --cluster ceph --id "localhost" --setuser ceph --setgroup ceph

##
# Create osd
##

OSD=$(ceph osd create)

mkdir -p "/osd/osd.${OSD}/data"
ceph auth get-or-create "osd.${OSD}" mon 'allow profile osd' mgr 'allow profile osd' osd 'allow *' \
    > "/osd/osd.${OSD}/data/keyring"
ceph-osd -i "${OSD}" --mkfs --osd-data "/osd/osd.${OSD}/data"
chown -R ceph:ceph "/osd/osd.${OSD}/data"
ceph-osd -i "${OSD}" --osd-data "/osd/osd.${OSD}/data" --keyring "/osd/osd.${OSD}/data/keyring"

##
# Create rgw
##

mkdir -p "/var/lib/ceph/radosgw/ceph-rgw.localhost"
ceph auth get-or-create "client.rgw.localhost" osd 'allow rwx' mon 'allow rw' \
    -o "/var/lib/ceph/radosgw/ceph-rgw.localhost/keyring"
touch "/var/lib/ceph/radosgw/ceph-rgw.localhost/done"
chown -R ceph:ceph /var/lib/ceph/radosgw

##
# Create admin user
##

radosgw-admin user create \
    --uid=".admin" \
    --display-name="admin" \
    --system \
    --key-type="s3" \
    --access-key="${ACCESS_KEY}" \
    --secret-key="${SECRET_KEY}" 

radosgw --cluster ceph --rgw-zone "default" --name "client.rgw.localhost" --setuser ceph --setgroup ceph

s3cmd mb --quiet s3://$BUCKET_NAME

echo "Successfully started"

##
# log output in forground
##

while ! tail -F /var/log/ceph/ceph* ; do
  sleep 0.1
done

echo "Successfully terminated ..."
