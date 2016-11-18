#!/bin/bash

set -ex

SPARK_VERSION=1.6.2
echo "spark.version=$SPARK_VERSION"

rm -rf hail

ORIGIN=hail-is
BRANCH=master
REPO=https://github.com/$ORIGIN/hail.git

git clone --origin $ORIGIN --branch $BRANCH $REPO
cd hail

./gradlew --daemon -Dspark.version=$SPARK_VERSION clean installDist shadowTestJar shadowJar

# run tests
ID=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 12 | head -n 1)
CLUSTER=cluster-ci-$ID
echo "CLUSTER=$CLUSTER"

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

gcloud -q dataproc clusters delete $CLUSTER

# copy locally for the record

HASH=`git rev-parse --verify --short HEAD`
echo "HASH=$HASH"

GS_JAR=gs://hail-common/hail-$ORIGIN-$BRANCH-all-spark$SPARK_VERSION-$HASH.jar
echo "GS_JAR=$GS_JAR"
gsutil cp ./build/libs/hail-all-spark.jar $GS_JAR
gsutil acl set public-read $GS_JAR

PYHAIL_ZIP=pyhail-$ORIGIN-$BRANCH-$HASH.zip
GS_PYHAIL_ZIP=gs://hail-common/$PYHAIL_ZIP
(cd python && zip -r ../build/$PYHAIL_ZIP pyhail)
gsutil cp ./build/$PYHAIL_ZIP $GS_PYHAIL_ZIP
gsutil acl set public-read $GS_PYHAIL_ZIP

if [ x"$ORIGIN-$BRANCH" = x"hail-is-master" ]; then
    TMP_CURRENT_HASH=`mktemp`
    echo $HASH >> $TMP_CURRENT_HASH
    gsutil cp $TMP_CURRENT_HASH gs://hail-common/latest-hash.txt
    gsutil acl set public-read gs://hail-common/latest-hash.txt
    
    rm -f $TMP_CURRENT_HASH
fi

echo "Done!"
