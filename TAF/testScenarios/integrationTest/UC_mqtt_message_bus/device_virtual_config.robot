*** Settings ***
Documentation  Configrations
Resource     TAF/testCaseModules/keywords/common/commonKeywords.robot
Resource  TAF/testCaseModules/keywords/device-sdk/deviceServiceAPI.robot
Suite Setup  Run Keywords  Setup Suite
...                        AND  Run Keyword if  $SECURITY_SERVICE_NEEDED == 'true'  Get Token
...                        AND  Run Keyword And Ignore Error  Stop Services  scalability-test-mqtt-export  app-service-mqtt-export  # No data received from the both services
Suite Teardown  Run Teardown Keywords
Force Tags   MessageQueue=MQTT

*** Variables ***
${SUITE}              Configrations

*** Test Cases ***
Config001 - Set MessageQueue.Protocol to MQTT
    ${handle}  Run MQTT Subscriber Progress And Output  edgex/events/device/#
    Given Set Test Variable  ${device_name}  messageQueue-mqtt
    And Set Writable LogLevel To Debug For device-virtual On Consul
    And Create Device For device-virtual With Name ${device_name}
    When Retrive device data by device ${device_name} and command ${PREFIX}_GenerateDeviceValue_UINT8_RW
    Then Should Return Status Code "200" And event
    And Event Has Been Recevied By MQTT Subscriber
    And Event Has Been Pushed To Core Data
    [Teardown]  Run keywords  Delete device by name ${device_name}
                ...           AND  Delete all events by age
                ...           AND  Terminate Process  ${handle}  kill=True

Config002 - Modify MessageQueue.PublishTopicPrefix and receive data from the topic correctly
    Set Test Variable  ${device_name}  messagebus-true-device-5
    ${handle}  Run MQTT Subscriber Progress And Output  edgex/events/custom/#
    Given Set MessageQueue PublishTopicPrefix=edgex/events/custom For device-virtual On Consul
    And Set MessageQueue SubscribeTopic=edgex/events/custom/# For core-data On Consul
    And Create Device For device-virtual With Name ${device_name}
    When Retrive device data by device ${device_name} and command ${PREFIX}_GenerateDeviceValue_INT8_RW
    Then Should Return Status Code "200" And event
    And Event Has Been Pushed To Core Data
    And Event Has Been Recevied By MQTT Subscriber
    [Teardown]  Run keywords  Delete device by name ${device_name}
                ...           AND  Delete all events by age
                ...           AND  Terminate Process  ${handle}  kill=True
                ...           AND  Set MessageQueue PublishTopicPrefix=edgex/events/device For device-virtual On Consul
                ...           AND  Set MessageQueue SubscribeTopic=edgex/events/device/# For core-data On Consul

Config003 - Set device-virtual MessageQueue.Optional.Qos (PUBLISH)
    Given Set Test Variable  ${device_name}  messagebus-true-device-6
    And Create Device For device-virtual With Name ${device_name}
    And Set MessageQueue Optional/Qos=2 For device-virtual On Consul
    And Set MessageQueue Optional/Qos=1 For core-data On Consul
    When Retrive device data by device ${device_name} and command ${PREFIX}_GenerateDeviceValue_UINT8_RW
    Then Should Return Status Code "200" And event
    And Event Has Been Pushed To Core Data
    And Verify MQTT Broker Qos
    [Teardown]  Run keywords  Delete device by name ${device_name}
                ...           AND  Delete all events by age
                ...           AND  Set MessageQueue Optional/Qos=0 For device-virtual On Consul
                ...           AND  Set MessageQueue Optional/Qos=0 For core-data On Consul

*** Keywords ***
Set MessageQueue ${key}=${value} For ${service_name} On Consul
    ${service_layer}  Run Keyword If  "core" in "${service_name}"  Set Variable  core
                      ...    ELSE IF  "device" in "${service_name}"  Set Variable  devices
    ${path}=  Set Variable  /v1/kv/edgex/${service_layer}/${CONSUL_CONFIG_VERSION}/${service_name}/MessageQueue/${key}
    Update Service Configuration On Consul  ${path}  ${value}
    Sleep  500ms
    ${service}  Run Keyword If  "data" in "${service_name}"  Set Variable  data
                ...       ELSE  Set Variable  ${service_name}
    Restart Services  ${service}

Set Writable LogLevel To Debug For ${service_name} On Consul
    ${path}=  Set Variable  /v1/kv/edgex/devices/${CONSUL_CONFIG_VERSION}/${service_name}/Writable/LogLevel
    Update Service Configuration On Consul  ${path}  DEBUG
    Sleep  500ms

Run MQTT Subscriber Progress And Output
    [Arguments]  ${topic}
    ${current_time}  get current epoch time
    Set Test Variable  ${subscriber_file}  mqtt-subscriber-${current_time}.log
    Set Test Variable  ${error_file}  mqtt-error-${current_time}.log
    ${handle}  Start process  python ${WORK_DIR}/TAF/utils/src/setup/mqtt-subscriber.py ${topic} CorrelationID arg &
    ...                shell=True  stdout=${WORK_DIR}/TAF/testArtifacts/logs/${subscriber_file}
    ...                stderr=${WORK_DIR}/TAF/testArtifacts/logs/${error_file}
    sleep  2s
    [Return]  ${handle}

Retrive device data by device ${device_name} and command ${command}
    ${timestamp}  get current epoch time
    Get device data by device ${device_name} and command ${PREFIX}_GenerateDeviceValue_UINT8_RW with ds-pushevent=yes
    Set Test Variable  ${log_timestamp}  ${timestamp}
    sleep  500ms

Event Has Been Recevied By MQTT Subscriber
    ${logs}  Run Process  ${WORK_DIR}/TAF/utils/scripts/${DEPLOY_TYPE}/query-docker-logs.sh device-virtual ${log_timestamp}
    ...     shell=True  stderr=STDOUT  output_encoding=UTF-8
    ${correlation_line}  Get Lines Containing String  ${logs.stdout}.encode()  Correlation-ID
    ${correlation_id}  Fetch From Right  ${correlation_line}  X-Correlation-ID:
    ${correlation_id}  Fetch From Left  ${correlation_id.strip()}  "

    ${received_event}  Get file  ${WORK_DIR}/TAF/testArtifacts/logs/${subscriber_file}
    run keyword if  "${correlation_id}" not in """${received_event}"""
    ...             fail  Event is not received by mqtt subscriber

Verify MQTT Broker Qos
    ${result} =  Run Process  ${WORK_DIR}/TAF/utils/scripts/${DEPLOY_TYPE}/query-docker-logs.sh mqtt-broker ${log_timestamp}
    ...          shell=True  stderr=STDOUT  output_encoding=UTF-8
    Log  ${result.stdout}
    ${publish_log}  Get Lines Containing String  ${result.stdout}  Received PUBLISH from device-virtual
    Should Contain  ${publish_log}  q2
    ${subscribe_log}   Get Lines Containing String  ${result.stdout}  Sending PUBLISH to core-data
    Should Contain  ${subscribe_log}   q1
