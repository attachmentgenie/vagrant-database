#!/bin/bash
set -e;

docker-ip() {
  sudo docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$@"
}

docker-port() {
  sudo docker port $@ 27017|cut -d ":" -f2
}

create_rs_srv() {
  ID=$(sudo docker ps | grep ${1}_srv${2} |  awk '{print $1}')
  if [[ -z "$ID" ]]; then
    echo "Creating container ${1}_srv${2}."
    sudo docker run \
    -P --name ${1}_srv${2} \
    -d mongo:${3} \
    --replSet ${1} \
    --noprealloc --smallfiles
    attempt=0
    while [ $attempt -le 59 ]; do
      attempt=$(( $attempt + 1 ))
      echo "Waiting for server to be up (attempt: $attempt)..."
      result=$(sudo docker logs ${1}_srv${2})
      if grep -q 'waiting for connections on port 27017' <<< $result ; then
        echo "Mongodb is up!"
        break
      fi
      sleep 2
    done
  else
    echo "Container ${1}_srv${2} exists."
  fi
}

echo "Creating Mongodb Replication Set."

if (( EUID != 0 )); then
  echo "You must have sudo permissions to do this."
  sudo -v
fi

DEFAULT="rs1"
read -e -i "$DEFAULT" -p "MongoDB Replication Set name : " INPUT
RSNAME="${INPUT:-$DEFAULT}"

DEFAULT="latest"
read -e -i "$DEFAULT" -p "MongoDB Version : " INPUT
VERSION="${INPUT:-$DEFAULT}"


echo "Creating MongoDB Replication Set named ${RSNAME}."

for ID in $(seq 1 3)
do
  create_rs_srv ${RSNAME} ${ID} ${VERSION}
done

ID=$(mongo --port $(docker-port ${RSNAME}_srv1) --eval "printjson(rs.status().ok)" | tail -1)
if [ "$ID" -eq "1" ]; then
  echo "Replication set ${RSNAME} is active."
else
  echo "Creating replication set ${RSNAME}"
  rm -f ${RSNAME}.js
cat <<EOF > ${RSNAME}.js
  config = {_id: '${RSNAME}', members: [
  {_id: 0, host: '$(docker-ip ${RSNAME}_srv1)'},
  {_id: 1, host: '$(docker-ip ${RSNAME}_srv2)'},
  {_id: 2, host: '$(docker-ip ${RSNAME}_srv3)'}]
}
rs.initiate(config);
EOF
  mongo --quiet --port $(docker-port ${RSNAME}_srv1) < ${RSNAME}.js >/dev/null
  attempt=0
  while [ $attempt -le 59 ]; do
    attempt=$(( $attempt + 1 ))
    echo "Waiting for Replication set to be up (attempt: $attempt)..."
    result=$(mongo --port $(docker-port ${RSNAME}_srv1) --eval "printjson(rs.status().ok)" | tail -1)
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
    result=$(mongo --port $(docker-port ${RSNAME}_srv1) --eval "printjson(rs.status().myState)" | tail -1)
    if [ "$result" -eq "1" ]; then
      echo "Election has taken place!"
      break
    fi
    sleep 2
  done
fi

echo "MongoDB Replication Set is now ready to use"
mongo --quiet --port $(docker-port ${RSNAME}_srv1) --eval "printjson(rs.status())"
echo "Connect to MongoDB Replication Set by:"
echo "$ mongo --port $(docker-port ${RSNAME}_srv1)"
