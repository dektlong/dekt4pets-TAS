#!/usr/bin/env bash

CF_SYS_DOMAIN="sys.naplesyellow.cf-app.com" #run.pcfone.io
CF_USER="admin" #SSO for pcf-one and remeber to update sso-plan to 'dekt-prod' in all gw configs
CF_PASSWORD="nxbjQ97NgRi8obO-B0Biz99N60TRwKJT"
CF_ORG="dekt-lob" #dekt-pcfone
CF_APP_SPACE="dekt4pets"
CF_BROWNFIELD_SPACE="brownfield"
CF_API_PORTAL_SPACE="api-portal"

#-------------------------------------------------------------------------------------
# do not update these vars unless you modify the manifest and api-config files as well
#-------------------------------------------------------------------------------------

#dekt4pets
dekt4pets_gw="dekt4pets-gateway"
dekt4pets_gw_config="api-config/dekt4pets-gateway.json"
dekt4pets_backend="dekt4pets-backend"
dekt4pets_backend_routes="api-config/dekt4pets-backend-routes.json"
dekt4pets_frontend="dekt4pets-frontend"
dekt4pets_frontend_routes="api-config/dekt4pets-frontend-routes.json"

#datacheck
datacheck_gw="datacheck-gateway"
datacheck_gw_config="api-config/datacheck-gateway.json"
datacheck="datacheck"
datacheck_routes="api-config/datacheck-routes.json"

#payments
#payments_gw="payments-gateway"
#payments_gw_config="api-config/payments-gateway.json"
#payments="payments"
#payments_routes="api-config/payments-routes.json"

#api-portal
api_portal="dekt-api-portal"

#deploy
deploy() {

    if [ $CF_USER = "SSO" ]; then
        cf login -a api.$CF_SYS_DOMAIN --sso -o $CF_ORG -s $CF_APP_SPACE
    else        
        cf login -a api.$CF_SYS_DOMAIN -u $CF_USER -p $CF_PASSWORD -o $CF_ORG -s $CF_APP_SPACE --skip-ssl-validation
    fi

    deploy-dekt4pets

    deploy-brownfield

    deploy-api-portal
}

#deploy-dekt4pets
deploy-dekt4pets () {

    create-gateway $dekt4pets_gw $dekt4pets_gw_config
    
    cf push -f manifest-dekt4pets.yml
    
    cf bind-service $dekt4pets_frontend $dekt4pets_gw -c $dekt4pets_frontend_routes
    cf bind-service $dekt4pets_backend $dekt4pets_gw -c $dekt4pets_backend_routes

    dynamic-routes-update $dekt4pets_frontend $dekt4pets_gw $dekt4pets_frontend_routes
    dynamic-routes-update $dekt4pets_backend $dekt4pets_gw $dekt4pets_backend_routes
    
}

#deploy-brownfield
deploy-brownfield() {

    cf target -o $CF_ORG -s $CF_BROWNFIELD_SPACE

    create-gateway $datacheck_gw $datacheck_gw_config
#    create-gateway $payments_gw $payments_gw_config

    cf push -f manifest-brownfield.yml

    cf bind-service $datacheck $datacheck_gw -c $datacheck_routes
#    cf bind-service $payments $payments_gw -c $payments_routes

    dynamic-routes-update $datacheck $datacheck_gw $datacheck_routes 
#    dynamic-routes-update $payments $payments_gw $payments_routes
}

#deploy-api-portal
deploy-api-portal () {

    cf target -o $CF_ORG -s $CF_API_PORTAL_SPACE

    cf push -f manifest-api-portal.yml
    cf set-env $api_portal API_PORTAL_SOURCE_URLS "https://scg-service-broker.$CF_SYS_DOMAIN/openapi"
    cf set-env $api_portal API_PORTAL_SOURCE_URLS_CACHE_TTL_SEC 10

    cf restage $api_portal
}
    
#dynamic-routes-update
dynamic-routes-update() {

    app_name=$1
    gateway_name=$2
    route_config_file=$3
    
    
    app_guid=$(cf app "$app_name" --guid)
    gateway_service_instance_id="$(cf service $gateway_name --guid)"
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
    
    cf target -o $CF_ORG -s $CF_APP_SPACE

    cf restage $dekt4pets_backend
    
    dynamic-routes-update $dekt4pets_backend $dekt4pets_gw $dekt4pets_backend_routes
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


#cleanup
cleanup() {

    #portal
    cf target -o $CF_ORG -s $CF_API_PORTAL_SPACE
    cf delete -f -r $api_portal
    
    #brownfield
    cf target -o $CF_ORG -s $CF_BROWNFIELD_SPACE
    cf unbind-service $datacheck $datacheck_gw
    cf unbind-service $payments $payments_gw
    cf delete-service -f $datacheck_gw
    cf delete-service -f $payments_gw
    cf delete -f -r $datacheck
    cf delete -f -r $payments
   

    #apps
    cf target -o $CF_ORG -s $CF_APP_SPACE
    cf unbind-service $dekt4pets_backend $dekt4pets_gw
    cf unbind-service $dekt4pets_frontend $dekt4pets_gw
    cf delete-service -f $dekt4pets_gw
    cf delete -f -r $dekt4pets_backend
    cf delete -f -r $dekt4pets_frontend


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
update-backend)
	update-backend
	;;
cleanup)
    cleanup
    ;;
*)
  	echo "incorrect usage. Please specify one of the following:"
    echo "  * deploy"
    echo "  * update-backend"
    echo "  * cleanup"
  	;;
esac
