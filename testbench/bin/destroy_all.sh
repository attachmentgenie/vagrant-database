#!/bin/bash
set -e;

if (( EUID != 0 )); then
  echo "You must have sudo permissions to do this."
  sudo -v
fi

docker stop $(docker ps -a -q)
docker rm $(docker ps -a -q)
docker rmi $(docker images -q)