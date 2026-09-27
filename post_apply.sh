#!/usr/bin/sh
BUILDLOG=/TopStordata/reactbuild.log

docker ps --format '{{.Names}}' | grep -qx httpd
if [ $? -ne 0 ];
then
	echo `date` httpd not running on this node, skipping UI build >> $BUILDLOG
	exit 0
fi

docker images -q quickstor-ui:latest | grep -q .
if [ $? -ne 0 ];
then
	echo `date` ERROR: quickstor-ui:latest image not loaded, run pre_apply.sh first >> $BUILDLOG
	exit 1
fi

echo `date` Building React UI from newly pulled sources... >> $BUILDLOG
mkdir -p /topstorweb/build_react
rm -rf /topstorweb/build_react/*
docker run --rm \
	-v /topstorweb/src:/app/src \
	-v /topstorweb/public:/app/public \
	-v /topstorweb/index.html:/app/index.html \
	-v /topstorweb/vite.config.js:/app/vite.config.js \
	-v /topstorweb/tailwind.config.js:/app/tailwind.config.js \
	-v /topstorweb/postcss.config.js:/app/postcss.config.js \
	-v /topstorweb/build_react:/app/build_react \
	quickstor-ui:latest npm run build >> $BUILDLOG 2>&1
buildexit=$?
echo `date` EXIT=$buildexit >> $BUILDLOG

if [ $buildexit -ne 0 ] || [ -z "$(ls -A /topstorweb/build_react/assets 2>/dev/null)" ];
then
	echo `date` ERROR: React build failed or produced no assets, see $BUILDLOG >&2
	exit 1
fi

echo `date` UI Post-Application Completed! >> $BUILDLOG
