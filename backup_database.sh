#!/bin/bash
# @Author: Seaky
# @Date:   2019-07-03 11:01:54


TIME=`date +%y%m%d%H%M%S`

SOURCE_IP='database.address'
SOURCE_PORT=3306
SOURCE_DB='database.name'
SOURCE_USER='database.user'
SOURCE_PASS='database.pass'
# only backup specific tables defined in $TABLES if $TABLES is set
TABLES=''

# use ssh tunnel if required
SSH_TUNNEL=false
SOURCE_SSH_HOST=${SOURCE_IP}
[[ $SSH_TUNNEL == true ]] && SOURCE_IP='localhost'
SOURCE_SSH_PORT=22
SOURCE_SSH_USER='ssh.user'
SOURCE_SSH_KEY='ssh.key'

# auto set the fold which script resides is backup folder
BACKUP_DIR=$(dirname $(readlink -f "$0"))
BACKUP_FILE=${BACKUP_DIR}/${SOURCE_DB}_$TIME.sql
LOG_FILE=${BACKUP_DIR}/${SOURCE_DB}.log
BACKUPS=5
# 1-days, 2-files
KEEP_BY=2

# dump the data to backup server
TARGET_IP=''
TARGET_PORT=3306
TARGET_DB=''
TARGET_USER=''
TARGET_PASS=''


check_dir() {
    [[ ! -d $1 ]] && mkdir -p $1
}

log() {
    echo -e $1 |& tee -a $LOG_FILE
}

title () {
    log "\n\n#################"
    log "$(date +'%y.%m.%d %H:%M:%S')"
    log "#################"
}

exec_cmd() {
    log "$*"
    (/usr/bin/time -f "\t%E real,\t%U user,\t%S sys" bash -c "$*") |& tee -a $LOG_FILE
}

backup_from_source() {
    log "\nDump database '$SOURCE_DB' on '$SOURCE_IP' to '$BACKUP_FILE'"
    [[ $TABLES ]] && log "  tables: $TABLES"
    # --set-gtid-purged=OFF
    dump_cmd="mysqldump --single-transaction --quick -h $SOURCE_IP -P $SOURCE_PORT -u $SOURCE_USER $SOURCE_DB $TABLES"
    if $SSH_TUNNEL; then
        cmd="ssh -p $SOURCE_SSH_PORT -i $SOURCE_SSH_KEY ${SOURCE_SSH_USER}@${SOURCE_SSH_HOST} 'export MYSQL_PWD=$SOURCE_PASS;$dump_cmd' > $BACKUP_FILE"
    else
        export MYSQL_PWD=$SOURCE_PASS
        cmd=$dump_cmd" > $BACKUP_FILE"
    fi
    exec_cmd $cmd
    unset MYSQL_PWD
}

create_symlink() {
    symlink=${BACKUP_DIR}/$SOURCE_DB.sql
    ln -sf $BACKUP_FILE $symlink
    log "\nCreating symlink $symlink to $BACKUP_FILE"
}

delete_expired() {
    if [[ $KEEP_BY == 1 ]]; then
        log "\nDeleting backups older than $BACKUPS days"
        expired=$(find $BACKUP_DIR -maxdepth 1 \( -name '*.sql' -o -name '*.sql.tar.gz' \) -type f -mtime +$BACKUPS -exec echo '{}' +)
    elif [[ $KEEP_BY == 2 ]]; then
        log "\nDeleting backups except last $BACKUPS files"
        backups=($(ls -t $(find $BACKUP_DIR -maxdepth 1 \( -name '*.sql' -o -name '*.sql.tar.gz' \) -type f -exec echo '{}' +)))
        # bash array
        expired=${backups[@]:${BACKUPS}}
    fi
    [[ -n "$expired" ]] && exec_cmd "rm $expired"
}

delete_target_db() {
    if [ -n "$TABLES" ]; then
        log "\nStart delete tables in '$TARGET_DB' on '$TARGET_IP'"
        export MYSQL_PWD=$TARGET_PASS
        for tb in $TABLES
        do
            drop_sql=$drop_sql"DROP TABLE IF EXISTS $tb;"
        done
        cmd="mysql -h $TARGET_IP -P $TARGET_PORT -u $TARGET_USER $TARGET_DB -e '$drop_sql'"
        exec_cmd $cmd
        unset MYSQL_PWD
    fi
}

compress_earlier() {
    log "\nCompress earlier backups"
    backups=($(ls -t $(find $BACKUP_DIR -maxdepth 1 -name '*.sql' -type f -exec echo '{}' +)))
    earlier=${backups[@]:1}
    for f in $earlier; do
        cmd="cd $(dirname ${f}) && tar zcf ${f}.tar.gz $(basename ${f}) && rm ${f}"
        exec_cmd $cmd
    done
}

import_to_target_db() {
    log "\nImport '$BACKUP_FILE' to '$TARGET_DB' on '$TARGET_IP'"
    export MYSQL_PWD=$TARGET_PASS
    cmd="mysql -h $TARGET_IP -P $TARGET_PORT -u $TARGET_USER $TARGET_DB < $BACKUP_FILE"
    exec_cmd $cmd
    unset MYSQL_PWD
}

call_target_func() {
    log "\nCall '$1' to '$TARGET_DB' on '$TARGET_IP'"
    export MYSQL_PWD=$TARGET_PASS
    cmd="mysql -h $TARGET_IP -P $TARGET_PORT -u $TARGET_USER $TARGET_DB -e 'CALL $1()'"
    exec_cmd $cmd
    unset MYSQL_PWD
}

title
check_dir $BACKUP_DIR
backup_from_source
create_symlink
delete_expired
compress_earlier
# delete_target_db
# import_to_target_db
# call_target_func func
