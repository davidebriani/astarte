docker run --rm -it --name rabbitmq -d -p 5672:5672 -p 15672:15672 rabbitmq:management
docker run --rm -it --name scylladb -d -p 9042:9042 scylladb/scylla
sleep 3
docker exec rabbitmq rabbitmqadmin declare exchange name=astarte_events type=direct
