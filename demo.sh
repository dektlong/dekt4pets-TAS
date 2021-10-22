#!/usr/bin/env bash

#CF_SYS_DOMAIN="run.haas-459.pez.vmware.com"
CF_SYS_DOMAIN="sys.porcupine.cf-app.com"
CF_USER="dekel"
CF_PASSWORD="appcloud"
CF_ORG="dekt"
CF_APP_SPACE="dekt4pets"
CF_BROWNFIELD_SPACE="brownfield"

#deploy
deploy() {

    cf login -a api.$CF_SYS_DOMAIN -o $CF_ORG -s $CF_APP_SPACE -u $CF_USER -p $CF_PASSWORD --skip-ssl-validation

    #apps
    create-gateway "dekt4pets-gateway" "api-config/dekt4pets-gateway.json"

    cf push -f manifest-apps.yml

    dynamic-routes-update "dekt4pets-backend" "api-config/dekt4pets-backend-routes.json"
    dynamic-routes-update "dekt4pets-frontend" "api-config/dekt4pets-frontend-routes.json"

    cf target -o $CF_ORG -s $CF_BROWNFIELD_SPACE

    #brownfield
    create-gateway "user-services-gateway" "api-config/user-services-gateway.json"
    create-gateway "payments-gateway" "api-config/payments-gateway.json"

    cf push -f manifest-brownfield.yml

    dynamic-routes-update "user-services" "api-config/user-services-routes.json"
    dynamic-routes-update "payments" "api-config/payments-routes.json"

    #api-portal
    cf push -f manifest-api-portal.yml




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

#update-backend
update-backend() {
    
    cf restage $BACKEND_APP_NAME
    
    dynamic-routes-update $BACKEND_APP_NAME -c $BACKEND_ROUTE_CONFIG
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

#create-gateway
create-gateway() {
    
    gatewayName=$1
    routeConfigPath=$2

    cf create-service p.gateway standard $gatewayName -c $routeConfigPath

    echo
	printf "Waiting for $gatewayName to create."
	while [ `cf services | grep 'in progress' | wc -l | sed 's/ //g'` != 0 ]; do
  		printf "."
  		sleep 5
	done
	echo
	echo "$gatewayName creation completed."
	echo
}

#add-brownfield-apis
add-brownfield-apis () {


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
update-backend)
	update-backend
	;;
	;;
cleanup)
    cleanup
    ;;
*)
  	echo "incorrect usage. Please specify one of the following:"
    echo "  * build"
    echo "  * deploy"
    echo "  * update-backend"
    echo "  * cleanup"
  	;;
esac
