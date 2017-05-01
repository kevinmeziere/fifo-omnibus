#!/bin/bash

# This installer is only to be used with this version
fifo_version='0.9.0'
branch='rel'

# Default settings
nic_tag='admin'
fifo_gw=$(route get default | awk '/gateway/{print $2}')

# The ip of the fifo zone must be set here
fifo_ip='10.0.100.50'

# Sets the same dns as the global zone 
# fifo_dns='"8.8.8.8', "8.8.4.4"'
fifo_dns=$(cat /etc/resolv.conf | awk 'BEGIN{ORS=", "}/^nameserver/{print "\""$2"\""}')

get_dataset()
{
imgadm get ${dataset} > /dev/null
if [ ! $? -eq 0 ]; then
  echo "Fetching latest dataset..."
  imgadm sources -a https://datasets.project-fifo.net
  dataset=$(imgadm avail -o name,version,uuid | awk '/^fifo-aio.*${fifo_version}/{printf $3}')
  imgadm import ${dataset}
fi
}

create_fifo_AIO_manifest ()
{
echo "Generating FiFo zone manifest..."
cat > /var/tmp/fifo_aio.json << EOF
{
 "autoboot": true,
 "brand": "joyent",
 "image_uuid": "${dataset}",
 "delegate_dataset": true,
 "indestructible_delegated": true,
 "max_physical_memory": 3072,
 "cpu_cap": 100,
 "alias": "fifo",
 "quota": "40",
 "resolvers": [${fifo_dns}],
 "nics": [
  {
   "interface": "net0",
   "nic_tag": "${nic_tag}",
   "ip": "${fifo_ip}",
   "gateway": "${fifo_gw}",
   "netmask": "255.255.255.0"
  }
 ]
}
EOF
}

create_leofs_manager_manifest() {
echo "Generating LeoFS Manager zone manifest..."
cat > /var/tmp/leofs_manager.json << EOF
{
 "autoboot": true,
 "brand": "joyent",
 "image_uuid": "e1faace4-e19b-11e5-928b-83849e2fd94a",
 "delegate_dataset": true,
 "max_physical_memory": 512,
 "cpu_cap": 100,
 "alias": "2.leofs",
 "quota": "20",
 "resolvers": [
  "10.0.100.1"
 ],
 "nics": [
  {
   "interface": "net0",
   "nic_tag": "admin",
   "ip": "10.0.100.52",
   "gateway": "10.0.100.1",
   "netmask": "255.255.255.0"
  }
 ]
}
EOF
}


start_fifo()
{
echo "Configuring fifo..."
zlogin ${zone_uuid} 'fifo-config' 

echo "Starting services..."
zone_services=(epmd snarl howl sniffle)
for service in ${zone_services[@]}; do
  zlogin ${zone_uuid} svcs ${service} | grep online > /dev/null
  if [ ! ${?} -eq 0 ]; then
    zlogin ${zone_uuid} svcadm enable ${service}
    sleep 2
  fi
done

zone_ports=(4200 4210)
for port in ${zone_ports[@]}; do
  until zlogin ${zone_uuid} nc -w 2 -v ${fifo_ip} ${port}; do
    sleep 5
  done
done

zlogin ${zone_uuid} 'snarl-admin init default ducker.cloud Users admin admin'
zlogin ${zone_uuid} 'sniffle-admin config set storage.s3.host no_s3'
}

install_zdoor() 
{
echo "Installing zdoor..."
curl -s -o /opt/fifo_zlogin-latest.gz http://release.project-fifo.net/gz/${branch}/fifo_zlogin-latest.gz 
gunzip /opt/fifo_zlogin-latest.gz 
sh /opt/fifo_zlogin-latest

}

install_chunter()
{
echo "Installing chunter..."
curl -s -o /opt/chunter-latest.gz http://release.project-fifo.net/gz/${branch}/chunter-latest.gz
gunzip /opt/chunter-latest.gz
sh /opt/chunter-latest
}

printf "//////////////////////\n"
printf "FiFo Omnibus Installer\n\n"
printf "!!! This is not an official Project FiFo installer\n"
printf "!!! For support contact dev@null.de\n"
printf "!!! This installer is built and tested exclusively for version %s\n\n" ${fifo_version}

if [ $(uname) = 'SunOS' ]; then
  case ${1} in
    "all")
          echo "> Bootstraping all"
          get_dataset
          create_fifo_AIO_manifest 
          if [ $(vmadm list alias=fifo -o uuid -H | wc -l) -eq 0 ]; then
            vmadm create -f /var/tmp/fifo_aio.json
          else
            echo "A FiFo zone is already running"
            exit 1
          fi
          zone_uuid=$(vmadm list alias=fifo -o uuid -H)
          start_fifo
          install_zdoor
          install_chunter
          ;;
    "zone")
          echo "> Bootstraping FiFo Zone only"
          get_dataset
          create_fifo_AIO_manifest 
          if [ $(vmadm list alias=fifo -o uuid -H | wc -l) -eq 0 ]; then
            vmadm create -f /var/tmp/fifo_aio.json
          else
            echo "A FiFo zone is already running"
            exit 1
          fi
          zone_uuid=$(vmadm list alias=fifo -o uuid -H)
          start_fifo
          ;;
    "chunter")
          install_zdoor
          install_chunter
          ;;
    "leofs")
          echo "> Installing LeoFS"
          ;;
    *) 
      printf "Usage: you should really know what up\n"
      ;;
  esac

  exit 0
else
  printf "At the moment Project FiFo only works on SmartOS, OmniOS, and Solaris"
  exit 1
fi

