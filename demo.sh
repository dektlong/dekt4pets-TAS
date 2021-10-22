#!/usr/bin/env bash

#CF_SYS_DOMAIN="run.haas-459.pez.vmware.com"
CF_SYS_DOMAIN="sys.porcupine.cf-app.com"
CF_USER="dekel"
CF_PASSWORD="appcloud"
CF_ORG="dekt"
CF_APP_SPACE="dekt4pets"
CF_BROWNFIELD_SPACE="brownfield"

#-------------------------------------------------------------------------------------
# do not update these vars unless you modify the manifest and api-config files as well
#-------------------------------------------------------------------------------------
#dekt4pets
dekt4petsGatewayName="dekt4pets-gateway"
det4petsGatewayConfig="api-config/dekt4pets-gateway.json"
dekt4petsBackendName="dekt4pets-backend"
dekt4petsBackendRoutesConfig="api-config/dekt4pets-backend-routes.json"
dekt4petsFrontendName="dekt4pets-frontend"
dekt4petsFrontendRoutesConfig="api-config/dekt4pets-frontend-routes.json"
#user-services
userServicesGatewayName="user-services-gateway"
userServicesGatewayConfig="api-config/user-services-gateway.json"
userServicesAppName="user-services"
userServicesRoutesConfig="api-config/user-services-gateway.json"
#payments
paymentsGatewayName="payments-gateway"
userServicesGatewayConfig="api-config/payments-gateway.json"
paymentsAppName="payments"
paymentsRoutesConfig="api-config/payments-gateway.json"
#api-portal
apiPortalAppName="dekt-api-portal"

#deploy
deploy() {

    cf login -a api.$CF_SYS_DOMAIN -o $CF_ORG -s $CF_APP_SPACE -u $CF_USER -p $CF_PASSWORD --skip-ssl-validation

    #apps
    create-gateway $dekt4petsGatewayName $det4petsGatewayConfig

    cf push -f manifest-apps.yml

    dynamic-routes-update $dekt4petsBackendName $dekt4petsBackendRoutesConfig
    dynamic-routes-update $dekt4petsFrontendName $dekt4petsFrontendRoutesConfig

    cf target -o $CF_ORG -s $CF_BROWNFIELD_SPACE

    #brownfield
    create-gateway $userServicesGatewayName $userServicesGatewayConfig
    create-gateway $paymentsGatewayName $userServicesGatewayConfig

    cf push -f manifest-brownfield.yml

    dynamic-routes-update $userServicesAppName $userServicesRoutesConfig
    dynamic-routes-update $paymentsAppName $paymentsRoutesConfig

    #api-portal
    cf push -f manifest-api-portal.yml
    cf set-env $apiPortalAppName API_PORTAL_SOURCE_URLS: "https://scg-service-broker.$CF_SYS_DOMAIN/openapi"
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

    #brownfield
    cf target -o $CF_ORG -s $CF_BROWNFIELD_SPACE
    cf unbind-service $userServicesAppName $userServicesGatewayName
    cf unbind-service $paymentsAppName $paymentssGatewayName
    cf delete-service -f $userServicesGatewayName
    cf delete-service -f $paymentsGatewayName
    cf delete -f $userServicesAppName
    cf delete -f $paymentsAppName
    cf delete -f $apiPortalAppName

    #apps
    cf target -o $CF_ORG -s $CF_APP_SPACE
    cf unbind-service $dekt4petsBackendName $dekt4petsGatewayName
    cf unbind-service $dekt4petsFrontenddName $dekt4petsGatewayName
    cf delete-service -f $dekt4petsGatewayName
    cf delete -f $dekt4petsBackendName
    cf delete -f $dekt4petsFrontenddName


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
