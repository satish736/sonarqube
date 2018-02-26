#!/bin/bash

## Source Common Functions
curl -s "https://raw.githubusercontent.com/devops2k18/scripts/master/common-functions.sh" >/tmp/common-functions.sh
#source /root/scripts/common-functions.sh
source /tmp/common-functions.sh

## Checking Root User or not.
CheckRoot

## Checking SELINUX Enabled or not.
CheckSELinux

## Checking Firewall on the Server.
CheckFirewall

which java &>/dev/null
if [ $? -ne 0 ]; then 
	## Downloading Java
	DownloadJava 8
	## Installing Java
	yum install /opt/jdk* -y &>/dev/null
	if [ $? -eq 0 ]; then 
		success "JAVA Installed Successfully"
	else
		error "JAVA Installation Failure!"
		exit 1
	fi
else
	success "Java already Installed"
fi


## Downloading MYSQL Repositories and MySQL Server
yum install https://kojipkgs.fedoraproject.org/packages/python-html2text/2016.9.19/1.el7/noarch/python2-html2text-2016.9.19-1.el7.noarch.rpm -y &>/dev/null
MYSQLRPM=$(curl -s http://repo.mysql.com/ | html2text | grep el7 | tail -1 | sed -e 's/(/ /g' -e 's/)/ /g' | xargs -n1 | grep ^mysql)
MYSQLURL="http://repo.mysql.com/$MYSQLRPM"

if [ ! -f /etc/yum.repos.d/mysql-community.repo ]; then 

	yum install $MYSQLURL -y &>/dev/null
	if [ $? -eq 0 ]; then 
		success "Successfully Configured MySQL Repositories"
	else
		error "Error in Configuring MySQL Repositories"
		exit 1
	fi
else
	warning "MySQL Repositories are already Configured"
fi     

## Installing MySQL Server
yum install mysql-server -y &>/dev/null
if [ $? -eq 0 ]; then 
	success "Successfully Installed MySQL Server"
else
	error "Error in Installing MySQL Server"
	exit 1
fi

## Set Root Password and reset it
sed -i -e '/query_cache_size/ d' -e '$ a query_cache_size = 15M' /etc/my.cnf 
systemctl enable mysqld &>/dev/null
systemctl set-environment MYSQLD_OPTS="--skip-grant-tables"
systemctl restart mysqld
mysql -e "use mysql;update user set authentication_string=password(''), plugin='mysql_native_password' where user='root';"
systemctl unset-environment MYSQLD_OPTS
systemctl restart mysqld
mysql --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'P@$$w0rD'"
systemctl set-environment MYSQLD_OPTS="--skip-grant-tables"
systemctl restart mysqld
mysql -e "use mysql;update user set authentication_string=password(''), plugin='mysql_native_password' where user='root';"
systemctl unset-environment MYSQLD_OPTS
systemctl restart mysqld
mysql -e "grant all privileges on sonarqube.* to 'sonarqube'@'localhost' identified by 'password';" &>/dev/null
mysql -e 'uninstall plugin validate_password;' &>/dev/null

## Creating DB and User access
wget https://raw.githubusercontent.com/linuxautomations/sonarqube/master/sonarqube.sql -O /tmp/sonarqube.sql &>/dev/null
mysql </tmp/sonarqube.sql
if [ $? -eq 0 ]; then
	success "Successfully Created DB and User access"
else
	error "Failed to create DB and User access"
	exit 1
fi


## Downloading SonarQube 
VER=$(curl -s https://sonarsource.bintray.com/Distribution/sonarqube/  | tail -n 10 | awk -F '[<,>]' '{print $5}' | grep zip$ |tail -1)
URL="https://sonarsource.bintray.com/Distribution/sonarqube/$VER"
TFILE="/opt/$VER"
TDIR=$(echo $TFILE|sed -e 's/.zip//')
rm -rf /opt/sonarqube
wget $URL -O $TFILE &>/dev/null
cd /opt
unzip $VER &>/dev/null
mv $TDIR sonarqube 
if [ $? -eq 0 ]; then
	success "Successfully Downloaded and Extracted SonarQube"
else
	error "Error in Downlading and Extracting SonarQube"
	exit 1
fi

## Configure SonarQube
sed -i -e '/^sonar.jdbc.username/ d' -e '/^sonar.jdbc.password/ d' -e '/^sonar.jdbc.url/ d' -e '/^sonar.web.host/ d' -e '/^sonar.web.port/ d' /opt/sonarqube/conf/sonar.properties
sed -i -e '/#sonar.jdbc.username/ a sonar.jdbc.username=sonarqube' -e '/#sonar.jdbc.password/ a sonar.jdbc.password=password' -e '/InnoDB/ a sonar.jdbc.url=jdbc:mysql://localhost:3306/sonarqube?useUnicode=true&amp;characterEncoding=utf8&amp;rewriteBatchedStatements=true&amp;useConfigs=maxPerformance' -e '/#sonar.web.host/ a sonar.web.host=0.0.0.0' /opt/sonarqube/conf/sonar.properties

useradd sonar
chown sonar:sonar /opt/sonarqube -R
sed -i -e '/^#RUN_AS_USER/ c RUN_AS_USER=sonar' /opt/sonarqube/bin/linux-x86-64/sonar.sh
ln -s /opt/sonarqube/bin/linux-x86-64/sonar.sh /etc/init.d/sonar
systemctl enable sonar &>/dev/null 
systemctl start sonar &>/dev/null
if [ $? -eq 0 ]; then
	success "Configured and Started SonarQube Successfully"
else
	error "SonarQube Startup Failed"
	exit 1
fi
