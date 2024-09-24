#!/bin/bash

# Loop through job IDs from 1280 to 1299
for job_id in {15620..15639}
do
    echo "Cancelling job $job_id"
    scancel $job_id
done

echo "All specified jobs have been cancelled."
