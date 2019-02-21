kubectl delete configmap agrius-logstash-scripts
kubectl create configmap agrius-logstash-scripts --from-file prep_tweet.rb
kubectl delete -f .
kubectl apply -f .
