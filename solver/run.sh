#!/bin/bash -eu

shards build -Dlocal --release
for (( i = 1; i <= 40; i++ )); do
	seed=$(printf "%04d" $i)
	echo "seed:$seed"
	bin/solver $i > ../output/$seed.txt 2> log.txt
	tail -n 1 log.txt 
done
