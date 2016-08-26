git fetch origin
git checkout origin/master
gradle --daemon  -Dhail.sparkversion=1.6.0-cdh5.7.2 shadowJar
CODE=$?
if [ $CODE -eq 0 ]; then
    HASH=`git rev-parse --verify --short HEAD`
    echo Current build hash is [$HASH]
    cp build/libs/hail-all-spark.jar ~/hail-inst/lib/hail-all-spark-$HASH.jar
    awk '/#/ {print $0; next} {printf "#%s\n", $0}' ~/hail-inst/etc/jar.sh > jar.tmp.sh
    echo "#`date +"%Y-%m-%d %T"`" >> jar.tmp.sh
    echo "JAR='/psych/genetics_data/working/cseed/hail-inst/lib/hail-all-spark-$HASH.jar'" >> jar.tmp.sh
    mv jar.tmp.sh ~/hail-inst/etc/jar.sh
    echo Done!
else
    echo "Problem occurred with gradle build, exiting..."
fi
