FROM docker.elastic.co/logstash/logstash:6.5.4

# install plugins
RUN /usr/share/logstash/bin/logstash-plugin install logstash-input-google_pubsub
RUN /usr/share/logstash/bin/logstash-plugin install logstash-output-google_cloud_storage
