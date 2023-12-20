--[[----------------------------------------------------------------------------

  Application Name:
  DeviceDiscovery

  Summary:
  Introduction to device scanning and configuration.

  Description:
  This application can be used to scan specific network interfaces for SICK-devices.
  It includes a specific user interface, which can be used to:
    - specify the interface, which should be scanned.
    - show the resuls of the scan in a table.
      Scan results can be selected for configuration and indentification in the table. This will
      automaticly fill the configuration and identify fields.
    - configure a device.
    - identify a device.

  How to run:
  Connect a web-browser to the device IP-Address and you will see the webpage of this sample.

------------------------------------------------------------------------------]]

--Start of Global Scope---------------------------------------------------------

--serve events for access via the user interface
Script.serveEvent("DeviceDiscovery.ScansChanged","ScansChanged")
Script.serveEvent("DeviceDiscovery.SelectionChanged","SelectionChanged")
Script.serveEvent("DeviceDiscovery.DHCPChanged","DHCPChanged")
Script.serveEvent("DeviceDiscovery.ScanRunningStateChanged","ScanRunningStateChanged")

--parameters used for configuring
local configMacAddress = ""
local configIpAddress = ""
local configSubnetMask = ""
local configDefaultGateway = ""
local configDhcpEnabled = false

--parameters used for beeping
local beepTime = 2000
local beepMAC = ""

--create the handle used for scanning, configuring and beeping
local deviceScanner = Command.Scan.create()

--flag to trigger a demo-mode
local demoMode = true

--currently used interface
local currentInterface = "ALL"

--results of last scan
local currentScans = "[]"

---Scan multiple interfaces at the same time
---@param interfaces EthernetInterfaces[]
---@return Command.Scan.DeviceInfo[]
local function multiScan(interfaces)

  local hTasks = {}
  local hScanner = {}
  local hFuture = {}
  local hDevices = {}

  -- set up tasks
  for key,interface in pairs(interfaces) do
    hTasks[key] = Engine.AsyncFunction.create()
    hScanner[key] = Command.Scan.create()
    Command.Scan.setInterface(hScanner[key], interface)
    Engine.AsyncFunction.setFunction(hTasks[key], "Command.Scan.scan", hScanner[key])
  end

  -- launch tasks
  for i,task in pairs(hTasks) do
    hFuture[i] = Engine.AsyncFunction.launch(task)
  end

  -- wait until finished
  for i,handle in pairs(hFuture) do
    hDevices[i] = Engine.AsyncFunction.Future.wait(handle)
  end

  return(hDevices)
end

---Create the string representing the devices for displaying in tabelview
---@param devices Command.Scan.DeviceInfo[]
---@return string
local function getDevicesJSON(devices)
  local scans = ""
  for _,value in pairs(devices) do
    scans = scans .. "{"
    scans = scans .. "\"deviceName\":\""      .. tostring(Command.Scan.DeviceInfo.getDeviceName(value))        .. "\","
    scans = scans .. "\"locationName\":\""    .. tostring(Command.Scan.DeviceInfo.getLocationName(value))      .. "\","
    scans = scans .. "\"serialNumber\":\""    .. tostring(Command.Scan.DeviceInfo.getSerialNumber(value))      .. "\","
    scans = scans .. "\"firmwareVersion\":\"" .. tostring(Command.Scan.DeviceInfo.getFirmwareVersion(value))   .. "\","
    scans = scans .. "\"macAddress\":\""      .. tostring(Command.Scan.DeviceInfo.getMACAddress(value))        .. "\","
    scans = scans .. "\"ipAddress\":\""       .. tostring(Command.Scan.DeviceInfo.getIPAddress(value))         .. "\","
    scans = scans .. "\"subnetMask\":\""      .. tostring(Command.Scan.DeviceInfo.getSubnetMask(value))        .. "\","
    scans = scans .. "\"defaultGateway\":\""  .. tostring(Command.Scan.DeviceInfo.getDefaultGateway(value))    .. "\","
    if(Command.Scan.DeviceInfo.getDHCPClientEnabled(value)) then
      scans = scans .. "\"dhcpEnabled\":true"
    else
      scans = scans .. "\"dhcpEnabled\":false"
    end
    scans = scans .. "},"
    print(Command.Scan.DeviceInfo.getDeviceName(value), Command.Scan.DeviceInfo.getProtocolType(value))
  end
  return scans
end

---This function is used to scan for devices via the specified interface.
---After the scan is finished, the results are serialized into JSON and published
---via the event "ScanChanged".
local function scan()
  Script.notifyEvent("ScanRunningStateChanged",true)
  Script.notifyEvent("ScansChanged", "[]")
  local devices
  if(currentInterface == "ALL") then
    devices = multiScan(Engine.getEnumValues("EthernetInterfaces"))
  else
    devices = Command.Scan.scan(deviceScanner,5000)
  end
  Script.notifyEvent("ScanRunningStateChanged",false)
  --build the JSON-string of the scan-results to be shown in the table
  local scans = "["
  if(currentInterface == "ALL") then
    for _,value in pairs(devices) do
      scans = scans .. getDevicesJSON(value)
    end
  else
    scans = scans .. getDevicesJSON(devices)
  end
  if(scans:len() > 1) then
    scans = scans:sub(1, -2) .. "]"
  else
    scans = scans .. "]"
  end
  Script.notifyEvent("ScansChanged", scans)
  currentScans = scans
end

---@return bool
local function config()
  --if demo-mode is activated, just print the parameters of the configuration
  if(demoMode) then
    print(configMacAddress)
    print(configIpAddress)
    print(configSubnetMask)
    print(configDefaultGateway)
    print(configDhcpEnabled)
    return configDhcpEnabled
  else
    local success =
      Command.Scan.configure(
      deviceScanner,
      configMacAddress,
      configIpAddress,
      configSubnetMask,
      configDefaultGateway,
      configDhcpEnabled
    )
    scan()
    return success
  end
end

---@return bool
local function beep()
  --if demo-mode is activated, just print the parameters of the beep
  if(demoMode) then
    print(beepMAC)
    print(beepTime)
    return (beepTime > 10)
  else
    return Command.Scan.beep(deviceScanner, beepMAC, beepTime)
  end
end

---@param interface EthernetInterfaces
local function setInterface(interface)
  currentInterface = interface
  Command.Scan.setInterface(deviceScanner,interface)
end

---This function is triggered, when the user selects a row in the table.
---It parses the parameters for the device-configuration out of the incoming
---JSON-string. The values of the parmeters are then set as values of the
---global variables used for the configuration and beeping.
---@param selection string
local function setSelectionToConfig(selection)
  if(nil ~= selection) then
    Script.notifyEvent("SelectionChanged", selection)
    local macInd = selection:find("\"macAddress\":\"")
    local macStart = macInd + 14
    local macEnd = selection:find("\"", macStart + 1) - 1
    configMacAddress = selection:sub(macStart, macEnd)
    beepMAC = configMacAddress
    local ipInd = selection:find("\"ipAddress\":\"")
    local ipStart = ipInd + 13
    local ipEnd = selection:find("\"", ipStart + 1) - 1
    configIpAddress = selection:sub(ipStart, ipEnd)
    local subnetInd = selection:find("\"subnetMask\":\"")
    local subnetStart = subnetInd + 14
    local subnetEnd = selection:find("\"", subnetStart + 1) - 1
    configSubnetMask = selection:sub(subnetStart, subnetEnd)
    local gatewayInd = selection:find("\"defaultGateway\":\"")
    local gatewayStart = gatewayInd + 18
    local gatewayEnd = selection:find("\"", gatewayStart + 1) - 1
    configDefaultGateway = selection:sub(gatewayStart, gatewayEnd)
    local dhcpInd = selection:find("\"dhcpEnabled\":")
    local dhcpStart = dhcpInd + 14
    local dhcpEnd = selection:find("}", dhcpStart + 1) - 1
    local enabled = selection:sub(dhcpStart, dhcpEnd)
    if(enabled == "true") then
      configDhcpEnabled = true
    else
      configDhcpEnabled = false
    end
    Script.notifyEvent("DHCPChanged", configDhcpEnabled)
  end
end

---@param macAddress string
local function setConfigMacAddress(macAddress)
  configMacAddress = macAddress
end

---@param ipAddress string
local function setConfigIpAddress(ipAddress)
  configIpAddress = ipAddress
end

---@param subnetMask string
local function setConfigSubnetMask(subnetMask)
  configSubnetMask = subnetMask
end

---@param defaultGateway string
local function setConfigDefaultGateway(defaultGateway)
  configDefaultGateway = defaultGateway
end

---@param dhcpEnabled bool
local function setConfigDHCPEnabled(dhcpEnabled)
  configDhcpEnabled = dhcpEnabled
  Script.notifyEvent("DHCPChanged", configDhcpEnabled)
end

---@param time int
local function setBeepTime(time)
  beepTime = time
end

---@return int
local function getBeepTime()
  return beepTime
end

---@param macAddress string
local function setBeepMAC(macAddress)
  beepMAC = macAddress
end

---@return bool
local function getConfigDHCP()
  Script.notifyEvent("DHCPChanged", configDhcpEnabled)
  return configDhcpEnabled
end

---@return string
local function getInterfaces()
  local interfaces = Engine.getEnumValues("EthernetInterfaces")
  local res = "[{\"label\":\"ALL\",\"value\":\"ALL\"}"
  for _,value in pairs(interfaces) do
    res = res .. ",{" .. "\"label\":\"" .. value .. "\",\"value\":\"" .. value .. "\"}"
  end
  res = res .. "]"
  return res
end

---@return string
local function getCurrentConfigMAC()
  return configMacAddress
end

---@return string
local function getCurrentConfigIP()
  return configIpAddress
end

---@return string
local function getCurrentConfigSubnet()
  return configSubnetMask
end

---@return string
local function getCurrentConfigGateway()
  return configDefaultGateway
end

---@return boolean
local function getCurrentConfigDHCP()
  return configDhcpEnabled
end

---@return string
local function getCurrentInterface()
  return currentInterface
end

---@return string
local function getCurrentScans()
  return currentScans
end

--servce functions for acces via the user interface
Script.serveFunction("DeviceDiscovery.scan",scan)
Script.serveFunction("DeviceDiscovery.setInterface",setInterface)
Script.serveFunction("DeviceDiscovery.config",config)
Script.serveFunction("DeviceDiscovery.beep",beep)
Script.serveFunction("DeviceDiscovery.setSelectionToConfig",setSelectionToConfig)
Script.serveFunction("DeviceDiscovery.setConfigMacAddress",setConfigMacAddress)
Script.serveFunction("DeviceDiscovery.setConfigIpAddress",setConfigIpAddress)
Script.serveFunction("DeviceDiscovery.setConfigSubnetMask",setConfigSubnetMask)
Script.serveFunction("DeviceDiscovery.setConfigDefaultGateway",setConfigDefaultGateway)
Script.serveFunction("DeviceDiscovery.setConfigDHCPEnabled",setConfigDHCPEnabled)
Script.serveFunction("DeviceDiscovery.setBeepTime",setBeepTime)
Script.serveFunction("DeviceDiscovery.getBeepTime",getBeepTime)
Script.serveFunction("DeviceDiscovery.setBeepMAC",setBeepMAC)
Script.serveFunction("DeviceDiscovery.getConfigDHCP",getConfigDHCP)
Script.serveFunction("DeviceDiscovery.getInterfaces",getInterfaces)
Script.serveFunction("DeviceDiscovery.getCurrentConfigMAC",getCurrentConfigMAC)
Script.serveFunction("DeviceDiscovery.getCurrentConfigIP",getCurrentConfigIP)
Script.serveFunction("DeviceDiscovery.getCurrentConfigSubnet",getCurrentConfigSubnet)
Script.serveFunction("DeviceDiscovery.getCurrentConfigGateway",getCurrentConfigGateway)
Script.serveFunction("DeviceDiscovery.getCurrentConfigDHCP",getCurrentConfigDHCP)
Script.serveFunction("DeviceDiscovery.getCurrentInterface",getCurrentInterface)
Script.serveFunction("DeviceDiscovery.getCurrentScans",getCurrentScans)
