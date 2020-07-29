#!/usr/bin/bash
 set -x

EXTERNAL_KEY='raspberry'
EXTERNAL_ID='pi'
MAINFLUX_HOST='mt-global.ml'
MAINFLUX_USER_EMAIL='certs@email.com'
MAINFLUX_USER_PASSWORD='12345678'
EXPORT_CONFIG_FILE_TMPL='./configs/export-config.toml.tmpl'
EXPORT_CONFIG_FILE='./configs/export-config.toml'

token=`curl -s -S -X POST https://${MAINFLUX_HOST}/tokens -d "{\"email\":\"${MAINFLUX_USER_EMAIL}\",\"password\":\"${MAINFLUX_USER_PASSWORD}\"}" -H 'Content-Type: application/json' |jq -r .token`

bootstrapResponse=`curl -s -S -X GET https://${MAINFLUX_HOST}/bootstrap/things/bootstrap/${EXTERNAL_ID} -H "Authorization: ${EXTERNAL_KEY}" -H 'Content-Type: application/json'`

clientKey=`echo "${bootstrapResponse}" | jq -r .client_key`
clientCert=$(echo "${bootstrapResponse}" | jq -r .client_cert)
caCert=`echo "${bootstrapResponse}" | jq -r .ca_cert`
thingID=`echo "${bootstrapResponse}" | jq -r .mainflux_id`
thingKey=`echo "${bootstrapResponse}" | jq -r .mainflux_key`
echo "${bootstrapResponse}"
controlChannel=`echo "${bootstrapResponse}" | jq -r '.mainflux_channels[0]'.id`
echo $controlChannel


exportChannel=`curl -s -S -X GET https://${MAINFLUX_HOST}/things/${thingID}  -H 'Content-Type: application/json' -H "Authorization: ${token}" | jq -r .metadata.export_channel_id`
echo "$clientCert" >> client.crt
echo "$clientKey" >> client.key
clientCert=$(sed  -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//'   <<<"${clientCert}")
clientKey=$(sed  -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//'   <<<"${clientKey}")


 sed -e 's,mqtt_topic =.*,mqtt_topic = \"channels/'"$exportChannel"'/messages\",g' \
     -e 's,username =.*,username = '"\"${thingID}\""',g' \
     -e 's,password =.*,password = '"\"${thingKey}\""',g' \
     -e 's,client_cert =.*,client_cert = '"'''${clientCert}'''"',g' \
     -e 's,client_cert_key =.*,client_cert_key = '"'''${clientKey}'''"',g' ${EXPORT_CONFIG_FILE_TMPL}>${EXPORT_CONFIG_FILE}

# this will create encoded payload of configs/export-config.toml
payload=`go run cmd/encode/main.go`


# Send export configuration
mosquitto_pub -d -L mqtts://${thingID}:${thingKey}@${MAINFLUX_HOST}:8883/channels/$controlChannel/messages/req  --cert  `pwd`/client.crt --key `pwd`/client.key --cafile `pwd`/ca.crt -m  '[{"bn":"1:", "n":"config", "vs":"save, export, export-config.toml, '"${payload}"'"}]'
sleep 2
# Start the export service
mosquitto_pub -d -L mqtts://${thingID}:${thingKey}@${MAINFLUX_HOST}:8883/channels/$controlChannel/messages/req  --cert  `pwd`/client.crt --key `pwd`/client.key --cafile `pwd`/ca.crt -m  '[{"bn":"1:", "n":"exec", "vs":"export_start, test"}]'

