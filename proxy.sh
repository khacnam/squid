#!/bin/bash
###Global Variables
OS=`uname -s`
DISTRIB=`cat /etc/*release* | grep -i DISTRIB_ID | cut -f2 -d=`
SQUID_VERSION=4.8
BASEDIR="/opt/squid"
CONFIGDIR="/etc/squid"
CONFIG_FILE="${BASEDIR}/config.cfg"
PASSWDMASTER="/etc/squid/squid.passwd"
BLACKLIST="/etc/squid/blacklist.acl"
MYSQLDB="squiddb"
MYSQLUSER="squid"
MYSQL_PWD="root@2019"
export MYSQL_PWD

if [ $# -eq 1 ]
then
        userid=`mysql -N -h localhost -u $MYSQLUSER $MYSQLDB -e "SELECT USERID FROM USERMASTER WHERE USERNAME='$1';"`
        if [ -z "$userid" ];then echo "User $1 Doesn't EXIST!!!";exit 32;fi
        ipids=`mysql -N -h localhost -u $MYSQLUSER $MYSQLDB -e "select IPID from PROXYMASTER where USERID=$userid;"`
        for IPID in $ipids
        do
            mysql -h localhost -u $MYSQLUSER $MYSQLDB -e "DELETE from PROXYMASTER WHERE IPID=$IPID and USERID=$userid;"
            mysql -h localhost -u $MYSQLUSER $MYSQLDB -e "UPDATE IPMASTER SET STATUS=0 WHERE IPID=$IPID;"
        done
        mysql -N -h localhost -u $MYSQLUSER $MYSQLDB -e "DELETE from USERMASTER WHERE USERNAME='$1';"
        echo "User: $1 DELETED!!!!"
        rm -rf /etc/squid/conf.d/${userid}.conf
        systemctl reload squid
        exit 0
else
        echo > /dev/null
fi

checkRoot()
{
        if [ `id -u` -ne 0 ]
        then
                echo "SCRIPT must be RUN as root user"
                exit 13
        else
                echo "USER: root" 1>/dev/null
        fi
}
checkOS()
{
        if [ "$OS" == "Linux" ] && [ "$DISTRIB" == "Ubuntu" ]
        then
                echo "Operating System = $DISTRIB $OS" 1>/dev/null
        else
                echo "Please run this script on Ubuntu Linux" 1>/dev/null
                exit 12
        fi
}
checkSquid()
{
        dpkg-query --list squid >/dev/null 2>&1
        if [ `echo $?` -eq 0 ]
        then
                echo "Squid Installed" > /dev/null
        else
                apt-get install squid apache2-utils -y
        fi
        clear
}
printMenu()
{
        clear
        tput clear
        for I in {1..80};do tput cup 1 $I;printf "#";done
        printf "\n"
        R=2
        C1=1
        C2=45
        M=1
        while read LINE
        do
                tput cup $R $C1;printf "[$M]`echo $LINE | awk -F, '{print $1}'`"
                M=$((M+1))
                tput cup $R $C2;printf "[$M]`echo $LINE | awk -F, '{print $2}'`"
                M=$((M+1))
                R=$((R+1))
        done <<EOM
ADD IP TO SERVER,SHOW AVAILABLE PROXIES
ADD USER,ASSIGN IP TO USER
SHOWS USERS EXPIRE DATE,MODIFY USERS EXPIRY DATE
SHOW USERS PROXY INFO,DELETE IP FROM SERVER
DELETE USER PROXY,DELETE USER
SHUTDOWN PROXY,START PROXY
EXPORT AVAILABLE PROXY,EXPORT USERS PROXY
ADD BLACK LIST,SHOW BLACKLIST
DELETE BLACKLIST,EXIT
RANDOM PROXIES,CHANGE IP-MULTIPLIER
EOM
        for I in {1..11};do tput cup $I 80;printf "#";done
        for I in {1..80};do tput cup 12 $I;printf "#";done
        printf "\n"
        tput sgr0
}
createProxyFile()
{
        cd ${CONFIGDIR}/conf.d/
        printf "acl $1_$2 myip $1\n" >> $5
        printf "tcp_outgoing_address $1 $1_$2\n" >>$5
        printf "http_access allow $3 $1_$2 $3_$2\n" >> $5
}
Menu_1()
{
        INT=`cat ${CONFIG_FILE} | grep INTERFACE | awk -F"=" '{print $2}'`
        echo "Please Enter IP Address Block Details"
        read -p "Enter Starting IP address:" IPBLK
        read -p "Enter total number of IP :" N
        read -p "Enter Subnet[21|22|23|24]:" S
        J=`echo ${IPBLK} | cut -f3 -d.`
    IP=`echo ${IPBLK} | cut -f1,2 -d.`
    M=0
    I=`echo ${IPBLK} | cut -f4 -d.`
    while [ $M -lt $N ]
    do
    if [ $I -eq 256 ]; then J=$((J+1));I=0;fi
    NEWIP="$IP.$J.$I"
    I=$((I+1))
    M=$((M+1))
    mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "insert into IPMASTER (IPADDRESS,STATUS,MUL,USED) values (INET_ATON('$NEWIP'),0,1,0);"
    ip addr add $NEWIP/$S dev $INT
        touch /etc/network/interfaces.d/${NEWIP}
        echo "auto $INT" >> /etc/network/interfaces.d/${NEWIP}
    echo "iface $INT inet static" >> /etc/network/interfaces.d/${NEWIP}
    echo "address ${NEWIP}" >> /etc/network/interfaces.d/${NEWIP}
    echo "netmask 255.255.255.255" >> /etc/network/interfaces.d/${NEWIP}
    done
}
Menu_2()
{
    mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT INET_NTOA(IPADDRESS),MUL-USED as FREE_IP FROM IPMASTER WHERE STATUS IS FALSE;"
    mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT SUM(MUL-USED) as FREE_IP FROM IPMASTER WHERE STATUS IS FALSE;"
}
Menu_3()
{
        read -p "Enter Username: " username
        read -p "Enter Password: " password
        #Check Duplicate Username
    USERCOUNT=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT COUNT(*) FROM USERMASTER WHERE USERNAME='$username';"`
    if [ $USERCOUNT -eq 1 ];then
                echo "Username already exist"
        exit 30
    fi
        mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "INSERT INTO USERMASTER (username,password) VALUES ('$username','$password');"
    /usr/bin/htpasswd -b $PASSWDMASTER $username $password
}
Menu_4()
{
        mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERNAME FROM USERMASTER;"
                read -p "Enter Username:" username
        userid=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERID FROM USERMASTER WHERE USERNAME='$username';"`
        if [ -z $userid ]; then echo "$username Doesn't EXIST!!"; exit 22;fi
        password=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT PASSWORD FROM USERMASTER WHERE USERNAME='$username';"`
        COUNTOFIP=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT SUM(MUL-USED) as FREEIP FROM IPMASTER WHERE STATUS IS FALSE;"`
        #COUNTOFIP=`echo $COUNTOFIP | wc -w`

        echo "Total Available proxies: $COUNTOFIP"
        read -p "Enter Number of proxies to create: " PXYNO
        if [ $COUNTOFIP -lt $PXYNO ]; then echo "Not enough available proxies to serve";exit 35;fi
        read -p "Enter Port Number:" PXYPORT
        EXPORTS=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT DISTINCT(PORT) FROM PROXYMASTER WHERE USERID=$userid;"`
        for EX_PORT in $EXPORTS
        do
                if [ $EX_PORT -eq $PXYPORT ];then echo "Port already exist";read -p "Enter Port Number:" PXYPORT;fi
        done
        read -p "Enter number of days:" PXYDAYS

    LISTOFIPID=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT IPID FROM IPMASTER WHERE STATUS IS FALSE ORDER BY USED LIMIT $PXYNO;"`
    SDATE=`echo $(date +%F)`
    STIME=`echo $(date +%T)`
    EDATE=`echo $(date +%F -d "+$PXYDAYS days")`
    ETIME=`echo $(date +%T)`
    for IPID in $LISTOFIPID
    do
        mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "INSERT INTO PROXYMASTER (USERID,IPID,PORT,SDATE,STIME,EDATE,ETIME) VALUES ($userid,$IPID,$PXYPORT,'$SDATE','$STIME','$EDATE','$ETIME');"
		mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "UPDATE IPMASTER SET USED=USED+1 WHERE IPID=$IPID;"
        mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "UPDATE IPMASTER SET STATUS=1 WHERE IPID=$IPID AND MUL=USED;"
    done
        for IPID in $LISTOFIPID
        do
                IPA=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT INET_NTOA(IPADDRESS) as IP FROM IPMASTER WHERE IPID=$IPID;"`
                echo "$IPA:$PXYPORT:$username:$password"
        done

        FILENAME="${userid}.conf"
    cd ${CONFIGDIR}/conf.d/
    touch $FILENAME
    printf "http_port $PXYPORT name=$username$PXYPORT\n" >>$FILENAME
    printf "acl ${username}_${PXYPORT} myportname $username$PXYPORT\n" >>$FILENAME
    printf "acl ${username} proxy_auth $username\n" >>$FILENAME
    for IPID in $LISTOFIPID
    do
        IPA=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT INET_NTOA(IPADDRESS) as IP FROM IPMASTER WHERE IPID=$IPID;"`
        createProxyFile "$IPA" "$PXYPORT" "$username" "$password" "$FILENAME"
    done
    systemctl reload squid
}
Menu_5()
{
        mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERNAME FROM USERMASTER;"
        read -p "Enter Username:" username
        userid=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERID FROM USERMASTER WHERE USERNAME='$username';"`
        if [ -z $userid ]; then echo "No $username exist"; exit 22;fi
        EXPDATE=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT EDATE FROM PROXYMASTER WHERE USERID='$userid';"`
        echo "USER  : $username"
        mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "select INET_NTOA(IPADDRESS) as IP,EDATE FROM IPMASTER I INNER JOIN PROXYMASTER X ON X.IPID=I.IPID WHERE X.USERID=$userid;"
}
Menu_6()
{
        mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERNAME FROM USERMASTER;"
        read -p "Enter Username:" username
        userid=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERID FROM USERMASTER WHERE USERNAME='$username';"`
        if [ -z $userid ]; then echo "No $username exist"; exit 22;fi

        echo "USER  : $username"
        echo "EXPIRY"
        mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "select INET_NTOA(IPADDRESS) as IP,EDATE FROM IPMASTER I INNER JOIN PROXYMASTER X ON X.IPID=I.IPID WHERE X.USERID=$userid;"
        read -p "Enter New Expiry Date [2019-12-25]:" NEWEXPDATE
        mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "UPDATE PROXYMASTER SET EDATE='$NEWEXPDATE' WHERE USERID='$userid';"
}
Menu_7()
{
        mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERNAME FROM USERMASTER;"
        read -p "Enter Username:" username
        userid=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERID FROM USERMASTER WHERE USERNAME='$username';"`
        if [ -z $userid ]; then echo "No $username exist"; exit 22;fi
        mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e  "select INET_NTOA(IPADDRESS) as IP,PORT,USERNAME,PASSWORD FROM USERMASTER U inner join PROXYMASTER X on U.USERID=X.USERID inner join IPMASTER I on X.IPID=I.IPID where U.USERNAME='$username';"
        PROXIES=`mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e  "select INET_NTOA(IPADDRESS) as IP,PORT,USERNAME,PASSWORD FROM USERMASTER U inner join PROXYMASTER X on U.USERID=X.USERID inner join IPMASTER I on X.IPID=I.IPID where U.USERNAME='$username';"`
        IFS=$'\n'
        for LINE in $PROXIES; do echo $LINE | awk '{print $1":"$2":"$3":"$4}'; done
}
Menu_8()
{
        INT=`cat ${CONFIG_FILE} | grep INTERFACE | awk -F"=" '{print $2}'`
        echo "Please Enter IP Address Block Details"
        read -p "Enter Starting IP address:" IPBLK
        read -p "Enter total number of IP :" N
        read -p "Enter Subnet[21|22|23|24]:" S
        J=`echo ${IPBLK} | cut -f3 -d.`
    IP=`echo ${IPBLK} | cut -f1,2 -d.`
    M=0
    I=`echo ${IPBLK} | cut -f4 -d.`
    while [ $M -lt $N ]
    do
    if [ $I -eq 256 ]; then J=$((J+1));I=0;fi
    NEWIP="$IP.$J.$I"
    I=$((I+1))
    M=$((M+1))
    mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "delete from IPMASTER where IPADDRESS=INET_ATON('$NEWIP');"
    ip addr del $NEWIP/$S dev $INT
        rm -rf /etc/network/interfaces.d/${NEWIP} 2>/dev/null
    done
}
Menu_9()
{
        mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERNAME FROM USERMASTER;"
        read -p "Enter Username:" username

        userid=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERID FROM USERMASTER WHERE USERNAME='$username';"`
        if [ -z "$userid" ];then echo "User $username Doesn't EXIST!!!";exit 32;fi
        ipids=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "select IPID from PROXYMASTER where USERID=$userid;"`
        for IPID in $ipids
        do
            mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "DELETE from PROXYMASTER WHERE IPID=$IPID and USERID=$userid;"
			mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "UPDATE IPMASTER SET USED=USED-1 WHERE IPID=$IPID;"
            mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "UPDATE IPMASTER SET STATUS=0 WHERE IPID=$IPID;"
        done
        rm -rf /etc/squid/conf.d/${userid}.conf
        systemctl reload squid
}
Menu_10()
{
        mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERNAME FROM USERMASTER;"
        read -p "Enter Username: " username
        mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "DELETE from USERMASTER WHERE USERNAME='$username';"
    echo "User: $username DELETED!!!!"
    /usr/bin/htpasswd -D ${PASSWDMASTER} $username
}
Menu_11()
{
        echo "Shutting down.."
        systemctl stop squid
        echo "Proxy is DOWN now"
}
Menu_12()
{
        echo "Starting Proxy.."
        systemctl start squid
        if [ `echo $?` -eq 0 ]
        then
                echo "Proxy is UP now"
        else
                echo "Proxy Configuration error"
        fi
}
Menu_13()
{
        mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT INET_NTOA(IPADDRESS) as FREE_IP FROM IPMASTER WHERE STATUS IS FALSE;" > /root/availableip.txt
        echo "Available IP's exported to /root/availableip.txt"

}
Menu_14()
{
        PROXIES=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "select INET_NTOA(IPADDRESS) as IP,PORT,USERNAME,PASSWORD FROM USERMASTER U inner join PROXYMASTER X on U.USERID=X.USERID inner join IPMASTER I on X.IPID=I.IPID ORDER BY USERNAME;"`
        IFS=$'\n'
        >/root/usersproxy.txt
        for LINE in $PROXIES; do echo $LINE | awk '{print $1":"$2":"$3":"$4}' |tee -a /root/usersproxy.txt; done
        echo "User Proxies exported to /root/usersproxy.txt"
}
Menu_15()
{
        read -p "Enter URL to add in blacklist: " blackurl
        echo ".${blackurl}" >> $BLACKLIST
        echo "$blackurl added to Blacklist Category"
                systemctl reload squid
}
Menu_16()
{
        echo "Following URL's are in Blacklist Category"
        cat $BLACKLIST
}
Menu_17()
{
        echo "Following URL's are in Blacklist Category"
        cat $BLACKLIST
        read -p "Enter URL to be removed from Blacklist: " whiteurl
        cat $BLACKLIST | grep -v $whiteurl > newblacklist
        mv newblacklist $BLACKLIST
                systemctl reload squid
}
Menu_19()
{	
	RNDUSER=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
	RNDPASSWORD=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
	#Check Duplicate Username
    USERCOUNT=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT COUNT(*) FROM USERMASTER WHERE USERNAME='$RNDUSER';"`
    if [ $USERCOUNT -eq 1 ];then
        RNDUSER=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 7 | head -n 1)
    fi
    mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "INSERT INTO USERMASTER (username,password) VALUES ('$RNDUSER','$RNDPASSWORD');"
    /usr/bin/htpasswd -b $PASSWDMASTER $RNDUSER $RNDPASSWORD
	
	userid=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT USERID FROM USERMASTER WHERE USERNAME='$RNDUSER';"`
    COUNTOFIP=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT SUM(MUL-USED) as FREEIP FROM IPMASTER WHERE STATUS IS FALSE;"`
    #COUNTOFIP=`echo $COUNTOFIP | wc -w`
    echo "Total Available proxies: $COUNTOFIP"
	read -p "Enter Number of RANDOM Proxies: " RNDNO
    if [ $COUNTOFIP -lt $RNDNO ]; then echo "Not enough available proxies to serve";exit 35;fi
	RNDPORT=$(shuf -i 10000-16000 -n 1)
    EXPORTS=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT DISTINCT(PORT) FROM PROXYMASTER WHERE USERID=$userid;"`
    for EX_PORT in $EXPORTS
    do
        if [ $EX_PORT -eq $RNDPORT ];then RNDPORT=$(shuf -i 10000-16000 -n 1);fi
    done
    read -p "Enter number of days:" PXYDAYS

    LISTOFIPID=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT IPID FROM IPMASTER WHERE STATUS IS FALSE ORDER BY USED LIMIT $RNDNO;"`
    SDATE=`echo $(date +%F)`
    STIME=`echo $(date +%T)`
    EDATE=`echo $(date +%F -d "+$PXYDAYS days")`
    ETIME=`echo $(date +%T)`
    for IPID in $LISTOFIPID
    do
        mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "INSERT INTO PROXYMASTER (USERID,IPID,PORT,SDATE,STIME,EDATE,ETIME) VALUES ($userid,$IPID,$RNDPORT,'$SDATE','$STIME','$EDATE','$ETIME');"
        mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "UPDATE IPMASTER SET USED=USED+1 WHERE IPID=$IPID;"
        mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "UPDATE IPMASTER SET STATUS=1 WHERE IPID=$IPID AND MUL=USED;"
    done
    for IPID in $LISTOFIPID
    do
        IPA=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT INET_NTOA(IPADDRESS) as IP FROM IPMASTER WHERE IPID=$IPID;"`
        echo "$IPA:$RNDPORT:$RNDUSER:$RNDPASSWORD"
    done

    FILENAME="${userid}.conf"
    cd ${CONFIGDIR}/conf.d/
    touch $FILENAME
    printf "http_port $RNDPORT name=$RNDUSER$RNDPORT\n" >>$FILENAME
    printf "acl ${RNDUSER}_${RNDPORT} myportname $RNDUSER$RNDPORT\n" >>$FILENAME
    printf "acl ${RNDUSER} proxy_auth $RNDUSER\n" >>$FILENAME
    for IPID in $LISTOFIPID
    do
        IPA=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT INET_NTOA(IPADDRESS) as IP FROM IPMASTER WHERE IPID=$IPID;"`
        createProxyFile "$IPA" "$RNDPORT" "$RNDUSER" "$RNDPASSWORD" "$FILENAME"
    done
    systemctl reload squid
}
Menu_20()
{
	CURMUX=`mysql -N -h localhost -u $MYSQLUSER  $MYSQLDB -e "SELECT MUL FROM IPMASTER limit 1;"`
	echo "Current Multiplier = $CURMUX"
	read -p "Enter New Multiplier value [${CURMUX}-99]: " NEWMUX
	if [ $NEWMUX -lt $CURMUX ];then echo "Please Delete all proxies and then change the Multiplier Values"; exit 33;fi
	if [ $NEWMUX -eq 0 ];then echo "Please enter a value greater than 0"; exit 33;fi
	read -p "Are you sure [Y/N]: " RES
	if [ "${RES}" == "Y" ] || [ "${RES}" == "y" ]
	then
		mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "UPDATE IPMASTER SET MUL=$NEWMUX;"
		mysql -h localhost -u $MYSQLUSER  $MYSQLDB -e "UPDATE IPMASTER SET STATUS=0;"
	else
		echo ""
	fi
}
getMenuInput()
{
        read -p "Select an option from above menu: " MenuAnswer
        case ${MenuAnswer} in
        1)
        Menu_1
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        2)
        Menu_2
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        3)
        Menu_3
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        4)
        Menu_4
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        5)
        Menu_5
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        6)
        Menu_6
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        7)
        Menu_7
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        8)
        Menu_8
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        9)
        Menu_9
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        10)
        Menu_10
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        11)
        Menu_11
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        12)
        Menu_12
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        13)
        Menu_13
        ;;
        14)
        Menu_14
        ;;
        15)
        Menu_15
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        16)
        Menu_16
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        17)
        Menu_17
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        18)
        exit 0
        ;;
		19)
        Menu_19
        read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
		20)
        #Menu_20
        #read -p "Press any key to continue" KEY
        printMenu
        getMenuInput
        ;;
        *)
        printMenu
		getMenuInput
        ;;
        esac

}
checkRoot
checkOS
checkSquid
printMenu
getMenuInput
