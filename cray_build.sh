git fetch
git checkout origin/master
gradle --daemon shadowJar
CODE=$?
if [ $CODE -eq 0 ]; then
    HASH=`git rev-parse --verify --short HEAD`
    echo Current build hash is [$HASH]
    cp /mnt/lustre/tpoterba/hail/build/libs/hail-all-spark.jar /mnt/lustre/tpoterba/hail-inst/lib/hail-all-spark-$HASH.jar
    awk '/#/ {print $0; next} {printf "# %s\n", $0}' /mnt/lustre/tpoterba/hail-inst/etc/jar.sh >> /mnt/lustre/tpoterba/hail-inst/etc/jar.tmp.sh
    echo "# `date +"%Y-%m-%d %T"`" >> /mnt/lustre/tpoterba/hail-inst/etc/jar.tmp.sh
    echo "JAR='/mnt/lustre/tpoterba/hail-inst/lib/hail-all-spark-$HASH.jar'" >> /mnt/lustre/tpoterba/hail-inst/etc/jar.tmp.sh
    mv /mnt/lustre/tpoterba/hail-inst/etc/jar.tmp.sh /mnt/lustre/tpoterba/hail-inst/etc/jar.sh
    echo Done!
else
    echo "Problem occurred with gradle build, exiting..."
fi
