#!/bin/bash
#####################################################################
#######            MOnitor Script                           #########
#####################################################################

###Global Variables
OS=`uname -s`
DISTRIB=`cat /etc/centos-release | awk '{print $1}'`
SQUID_VERSION=4.8
CONFIG_FILE="/opt/squid/config.cfg"
BASEDIR="/opt/squid"
CONFIGDIR="/etc/squid"
USERMASTER="/etc/squid/squid.passwd"
MYSQLDB="squiddb"
MYSQLUSER="squid"
MYSQL_PWD="root@2019"
export MYSQL_PWD

CDATE=`echo $(date +%F)`
CTIME=`echo $(date +%T)`

userids=`mysql -N -h localhost -u $MYSQLUSER $MYSQLDB -e "SELECT USERID from PROXYMASTER where DATE(edate) <= curdate() and TIME(etime) < curtime() ;"`
echo "Proxy Expiry Log: $(date +%T)" >> /var/tmp/proxydelete.log
for userid in $userids
do
        username=`mysql -N -h localhost -u $MYSQLUSER $MYSQLDB -e "SELECT USERNAME FROM USERMASTER WHERE USERID=$userid;"`
        ${BASEDIR}/proxy.sh $username
done

