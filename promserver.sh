#!/bin/sh
cd /TopStor/
leaderip=`echo $@ | awk '{print $1}'`
echo $@  > /root/promserver
declare -a actives=(`/TopStor/etcdget.py $leaderip Active --prefix | awk '{print $2}' | awk -F"'" '{print $2}'`)
declare -a ports=(`echo -e ":9100\n:9101\n:19916"`)
rm -rf /prom/prom.yml
cp /TopStor/prom.yml  /prom/promyaml
counter=1
for port in "${ports[@]}"; do
	portstr=''
	for line in "${actives[@]}"; do
  	# Process each line in the loop
		portstr=${portstr}${line}${port}','
	done
	echo portstr="$portstr"
  	sed -i "s/PORTSTR${counter}/$portstr/g" /prom/promyaml
	counter=$((counter+1))
done
cat /prom/promyaml >> /prom/prom.yml
rm -rf /prom/promyaml
docker rm -f promserver
docker rm -f promgraf
	docker run --rm -d -p $leaderip:9090:9090 -v /prom/prom.yml:/etc/prometheus/prometheus.yml -v /prom/:/prometheus -v /etc/passwd:/etc/passwd -v /etc/group:/etc/group --name promserver prom/prometheus
 	rm -rf /promgraf/hosts
 	cp /TopStor/promgrafhosts /promgraf/hosts
 	sed -i "s/MYCLUSTER/$leaderip/g" /promgraf/hosts 
 	docker run --rm -d -p $leaderip:4000:3000 -v /promgraf/grafana.ini:/etc/grafana/grafana.ini -v /promgraf:/var/lib/grafana -v /promgraf/hosts:/etc/hosts --name promgraf grafana/grafana
	useradd -s /sbin/nologin --uid 472 -g root grafana
	chown grafana /promgraf/grafana.db
	phash=`/TopStor/etcdget.py $leaderip usershash/admin`
	plhash=`/TopStor/decthis.sh admin $phash | awk -F'_result' '{print $2}'`
	echo plhash=$plhash > /root/plhashtmp
	docker restart promgraf
	docker exec -it promgraf grafana-cli admin reset-admin-password $plhash 
