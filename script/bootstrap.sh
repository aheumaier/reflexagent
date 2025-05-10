#!/bin/bash

# reset the database
rails runner script/clear_metrics_and_events.rb

# load the demo events
rails runner bin/demo_events.rb


# wait untile the redis metric_calculation is empty 
while redis-cli llen metric_calculation > 10; do
  sleep 10
done

sleep 60

# run the MetricAggregations
rails runner "MetricAggregationJob.new.perform('daily')"


