#!/bin/bash

USAGE="Usage: $0 [{-c|--config} ConfigFile] {start|daemon|stop|status|cleanpid}"

if [ $# == "0" ]; then
  echo "$USAGE" >&2
  exit 3
fi

while (( $# )); do
  key="$1"
  case $key in
    -c|--config)
      CONFIG="$2"
      shift # past argument
    ;;
    start|daemon|stop|status|cleanpid)
      COMMAND=$1
    ;;
    *)
      # unknown option
      echo "$USAGE" >&2
      exit 3
    ;;
  esac
  shift # past argument or value
done

# Set defaults
CATALINA_HOME=/opt/tomcat/current
JRE_HOME=/opt/java/jre/current
ALLOW_TOMCAT_ASROOT=0

# Read configuration variable file if it is present
if [ -n "$CONFIG" ] && [ -f $CONFIG ] ; then
  . "$CONFIG"
  echo "Config file $CONFIG loaded"
fi

# If CATALINA_BASE not set, set default
if [ -z $CATALINA_BASE ] ; then
  CATALINA_BASE=$CATALINA_HOME
  echo "CATALINA_BASE set to CATALINA_HOME"
fi

# Read CATALINA_BASE configuration variables
TOMCAT_SETENV=$CATALINA_BASE/bin/setenv.sh
if [ -f $TOMCAT_SETENV ] ; then
  . $TOMCAT_SETENV
  echo "Config set from $TOMCAT_SETENV"
fi

# If CATALINA_PID not set, set default
if [ -z $CATALINA_PID ] ; then
  CATALINA_PID=$CATALINA_BASE/catalina.pid
  echo "CATALINA_PID set to default: $CATALINA_PID"
fi
                
# Init script variables
TOMCAT_BINDIR=$CATALINA_HOME/bin
TOMCAT_STATUS=""
ERROR=0
PID=""

echo "Home: $CATALINA_HOME"
echo "Base: $CATALINA_BASE"
echo "JRE:  $JRE_HOME"
echo "PIDF: $CATALINA_PID"

export JRE_HOME
export CATALINA_HOME
export CATALINA_BASE


TOMCAT_ASTOMCATUSER=0
if [ `id|sed -e s/uid=//g -e s/\(.*//g` -eq 0 ] && [ $ALLOW_TOMCAT_ASROOT -eq 0 ]; then
    TOMCAT_ASTOMCATUSER=1
fi


start_tomcat() {
    is_tomcat_running
    RUNNING=$?
    if [ $RUNNING -eq 1 ]; then
        echo "$0 $ARG: tomcat (pid $PID) already running"
    else
	rm -f $CATALINA_PID
	if [ $TOMCAT_ASTOMCATUSER -eq 1 ]; then
	    $TOMCAT_BINDIR/daemon.sh start
	else
	    $TOMCAT_BINDIR/startup.sh
	fi
        is_tomcat_running
        RUNNING=$?
	if [ $RUNNING -eq 1 ];  then
            echo "$0 $ARG: tomcat started"
	else
            echo "$0 $ARG: tomcat could not be started"
            ERROR=1
	fi
    fi
}

daemon_tomcat() {
    if [ $TOMCAT_ASTOMCATUSER -eq 1 ]; then
	$TOMCAT_BINDIR/daemon.sh start
    else
	$TOMCAT_BINDIR/catalina.sh run
    fi
}

stop_tomcat() {
    is_tomcat_running
    RUNNING=$?
    if [ $RUNNING -eq 0 ]; then
        echo "$0 $ARG: $TOMCAT_STATUS"
        exit
    fi
    echo "CPID: $CATALINA_PID"
    if [ $TOMCAT_ASTOMCATUSER -eq 1 ]; then
      echo "Stopping using daemon.sh"
      $TOMCAT_BINDIR/daemon.sh stop
    else
      # 2013-09-05: bug 33242: change from 300 to 10 seconds 
      echo "Stopping using shutdown.sh"
      $TOMCAT_BINDIR/shutdown.sh 10 -force 
    fi    
    sleep 2
    is_tomcat_running
    RUNNING=$?
    COUNTER=4
    while [ $RUNNING -ne 0 ] && [ $COUNTER -ne 0 ]; do
        COUNTER=`expr $COUNTER - 1`
        sleep 2
        is_tomcat_running
        RUNNING=$?
    done
    if [ $RUNNING -eq 0 ]; then
        echo "$0 $ARG: tomcat stopped"
        sleep 3
    else
        echo "$0 $ARG: tomcat could not be stopped"
        ERROR=2
    fi
}

get_pid() {
    PID=""
    PIDFILE=$1
    # check for pidfile
    if [ -f $PIDFILE ] ; then
        PID=`cat $PIDFILE`
    fi
}

get_tomcat_pid() {
    get_pid $CATALINA_PID
    if [ ! $PID ]; then
        return
    fi
}

is_service_running() {
    PID=$1
    if [ "x$PID" != "x" ] && kill -0 $PID 2>/dev/null ; then
        RUNNING=1
    else
        RUNNING=0
    fi
    return $RUNNING
}

is_tomcat_running() {
    get_tomcat_pid
    is_service_running $PID
    RUNNING=$?
    if [ $RUNNING -eq 0 ]; then
        TOMCAT_STATUS="tomcat not running"
    else
        TOMCAT_STATUS="tomcat already running"
    fi
    return $RUNNING
}

cleanpid() {
    rm -f $CATALINA_PID
}

if [ "x$COMMAND" = "xstart" ]; then
    start_tomcat
    sleep 2
elif [ "x$COMMAND" = "xdaemon" ]; then
    daemon_tomcat
elif [ "x$COMMAND" = "xstop" ]; then
    stop_tomcat
    sleep 2
elif [ "x$COMMAND" = "xstatus" ]; then
    is_tomcat_running
    echo $TOMCAT_STATUS
elif [ "x$COMMAND" = "xcleanpid" ]; then
    cleanpid
fi

exit $ERROR
