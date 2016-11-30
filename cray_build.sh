#!/bin/bash

set -ex

umask 002

HAIL_INST=/mnt/lustre/tpoterba/hail-inst
echo "HAIL_INST=$HAIL_INST"

SPARK_VERSION=1.5.2
echo "spark.version=$SPARK_VERSION"

rm -rf hail

ORIGIN=hail-is
BRANCH=master
REPO=https://github.com/$ORIGIN/hail.git

git clone --origin $ORIGIN --branch $BRANCH $REPO
cd hail

patch -p0 < spark1.patch

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

HASH=`git rev-parse --verify --short HEAD`
echo "HASH=$HASH"

JAR=$HAIL_INST/lib/hail-all-spark$SPARK_VERSION-$HASH.jar
echo "JAR=$JAR"

cp build/libs/hail-all-spark.jar $JAR

TMP_JAR_SH=`mktemp`

chgrp hail $TMP_JAR_SH
chmod g+rw $TMP_JAR_SH
chmod o+r $TMP_JAR_SH

if [ -f $HAIL_INST/etc/jar.sh ]; then
    awk '/#/ {print $0; next} {printf "# %s\n", $0}' $HAIL_INST/etc/jar.sh > $TMP_JAR_SH
fi

echo "# `date +"%Y-%m-%d %T"` hail-all-spark$SPARK_VERSION-$HASH.jar" >> $TMP_JAR_SH
echo "JAR='$JAR'" >> $TMP_JAR_SH

rm -f $HAIL_INST/etc/jar.sh
mv $TMP_JAR_SH $HAIL_INST/etc/jar.sh

rm -rf $HAIL_INST/python/pyhail-old
if [ -e $HAIL_INST/python/pyhail ]; then
    mv $HAIL_INST/python/pyhail $HAIL_INST/python/pyhail-old
fi
cp -r python/pyhail $HAIL_INST/python

echo "Done!"
