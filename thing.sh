#!/bin/bash

# Check for aws command existence
type aws > /dev/null 2>&1
if [ $? != 0 ]; then
    echo "aws command not found."
    exit 1
fi

THING_NAME=$(date +%s | shasum | cut -c 1-8)
POLICY_NAME=$THING_NAME

echo "Creating Thing and its associated certificates..."
ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --output text --query 'endpointAddress')

mkdir -p $THING_NAME && cd $THING_NAME

# Create thing
aws iot create-thing --thing-name $THING_NAME \
--attribute-payload '{"attributes": {"type": "device", "location": "tokyo", "model": "v1"}}' \
--output text \
--query 'thingName' > /dev/null
echo "Created Thing: $THING_NAME"

# Download root certificate
wget -q https://www.amazontrust.com/repository/AmazonRootCA1.pem
echo "Downloaded root CA certificate."

# Create keys and certificates for the thing and save to the directory
CERTIFICATE_ARN=$(aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile "./device.pem.crt" \
    --public-key-outfile "./public.pem.key" \
    --private-key-outfile "./private.pem.key" \
    --query "certificateArn" --output text)

CERTIFICATE_ID=$(echo $CERTIFICATE_ARN | awk -F/ '{print $NF}')

echo "Created keys and certificates for the Thing."
echo "Certificate ID: $CERTIFICATE_ID"
echo "Certificate ARN: $CERTIFICATE_ARN"

# Attach the thing to its principal
aws iot attach-thing-principal --thing-name $THING_NAME --principal $CERTIFICATE_ARN
echo "Attached Thing to its principal."

echo "Creating and attaching policy..."
# Create policy
aws iot create-policy --policy-name "$POLICY_NAME" --policy-document '{"Version": "2012-10-17","Statement": [{"Effect": "Allow","Action": ["iot:Publish","iot:Subscribe","iot:Receive","iot:Connect"],"Resource": ["*"]}]}'> /dev/null
echo "Created policy: $POLICY_NAME"

# Attach the policy
aws iot attach-policy --policy-name "$POLICY_NAME" --target $CERTIFICATE_ARN
echo "Attached policy to Thing."

echo "Generating MQTT scripts..."
# Generate MQTT scripts
cat << EOS > sub.sh
mosquitto_sub --cafile AmazonRootCA1.pem \\
  --cert device.pem.crt \\
  --key private.pem.key \\
  -h $ENDPOINT \\
  -p 8883 \\
  -t t1 \\
  -i s$THING_NAME \\
  -F '%j' \\
  -d
EOS

cat << EOS > pub.sh
TIME=\$(date "+%Y-%m-%dT%H:%M:%S%z")
mosquitto_pub --cafile AmazonRootCA1.pem \\
  --cert device.pem.crt \\
  --key private.pem.key \\
  -h $ENDPOINT \\
  -p 8883 \\
  -t t1 \\
  -i p$THING_NAME \\
  -m {\"time\":\"\$TIME\"} \\
  -d
EOS

chmod +x ./pub.sh ./sub.sh
echo "Generated MQTT publish and subscribe scripts."

echo "Process completed!"
