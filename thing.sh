THING_NAME=$(date +%s | shasum | cut -c 1-8)
POLICY_NAME=$THING_NAME
ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS | jq -r .endpointAddress)

mkdir -p $THING_NAME && cd $THING_NAME

aws iot create-thing --thing-name $THING_NAME

wget https://www.amazontrust.com/repository/AmazonRootCA1.pem

aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile "./device.pem.crt" \
    --public-key-outfile "./public.pem.key" \
    --private-key-outfile "./private.pem.key" \
    > certs-and-keys.json

aws iot attach-thing-principal \
    --thing-name $THING_NAME \
    --principal $(jq -r .certificateArn certs-and-keys.json)

cat << EOS >> policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Publish",
                "iot:Subscribe",
                "iot:Receive",
                "iot:Connect"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOS

aws iot create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "file://policy.json"

aws iot attach-policy --policy-name "$POLICY_NAME" --target $(jq -r .certificateArn certs-and-keys.json)

cat << EOS >> sub.sh
mosquitto_sub --cafile AmazonRootCA1.pem \\
  --cert device.pem.crt \\
  --key private.pem.key \\
  -h $ENDPOINT \\
  -p 8883 \\
  -t t1 \\
  -i sub_$THING_NAME \\
  -F '%j' \\
  -d
EOS

cat << EOS >> pub.sh
mosquitto_pub --cafile AmazonRootCA1.pem \\
  --cert device.pem.crt \\
  --key private.pem.key \\
  -h $ENDPOINT \\
  -p 8883 \\
  -t t1 \\
  -i pub_$THING_NAME \\
  -m {\"id\":1} \\
  -d
EOS

chmod +x ./pub.sh
chmod +x ./sub.sh
