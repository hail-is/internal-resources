#!/bin/bash

set -ex

HAIL_INST=../hail-inst
echo "HAIL_INST=$HAIL_INST"

SPARK_VERSION=1.6.2
echo "spark.version=$SPARK_VERSION"

git fetch
git checkout origin/master

./gradlew --daemon -Dspark.version=$SPARK_VERSION clean installDist shadowTestJar shadowJar

# run tests
ID=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 12 | head -n 1)
CLUSTER=cluster-ci-$ID
echo CLUSTER = $CLUSTER

MASTER=$CLUSTER-m

gcloud dataproc clusters create $CLUSTER --zone us-central1-f --master-machine-type n1-standard-2 --master-boot-disk-size 100 --num-workers 2 --worker-machine-type n1-standard-2 --worker-boot-disk-size 100 --image-version 1.0 --project broad-ctsa --initialization-actions 'gs://hail-dataproc-deps/initialization-actions.sh'

# copy up necessary files
gcloud compute copy-files \
       ./build/libs/hail-all-spark-test.jar \
       ./testng.xml \
       $MASTER:~

gcloud compute ssh $MASTER 'mkdir -p src/test'
gcloud compute copy-files \
       ./src/test/resources \
       $MASTER:~/src/test

cat <<EOF | gcloud compute ssh $MASTER bash
set -ex

hdfs dfs -mkdir -p src/test
hdfs dfs -rm -r -f -skipTrash src/test/resources
hdfs dfs -put ./src/test/resources src/test

SPARK_CLASSPATH=./hail-all-spark-test.jar \
	       spark-submit \
	       --class org.testng.TestNG \
	       ./hail-all-spark-test.jar \
	       ./testng.xml
EOF

# pull down test results for record
rm -rf test-output
gcloud compute copy-files $MASTER:~/test-output ..

gcloud dataproc clusters delete $CLUSTER

# copy locally for the record

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

# copy to gs
GS_JAR=gs://hail-common/hail-all-spark$SPARK_VERSION-$HASH.jar
echo GS_JAR = $GS_JAR
gsutil cp ./build/libs/hail-all-spark.jar $GS_JAR

echo "Done!"
