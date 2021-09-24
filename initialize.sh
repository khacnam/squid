#!/bin/bash
#####################################################################
#######            Initialize Script                        #########
#####################################################################

###Global Variables
OS=`uname -s`
DISTRIB=`cat /etc/*release* | grep -i DISTRIB_ID | cut -f2 -d=`
SQUID_VERSION=4.8
CONFIG_FILE="config.cfg"
BASEDIR="/opt/squid"
PRIMARYKEY=18000
echo >${CONFIG_FILE}

checkRoot()
{
        if [ `id -u` -ne 0 ]
        then
                echo "SCRIPT must be RUN as root user"
                exit 13
        else
                echo "USER: root"
        fi
}
checkOS()
{
        if [ "$OS" == "Linux" ] && [ "$DISTRIB" == "Ubuntu" ]
        then
                echo "Operating System = $DISTRIB $OS"
        else
                echo "Please run this script on Ubuntu Linux"
                exit 12
        fi
       
}
getInterface()
{
        INTERFACES=`ls -l /sys/class/net/ | grep -v lo | grep -v total | awk '{print $9}'`
        COUNT=`echo $INTERFACES | wc -c`
        echo "Interfaces found"
        if [ $COUNT -eq 1 ]
        then
                INTERFACE=`echo $INTERFACES`
                echo $INTERFACES
        else
                echo "Interfaces found"
                COUNT=1
                for INTERFACE in $INTERFACES
                do
                        LINK=`ethtool $INTERFACE | grep Link`
                        echo "$COUNT. $INTERFACE -- Status: $LINK"
                        COUNT=$((COUNT+1))
                done
                read -p "Enter the INTERFACE to be used:" ANSWER
                INTERFACE=$ANSWER
        fi
        echo "Setting INTERFACE: $INTERFACE"
        echo "INTERFACE=$INTERFACE" >> ${BASEDIR}/${CONFIG_FILE}
}
installSquid()
{
		apt-get update -y
        apt-get install squid -y
        apt-get install apache2 apache2-utils -y
        mkdir /var/log/squid 2>/dev/null
        mkdir /var/cache/squid 2>/dev/null
        mkdir /var/spool/squid 2>/dev/null
        #squid -z
        #service squid start
        systemctl enable squid
        systemctl start squid
}
initializeFiles()
{
		mkdir -p ${BASEDIR}
        cp proxy.sh ${BASEDIR}/proxy.sh
        cp monitor.sh ${BASEDIR}/monitor.sh
        cp initdb.sql ${BASEDIR}/initdb.sql
        echo "OS=$OS" >> ${BASEDIR}/${CONFIG_FILE}
        echo "DISTRIBUTION=$DISTRIB" >>${BASEDIR}/${CONFIG_FILE}
        echo "BASEDIR=${BASEDIR}" >> ${BASEDIR}/${CONFIG_FILE}
        echo "PRIMARYKEY=${PRIMARYKEY}" >> ${BASEDIR}/${CONFIG_FILE}
        cd ${BASEDIR}
        chmod +x proxy.sh
        >/etc/squid/squiddb
        >/etc/squid/squid.passwd
        mkdir -p /etc/squid/conf.d/
        touch /etc/squid/conf.d/sample.conf
}
installMariadb()
{
        apt-get install -y mariadb-server
		echo "Initialize Database structure. Please enter Password as root@2019 when prompted"
        read -p "press any key to continue" ANS
		systemctl enable mysql
		systemctl start mysql
		/usr/bin/mysql_secure_installation
			
}
initializeDB()
{
        echo "Initialize Database structure. Please enter Password as root@2019 when prompted"
        cat initdb.sql | mysql -u root -p
}
setconfig()
{
        cp /etc/squid/squid.conf /etc/squid/squid.conf.orig
        > /etc/squid/squid.conf
        while read LINE
        do
                echo "$LINE" >> /etc/squid/squid.conf
        done <<EOL
http_port 7656
visible_hostname localhost
forwarded_for delete
via off

logformat squid %ts.%03tu %6tr %>a %Ss/%03>Hs %<st %rm %ru %un %Sh/%<A %mt
access_log /var/log/squid/access.log squid

cache deny all
coredump_dir /var/spool/squid

acl QUERY urlpath_regex cgi-bin \?


refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/squid.passwd
auth_param basic children 1024
auth_param basic realm Proxy
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off

request_header_access Allow allow all
request_header_access Authorization allow all
request_header_access WWW-Authenticate allow all
request_header_access Proxy-Authorization allow all
request_header_access Proxy-Authenticate allow all
request_header_access Cache-Control allow all
request_header_access Content-Encoding allow all
request_header_access Content-Length allow all
request_header_access Content-Type allow all
request_header_access Date allow all
request_header_access Expires allow all
request_header_access Host allow all
request_header_access If-Modified-Since allow all
request_header_access Last-Modified allow all
request_header_access Location allow all
request_header_access Pragma allow all
request_header_access Accept allow all
request_header_access Accept-Charset allow all
request_header_access Accept-Encoding allow all
request_header_access Accept-Language allow all
request_header_access Content-Language allow all
request_header_access Mime-Version allow all
request_header_access Retry-After allow all
request_header_access Title allow all
request_header_access Connection allow all
request_header_access Proxy-Connection allow all
request_header_access User-Agent allow all
request_header_access Cookie allow all
request_header_access All deny all

reply_header_access Via deny all
reply_header_access X-Cache deny all
reply_header_access X-Cache-Lookup deny all

shutdown_lifetime 3 seconds
acl blockList dstdomain "/etc/squid/blacklist.acl"
http_access deny blockList

include /etc/squid/conf.d/*.conf

EOL
}

checkRoot
checkOS
getInterface
installSquid
initializeFiles
installMariadb
initializeDB
setconfig
ln -s /opt/squid/proxy.sh /usr/bin/proxy
touch /etc/squid/blacklist.acl
