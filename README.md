# Dekt4Pets on TAS

## Deploy
Sample app for VMware's Spring Cloud Gateway commercial products on TAS.

- Routing traffic to configured internal routes with container-to-container network
- Gateway routes configured through service bindings
- Simplified route configuration
- SSO login and token relay on behalf of the routed services
- Required scopes on routes (tag: `require-sso-scopes`)
- Circuit breaker filter
- api-portal on TAS
- 'brownfield' api dynamic updates


> **_NOTE:_** update vars in the `demo.sh` script. (orgs and space needs to exist prior to running)

Run the following scripts to set up everything:
```bash
./demo.sh build    # installs dependencies and builds the deployment artifact
./demo.sh deploy  # handles everything you need to deploy the frontend, backend, gateway and api-portal
```
Then visit the frontend url `https://dekt4pets.${appsDomain}/rescue` to view the sample app.

API-portal is available at `https://dekt-api-portal.${appsDomain}/apis`

All the gateway configuration can be found and updated here:

- Gateway service instance configuration file used on create/update: `api-config/dekt4pets-backend-routes.json` 
- Frontend routes configuration used on binding used on bind: `api-config/dekt4pets-frontend-routes.json`
- Backend routes configuration used on binding used on bind:`api-config/dekt4pets-gateway.json` 

## Update

- Add the following to `api-config/dekt4pets-backend-routes.json` 
```
{
      "title": "Check adopter.",
      "description": "Check adopter background.",
      "path": "/api/check-adopter",
      "method": "GET",
      "filters": [ "RateLimit=2,10s" ],
      "tags": ["pets"]
},
```
- Add the following to `backend/src/main/java/io/spring/cloud/samples/animalrescue/backend/AnimalController.java`
```
    @GetMapping("/check-adopter")
	public String checkAdopter(Principal adopter) {

		if (adopter == null) {
			return "Error: Invalid adopter ID";
		}

		String adopterID = adopter.getName();
    
		String adoptionHistoryCheckURI = "UPDATE_FROM_API_PORTAL" + adopterID;

   		RestTemplate restTemplate = new RestTemplate();
		
		  try
		  {
   			String result = restTemplate.getForObject(adoptionHistoryCheckURI, String.class);
		  }
		  catch (Exception e) {}

  		return "<h1>Congratulations,</h1>" + 
				"<h2>Adopter " + adopterID + ", you are cleared to adopt your next best friend.</h2>";
	} = "UPDATE_FROM_API_PORTAL" + adopterID;

   		RestTemplate restTemplate = new RestTemplate();
		
		  try
		  {
   			String result = restTemplate.getForObject(adoptionHistoryCheckURI, String.class);
		  }
		  catch (Exception e) {}

  		return "<h1>Congratulations,</h1>" + 
				"<h2>Adopter " + adopterID + ", you are cleared to adopt your next best friend.</h2>";
	}
```
- In API-portal show how devs 'discover' the "user-services" brownfield and update `adoptionHistoryCheckURI`

- run `./demo.sh update-backend` , which will invoke the following
	- restage the backend app
	- update backend routes using dynamic-routing 

- navigate to api-portal and show the new added api `check-adopter` 

- run this api: `https://dekt4pets.${appsDomain}/api/check-adopter`