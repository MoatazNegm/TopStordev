#!/bin/bash
cd /topstorweb
docker build -t quickstor-ui:latest .
rm -rf /topstorweb/build_react/*
docker run --rm -v /topstorweb/build_react:/app/build_react quickstor-ui:latest npm run build
echo EXIT=$?

