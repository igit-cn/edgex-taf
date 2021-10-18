*** Settings ***
Documentation  Configrations
Resource     TAF/testCaseModules/keywords/common/commonKeywords.robot
Resource     TAF/testCaseModules/keywords/device-sdk/deviceServiceAPI.robot
Suite Setup  Run Keywords  Setup Suite
...                   AND  Run Keyword if  $SECURITY_SERVICE_NEEDED == 'true'  Get Token
Suite Teardown  Run Keywords  Delete all events by age
                ...      AND  Run Teardown Keywords
Force Tags  MessageQueue=redis

*** Variables ***
${SUITE}              Configrations

*** Test Cases ***
Config001 - Verify the return value when Data Transform is true and shift field is set
    ${set_data}  Create Dictionary  Virtual_DeviceValue_UINT32_RW=4294901760
    Given Create Device For ${SERVICE_NAME} With Name Transform-Device-1
    And Set specified device ${device_name} write command ${PREFIX}_GenerateDeviceValue_UINT32_RW with ${set_data}
    When Retrive device data by device ${device_name} and command ${PREFIX}_DeviceValue_UINT32_RW
    Then Should return status code "200"
    And Should Return Content-Type "application/json"
    And Response Time Should Be Less Than "${default_response_time_threshold}"ms
    And Should Be Equal As Integers  65535  ${content}[event][readings][0][value]
    [Teardown]  Delete device by name ${device_name}

Config002 - Verify the return value when Data Transform is false and shift field is set
    ${set_data}  Create Dictionary  Virtual_DeviceValue_UINT32_RW=4294901760
    Given Set Device DataTransform to false For device-virtual On Consul
    And Create Device For ${SERVICE_NAME} With Name Transform-Device-2
    And Set specified device ${device_name} write command ${PREFIX}_GenerateDeviceValue_UINT32_RW with ${set_data}
    When Retrive device data by device ${device_name} and command ${PREFIX}_DeviceValue_UINT32_RW
    Then Should return status code "200"
    And Should Return Content-Type "application/json"
    And Response Time Should Be Less Than "${default_response_time_threshold}"ms
    And Should Be Equal As Integers  4294901760  ${content}[event][readings][0][value]
    [Teardown]  Run Keywords  Delete device by name ${device_name}
                ...      AND  Set Device DataTransform to true For device-virtual On Consul

Config003 - Verify LastConnected data when UpdateLastConnected is false
    Given Create Device For ${SERVICE_NAME} With Name Last-Connected-False
    And Retrive device data by device ${device_name} and command ${PREFIX}_GenerateDeviceValue_UINT8_RW
    When Query device by name  ${device_name}
    Then Should return status code "200"
    And Should Return Content-Type "application/json"
    And Response Time Should Be Less Than "${default_response_time_threshold}"ms
    And Dictionary Should Not Contain Key  ${content}[device]  lastConnected
    [Teardown]  Delete device by name ${device_name}

Config004 - Verify LastConnected data when UpdateLastConnected is true
    [Setup]  Set Device UpdateLastConnected to true For device-virtual On Consul
    Given Create Device For ${SERVICE_NAME} With Name Last-Connected-True
    And Retrive device data by device ${device_name} and command ${PREFIX}_GenerateDeviceValue_UINT8_RW
    When Query device by name  ${device_name}
    Then Should return status code "200"
    And Should Return Content-Type "application/json"
    And Response Time Should Be Less Than "${default_response_time_threshold}"ms
    And LastConnected Is Not Empty And Later Then ${timestamp}
    [Teardown]  Run Keywords  Set Device UpdateLastConnected to false For device-virtual On Consul
                ...      AND  Delete device by name ${device_name}



*** Keywords ***
Set Device ${config} to ${value} For ${service_name} On Consul
    ${path}=  Set Variable  /v1/kv/edgex/devices/${CONSUL_CONFIG_VERSION}/${service_name}/Device/${config}
    Update Service Configuration On Consul  ${path}  ${value}
    Sleep  500ms
    Restart Services  device-virtual

Retrive device data by device ${device_name} and command ${command}
    ${timestamp}  Get current milliseconds epoch time
    Get device data by device ${device_name} and command ${command} with ds-pushevent=yes
    Set Test Variable  ${timestamp}  ${timestamp}
    sleep  500ms

LastConnected Is Not Empty And Later Then ${timestamp}
    Should Not Be Empty  str(${content}[device][lastConnected])
    Should Be True  float(${content}[device][lastConnected]) > float(${timestamp})