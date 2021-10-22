#!/usr/bin/env bash

#CF_SYS_DOMAIN="run.haas-459.pez.vmware.com"
CF_SYS_DOMAIN="sys.porcupine.cf-app.com"
CF_USER="dekel"
CF_PASSWORD="appcloud"
CF_ORG="dekt"
CF_SPACE="dekt4pets"
GATEWAY_NAME="dekt4pets-gateway"
API_PORTAL_APP_NAME="dekt-api-portal"
BACKEND_APP_NAME="dekt4pets-backend"
FRONTEND_APP_NAME="dekt4pets-frontend"
GATEWAY_CONFIG="api-config/dekt4pets-gateway.json"
BACKEND_ROUTE_CONFIG="api-config/dekt4pets-backend-routes.json"
FRONTEND_ROUTE_CONFIG="api-config/dekt4pets-frontend-routes.json"

#don't foget to add to the generate rsa cert in opsman tas tile
#*.run.haas-459.pez.vmware.com,*.login.run.haas-459.pez.vmware,*.uaa.run.haas-459.pez.vmware,*.cfapps.haas-459.pez.vmware.com

#deploy
deploy() {

    #build-project

    cf login -a api.$CF_SYS_DOMAIN -o $CF_ORG -s $CF_SPACE -u $CF_USER -p $CF_PASSWORD --skip-ssl-validation

    cf create-service p.gateway standard $GATEWAY_NAME -c $GATEWAY_CONFIG

    wait-for-gateway-creation

    cf push 

    bind-update

    cf set-env $API_PORTAL_APP_NAME API_PORTAL_SOURCE_URLS "https://scg-service-broker.$CF_SYS_DOMAIN/openapi"
}

#dynamic-routes-update
dynamic-routes-update() {

    app_name=$1
    route_config_file=$2
    
    app_guid=$(cf app "$app_name" --guid)
    gateway_service_instance_id="$(cf service $GATEWAY_NAME --guid)"
    gateway_url=$(cf curl /v2/service_instances/"$gateway_service_instance_id" | jq .entity.dashboard_url | sed "s/\/scg-dashboard//" | sed "s/\"//g")

    printf "Calling dynamic binding update endpoint for %s...\n=====\n\n" "$app_name"
    
    status_code=$(curl -k -XPUT "$gateway_url/actuator/bound-apps/$app_guid/routes" -d "@$route_config_file" \
        -H "Authorization: $(cf oauth-token)" -H "Content-Type: application/json" --write-out %{http_code} -vsS)
    
    if [[ $status_code == '204' ]]; then
        printf "\n=====\nBound app %s route configuration update response status: %s\n\n" "$app_name" "$status_code"
    else
        printf "\033[31m\n=====\nUpdate %s configuration failed\033[0m" "$app_name" >/dev/stderr
        exit 1
    fi
}

#bind-update
bind-update () {
    unbind-all
    bind-all
}
#bind-all
bind-all() {
    cf bind-service $BACKEND_APP_NAME $GATEWAY_NAME -c $BACKEND_ROUTE_CONFIG
    cf bind-service $FRONTEND_APP_NAME $GATEWAY_NAME -c $FRONTEND_ROUTE_CONFIG
}

#unbind-all
unbind-all() {
    cf unbind-service $BACKEND_APP_NAME $GATEWAY_NAME
    cf unbind-service $FRONTEND_APP_NAME $GATEWAY_NAME
}

#wait-for-gateway-creation
wait-for-gateway-creation() {
    
    echo
	printf "Waiting for $GATEWAY_NAME to create."
	while [ `cf services | grep 'in progress' | wc -l | sed 's/ //g'` != 0 ]; do
  		printf "."
  		sleep 5
	done
	echo
	echo "$GATEWAY_NAME creation completed."
	echo
}

#cleanup
cleanup() {

    unbind-all

    cf delete-service -f $GATEWAY_NAME

    cf delete -f $BACKEND_APP_NAME

    cf delete -f $FRONTEND_APP_NAME

    cf delete -f $API_PORTAL_APP_NAME


}
#build-project
build-project () {
    
    ./gradlew :frontend:npm_ci
    
    ./gradlew assemble
    
}

case $1 in
deploy)
	deploy 
    ;;
update)
    bind-update
    ;;
build)
    build-project
    ;;
update-frontend-routes)
	dynamic-routes-update $FRONTEND_APP_NAME $FRONTEND_ROUTE_CONFIG
	;;
update-backend-routes)
	dynamic-routes-update $BACKEND_APP_NAME $BACKEND_ROUTE_CONFIG
	;;
cleanup)
    cleanup
    ;;
*)
  	echo "incorrect usage. Please specify one of the following:"
    echo "  * deploy"
    echo "  * update"
    echo "  * build"
    echo "  * update-backend-routes"
    echo "  * update-frontend-routes"
    echo "  * cleanup"
  	;;
esac
