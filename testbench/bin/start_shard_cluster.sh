#!/bin/bash
set -e;

docker-ip() {
  sudo docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$@"
}

docker-port() {
  sudo docker port $@ 27017|cut -d ":" -f2
}

create_cfg_srv() {
  ID=$(sudo docker ps | grep cfg$@ |  awk '{print $1}')
  if [[ -z "$ID" ]]; then
    echo "Creating container cfg${@}."
    sudo docker run \
    -P --name cfg${@} \
    -d mongo:2.6 \
    --noprealloc --smallfiles \
    --configsvr \
    --dbpath /data/db \
    --port 27017
    attempt=0
    while [ $attempt -le 59 ]; do
      attempt=$(( $attempt + 1 ))
      echo "Waiting for server to be up (attempt: $attempt)..."
      result=$(sudo docker logs cfg${@})
      if grep -q 'waiting for connections on port 27017' <<< $result ; then
        echo "Mongodb is up!"
        break
      fi
      sleep 2
    done
  else
    echo "Container cfg${@} exists."
  fi
}

create_mongos_srv() {
  ID=$(sudo docker ps | grep mongos${@} |  awk '{print $1}')
  if [[ -z "$ID" ]]; then
    echo "Creating container mongos${@}."
    IMAGE=$(sudo docker images | grep "attachmentgenie/mongos " |  awk '{print $3}')
    if [[ -z $IMAGE ]]; then
      echo "Creating image attachmentgenie/mongos."
      sudo docker build -t attachmentgenie/mongos virt/docker/mongos
    fi
    sudo docker run \
    -P --name mongos1 \
    -d attachmentgenie/mongos \
    --port 27017 \
    --configdb $(docker-ip cfg1):27017,$(docker-ip cfg2):27017,$(docker-ip cfg3):27017
    attempt=0
    while [ $attempt -le 59 ]; do
      attempt=$(( $attempt + 1 ))
      echo "Waiting for server to be up (attempt: $attempt)..."
      result=$(sudo docker logs mongos${@})
      if grep -q 'waiting for connections on port 27017' <<< $result ; then
        echo "Mongodb is up!"
        break
      fi
      sleep 2
    done
  else
    echo "Container mongos${@} exists."
  fi
}

create_rs_srv() {
  ID=$(sudo docker ps | grep rs${1}_srv${2} |  awk '{print $1}')
  if [[ -z "$ID" ]]; then
    echo "Creating container rs${1}_srv${2}."
    sudo docker run \
    -P --name rs${1}_srv${2} \
    -d mongo:2.6 \
    --replSet rs${1} \
    --noprealloc --smallfiles
    attempt=0
    while [ $attempt -le 59 ]; do
      attempt=$(( $attempt + 1 ))
      echo "Waiting for server to be up (attempt: $attempt)..."
      result=$(sudo docker logs rs${1}_srv${2})
      if grep -q 'waiting for connections on port 27017' <<< $result ; then
        echo "Mongodb is up!"
        break
      fi
      sleep 2
    done
  else
    echo "Container rs${1}_srv${2} exists."
  fi
}

DEFAULT="2"
read -e -i "$DEFAULT" -p "How many shards do you want to create : " INPUT
SHARDS="${INPUT:-$DEFAULT}"

echo "Creating Mongodb cluster with $SHARDS shards."

if (( EUID != 0 )); then
  echo "You must have sudo permissions to do this."
  sudo -v
fi

for cfg in $(seq 1 3)
do
  create_cfg_srv ${cfg}
done
create_mongos_srv 1

for i in $(seq 1 $SHARDS)
do
  echo "Creating Shard ${i} of $SHARDS"
  for rs in $(seq 1 3)
  do
    create_rs_srv ${i} ${rs}
  done

  ID=$(mongo --port $(docker-port rs${i}_srv1) --eval "printjson(rs.status().ok)" | tail -1)
  if [ "$ID" -eq "1" ]; then
    echo "Replication set rs${i} is active."
  else
    echo "Creating replication set rs${i}"
    rm -f rs${i}.js
cat <<EOF > rs${i}.js
  config = {_id: 'rs${i}', members: [
  {_id: 0, host: '$(docker-ip rs${i}_srv1)'},
  {_id: 1, host: '$(docker-ip rs${i}_srv2)'},
  {_id: 2, host: '$(docker-ip rs${i}_srv3)'}]
}
rs.initiate(config);
EOF
    mongo --quiet --port $(docker-port rs${i}_srv1) < rs${i}.js >/dev/null
    attempt=0
    while [ $attempt -le 59 ]; do
      attempt=$(( $attempt + 1 ))
      echo "Waiting for Replication set to be up (attempt: $attempt)..."
      result=$(mongo --port $(docker-port rs${i}_srv1) --eval "printjson(rs.status().ok)" | tail -1)
      if [ "$result" -eq "1" ]; then
        echo "Replication set is up!"
        break
      fi
      sleep 2
    done

    attempt=0
    while [ $attempt -le 59 ]; do
      attempt=$(( $attempt + 1 ))
      echo "Waiting for primary to be elected (attempt: $attempt)..."
      result=$(mongo --port $(docker-port rs${i}_srv1) --eval "printjson(rs.status().myState)" | tail -1)
      if [ "$result" -eq "1" ]; then
        echo "Election has taken place!"
        break
      fi
      sleep 2
    done
  fi

  ID=$(mongo --port $(docker-port mongos1) --eval "printjson(sh.status())")
  if grep -q "rs${i}" <<< $ID ; then
    echo "Shard rs${i} is present."
  else
    echo "Adding rs${i} as shard to cluster."
    rm -f sh.js
cat <<EOF > rs${i}_sh.js
sh.addShard("rs${i}/$(docker-ip rs${i}_srv1):27017")
EOF
    mongo --quiet --port $(docker-port mongos1) < rs${i}_sh.js >/dev/null
  fi
done

echo "MongoDB Cluster is now ready to use"
mongo --quiet --port $(docker-port mongos1) --eval "sh.status()"
echo "Connect to cluster by:"
echo "$ mongo --port $(docker-port mongos1)"
