#!/bin/bash
# ZStack All-In-One Installer
# Usage: bash install.sh
#DEBUG='y'
ZSTACK_INSTALL_ROOT=${ZSTACK_INSTALL_ROOT:-"/usr/local/zstack"}

CENTOS6='CENTOS6'
CENTOS7='CENTOS7'
UBUNTU1404='UBUNTU14.04'
MANAGEMENT_INTERFACE=`ip route | grep default | cut -d ' ' -f 5`
SUPPORTED_OS="$CENTOS6, $CENTOS7, $UBUNTU1404"
ZSTACK_INSTALL_LOG='/tmp/zstack_installation.log'
[ -f $ZSTACK_INSTALL_LOG ] && /bin/rm -f $ZSTACK_INSTALL_LOG
INSTALLATION_FAILURE=/tmp/zstack_installation_failure_exit_code
[ -f $INSTALLATION_FAILURE ] && /bin/rm -f $INSTALLATION_FAILURE

WIDTH=`tput cols`
[ -z $WIDTH ] && WIDTH=80
HEIGHT=`tput lines`
[ -z $HEIGHT ] && HEIGHT=25
ZSTACK_INSTALLATION='ZStack Intallation'
START_POINT=`expr $WIDTH / 2 + 9`
END_POINT=`expr $WIDTH - $START_POINT - 1`
STEP="1"

zstack_tmp_file=`mktemp`
ZSTACK_ALL_IN_ONE=${ZSTACK_ALL_IN_ONE-"http://download.zstack.org/releases/0.6/zstack-all-in-one-0.6.tgz"}
#TODO: change to ZStack WEBSITE
WEBSITE=${WEBSITE-'www.w3.org'}
DEFAULT_PYPI='https://pypi.python.org/simple/'
ZSTACK_PYPI_URL=${ZSTACK_PYPI_URL-$DEFAULT_PYPI}
ZSTACK_VERSION=$ZSTACK_INSTALL_ROOT/VERSION
CATALINA_ZSTACK_PATH=apache-tomcat/webapps/zstack
CATALINA_ZSTACK_CLASSES=$CATALINA_ZSTACK_PATH/WEB-INF/classes
ZSTACK_PROPERTIES=$CATALINA_ZSTACK_CLASSES/zstack.properties
ZSTACK_DB_DEPLOYER=$CATALINA_ZSTACK_CLASSES/deploydb.sh
CATALINA_ZSTACK_TOOLS=$CATALINA_ZSTACK_CLASSES/tools
ZSTACK_TOOLS_INSTALLER=$CATALINA_ZSTACK_TOOLS/install.sh

NEED_NFS=''
NEED_HTTP=''
NEED_DROP_DB=''
NEED_KEEP_DB=''
ONLY_INSTALL_LIBS=''
ONLY_INSTALL_ZSTACK=''

MYSQL_ROOT_PASSWORD=''
MYSQL_ZSTACK_PASSWORD=''

show_download()
{
    $1 &
    PID=$!
    local delay=0.2
    ps -p $PID >/dev/null 2>&1
    sleep 0.05
    echo -n " ... "
    while [ $? -eq 0 ]; do
        if [ -z $DEBUG ];then
            local temp=`ls -sh $zstack_tmp_file |awk '{print $1}'`
            to_print="$temp"
            echo -n $to_print
            size=${#to_print} 
            sleep $delay
            count=0
            while [ $count -lt $size ]; do echo -ne "\b" ; count=`expr $count + 1`; done
        else
            sleep $delay
        fi
        ps -p $PID >/dev/null 2>&1
    done
    if [ -f $INSTALLATION_FAILURE ]; then
        failure_reason=`cat $INSTALLATION_FAILURE`
        #tput cub 6
        if [ -z $DEBUG ]; then
            echo -e "$(tput setaf 1)FAIL\n$(tput sgr0)"|tee -a $ZSTACK_INSTALL_LOG
            echo -e "$(tput setaf 1)  Reason: $failure_reason\n$(tput sgr0)"|tee -a $ZSTACK_INSTALL_LOG
        else
            echo "FAIL"
            echo "Reason: $failure_reason"
        fi
        exit 1
    else
        if  [ -z $DEBUG ]; then
            echo -e "$(tput setaf 2)PASS$(tput sgr0)"|tee -a $ZSTACK_INSTALL_LOG
        else
            echo "PASS"
        fi
    fi
}

show_spinner()
{
    $* &
    PID=$!
    local delay=0.1
    local spinstr='|/-\'
    spin[0]="-"
    spin[1]="\\"
    spin[2]="|"
    spin[3]="/"
    sleep 0.05
    echo -n " ... "
    while kill -0 $PID 2>/dev/null
    do
        if [ -z $DEBUG ];then
            for i in "${spin[@]}"
                do
                    echo -ne "$i"
                    sleep 0.1
                    echo -ne "\b"
            done
        else
            sleep 0.1
        fi
    done

    if [ -f $INSTALLATION_FAILURE ]; then
        failure_reason=`cat $INSTALLATION_FAILURE`
        #tput cub 6
        if [ -z $DEBUG ]; then
            echo -e "$(tput setaf 1)FAIL\n$(tput sgr0)"|tee -a $ZSTACK_INSTALL_LOG
            echo -e "$(tput setaf 1)  Reason: $failure_reason\n$(tput sgr0)"|tee -a $ZSTACK_INSTALL_LOG
        else
            echo "FAIL"
            echo "Reason: $failure_reason"
        fi
        exit 1
    else
        if [ -z $DEBUG ]; then
            echo -e "$(tput setaf 2)PASS$(tput sgr0)"|tee -a $ZSTACK_INSTALL_LOG
        else
            echo "PASS"
        fi
    fi
}

debug(){
    [ ! -z $DEBUG ] && echo "  [DEBUG]: " $*
}

echo_star_line(){
    i=0
    line=''
    while [ $i -lt $WIDTH ];do
        line=$line"_"
        i=`expr $i + 1 `
    done
    echo $line
}

cancel(){
    echo ""|tee -a $ZSTACK_INSTALL_LOG
    [ ! -z $PID ] && kill -9 $PID
    tput sgr0
    tput rc
    echo -e "$(tput setaf 3)Installation canceled by User\n$(tput sgr0)"
    echo "The detailed installation log could be found in $ZSTACK_INSTALL_LOG"
    /bin/rm -f $INSTALLATION_FAILURE
    /bin/rm -f $zstack_tmp_file
    exit 1
}

trap cancel INT

# The params is failed reason
fail(){
    #tput cub 6
    #echo -e "$(tput setaf 1) FAIL\n$(tput sgr0)"|tee -a $ZSTACK_INSTALL_LOG
    #echo -e "$(tput setaf 1)  Reason: $*\n$(tput sgr0)"|tee -a $ZSTACK_INSTALL_LOG
    echo "$*  \n\nThe detailed installation log could be found in $ZSTACK_INSTALL_LOG " > $INSTALLATION_FAILURE
    exit 1
}

pass(){
    #echo -e "$(tput setaf 2) PASS$(tput sgr0)"|tee -a $ZSTACK_INSTALL_LOG
    return
}

echo_title(){
    echo "\n================">> $ZSTACK_INSTALL_LOG
    echo ""|tee -a $ZSTACK_INSTALL_LOG
    echo -n " ${STEP}. $*:" |tee -a $ZSTACK_INSTALL_LOG
    STEP=`expr $STEP + 1`
}

echo_subtitle(){
    echo "\n----------------" >> $ZSTACK_INSTALL_LOG
    echo -n "    $*:"|tee -a $ZSTACK_INSTALL_LOG
}

#Do preinstallation checking for CentOS and Ubuntu
check_system(){
    echo_title "Check System"
    cat /etc/*-release |grep -i centos >>$ZSTACK_INSTALL_LOG 2>&1
    if [ $? -eq 0 ]; then
        grep 'release 6' /etc/redhat-release >>$ZSTACK_INSTALL_LOG 2>&1
        if [ $? -eq 0 ]; then
            OS=$CENTOS6
        else
            grep 'release 7' /etc/redhat-release >>$ZSTACK_INSTALL_LOG 2>&1
            if [ $? -eq 0 ]; then
                OS=$CENTOS7
            else
                fail "Host OS checking failure: your system is: `cat /etc/redhat-release`, we can only support $SUPPORTED_OS currently"
            fi
        fi
    else
        grep 'Ubuntu 14.04' /etc/issue >>$ZSTACK_INSTALL_LOG 2>&1
        if [ $? -eq 0 ]; then
            OS=$UBUNTU1404
        else
            fail "Host OS checking failure: your system is: `cat /etc/issue`, we can only support $SUPPORTED_OS currently"
        fi
    fi
    
    debug "Your system is: $OS"
    show_spinner do_check_system
}

do_check_system(){
    if [ -d $ZSTACK_INSTALL_ROOT -o -f $ZSTACK_INSTALL_ROOT ];then
        fail "$ZSTACK_INSTALL_ROOT is existing. Please delete it manually before installing a new ZStack. \n  You might also want to stop zstack related services before deleting: \n\t/etc/init.d/zstack-server stop \n\t/etc/init.d/zstack-dashboard stop"
    fi

    if [ `whoami` != 'root' ];then
        fail "User checking failure: ZStack installation must be run with user: root . Current user is: `whoami`. Please append 'sudo'."
    fi

    ping -c 1 -w 1 $WEBSITE >>$ZSTACK_INSTALL_LOG 2>&1
    if [ $? -ne 0 ]; then
        fail "Network checking failure: can not reach $WEBSITE. Please make sure your DNS is configured correctly."
    fi

    rpm -qi python-crypto >/dev/null 2>&1
    if [ $? -eq 0 ]; then 
        fail "need to manually remove python-crypto by \n\n \`rpm -ev python-crypto\` \n\n; otherwise it will conflict with ansible's pycrypto." >>$ZSTACK_INSTALL_LOG
        #rpm -ev python-crypto >>$ZSTACK_INSTALL_LOG 2>&1
        #[ $? -ne 0 ] && fail "Uninstall python-crypto fail"
    fi

    ia_check_ip_hijack

    #add user: zstack and add sudo permission for it.
    id -u zstack >/dev/null 2>&1 || useradd -d $ZSTACK_INSTALL_ROOT zstack
    grep 'zstack' /etc/sudoers >/dev/null || echo 'zstack        ALL=(ALL)       NOPASSWD: ALL' >> /etc/sudoers
    sed -i '/requiretty$/d' /etc/sudoers

    pass
}

ia_check_ip_hijack(){
    HOSTNAME=`hostname`
    
    pintret=`ping -c 1 -W 2 $HOSTNAME 2>/dev/null | head -n1`
    echo $pintret | grep 'PING' > /dev/null
    [ $? -ne 0 ] && return 0
    
    ip=`echo $pintret | cut -d' ' -f 3 | cut -d'(' -f 2 | cut -d')' -f 1`
    
    ip_1=`echo $ip | cut -d'.' -f 1`
    [ "127" = "$ip_1" ] && return 0
    
    ip addr | grep $ip > /dev/null
    [ $? -eq 0 ] && return 0
    
    fail "The hostname($HOSTNAME) of your machine is resolved to IP($ip) which is none of IPs of your machine.
    It's likely your DNS server has been hijacking, please try fixing it or add \"127.0.0.1 $HOSTNAME\" to /etc/hosts by \n\n \`echo \"127.0.0.1 $HOSTNAME\" >>/etc/hosts\`."
}

ia_install_python_gcc_rh(){
    echo_subtitle "Install Python and GCC"
    if [ -z $DEBUG ];then
        yum -y install python python-devel python-pip python-setuptools gcc>>$ZSTACK_INSTALL_LOG 2>&1
    else
        yum -y install python python-devel python-pip python-setuptools gcc
    fi
    [ $? -ne 0 ] && fail "Install python and gcc fail."
    which pip >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        easy_install -i $ZSTACK_PYPI_URL pip >>$ZSTACK_INSTALL_LOG 2>&1
        [ $? -ne 0 ] && fail "Install pip fail"
    fi
    pass
}

ia_install_ansible(){
    echo_subtitle "Install Ansible"
    if [ ! -z $DEBUG ]; then
        pip install -i $ZSTACK_PYPI_URL ansible 
    else
        pip install -i $ZSTACK_PYPI_URL ansible >>$ZSTACK_INSTALL_LOG 2>&1
    fi
    [ $? -ne 0 ] && fail "install Ansible failed"
    pass
}

ia_install_python_gcc_db(){
    echo_subtitle "Install Python GCC."
    if [ ! -z $DEBUG ]; then
        apt-get -y install python python-dev python-pip python-setuptools gcc 
    else
        apt-get -y install python python-dev python-pip python-setuptools gcc >>$ZSTACK_INSTALL_LOG 2>&1
    fi
    [ $? -ne 0 ] && fail "Install python and gcc fail."
    pass
}

ia_update_apt(){
    echo_subtitle "Update Apt Source"
    dpkg --configure -a >>$ZSTACK_INSTALL_LOG 2>&1
    [ $? -ne 0 ] && fail "execute \`dpkg -- configure -a\` failed."
    apt-get update >>$ZSTACK_INSTALL_LOG 2>&1
    [ $? -ne 0 ] && fail "Update apt source fail."
    pass
}

install_ansible(){
    echo_title "Install Ansible"
    echo ""
    if [ $OS = $CENTOS7 -o $OS = $CENTOS6 ]; then
        show_spinner ia_disable_selinux
        show_spinner ia_install_python_gcc_rh
        show_spinner ia_install_ansible
    elif [ $OS = $UBUNTU1404 ]; then
        export DEBIAN_FRONTEND=noninteractive
        show_spinner ia_update_apt
        show_spinner ia_install_python_gcc_db
        show_spinner ia_install_ansible
    fi
}

is_install_general_libs(){
    echo_subtitle "Install General Libraries"
    ansible_inventory=`mktemp`
    cat > $ansible_inventory << EOF
[localhost]
$MNT ansible_connection=localhost
EOF

    epel_repo_file=`mktemp`
    cat > $epel_repo_file <<EOF
[epel-release-source]
name = epel release source package
mirrorlist = http://mirrors.fedoraproject.org/mirrorlist?repo=epel-\$releasever&arch=\$basearch
failovermethod = priority
enabled = 0
gpgcheck = 0
EOF

    ansible_yaml=`mktemp`
    cat > $ansible_yaml <<EOF
---
- hosts: 127.0.0.1
  connection: local
  remote_user: root

  tasks:
    - name: install lib-selinux for RedHatOS
      when: ansible_os_family == 'RedHat'
      yum: pkg=libselinux-python

    - name: state epel.repo
      stat: path=/etc/yum.repos.d/epel.repo
      register: epel_repo

    - name: install epel-release yum repo
      when: ansible_os_family == 'RedHat' and epel_repo.stat.exists != true
      copy: src=$epel_repo_file
            dest=/etc/yum.repos.d/epel_src.repo
            owner=root group=root mode=0644
    
    - name: install epel-release
      when: ansible_os_family == 'RedHat' and epel_repo.stat.exists != true
      yum: name=epel-release
           enablerepo=epel-release-source
           state=present
    
    - name: enable epel repository
      when: ansible_os_family == 'RedHat'
      ini_file: dest=/etc/yum.repos.d/epel.repo
                section=epel
                option=enabled
                value=1

    - name: install ZStack required libraries for RedHat OSes
      when: ansible_os_family == 'RedHat' 
      yum: pkg={{item}}
      with_items:
        - java-1.7.0-openjdk
        - qemu-kvm
        - bridge-utils
        - wget
        - qemu-img
        - libvirt-python
        - libvirt
        - nfs-utils
        - vconfig
        - libvirt-client
        - python-devel
        - gcc
        - autoconf
        - libselinux-python
        - iptables
        - tar
        - gzip
        - unzip
        - httpd
        - openssh-clients
        - openssh-server
        - sshpass

    - name: install ZStack required libraries for Debian OSes
      when: ansible_os_family == 'Debian'
      apt: pkg={{item}}
      with_items:
        - openjdk-7-jdk
        - qemu-kvm
        - bridge-utils
        - wget
        - qemu-utils
        - python-libvirt
        - libvirt-bin
        - vlan
        - nfs-common
        - nfs-kernel-server
        - python-dev
        - gcc
        - autoconf
        - iptables
        - tar
        - gzip
        - unzip
        - apache2
        - sshpass

EOF

    if [ -z $DEBUG ]; then
        ansible-playbook $ansible_yaml -i $ansible_inventory -e "gather_facts=No pypi_url=$ZSTACK_PYPI_URL" >>$ZSTACK_INSTALL_LOG 2>&1
    else
        ansible-playbook $ansible_yaml -i $ansible_inventory -e "gather_facts=No pypi_url=$ZSTACK_PYPI_URL" 
    fi

    if [ $? -ne 0 ];then
        /bin/rm -f $ansible_inventory
        /bin/rm -f $ansible_yaml
        /bin/rm -f $epel_repo_file
        fail "install system libraries failed."
    else
        /bin/rm -f $ansible_inventory
        /bin/rm -f $ansible_yaml
        /bin/rm -f $epel_repo_file
        pass
    fi
}

is_install_virtualenv(){
    echo_subtitle "Install Virtualenv"
    if [ ! -z $DEBUG ]; then
        pip install -i $ZSTACK_PYPI_URL virtualenv
    else
        pip install -i $ZSTACK_PYPI_URL virtualenv >>$ZSTACK_INSTALL_LOG 2>&1
    fi
    [ $? -ne 0 ] && fail "install virtualenv failed"
    pass
}

sd_install_dashboard_libs(){
    echo_subtitle "Install Dashboard Dependent Libs"
    source $VIRTUAL_ENV/bin/activate >>$ZSTACK_INSTALL_LOG 2>&1
    if [ $? -ne 0 ];then
        fail "failed to create virtualenv for zstack-dashboard in $VIRTUAL_ENV"
    fi
    if [ ! -z $DEBUG ]; then
        pip install -i $ZSTACK_PYPI_URL Flask pika Flask-Script argparse simplejson 
    else
        pip install Flask pika Flask-Script argparse simplejson >>$ZSTACK_INSTALL_LOG 2>&1
    fi
    [ $? -ne 0 ] && fail "failed to install dashboard dependent libs"
    pass
}

install_system_libs(){
    echo_title "Install System Libs"
    echo ""
    show_spinner is_install_general_libs
    #mysql and rabbitmq will be installed by zstack-ctl later
    show_spinner is_install_virtualenv
}

iz_download_zstack(){
    echo_subtitle "Download ZStack all-in-one package"
    if [ -f $ZSTACK_ALL_IN_ONE ]; then
        cp $ZSTACK_ALL_IN_ONE $zstack_tmp_file >>$ZSTACK_INSTALL_LOG 2>&1
        if [ $? -ne 0 ];then
           /bin/rm -f $zstack_tmp_file
           fail "failed to copy zstack all-in-one package from $ZSTACK_ALL_IN_ONE to $zstack_tmp_file"
        fi
    else
        wget -w 10 -O $zstack_tmp_file $ZSTACK_ALL_IN_ONE >>$ZSTACK_INSTALL_LOG 2>&1
        if [ $? -ne 0 ];then
           /bin/rm -f $zstack_tmp_file
           fail "failed to download zstack all-in-one package from $ZSTACK_ALL_IN_ONE"
        fi
    fi
    pass 
}

iz_unpack_zstack(){
    echo_subtitle "Unpack ZStack all-in-one package"
    mkdir -p $ZSTACK_INSTALL_ROOT
    all_in_one=$ZSTACK_INSTALL_ROOT/zstack_all_in_one.tgz
    mv $zstack_tmp_file $all_in_one
    cd $ZSTACK_INSTALL_ROOT
    tar -zxf $all_in_one >>$ZSTACK_INSTALL_LOG 2>&1
    if [ $? -ne 0 ];then
       fail "failed to unpack ZStack all-in-one package: $all_in_one."
    fi
    pass
}

iz_unzip_tomcat(){
    echo_subtitle "Unpack Tomcat"
    cd $ZSTACK_INSTALL_ROOT
    unzip apache-tomcat*.zip >>$ZSTACK_INSTALL_LOG 2>&1
    if [ $? -ne 0 ];then
       fail "failed to unzip Tomcat package: $ZSTACK_INSTALL_ROOT/apache-tomcat*.zip."
    fi
    apache_temp=`mktemp`
    apache_zip=`ls apache-tomcat*.zip`
    mv $apache_zip $apache_temp
    ln -s apache-tomcat* apache-tomcat
    mv $apache_temp $apache_zip
    chmod a+x apache-tomcat/bin/*
    if [ $? -ne 0 ];then
       fail "chmod failed in: $ZSTACK_INSTALL_ROOT/apache-tomcat/bin/*."
    fi

    pass
}

iz_install_zstack(){
    echo_subtitle "Install ZStack into Tomcat"
    cd $ZSTACK_INSTALL_ROOT
    unzip -d $CATALINA_ZSTACK_PATH zstack.war >>$ZSTACK_INSTALL_LOG 2>&1
    if [ $? -ne 0 ];then
       fail "failed to install zstack.war to $ZSTACK_INSTALL_ROOT/$CATALINA_ZSTACK_PATH."
    fi
    pass
}

iz_install_zstackcli(){
    echo_subtitle "Install ZStack Command Line"
    cd $ZSTACK_INSTALL_ROOT
    bash $ZSTACK_TOOLS_INSTALLER zstack-cli >$ZSTACK_INSTALL_LOG 2>&1

    if [ $? -ne 0 ];then
       fail "failed to install zstackcli in $ZSTACK_INSTALL_ROOT/$ZSTACK_TOOLS_INSTALLER"
    fi
    pass
}

iz_install_zstackctl(){
    echo_subtitle "Install ZStack Control"
    cd $ZSTACK_INSTALL_ROOT
    bash $ZSTACK_TOOLS_INSTALLER zstack-ctl >$ZSTACK_INSTALL_LOG 2>&1

    if [ $? -ne 0 ];then
       fail "failed to install zstackctl in $ZSTACK_INSTALL_ROOT/$ZSTACK_TOOLS_INSTALLER"
    fi
    pass
}

install_zstack(){
    echo_title "Download and Install ZStack"
    echo ""
    show_download iz_download_zstack
    show_spinner iz_unpack_zstack
    show_spinner iz_unzip_tomcat
    show_spinner iz_install_zstack
    show_spinner iz_install_zstackcli
    show_spinner iz_install_zstackctl
}

install_db_msgbus(){
    echo_title "Install Database and Message Bus"
    echo ""
    #generate ssh key for install mysql and rabbitmq by ansible remote host
    ssh_tmp_dir=`mktemp`
    /bin/rm -rf $ssh_tmp_dir
    mkdir -p $ssh_tmp_dir
    show_spinner cs_gen_sshkey $ssh_tmp_dir
    #install mysql db
    show_spinner cs_install_mysql $ssh_tmp_dir
    #deploy initial database
    show_spinner cs_deploy_db
    #install rabbitmq server
    show_spinner cs_install_rabbitmq $ssh_tmp_dir
    cs_clean_ssh_tmp_key $ssh_tmp_dir
    #show_spinner cs_start_rabbitmq
}

config_system(){
    echo_title "Configure System"
    echo ""
    #show_spinner cs_flush_iptables
    show_spinner cs_chown_install_root
    show_spinner cs_config_zstack_properties
    show_spinner cs_config_tomcat
    show_spinner cs_install_zstack_service
    if [ ! -z $NEED_NFS ];then
        show_spinner cs_setup_nfs
    fi
    if [ ! -z $NEED_HTTP ];then
        show_spinner cs_setup_http
    fi
}

cs_config_zstack_properties(){
    echo_subtitle "Config zstack.properties"
    if [ $ZSTACK_PYPI_URL != $DEFAULT_PYPI ];then
        zstack-ctl configure Ansible.var.pypi_url=$ZSTACK_PYPI_URL
    fi
    if [ $? -ne 0 ];then
        fail "failed to add user pypi config to $ZSTACK_PROPERTIES"
    fi
    pass
}

cs_chown_install_root(){
    echo_subtitle "Change Ownership of ZStack Install Root"
    chown -R zstack.zstack $ZSTACK_INSTALL_ROOT >>$ZSTACK_INSTALL_LOG 2>&1
    if [ $? -ne 0 ];then
        fail "failed to chown for $ZSTACK_INSTALL_ROOT with zstack.zstack"
    fi
    pass
}

cs_gen_sshkey(){
    echo_subtitle "Generate Temp SSH Key"
    [ ! -d /root/.ssh ] && mkdir -p /root/.ssh && chmod 700 /root/.ssh
    
    dsa_key_file=$1/id_dsa
    dsa_pub_key_file=$1/id_dsa.pub
    authorized_keys_file=/root/.ssh/authorized_keys
    ssh-keygen -t dsa -N '' -f $dsa_key_file >>$ZSTACK_INSTALL_LOG 2>&1 
    if [ ! -f $authorized_keys_file ]; then
        cat $dsa_pub_key_file > $authorized_keys_file
        chmod 600 $authorized_keys_file
    else
        ssh_pub_key=`cat $dsa_pub_key_file`
        grep $ssh_pub_key $authorized_keys_file >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            cat $dsa_pub_key_file >> $authorized_keys_file
        fi
    fi
    if [ -x /sbin/restorecon ]; then
        /sbin/restorecon /root/.ssh /root/.ssh/authorized_keys
    fi
    pass
}

cs_install_mysql(){
    echo_subtitle "Install Mysql Server"
    dsa_key_file=$1/id_dsa
    if [ -z $MYSQL_ROOT_PASSWORD ]; then
        zstack-ctl install_db --host=$MANAGEMENT_IP --ssh-key=$dsa_key_file >>$ZSTACK_INSTALL_LOG 2>&1
    else
        zstack-ctl install_db --host=$MANAGEMENT_IP --login-password="$MYSQL_ROOT_PASSWORD" --ssh-key=$dsa_key_file >>$ZSTACK_INSTALL_LOG 2>&1
    fi
    if [ $? -ne 0 ];then
        cs_clean_ssh_tmp_key $1
        fail "failed to install mysql server."
    fi
    pass
}

cs_install_rabbitmq(){
    echo_subtitle "Install Rabbitmq Server"
    dsa_key_file=$1/id_dsa
    zstack-ctl install_rabbitmq --host=$MANAGEMENT_IP --ssh-key=$dsa_key_file >>$ZSTACK_INSTALL_LOG 2>&1
    if [ $? -ne 0 ];then
        cs_clean_ssh_tmp_key $1
        fail "failed to install rabbitmq server."
    fi
    pass
}

cs_clean_ssh_tmp_key(){
    #echo_subtitle "Clean up ssh temp key"
    dsa_pub_key_file=$1/id_dsa.pub
    ssh_pub_key=`cat $dsa_pub_key_file`
    authorized_keys_file=/root/.ssh/authorized_keys
    sed -i "\;$ssh_pub_key;d" $authorized_keys_file >>$ZSTACK_INSTALL_LOG 2>&1
    /bin/rm -rf $1
    #pass
}

ia_disable_selinux(){
    echo_subtitle "Disable SELinux"
    which setenforce >>$ZSTACK_INSTALL_LOG 2>&1
    if [ $? -eq 0 ];then
        setenforce 0
        if [ $? -ne 0 ]; then
            setenforce 0 2>&1 |grep -i 'selinux is disabled'
            [ $? -ne 0 ] && fail "failed to disable selinux."
        fi

        if [ -f /etc/sysconfig/selinux ]; then
            sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux >>$ZSTACK_INSTALL_LOG 2>&1
        fi
        [ $? -ne 0 ] && fail "failed to modify selinux config file: /etc/sysconfig/selinux"
    fi
    pass
}

cs_flush_iptables(){
    echo_subtitle "Flush iptables rules"
    iptables -F
    iptables -F -t nat
    [ $? -ne 0 ] && fail "disable iptables failed"
    pass
}

cs_config_tomcat(){
    echo_subtitle "Configure Tomcat Java Option"
    cat >> $ZSTACK_INSTALL_ROOT/apache-tomcat/bin/setenv.sh <<EOF
export CATALINA_OPTS=" -Djava.net.preferIPv4Stack=true -Dcom.sun.management.jmxremote=true"
EOF
    pass
}

cs_install_zstack_service(){
    echo_subtitle "Install ZStack management node"
    /bin/cp -f $ZSTACK_INSTALL_ROOT/$CATALINA_ZSTACK_CLASSES/install/zstack-server /etc/init.d
    chmod a+x /etc/init.d/zstack-server
    tomcat_folder_path=$ZSTACK_INSTALL_ROOT/apache-tomcat
    sed -i "s#^TOMCAT_PATH=.*#TOMCAT_PATH=$tomcat_folder_path#" /etc/init.d/zstack-server
    [ $? -ne 0 ] && fail "failed to install ZStack management node."
    zstack-ctl setenv ZSTACK_HOME=$ZSTACK_HOME >> $ZSTACK_INSTALL_LOG 2>&1 
    [ $? -ne 0 ] && fail "failed to set ZSTACK_HOME path by zstack-ctl"
    pass
}

cs_setup_nfs(){
    echo_subtitle "Configure Local NFS Server (primary storage)"
    mkdir -p $NFS_FODLER
    grep $NFS_FODLER /etc/exports >>$ZSTACK_INSTALL_LOG 2>&1
    if [ $? -ne 0 ]; then 
        echo "$NFS_FODLER *(rw,sync,no_root_squash)" >> /etc/exports
    fi
    if [ $OS = $CENTOS6 ]; then
        chkconfig nfs on >>$ZSTACK_INSTALL_LOG 2>&1
        service nfs restart >>$ZSTACK_INSTALL_LOG 2>&1
    elif [ $OS = $CENTOS7 ]; then
        systemctl enable rpcbind >>$ZSTACK_INSTALL_LOG 2>&1
        systemctl enable nfs-server >>$ZSTACK_INSTALL_LOG 2>&1
        systemctl enable nfs-lock >>$ZSTACK_INSTALL_LOG 2>&1
        systemctl enable nfs-idmap >>$ZSTACK_INSTALL_LOG 2>&1
        systemctl restart rpcbind >>$ZSTACK_INSTALL_LOG 2>&1
        systemctl restart nfs-server >>$ZSTACK_INSTALL_LOG 2>&1
        systemctl restart nfs-lock >>$ZSTACK_INSTALL_LOG 2>&1
        systemctl restart nfs-idmap >>$ZSTACK_INSTALL_LOG 2>&1
    else
        service nfs-kernel-server restart >>$ZSTACK_INSTALL_LOG 2>&1
    fi
    [ $? -ne 0 ] && fail "failed to setup NFS server"
    iptables-save | grep -- "-A INPUT -p tcp -m tcp --dport 111 -j ACCEPT" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        iptables -I INPUT -p tcp -m tcp --dport 111 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
        iptables -I INPUT -p udp -m udp --dport 111 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
        iptables -I INPUT -p tcp -m tcp --dport 2049 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
        iptables -I INPUT -p tcp -m tcp --dport 32803  -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
        iptables -I INPUT -p udp -m udp --dport 32769 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
        iptables -I INPUT -p tcp -m tcp --dport 892 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
        iptables -I INPUT -p udp -m udp --dport 892 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
        iptables -I INPUT -p tcp -m tcp --dport 875 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
        iptables -I INPUT -p udp -m udp --dport 875 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
        iptables -I INPUT -p tcp -m tcp --dport 662 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
        iptables -I INPUT -p udp -m udp --dport 662 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
    fi
    pass
}

cs_setup_http(){
    echo_subtitle "Configure Local HTTP Server (for storing images)"
    mkdir $HTTP_FOLDER
    chmod 777 $HTTP_FOLDER
    if [ $OS = $CENTOS7 ]; then
        chkconfig httpd on >>$ZSTACK_INSTALL_LOG 2>&1
        cat > /etc/httpd/conf.d/zstack-http.conf <<EOF
Alias /image/ "$HTTP_FOLDER/"
<Directory $HTTP_FOLDER/>
    AllowOverride FileInfo AuthConfig Limit
    Options MultiViews Indexes SymLinksIfOwnerMatch IncludesNoExec
    Allow from all
    Require all granted
</Directory>
EOF
        service httpd restart >>$ZSTACK_INSTALL_LOG 2>&1
    elif [ $OS = $CENTOS6 ]; then
        chkconfig httpd on >>$ZSTACK_INSTALL_LOG 2>&1
        cat > /etc/httpd/conf.d/zstack-http.conf <<EOF
Alias /image/ "$HTTP_FOLDER/"
<Directory $HTTP_FOLDER/>
    AllowOverride FileInfo AuthConfig Limit
    Options MultiViews Indexes SymLinksIfOwnerMatch IncludesNoExec
    Allow from all
</Directory>
EOF
        service httpd restart >>$ZSTACK_INSTALL_LOG 2>&1
    else
        cat > /etc/apache2/conf-enabled/zstack-http.conf <<EOF
Alias /image/ "$HTTP_FOLDER/"
<Directory $HTTP_FOLDER/>
    AllowOverride FileInfo AuthConfig Limit
    Options MultiViews Indexes SymLinksIfOwnerMatch IncludesNoExec
    Allow from all
    AllowOverride None
    Options None
    Require all granted
</Directory>
EOF
        /etc/init.d/apache2 restart >>$ZSTACK_INSTALL_LOG 2>&1
    fi
    [ $? -ne 0 ] && fail "failed to setup HTTP Server"
    iptables-save | grep -- "-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT" > /dev/null 2>&1 || iptables -I INPUT -p tcp -m tcp --dport 80 -j ACCEPT >>$ZSTACK_INSTALL_LOG 2>&1
    pass
}

check_zstack_server(){
    curl -H "Content-Type: application/json" -d '{"org.zstack.header.apimediator.APIIsReadyToGoMsg": {}}' http://localhost:8080/zstack/api >>$ZSTACK_INSTALL_LOG 2>&1
    return $?
}

start_zstack(){
    echo_title "Start ZStack Server"
    echo ""
    show_spinner sz_start_zstack
}

cs_deploy_db(){
    echo_subtitle "Deploy ZStack Database"
    if [ -z $NEED_DROP_DB ]; then
        if [ -z $NEED_KEEP_DB ]; then
            zstack-ctl deploydb --root-password="$MYSQL_ROOT_PASSWORD" --zstack-password="$MYSQL_USER_PASSWORD" --host=$MANAGEMENT_IP >>$ZSTACK_INSTALL_LOG 2>&1
        else
            zstack-ctl deploydb --root-password="$MYSQL_ROOT_PASSWORD" --zstack-password="$MYSQL_USER_PASSWORD" --host=$MANAGEMENT_IP --keep-db >>$ZSTACK_INSTALL_LOG 2>&1
        fi
    else
        zstack-ctl deploydb --root-password="$MYSQL_ROOT_PASSWORD" --zstack-password="$MYSQL_USER_PASSWORD" --host=$MANAGEMENT_IP --drop >>$ZSTACK_INSTALL_LOG 2>&1
    fi
    if [ $? -ne 0 ];then
        fail "failed to deploy ZStack database. You might want to add -D to drop previous ZStack database or -k to keep previous zstack database"
    fi
    pass
}

sz_start_zstack(){
    echo_subtitle "Start ZStack management node"
    /etc/init.d/zstack-server restart >>$ZSTACK_INSTALL_LOG 2>&1
    [ $? -ne 0 ] && fail "failed to start zstack"
    i=1
    while [ $i -lt 120 ]; do
        i=`expr $i + 1`
        check_zstack_server && pass && return
        sleep 1
    done
    fail "zstack server failed to start in $i seconds"
}

start_dashboard(){
    echo_title "Start ZStack Web UI"
    echo ""
    show_spinner sd_install_dashboard
    #show_spinner sd_install_dashboard_libs
    show_spinner sd_start_dashboard
}

sd_install_dashboard(){
    echo_subtitle "Install ZStack Web UI"
    cd $ZSTACK_INSTALL_ROOT
    bash $ZSTACK_TOOLS_INSTALLER zstack-dashboard >$ZSTACK_INSTALL_LOG 2>&1

    if [ $? -ne 0 ];then
        fail "failed to install zstack-dashboard in $ZSTACK_INSTALL_ROOT"
    fi
    pass
}

sd_start_dashboard(){
    echo_subtitle "Start ZStack Dashboard"
    chmod a+x /etc/init.d/zstack-dashboard
    /etc/init.d/zstack-dashboard restart >>$ZSTACK_INSTALL_LOG 2>&1
    [ $? -ne 0 ] && fail "failed to zstack dashboard start"
    pass
}


help (){
    echo "
ZStack All-In-One Installer.

The script can install ZStack related software.

Warning: This script will disable SELinux on RedHat series OS (CentOS/Redhat RHEL)

Usage: $0 [options]

Options:
  -a    equal to -nHD

  -d    print detailed installation log to screen
        By default the installation log will be saved to $ZSTACK_INSTALL_LOG

  -D    drop previous ZStack database if it exists. An error will be raised
        if a previous ZStack DB is detected and no -D or -k option is provided.

  -f LOCAL_PATH_OR_URL_OF_ZSTACK_ALL_IN_ONE_PACKAGE
        file path to ZStack all-in-one package. By default the script
        will download the all-in-one package from ZStack's official website.
        You can provide a local file path or a URL with option if you want to
        use a separate all-in-one package.

  -h    show help message

  -H    setup an Apache HTTP server on this machine

  -i    only install ZStack management node and dependent packages

  -I MANAGEMENT_NODE_NETWORK_INTERFACE  
        the network interface (e.g. eth0) for management network. The IP address
        of this interface will be configured as IP of MySQL server and RabbitMQ
        if they are installed on this machine, remote ZStack managemet nodes
        will use this IP to access MySQL and RabbitMQ. By default, the installer
        script will grab the IP of interface providing default routing from
        routing table.

  -k    keep previous zstack DB if it exists.

  -l    only just install ZStack dependent libraries

  -n    setup a NFS server on this machine

  -p MYSQL_PASSWORD
        password for MySQL user 'zstack' that is the user ZStack management nodes use to access database. By default, an empty password is applied.

  -P MYSQL_PASSWORD
        password for MySQL root user. By default, an empty password is applied.

  -r ZSTACK_INSTALLATION_PATH
        the path where to install ZStack management node.  The default path is $ZSTACK_INSTALL_ROOT

  -R PYTHON_PACKAGE_INDEX
        the repository to install python libs. The default is https://pypi.python.org/simple/
------------
Example:

Following command will install the ZStack management node to /usr/local/zstack and all dependent packages:

. Apache Tomcat 7 with zstack.war deployed
. ZStack web UI
. ZStack command line tool (zstack-cli)
. ZStack control tool (zstack-ctl)
. MySQL
. RabbitMQ server
. NFS server
. Apache HTTP server

And an empty password is set to the root user of MySQL.

# $0 -a

--

In addition to all above results, below command sets the password of MySQL root user to DB_ROOT_PASSWORD
and password of MySQL user 'zstack' to DB_ZSTACK_PASSWORD, and uses the IP of eth1 for
deploying MySQL and RabbitMQ.

# $0 -r /home/zstack -a -P DB_ROOT_PASSWORD -p DB_ZSTACK_PASSWORD -I eth1

--

Following command only installs ZStack management node and dependent software.

# $0 -i

------------
"
    exit 1
}

OPTIND=1
while getopts "f:I:p:P:r:R:adDHihkln" Option
do
    case $Option in
        a ) NEED_NFS='y' && NEED_HTTP='y' && NEED_DROP_DB='y';;
        n ) NEED_NFS='y';;
        H ) NEED_HTTP='y';;
        d ) DEBUG='y';;
        D ) NEED_DROP_DB='y';;
        f ) ZSTACK_ALL_IN_ONE=$OPTARG;;
        i ) ONLY_INSTALL_ZSTACK='y';;
        I ) MANAGEMENT_INTERFACE=$OPTARG;;
        k ) NEED_KEEP_DB='y';;
        l ) ONLY_INSTALL_LIBS='y';;
        P ) MYSQL_ROOT_PASSWORD=$OPTARG;;
        p ) MYSQL_USER_PASSWORD=$OPTARG;;
        r ) ZSTACK_INSTALL_ROOT=$OPTARG;;
        R ) export ZSTACK_PYPI_URL=$OPTARG;;
        * ) help;;
    esac
done
OPTIND=1

echo "ZStack install root: $ZSTACK_INSTALL_ROOT" >>$ZSTACK_INSTALL_LOG
NFS_FODLER=$ZSTACK_INSTALL_ROOT/nfs_root
echo "NFS Folder: $NFS_FODLER" >> $ZSTACK_INSTALL_LOG
HTTP_FOLDER=$ZSTACK_INSTALL_ROOT/http_root
echo "HTTP Folder: $HTTP_FODLER" >> $ZSTACK_INSTALL_LOG

if [ -z $MANAGEMENT_INTERFACE ]; then
    echo "Cannot not identify default network interface. Please add your network interface by '-I NETWORK_INTERFACE'."
    exit 1
fi

MANAGEMENT_IP=`ip -4 addr | grep $MANAGEMENT_INTERFACE | grep inet | awk '{print $2}' | cut -f1  -d'/'`
echo "Management ip address: $MANAGEMENT_IP" >> $ZSTACK_INSTALL_LOG
echo "Management node network interface: $MANAGEMENT_INTERFACE" >> $ZSTACK_INSTALL_LOG

#Set ZSTACK_HOME for zstack-ctl.
export ZSTACK_HOME=$ZSTACK_INSTALL_ROOT/$CATALINA_ZSTACK_PATH

echo ""
echo_star_line
echo ' _________ _____  _    ____ _  __'
echo '|__  / ___|_   _|/ \  / ___| |/ /'
echo "  / /\___ \ | | / _ \| |   | ' / "
echo ' / /_ ___) || |/ ___ \ |___| . \ '
echo '/____|____/ |_/_/   \_\____|_|\_\'
echo '                                 '
sleep 0.1
echo '    _    _     _       ___ _   _    ___  _   _ _____ '
echo '   / \  | |   | |     |_ _| \ | |  / _ \| \ | | ____|'
echo '  / _ \ | |   | |      | ||  \| | | | | |  \| |  _|  '
echo ' / ___ \| |___| |___   | || |\  | | |_| | |\  | |___ '
echo '/_/   \_\_____|_____| |___|_| \_|  \___/|_| \_|_____|'
echo '                                                     '
sleep 0.3
echo ' ___ _   _ ____ _____  _    _     _        _  _____ ___ ___  _   _ '
echo '|_ _| \ | / ___|_   _|/ \  | |   | |      / \|_   _|_ _/ _ \| \ | |'
echo ' | ||  \| \___ \ | | / _ \ | |   | |     / _ \ | |  | | | | |  \| |'
echo ' | || |\  |___) || |/ ___ \| |___| |___ / ___ \| |  | | |_| | |\  |'
echo '|___|_| \_|____/ |_/_/   \_\_____|_____/_/   \_\_| |___\___/|_| \_|'
echo '                                                                   '
echo_star_line
sleep 0.3
echo ""

#Do preinstallation checking for CentOS and Ubuntu
check_system

#Install Ansible 
install_ansible

#Install ZStack required system libs through ansible
install_system_libs

if [ ! -z $ONLY_INSTALL_LIBS ];then
    echo ""
    echo_star_line
    echo "Finish installing ZStack dependent software."
    echo "ZStack management node and Tomcat are not installed."
    echo "P.S.: selinux is disabled!"
    echo_star_line
    exit 0
fi

#Download and install ZStack All-In-One Package
install_zstack

#Post Configuration, including apache, zstack-server, NFS Server, HTTP Server
config_system

if [ -f $ZSTACK_VERSION ]; then
    VERSION=`cat $ZSTACK_VERSION`' '
else
    VERSION=''
fi

if [ ! -z $ONLY_INSTALL_ZSTACK ]; then
    echo ""
    echo_star_line
    echo "ZStack ${VERSION}management node is installed to $ZSTACK_INSTALL_ROOT."
    echo "Mysql and RabbitMQ are not installed. You can use zstack-ctl to install them and start ZStack service later. "
    echo_star_line
    exit 0
fi

#Install Mysql and Rabbitmq
install_db_msgbus

#Start ZStack
start_zstack

#Start ZStack-Dashboard
start_dashboard

#Print all installation message

echo ""
echo_star_line
echo "ZStack All In One ${VERSION}Installation Completed:"
echo " - ZStack management node is successfully installed in $ZSTACK_INSTALL_ROOT"
echo " - the management node is running now"
echo "      You can use /etc/init.d/zstack-server (stop|start) to stop/start it"
echo " - ZStack web UI is running, vist http://$MANAGEMENT_IP:5000 in your browser"
echo "      You can use /etc/init.d/zstack-dashboard (stop|start) to stop/start the service"
echo " - ZStack command line tool is installed: zstack-cli"
echo " - ZStack control tool is installed: zstack-ctl"
[ ! -z $NEED_NFS ] && echo " - $MANAGEMENT_IP:$NFS_FODLER is configured for primary storage"
[ ! -z $NEED_HTTP ] && echo " - http://$MANAGEMENT_IP/image is ready for storing images, copy your images to the folder $HTTP_FOLDER"
echo ' - You can use `zstack-ctl install_management_node --remote=remote_ip` to install more management nodes'
echo_star_line
