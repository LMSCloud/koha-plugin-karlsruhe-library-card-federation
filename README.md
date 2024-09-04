# koha-plugin-karlsruhe-library-card-federation
## Overview
API functions for the Karlsruhe library card federation.
The plugin provides the following features:
* Plugin configuration:
  * Local card prefixes
  * Card prefixes of other federation members
  * The URL of the central card service
  * The API key of the central card service
  * Remote service IPs, that are allowed to access the service
  * Local debarment types that signal, that a local card should be blocked within the federation
  * A debarment type to set if a foreign cards is blocked 
  * A comment to set with debarments of foreign cards
* API functions to check the local status of a local library card
  * Check the local cards status using: /api/v1/contrib/kalibfed/card_status/{card_number}
  * Push a status update of a remote card: /api/v1/contrib/kalibfed/card_status
* An API function the check a remote card with in the Koha staff interface
* An implementation to check the status of foreign cards and to push status updates of local cards to the central card service
* A batch function to check local cards regularly for changes (deletes or new debarments) in order to push the changes to the central service
* A batch function to update all foreign cards based on the status received from the central service

## Installation
Just download and install the plugin. Configure the plugin and restart plack services of the instance.

## Details using the added API functions
### Service description
A description of the service is available after installation with the default API documentation: 
```
https://<KOHA-URL>/api/v1/.html
```
Look for:
* kalib-check-card-status
* kalib-get-card-status
* kalib-health-status
* kalib-set-card-status
### Test: push a card update for a foreign card number
```
curl -X 'POST' \
  'https://<KOHA-URL>/api/v1/contrib/kalibfed/card_status' \
  -H 'accept: application/json' \
  -H 'X-API-KEY: <API-KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
  "card_status": "<locked|active>",
  "card_number": "<CARD-NUMBER>"
}'
```
### Test: get the status of a local card
```
curl -X 'GET' \
  'https://<KOHA-URL>/api/v1/contrib/kalibfed/card_status/<CARD-NUMBER>' \
  -H 'accept: application/json' \
  -H 'X-API-KEY: <API-KEY>'
```

## Batch programs
### Push updates to the central card service
Run:
```
/var/lib/koha/<KOHA-INSTANCE-NAME>/plugins/Koha/Plugin/Com/LMSCloud/KarlsruheLibraryCards/pushAndUpdateLibraryCardChanges.pl
```
The program writes a log file under 
```
/var/log/koha/<KOHA-INSTANCE-NAME>/cardlib-pusher.log
```
### Retrieve the card status of all foreign cards from the central card service
Run:
```
/var/lib/koha/<KOHA-INSTANCE-NAME>/plugins/Koha/Plugin/Com/LMSCloud/KarlsruheLibraryCards/updateAllForeignCards.pl
```
If cards are blocked, a local debarment of the configured type will be added.
If cards are active and blocked locally, a possibly existing debarment of the configured type will be removed.
The program writes all output to the standard output device.

## Create a new service version
To create a new service version, you need to increase the service version in module ```KarlsruheLibraryCards.pm```. Push the update.
Create than a git version tag and push the tag to github.
```
git tag -a 'v1.0.1' -m 'Build version v1.0.1'
git push origin master v1.0.1
```
