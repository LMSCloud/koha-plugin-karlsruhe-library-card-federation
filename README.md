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
  * Local debarment types that signal, that a local card shoudl be blocked within the federation
  * A debarment type to set if a foreign cards is blocked 
  * A comment to set with debarments of foreign cards
* API functions to check the local status of a local library card
  * Check the local cards status using: /api/v1/contrib/kalibfed/card_status/{card_number}
  * Push a status update of a remote card: /api/v1/contrib/kalibfed/card_status
* An API function the check a remote card with in the Koha staff interface
* An implementation to check the status of foreign cards udn push status update of local cards to the central card service
* A batch function to check local cards regularly for changes (deletes or new debarments) in order to push the changes to the central service
* A batch function to update all foreign cards based on the status received from the central service

## Installation
Just download and install the plugin. Configure the plugin and restart plack services of the instance.

## Details using the added API functions
### Service description
A description of the service is available after installation with the default API documentation: http://<KOHA-URL>/api/v1/.html
Look for:
* kalib-check-card-status
* kalib-get-card-status
* kalib-health-status
* kalib-set-card-status**
### Test: push a card update for an foreign card number
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
The program writes a Log file under 
```
/var/log/koha/<KOHA-INSTANCE-NAME>/cardlib-pusher.log
```
### Retrieve the card status of all oreign cards from the central card service
Run:
```
/var/lib/koha/<KOHA-INSTANCE-NAME>/plugins/Koha/Plugin/Com/LMSCloud/KarlsruheLibraryCards/updateAllForeignCards.pl
```
If cards are blocked a local debarment of the configured type will bed added.
If cards are active and blocked locally, an possibly existing debarment  of the configured type will be removed.
The program writes all output to the standard output device.
