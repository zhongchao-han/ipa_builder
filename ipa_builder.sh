#!/bin/bash
# Author: Andrey Toropchin
# -----------------------------------------------

IPA_OUTPUT_PATH="$HOME/Desktop"
TESTFLIGHT_API_TOKEN=""  # optional
TESTFLIGHT_TEAM_TOKEN="" # optional
TESTFLIGHT_DISTRIBUTION_LIST="" # optional

# A bunch of forward implemented functions

usage()
{
cat<<EOF
usage: `tput setaf 2`${0##*/}`tput sgr0` [`tput setaf 1`options`tput sgr0`] `tput setaf 1`path`tput sgr0` (to xcodeproj)
output directory: $IPA_OUTPUT_PATH

Automated iOS App Builder and Distributor (via TestFlight)

OPTIONS:
   -c     Build configuration (`tput setaf 1`required`tput sgr0`), example: adhoc or distrib
   -s     Scheme to build (optional)
   -t     Target to build (optional)

   -i     Codesign identity (optional), example: "iPhone Distribution: ..."
   -p     Provisioning profile path (optional)

   -n     TestFlight release notes (optional)
   -l     TestFlight distribution lists (optional)
   -d     Put archived dSYM to the output directory (yes/no) (optional)

EOF
}

clean()
{
    local build_dir=$(dirname $PROJECT_PATH)/build
    if [ -d $build_dir ]; then
        rm -rf $build_dir
    fi
    if [ -f $TEMP_FILE ]; then
        rm $TEMP_FILE
    fi
}

fail()
{
    echo "`tput setaf 1`ERROR:`tput sgr0` $1"
    clean
    exit 1
}

xcode_cmd()
{
    local cmd="xcodebuild -project $PROJECT_PATH -configuration $CONFIG"
    if [ $SCHEME ]; then
        cmd="$cmd -scheme $SCHEME"
    fi
    if [ $TARGET ]; then
        cmd="$cmd -target $TARGET"
    fi
    echo $cmd
}

# Identifying selected configuration
is_adhoc()
{
    if [ `echo $CONFIG | grep -o -i ad` ]; then
        return 0
    else
        return 1
    fi
}

is_debug()
{
    if [ `echo $CONFIG | grep -o -i debug` ]; then
        return 0
    else
        return 1
    fi
}

is_distribution()
{
    if [ `echo $CONFIG | grep -o -i distrib` ]; then
        return 0
    else
        return 1
    fi
}

is_release()
{
    if [ `echo $CONFIG | grep -o -i release` ]; then
        return 0
    else
        return 1
    fi
}

# Preparing plist
make_temp_plist()
{
    strings $1 >$TEMP_FILE 2>/dev/null
    local output=`strings $TEMP_FILE`
    if [ "${output:0:1}" != "<" ]; then
        output="${output:1:${#output}-1}"
        echo "$output" >$TEMP_FILE
    fi
}

# Reading plist
read_plist()
{
    /usr/libexec/PlistBuddy -c "Print $2" $1 2>/dev/null
}

# Select mobile provisiong profile
show_provisioning_profile()
{
    make_temp_plist $PROVISIONING_PROFILE
    local provisioning_name=`read_plist $TEMP_FILE ":Name"`
    if [ $provisioning_name ] && [ -z `echo $provisioning_name | grep "Error Reading File"` ] && [ -z `echo $provisioning_name | grep "Does Not Exist"` ]; then
        echo "Using `tput setaf 3`$provisioning_name`tput sgr0` (\"$PROVISIONING_PROFILE\")"
    else
        fail "Wrong provisioning profile is specified: $PROVISIONING_PROFILE"
    fi
}

# Mobile provisioning match function
find_provisioning_profile()
{
    while read provisioning_file; do
        make_temp_plist $provisioning_file
        if [ `read_plist $TEMP_FILE ":Entitlements:application-identifier" | grep "$1"` ]; then
            if is_adhoc || is_release; then
                if [ "`read_plist $TEMP_FILE ":Entitlements:get-task-allow"`" = "false" ] && [ "`read_plist $TEMP_FILE ":ProvisionedDevices" | grep -o Array`" = "Array" ]; then
                    PROVISIONING_PROFILE=$provisioning_file
                    break
                fi
            elif is_distribution; then
                if [ "`read_plist $TEMP_FILE ":Entitlements:get-task-allow"`" = "false" ] && [ "`read_plist $TEMP_FILE ":ProvisionedDevices" | grep -o Array`" = "" ]; then
                    PROVISIONING_PROFILE=$provisioning_file
                    break
                fi
            elif is_debug; then
                if [ "`read_plist $TEMP_FILE ":Entitlements:get-task-allow"`" = "true" ] && [ "`read_plist $TEMP_FILE ":ProvisionedDevices" | grep -o Array`" = "Array" ]; then
                    PROVISIONING_PROFILE=$provisioning_file
                    break
                fi
            fi
        fi
    done <<< `ls -t ~/Library/MobileDevice/Provisioning\ Profiles/*`
}

should_notify()
{
    if [ -z $TESTFLIGHT_DISTRIBUTION_LIST ]; then
        echo False
    else
        echo True
    fi
}


### Main ###


while getopts c:t:s:d:i:p:n:l: option
do
    case "${option}"
    in
        c) CONFIG=${OPTARG};;
        t) TARGET=${OPTARG};;
        s) SCHEME=${OPTARG};;
        d) DSYM=${OPTARG};;
        i) CODESIGN_IDENTITY=${OPTARG};;
        p) PROVISIONING_PROFILE=${OPTARG};;
        n) TESTFLIGHT_NOTES=${OPTARG};;
        l) TESTFLIGHT_DISTRIBUTION_LIST=${OPTARG};;
    esac
done

IFS="" # trick to deal with spaces in paths
TEMP_FILE="/tmp/temp"

# Checking required option
if [ -z $CONFIG ]; then
    usage
    exit 1
fi

# Getting path
if [ -d "${!#}" ]; then
    PROJECT_PATH=${!#}
else
    # Trying to find project file in `pwd`
    PROJECT_PATH=`pwd`/`ls $PROJECT_PATH | grep -m 1 xcodeproj`
fi

if ! [ -d $PROJECT_PATH ] || [ -z `echo $PROJECT_PATH | grep xcodeproj` ]; then
    fail "No xcodeproj directory is specified"
fi

# Validating configuration
CONFIG=`xcodebuild -project $PROJECT_PATH -list | grep -i $CONFIG | sed 's/^ *//g' | sed 's/ *$//g'`
if [ -z $CONFIG ]; then
    fail "Specified configuration is not valid"
else
    echo "Going to build `tput setaf 3``basename $PROJECT_PATH``tput sgr0` @ `tput setaf 2`$CONFIG`tput sgr0`"
fi

# Cleaning
echo -ne "Cleaning..."
BUILD_DIR="$(dirname $PROJECT_PATH)/build"
if [ $SCHEME ]; then
    xcodeclean_cmd="$(xcode_cmd) clean >$TEMP_FILE 2>&1"
    eval $xcodeclean_cmd
    if [ -z `cat $TEMP_FILE | grep -o SUCCEEDED` ]; then
        echo
        fail "`tail -n10 $TEMP_FILE`"
    else
        echo "`tput setaf 2`ok`tput sgr0`"
        # Build dir is now in DerivedData folder
        BUILD_DIR=$(cat $TEMP_FILE | grep -oE '/.*Build.*' | head -n1 | sed 's/Build\/.*-.*/Build/')
        BUILD_DIR="$BUILD_DIR/Products"
    fi
else
    clean
    echo "`tput setaf 2`ok`tput sgr0`"
fi

# Building
echo -ne "Building..."
xcodebuild_cmd="$(xcode_cmd) >$TEMP_FILE 2>&1"
eval $xcodebuild_cmd
if [ -z `cat $TEMP_FILE | grep -o SUCCEEDED` ]; then
    echo
    fail "`tail -n10 $TEMP_FILE`"
else
    echo "`tput setaf 2`ok`tput sgr0`"
fi

# Getting app name
APP_NAME=$(ls $BUILD_DIR/$CONFIG-iphoneos/ | grep -m 1 .app | sed 's/.app$//g')
echo "Preparing to build IPA for `tput setaf 3`$APP_NAME`tput sgr0`"

# Getting bundle id
BUNDLE_ID=$(codesign --display --verbose=2 $BUILD_DIR/$CONFIG-iphoneos/$APP_NAME.app 2>&1 | grep Identifier= | sed 's/Identifier=*//g')
if [ -z $BUNDLE_ID ]; then
    fail "Can't check your build and get your BUNDLE_ID"
else
    echo "BUNDLE_ID: `tput setaf 3`$BUNDLE_ID`tput sgr0`"
fi

# Getting $CODESIGN_IDENTITY (if not specified)
if [ -z $CODESIGN_IDENTITY ]; then
    CODESIGN_IDENTITY=$(codesign --display --verbose=2 $BUILD_DIR/$CONFIG-iphoneos/$APP_NAME.app 2>&1 | grep Authority=iPhone | sed 's/Authority=*//g')
    if [ -z $CODESIGN_IDENTITY ]; then
        fail "Please specify codesign identity using `tput setaf 2`-i`tput sgr0` option"
    fi
fi
echo "Using codesign identity: `tput setaf 3`\"$CODESIGN_IDENTITY\"`tput sgr0`"

# Trying to find proper provisioning profile (if not specified)
if [ -z $PROVISIONING_PROFILE ]; then
    find_provisioning_profile $BUNDLE_ID
    if [ -z $PROVISIONING_PROFILE ]; then
        # Trying profiles with application-identifier = ".*"
        find_provisioning_profile "*"
    fi
    if [ -z $PROVISIONING_PROFILE ]; then
        fail "Please specify provisioning profile using `tput setaf 2`-p`tput sgr0` option"
    fi
fi

# Displaying selected provisioning profile
show_provisioning_profile $PROVISIONING_PROFILE

# Getting CFBundleName & CFBundleVersion
BUNDLE_NAME=$(read_plist $BUILD_DIR/$CONFIG-iphoneos/$APP_NAME.app/Info.plist ":CFBundleName")
BUNDLE_VERSION=$(read_plist $BUILD_DIR/$CONFIG-iphoneos/$APP_NAME.app/Info.plist ":CFBundleVersion")
IPA_FILENAME=$IPA_OUTPUT_PATH/${BUNDLE_NAME}_${BUNDLE_VERSION}.ipa

# Building signed iPA
xcrun -sdk iphoneos PackageApplication $BUILD_DIR/$CONFIG-iphoneos/$APP_NAME.app -o $IPA_FILENAME --sign $CODESIGN_IDENTITY --embed $PROVISIONING_PROFILE
if [ -f $IPA_FILENAME ]; then
    echo "IPA is ready: `tput setaf 2`$IPA_FILENAME`tput sgr0`"
else
    fail "Failed to create IPA"
fi

# Zipping dSYM (always archiving dSYM if distributing via TestFlight)
if [ "$DSYM" = "yes" ] || [ $TESTFLIGHT_NOTES ]; then
    DSYM_FILENAME=$IPA_OUTPUT_PATH/${BUNDLE_NAME}_${BUNDLE_VERSION}_dSYM.zip
    zip -r $DSYM_FILENAME $BUILD_DIR/$CONFIG-iphoneos/$APP_NAME.app.dSYM >/dev/null 2>&1
    if [ -f $DSYM_FILENAME ]; then
        echo "dSYM is ready: $DSYM_FILENAME"
    else
        fail "Failed to zip dSYM"
    fi
fi

if ! is_distribution && [ $TESTFLIGHT_API_TOKEN ] && [ $TESTFLIGHT_TEAM_TOKEN ] && [ $TESTFLIGHT_NOTES ]; then
    echo -ne "Uploading IPA to the TestFlight..."
    curl http://testflightapp.com/api/builds.json                    \
        -F file=@"$IPA_FILENAME"                                     \
        -F dsym=@"$DSYM_FILENAME"                                    \
        -F api_token="$TESTFLIGHT_API_TOKEN"                         \
        -F team_token="$TESTFLIGHT_TEAM_TOKEN"                       \
        -F notes="$TESTFLIGHT_NOTES"                                 \
        -F distribution_lists="$TESTFLIGHT_DISTRIBUTION_LIST"        \
        -F notify=$(should_notify)          >$TEMP_FILE 2>$1

    url=`cat $TEMP_FILE | grep config_url | grep -o -e "http.*/"`
    if [ $url ]; then
        echo "`tput setaf 2`ok`tput sgr0`"
        echo "Complete url: `tput setaf 2`$url`tput sgr0`"
        # Open config_url in browser to finish distribution in case of empty TESTFLIGHT_DISTRIBUTION_LIST
        if [ -z $TESTFLIGHT_DISTRIBUTION_LIST ]; then
            open $url
        fi
    else
        echo
        fail "`tail -n10 $TEMP_FILE`"
    fi
fi

clean
