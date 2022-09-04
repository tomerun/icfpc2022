#!/bin/bash -exu

IDX=${AWS_BATCH_JOB_ARRAY_INDEX:-0}
SEED=$(expr $START_SEED + $IDX)
ISL_FILE=$(printf "%04d" $SEED).txt

aws s3 cp s3://marathon-tester/ICFPC2022/problem.zip .
unzip problem.zip
shards build --release -Dlocal
PROBLEM=./problem bin/solver ${SEED} > $ISL_FILE 2> log.txt

aws s3 cp $ISL_FILE s3://marathon-tester/$RESULT_PATH/$ISL_FILE
aws s3 cp log.txt s3://marathon-tester/$RESULT_PATH/$SEED.log
