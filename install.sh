DOMAIN=cloud.domain.com
MYSQL_ROOT_PASSWORD=password
EMAIL=your@email.com

yum -y update &> /dev/nul
yum -y install epel-release &> /dev/nul
rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm &> /dev/nul
yum -y install php70w php70w-opcache php70w-gd php70w-intl php70w-mbstring php70w-mcrypt php70w-mysql php70w-odbc php70w-pear php70w-pecl-imagick php70w-process php70w-tidy php70w-xml phpmyadmin mariadb mariadb-server expect policycoreutils-python mod_ssl python-certbot-apache vsftpd &> /dev/nul

setsebool -P httpd_can_network_connect on &> /dev/nul
setsebool -P httpd_can_network_connect_db on &> /dev/nul
setsebool -P httpd_anon_write on &> /dev/nul

semanage permissive -a httpd_t &> /dev/nul

sed -i.bak -r '\%<Directory "/var/www">%,\%</Directory>% s%(AllowOverride)\s+None%\1 All%i' /etc/httpd/conf/httpd.conf

yum -y install libunwind libicu &> /dev/nul
curl -sSL -o dotnet.tar.gz https://go.microsoft.com/fwlink/?linkid=843449 &> /dev/nul
mkdir -p /opt/dotnet && sudo tar zxf dotnet.tar.gz -C /opt/dotnet &> /dev/nul
ln -s /opt/dotnet/dotnet /usr/local/bin &> /dev/nul
rm -f dotnet.tar.gz &> /dev/nul

cat << EOF > /root/netcorereport.database
4999:start next port
EOF

cat << EOF > /etc/httpd/conf.d/default.conf
<VirtualHost _default_:80>
    DocumentRoot /var/www/html
</VirtualHost>
EOF

cat << EOF > /etc/cron.daily/certbot
certbot renew --quiet
EOF

chmod +x /etc/cron.daily/certbot

cat << EOF > /etc/httpd/conf.d/phpMyAdmin.conf
# phpMyAdmin - Web based MySQL browser written in php
#
# Allows only localhost by default
#
# But allowing phpMyAdmin to anyone other than localhost should be considered
# dangerous unless properly secured by SSL

<VirtualHost *:80>

ServerName phpmyadmin.$DOMAIN
ServerAlias www.phpmyadmin.$DOMAIN
DocumentRoot /usr/share/phpMyAdmin/

<Directory /usr/share/phpMyAdmin/>
   AddDefaultCharset UTF-8

   <IfModule mod_authz_core.c>
     # Apache 2.4
     <RequireAny>
       Require all granted
     </RequireAny>
   </IfModule>
   <IfModule !mod_authz_core.c>
     # Apache 2.2
     Order Allow,Deny
     Allow from All
   </IfModule>
</Directory>

<Directory /usr/share/phpMyAdmin/setup/>
   <IfModule mod_authz_core.c>
     # Apache 2.4
     <RequireAny>
       Require ip 127.0.0.1
       Require ip ::1
     </RequireAny>
   </IfModule>
   <IfModule !mod_authz_core.c>
     # Apache 2.2
     Order Deny,Allow
     Deny from All
     Allow from 127.0.0.1
     Allow from ::1
   </IfModule>
</Directory>

</VirtualHost>
EOF

groupadd student &> /dev/nul
mkdir -p /etc/httpd/sites-available &> /dev/nul
mkdir -p /etc/httpd/sites-enabled &> /dev/nul

echo "
ServerName $DOMAIN
IncludeOptional sites-enabled/*.conf
" >> /etc/httpd/conf/httpd.conf

systemctl enable httpd &> /dev/nul
systemctl start httpd &> /dev/nul
systemctl enable vsftpd &> /dev/nul
systemctl start vsftpd &> /dev/nul

firewall-cmd --permanent --add-service=ftp &> /dev/nul
firewall-cmd --permanent --add-service=http &> /dev/nul
firewall-cmd --permanent --add-service=https &> /dev/nul
firewall-cmd --reload &> /dev/nul

systemctl enable mariadb &> /dev/nul
systemctl start mariadb &> /dev/nul

SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"\r\"
expect \"Change the root password?\"
send \"y\r\"
expect \"New password:\"
send \"$MYSQL_ROOT_PASSWORD\r\"
expect \"Re-enter new password:\"
send \"$MYSQL_ROOT_PASSWORD\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")

echo "$SECURE_MYSQL" &> /dev/nul

cat << EOF > /root/updateSystemd.sh
#!/bin/bash

while true; do
        for dir in /var/www/*/; do
        dir2=${dir%*/};
        puredir=${dir2##*/};
        echo "Processing $dir";
        if [ -f ${dir}restart ]; then
                newdll=$(ls ${dir}public_html/*.pdb | cut -f1 -d.).dll
                if [ -f $newdll ]; then
                        echo "Detected new DLL";
                         sed -i "s@ExecStart=.*@ExecStart=\/usr\/local\/bin\/dotnet $newdll@g" /etc/systemd/system/aspnet-${puredir}.service
                else
                        sed -i 's/ExecStart=.*/ExecStart=\/usr\/local\/bin\/dotnet run -c release/g' /etc/systemd/system/aspnet-${puredir}.service
                fi;
                echo "Restarting ${puredir}";
                systemctl daemon-reload;
                systemctl restart aspnet-test3;
                rm -f ${dir}restart;
        fi;
        done;
        sleep 10;
done;
EOF

chmod +x /root/updateSystemd.sh

cat << EOF > /etc/systemd/system/aspnetcore-update.service
[Unit]
Description=Update ASP.NET Core Service

[Service]
Type=simple
ExecStart=/root/updateSystemd.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable aspnetcore-update
systemctl start aspnetcore-update


certbot --apache -d phpmyadmin.$DOMAIN --agree-tos --email $EMAIL --non-interactive --redirect &> /dev/nul
