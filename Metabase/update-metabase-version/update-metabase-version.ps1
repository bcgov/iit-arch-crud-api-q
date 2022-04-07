#This script will help setup Metabase on openshift namespace wihout any installation.

#Declare global Variables here.

$global:OC_BASE_PATH="C:\softwares\oc"
$global:NAMESPACE=""
$global:ENVIRONMENT=""
$global:DOCKER_USER=""
$global:DOCKER_PWD=""
$global:OPENSHIFT_TOKEN=""
$global:OPENSHIFT_SERVER=""
$global:METABASE_ADMIN_EMAIL=""
$global:FOREGROUND_COLOR="DarkGreen"
$global:ARTIFACTORY_CREDS_PRESENT=""
$global:METABASE_APP_PREFIX=""
$global:BASE_URL="https://raw.githubusercontent.com/bcgov/iit-arch/main/Metabase/openshift"
$global:DB_HOST=""
$global:DB_PORT=""
$global:OC_ALIAS_REQUIRED="false"

#This is our main function , which is the entry point of the script.
function main
{
  Clear-Host
  Write-Host -ForegroundColor $FOREGROUND_COLOR "This script will update the metabase version on a openshift namespace. Please make sure the version you pass is correct otherwise the build will fail. Please enter a key to continue."
  timeout /t -1
  checkAndAddOCClientForWindows
  if($global:OC_ALIAS_REQUIRED -eq "true")
  {
    Set-Alias -Name oc -Value $global:OC_BASE_PATH\oc.exe
    Write-Host "$( oc version )"
  }
  getInputsFromUser
  loginToOpenshift
  checkArtifactoryCreds
  if($ARTIFACTORY_CREDS_PRESENT -eq "false")
  {
    Write-Host -ForegroundColor yellow "Artifactory Creds are not present. Lets set it up."
    setupArtifactoryCreds
  }
  buildMetabase
  deployMetabase
  exit 0
}

#This function will check if the OC client is installed on the windows machine. If not it will install it.
function checkAndAddOCClientForWindows
{
  try
  {
    if (oc)
    {
      Write-Host -ForegroundColor $FOREGROUND_COLOR "OC client is installed already."
    }
  }
  catch
  {

    if (Test-Path $OC_BASE_PATH\oc.exe)
    {
      Write-Host -ForegroundColor $FOREGROUND_COLOR "$( $OC_BASE_PATH )\oc.exe path already exists."
    }
    else
    {
      Write-Host -ForegroundColor yellow "$( $OC_BASE_PATH ) path does not exist, it will be created."
      New-Item -Path $OC_BASE_PATH -ItemType Directory -Force
      Write-Host -ForegroundColor yellow "OC client is not present, it will downloaded and unzipped to $( $OC_BASE_PATH )"
      Write-Host -ForegroundColor $FOREGROUND_COLOR "Downloading OC CLI.... "
      Invoke-WebRequest -Uri https://downloads-openshift-console.apps.silver.devops.gov.bc.ca/amd64/windows/oc.zip -OutFile $OC_BASE_PATH\oc.zip
      Write-Host -ForegroundColor $FOREGROUND_COLOR "OC CLI Downloaded, now unzipping.... "
      Expand-Archive $OC_BASE_PATH\oc.zip -DestinationPath $OC_BASE_PATH
      Write-Host -ForegroundColor $FOREGROUND_COLOR "oc.exe extracted to $( $OC_BASE_PATH )"
    }
    $global:OC_ALIAS_REQUIRED="true"
  }


}
function getInputsFromUser
{
  getNamespace
  getEnvironment
  getOpenShiftToken
  getOpenShiftServer
  getMetabaseVersion
  getOracleDBHost
  getOracleDBPort
}

function getMetabaseVersion
{
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Please enter the Metabase version you want to deploy."
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Example: v0.42.3"
  $data = Read-Host
  $HTTP_Request = [System.Net.WebRequest]::Create("https://downloads.metabase.com/${data}/metabase.jar")

  # We then get a response from the site.
  $HTTP_Response = $HTTP_Request.GetResponse()

  # We then get the HTTP code as an integer.
  $HTTP_Status = [int]$HTTP_Response.StatusCode

  If ($HTTP_Status -eq 200) {
    Write-Host -ForegroundColor Cyan "The version is available."
    $global:METABASE_VERSION=$data
    # Finally, we clean up the http request by closing it.
    If ($HTTP_Response -eq $null) { }
    Else { $HTTP_Response.Close() }
  }
  Else {
    Write-Host -ForegroundColor red "The version you have specified is not available. Please try again."
    # Finally, we clean up the http request by closing it.
    If ($HTTP_Response -eq $null) { }
    Else { $HTTP_Response.Close() }
    getMetabaseVersion
  }



}
function getEnvironment
{
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Enter the environment where Metabase will be installed, for example(dev,test,prod)."
  $ENVIRONMENT = Read-Host
  if ($ENVIRONMENT -ne "dev" -and $ENVIRONMENT -ne "test" -and $ENVIRONMENT -ne "prod")
  {
    Write-Host -ForegroundColor red "Invalid environment, please enter dev, test or prod."
    getEnvironment
  }
  else
  {
    $global:ENVIRONMENT = $ENVIRONMENT.Trim()
  }
}
function getOracleDBHost
{
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Enter the oracle db host name, this is the DB Host which will be connected from the metabase instance. This is required."
  $data = Read-Host
  if (-not([string]::IsNullOrEmpty($data)))
  {
    $global:DB_HOST = $data.Trim()
  }
  else
  {
    Write-Host -ForegroundColor red "oracle db host name is required."
    getOracleDBHost
  }


}
function getOracleDBPort
{
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Enter the oracle db port number,this is the DB Port which will be connected from the metabase instance. This is required."
  $port = Read-Host
  if (-not([string]::IsNullOrEmpty($port)))
  {
    $global:DB_PORT = $port.Trim()
  }
  else
  {
    Write-Host -ForegroundColor red "oracle db port is required."
    getOracleDBPort
  }
}
function getNamespace
{
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Enter the Namespace of  where Metabase will be installed, it will be a 6 character alphanumeric string."
  $NAMESPACE = Read-Host
  if (-not([string]::IsNullOrEmpty($NAMESPACE)))
  {
    $global:NAMESPACE = $NAMESPACE.Trim()
  }
  else
  {
    Write-Host -ForegroundColor red "Namespace is required."
    getNamespace
  }
}
function getDockerUser
{
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Enter the docker user name."
  $DOCKER_USER = Read-Host
  if (-not([string]::IsNullOrEmpty($DOCKER_USER)))
  {
    $global:DOCKER_USER = $DOCKER_USER.Trim()
  }
  else
  {
    Write-Host -ForegroundColor red "Docker user name is required."
    getDockerUser
  }
}
function getDockerPwd
{
  Write-Host -ForegroundColor $FOREGROUND_COLOR  "Enter the docker password."
  $DOCKER_PWD = Read-Host
  if (-not([string]::IsNullOrEmpty($DOCKER_PWD)))
  {
    $global:DOCKER_PWD = $DOCKER_PWD.Trim()
  }
  else
  {
    Write-Host -ForegroundColor red "Docker password is required."
    getDockerPwd
  }
}
function getOpenShiftToken
{
  Write-Host -ForegroundColor cyan  "Go to openshift namespace in your browser and click on your name in the top right corner, click on Copy Login Command button.A new tab will open and after series of steps, you will see a display token link, click on that. Copy the token from where it says 'Your API token is' and paste it here."
  Write-Host -ForegroundColor $FOREGROUND_COLOR  "Enter the openshift token."
  $OPENSHIFT_TOKEN = Read-Host
  if (-not([string]::IsNullOrEmpty($OPENSHIFT_TOKEN)))
  {
    $global:OPENSHIFT_TOKEN = $OPENSHIFT_TOKEN.Trim()
  }
  else
  {
    Write-Host -ForegroundColor red  "OpenShift token is required."
    getOpenShiftToken
  }
}
function getOpenShiftServer
{
  Write-Host -ForegroundColor cyan "From the same place in your browser copy the server name where it is like '--server=****' and paste it here. Copy the value portion which is after '--server='"
  Write-Host -ForegroundColor $FOREGROUND_COLOR  "Enter the openshift server."
  $OPENSHIFT_SERVER = Read-Host
  if (-not([string]::IsNullOrEmpty($OPENSHIFT_SERVER)))
  {
    $global:OPENSHIFT_SERVER = $OPENSHIFT_SERVER.Trim()
  }
  else
  {
    Write-Host -ForegroundColor red "OpenShift server is required."
    getOpenShiftServer
  }
}

function getMetabaseAppPrefix
{
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Enter the prefix of the Metabase application name. A valid prefix is required. Make sure the prefix ends with a '-'."
  $METABASE_APP_PREFIX = Read-Host
  if (-not([string]::IsNullOrEmpty($METABASE_APP_PREFIX)))
  {
    $global:METABASE_APP_PREFIX = $METABASE_APP_PREFIX.Trim()
  }
  else
  {
    Write-Host -ForegroundColor red "Metabase app prefix is required."
    getMetabaseAppPrefix
  }
}
function loginToOpenshift
{
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Logging into openshift."
  oc login --token=$OPENSHIFT_TOKEN --server=$OPENSHIFT_SERVER
  oc project $NAMESPACE-tools
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Logged in to openshift."
}
function setupArtifactoryCreds
{

  Write-Host -ForegroundColor cyan "Go to 'tools' Environment of the openshift namespace, make sure you are an admin, on the left hand menu, expand workloads and click on secrets. click on the secret 'artifacts-default-****' once it opens , click on reveal values at the bottom right. That will give the user name and password which needs to be entered."
  getDockerUser
  getDockerPwd
  Write-Host -ForegroundColor $FOREGROUND_COLOR "Setting up artifactory creds."
  try
  {
    oc -n $NAMESPACE-tools create secret docker-registry artifactory-creds --docker-server=artifacts.developer.gov.bc.ca --docker-username=$DOCKER_USER --docker-password=$DOCKER_PWD --docker-email="admin@$NAMESPACE-$ENVIRONMENT.local"
  }
  catch
  {
    Write-Host -ForegroundColor red "Error setting up artifactory creds. exiting."
    exit 1
  }

  Write-Host -ForegroundColor $FOREGROUND_COLOR "Artifactory creds created."
}
function checkArtifactoryCreds
{
  $data = oc -n $NAMESPACE-tools get secret artifactory-creds -o json
  if([string]::IsNullOrEmpty($data))
  {
    $global:ARTIFACTORY_CREDS_PRESENT = "false"
  }
  else
  {
    $global:ARTIFACTORY_CREDS_PRESENT="true"
  }

}


function buildMetabase
{
    oc tag -d "$NAMESPACE-tools/metabase:$ENVIRONMENT"
    oc tag -d "$NAMESPACE-$ENVIRONMENT/metabase:$ENVIRONMENT"
    oc process -n $NAMESPACE-tools -f "$BASE_URL/metabase.bc.yaml" -p METABASE_VERSION=$METABASE_VERSION -p VERSION=$ENVIRONMENT -p DB_HOST=$DB_HOST -p DB_PORT=$DB_PORT -o yaml | oc apply -n $NAMESPACE-tools -f -
    Write-Host -ForegroundColor cyan "Metabase Image is being created, grab a cup of coffee as this might take 3-4 minutes."
    oc -n $NAMESPACE-tools start-build metabase --wait
    Write-Host -ForegroundColor $FOREGROUND_COLOR "Metabase Image build is completed."
    oc tag "$NAMESPACE-tools/metabase:$ENVIRONMENT" "$NAMESPACE-$ENVIRONMENT/metabase:$ENVIRONMENT"
    Write-Host -ForegroundColor $FOREGROUND_COLOR "Metabase Image is tagged in $($NAMESPACE)-$($ENVIRONMENT)."
    Write-Host -ForegroundColor cyan "Metabase secret is being created."
}
function deployMetabase
{
  oc process -n "$NAMESPACE-$ENVIRONMENT" -f "$BASE_URL/metabase.update.dc.yaml" -p NAMESPACE="$NAMESPACE-$ENVIRONMENT" -p VERSION=$ENVIRONMENT -o yaml | oc apply -n "$NAMESPACE-$ENVIRONMENT" -f -
  Write-Host -ForegroundColor cyan "Metabase updated, please check the pod logs for more details."
}
main
