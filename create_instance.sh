#!/bin/bash
# Script to create a CATALINA_BASE directory for your own tomcat

PROG=`basename $0`
TARGET=""

BPORT=8000

HPORT_OFFSET=80
HPORT_DEFAULT=$(($BPORT + $HPORT_OFFSET))
HPORT=$HPORT_DEFAULT

CPORT_OFFSET=5
CPORT_DEFAULT=$(($BPORT + $CPORT_OFFSET))
CPORT=$HPORT_DEFAULT

APORT_OFFSET=9
APORT_DEFAULT=$(($BPORT + $APORT_OFFSET))
APORT=$HPORT_DEFAULT

SPORT_OFFSET=443
SPORT_DEFAULT=$(($BPORT + $SPORT_OFFSET))
SPORT=$SPORT_DEFAULT

CWORD="SHUTDOWN"

WARNED=0
warnlowport=0

usage() {
  echo "Usage: $PROG [options] <directoryname>"
  echo "  directoryname: name of the tomcat instance directory to create"
  echo "Options:"
  echo "  -h, --help         Display this help message"
  echo "  -t CATALINA_HOME   Set the CATALINE_HOME (Tomcat HOME) directory"
  echo "  -j JAVA_HOME       Set the JAVA_HOME (Java JRE installation) directory"
  echo "  -b baseport        The base offset for generating other ports (explanation below)"
  echo "  -p httpport        HTTP port to be used by Tomcat (default is $HPORT_DEFAULT)"
  echo "  -s httpsport       HTTPS port to be used by Tomcat (default is $SPORT_DEFAULT)"
  echo "  -c controlport     Server shutdown control port (default is $CPORT_DEFAULT)"
  echo "  -a ajpport         AJP Connector port (default is $APORT_DEFAULT)"
  echo "  -w magicword       Word to send to trigger shutdown (default is $CWORD)"
  echo ""
  echo "Base port usage:"
  echo ""
  echo "Tomcat by default use ports in the 8000 range, for instance, 8080, 8433 and 8005."
  echo "When specifying the base port the script automatically calculate the required ports"
  echo "using the base port and adding an offset for each protocol, such as;"
  echo "  HTTP      80 --> BasePort + 80    Default: 8080"
  echo "  HTTPS    433 --> BasePort + 433   Default: 8433"
  echo "  Control    5 --> BasePort + 5     Default: 8005"
  echo "  AJP        9 --> BasePort + 9     Default: 8009"
  echo ""
  echo "NOTE: If base port is set the individual ports can still be overwritten."
}

checkport() {
  type=$1
  port=$2
  # Fail if port is non-numeric
  num=`expr ${port} + 1 2> /dev/null`
  if [ $? != 0 ] || [ $num -lt 2 ]; then
    echo "Error: ${type} port '${port}' is not a valid TCP port number."
    exit 1
  fi

  # Fail if port is above 65535
  if [ ${port} -gt 65535 ]; then
    echo "Error: ${type} port ${port} is above TCP port numbers (> 65535)."
    exit 1
  fi

  # Warn if port is below 1024 (once)
  if [ ${warnlowport} -eq 0 ]; then 
    if [ ${port} -lt 1024 ]; then
      echo "Warning: ports below 1024 are reserved to the super-user."
      warnlowport=1
      WARNED=1
    fi
  fi

  # Warn if port appears to be in use
  if nc localhost "${port}" -z > /dev/null; then
    echo "Warning: ${type} port ${port} appears to be in use."
    WARNED=1
  fi
}

setports() {
  HPORT=$(($BPORT + $HPORT_OFFSET))
  CPORT=$(($BPORT + $CPORT_OFFSET))
  APORT=$(($BPORT + $APORT_OFFSET))
  SPORT=$(($BPORT + $SPORT_OFFSET))
}

#Ensure minumum required parameters are used
if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
  exit 0
fi

#Set the ports based on current (default) base port
setports

#Parse the parameters
while getopts ":t:j:b:p:s:c:w:h" options; do
  case $options in
    t ) TOMCAT_PATH=$OPTARG ;;
    j ) JAVA_HOME=$OPTARG ;;
    b ) BPORT=$OPTARG; setports ;;
    p ) HPORT=$OPTARG ;;
    s ) SPORT=$OPTARG ;;
    c ) CPORT=$OPTARG ;;
    w ) CWORD=$OPTARG ;;
    h ) usage;;
    * ) echo "Error: Unknown parameter '$OPTARG'."
        exit 1;;
  esac
done

shift $(($OPTIND - 1))
TARGET=$1
shift

# Fail if no target specified
if [ -z "${TARGET}" ]; then
  echo "Error: No target directory specified (use -d)."
  exit 1
fi

# Fail if ports are the same
if [ "${HPORT}" = "${CPORT}" ]; then
  echo "Error: HTTP port and control port must be different."
  exit 1
fi

# Fail if target directory already exists
if [ -d "${TARGET}" ]; then
  echo "Error: Target directory already exists."
  exit 1
fi

# Check ports
checkport HTTP "${HPORT}"
checkport Control "${CPORT}"

if [ -z "$TOMCAT_PATH" ]; then
  SCRIPTDIR=`dirname "$0"`
  TOMCAT_PATH=`cd "$SCRIPTDIR/.." >/dev/null; pwd`
  echo "Assuming $TOMCAT_PATH as Tomcat HOME directory.  Use -t option to override."
  WARNED=1
fi

if [ ! -d $TOMCAT_PATH ]; then
  echo "Error: Tomcat HOME directory not found (CATALINA_HOME)."
  exit 1
fi 

if [ ! -d $JAVA_HOME ] || [ ! -f "$JAVA_HOME/bin/java" ]; then
  echo "Error: Java directory not found (JAVA_HOME)."
  exit 1
fi 

echo "You are about to create a Tomcat instance in directory '$TARGET'"
# Ask for confirmation if warnings were printed out
if [ ${WARNED} -eq 1 ]; then 
  echo "Type <ENTER> to continue, <CTRL-C> to abort."
  read answer
fi

mkdir -p "${TARGET}"
FULLTARGET=`cd "${TARGET}" > /dev/null && pwd`

mkdir "${TARGET}/conf"
mkdir "${TARGET}/logs"
mkdir "${TARGET}/webapps"
mkdir "${TARGET}/work"
mkdir "${TARGET}/temp"
mkdir "${TARGET}/bin"
cp -r "${TOMCAT_PATH}/conf"/* "${TARGET}/conf"
cp -r "${TOMCAT_PATH}/webapps"/* "${TARGET}/webapps"

REPLACE="s/port=\"${HPORT_DEFAULT}\"/port=\"${HPORT}\"/;"
REPLACE="${REPLACE}s/port=\"${CPORT_DEFAULT}\"/port=\"${CPORT}\"/;"
REPLACE="${REPLACE}s/port=\"${APORT_DEFAULT}\"/port=\"${APORT}\"/;"
REPLACE="${REPLACE}s/redirectPort=\"${SPORT_DEFAULT}\"/redirectPort=\"${SPORT}\"/;"
REPLACE="${REPLACE}s/shutdown=\"SHUTDOWN\"/shutdown=\"${CWORD}\"/;"

sed -i -e "$REPLACE" "${TARGET}/conf/server.xml"

cat > "${TARGET}/bin/startup.sh" << EOT
#!/bin/sh
export JAVA_HOME="${JAVA_HOME}"
export CATALINA_BASE="${FULLTARGET}"
${TOMCAT_PATH}/bin/startup.sh
echo "Tomcat started"
EOT

cat > "${TARGET}/bin/shutdown.sh" << EOT
#!/bin/sh
export JAVA_HOME="${JAVA_HOME}"
export CATALINA_BASE="${FULLTARGET}"
${TOMCAT_PATH}/bin/shutdown.sh
echo "Tomcat stopped"
EOT

chmod a+x "${TARGET}/bin/startup.sh" "${TARGET}/bin/shutdown.sh"
echo "* New Tomcat instance created in ${TARGET}"
echo "* You might want to edit default configuration in ${TARGET}/conf"
echo "* Run ${TARGET}/bin/startup.sh to start your Tomcat instance"
