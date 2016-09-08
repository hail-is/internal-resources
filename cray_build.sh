#!/bin/bash

set -ex

HAIL_INST=/mnt/lustre/tpoterba/hail-inst
echo "HAIL_INST=$HAIL_INST"

SPARK_VERSION=1.5.2
echo "spark.version=$SPARK_VERSION"

git fetch
git checkout origin/master

./gradlew --daemon -Dspark.version=$SPARK_VERSION clean shadowTestJar shadowJar

# test against cluster
hdfs dfs -mkdir -p src/test
hdfs dfs -rm -r -skipTrash src/test/resources
hdfs dfs -put src/test/resources src/test

SPARK_CLASSPATH=./build/libs/hail-all-spark-test.jar \
	       spark-submit \
	       --total-executor-cores 8 \
	       --class org.testng.TestNG \
	       ./build/libs/hail-all-spark-test.jar \
	       ./testng.xml

# create if necessary
mkdir -p $HAIL_INST/etc
mkdir -p $HAIL_INST/lib
touch $HAIL_INST/etc/jar.sh

HASH=`git rev-parse --verify --short HEAD`
echo "HASH=$HASH"

JAR=$HAIL_INST/lib/hail-all-spark$SPARK_VERSION-$HASH.jar
echo "JAR=$JAR"

cp build/libs/hail-all-spark.jar $JAR

TMP_JAR_SH=`mktemp`

chgrp hail $TMP_JAR_SH
chmod g+rw $TMP_JAR_SH
chmod o+r $TMP_JAR_SH

awk '/#/ {print $0; next} {printf "# %s\n", $0}' $HAIL_INST/etc/jar.sh > $TMP_JAR_SH
echo "# `date +"%Y-%m-%d %T"` hail-all-spark$SPARK_VERSION-$HASH.jar" >> $TMP_JAR_SH
echo "JAR='$JAR'" >> $TMP_JAR_SH
mv $TMP_JAR_SH $HAIL_INST/etc/jar.sh

echo "Done!"
