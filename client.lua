local lPostal

local function isAllSpaces(input)
	return input:match("^%s*$") ~= nil
end

local function generateVehicleData(vehicleEntity)
	local vehicleData = {
		entity = NetworkGetNetworkIdFromEntity(vehicleEntity),
		model = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicleEntity))),
		plate = GetVehicleNumberPlateText(vehicleEntity)
	}
	return vehicleData
end

local function getNearestCamera(baseCoords)
	local tCameraObject = GetClosestObjectOfType(baseCoords, 10.0, `prop_traffic_cam`, false, true, true)
	local tRadarObject = GetClosestObjectOfType(baseCoords, 50.0, `radar01`, false, true, true)

	if tCameraObject == 0 then
		if tRadarObject == 0 then
			return nil
		else
			return tRadarObject
		end
	else
		return tCameraObject
	end
end

local function isSpeeding(playerVehicle)
	local cVehicleSpeed = GetEntitySpeed(playerVehicle) * 2.23694
	local cSpeedLimit = exports["speedlimit"]:GetCurrentSpeed()
	local cSpeedDiff = cVehicleSpeed - cSpeedLimit

	if cSpeedDiff >= 5 then
		return true,
			tostring(math.floor(cVehicleSpeed)) ..
			" MPH in a " .. tostring(cSpeedLimit) .. " MPH zone. " .. tostring(math.floor(cSpeedDiff)) .. " MPH over."
	else
		return false, math.floor(cSpeedDiff)
	end
end

local requestedData = {}
local plateInfoReturn = nil
local function getPlateInformation(playerVehicle)
	local plateText = GetVehicleNumberPlateText(playerVehicle)
	if plateText == nil or isAllSpaces(plateText) then return nil end

	if requestedData[plateText] == nil then
		TriggerServerEvent("tcApiPlateReq", GetVehicleNumberPlateText(playerVehicle))
	else
		if GetGameTimer() > requestedData[plateText].expire then
			TriggerServerEvent("tcApiPlateReq", GetVehicleNumberPlateText(playerVehicle))
		else
			return requestedData[plateText].data
		end
	end

	repeat
		Wait(0)
	until plateInfoReturn ~= nil

	local plateInfo = json.decode(plateInfoReturn)
	plateInfoReturn = nil

	-- Cache
	requestedData[plateText] = {
		expire = GetGameTimer() + (60000 * 5),
		data = plateInfo
	}

	return plateInfo
end
RegisterNetEvent("tcApiPlateReturn", function(returnData)
	plateInfoReturn = returnData
end)

local function isBoloActive(dataSections)
	for _, data in pairs(dataSections) do
		if data.label == "Status" then
			local value = data.fields[1].value

			if value == 0 then
				return true
			else
				return false
			end
		end
	end

	return false
end

local function isOffense(playerVehicle)
	local iThereOffense = false
	local oList = {}

	-- SPEED OFFENSE
	local speeding, speedDiff = isSpeeding(playerVehicle)
	if speeding then
		iThereOffense = true
		oList["Speeding"] = speedDiff
	end

	-- PLATE / LOOKUP BASED OFFENSES
	local plateData = getPlateInformation(playerVehicle)

	for i, data in pairs(plateData) do
		-- VEHICLE REG
		if data.recordTypeId == 5 then
			for _, section in pairs(data.sections) do
				-- Flags
				-- temp like this, so I can print out that data
				if section.label == "Flags" then
					for _, flag in pairs(section.fields[1].data.flags) do
						-- STOLEN FLAG
						if flag == "STOLEN" then
							iThereOffense = true
							oList["WARNING"] = "Vehicle is reported stolen."
						end
					end
				end

				-- Veh Reg
				if section.label == "Registration Information" then
					for _, regData in pairs(section.fields) do
						print(regData.label, regData.value, type(regData.value))
						-- DMV Status
						if regData.label == "DMV Status" then
							if regData.value == "0" then
								iThereOffense = true
								oList["Registration DMV Status"] = "is still pending."
								print("dmv - pending")
							elseif regData.value == "2" then
								iThereOffense = true
								oList["Registration DMV Status"] = "is rejected."
								print("dmv - rejceted")
							end
							-- Registration Status
						elseif regData.label == "Status" then
							if regData.value == "PENDING" then
								iThereOffense = true
								oList["Registration"] = "is pending."
								print("reg - pending")
							elseif regData.value == "EXPIRED" then
								iThereOffense = true
								oList["Registration"] = "is expired."
								print("reg - expired")
							elseif regData.value == "SUSPENDED" then
								iThereOffense = true
								oList["Registration"] = "is suspended."
								print("reg - suspended")
							elseif regData.value == "STOLEN" then
								iThereOffense = true
								oList["WARNING"] = "Vehicle is reported stolen."
							end
						end
					end
				end
			end
			-- BOLO	
		elseif data.recordTypeId == 3 then
			local isActive = isBoloActive(data.sections)
			for _, section in pairs(data.sections) do
				if section.label == "Bolo Information" then
					for _, field in pairs(section.fields) do
						if field.label == "BOLO INFORMATION TYPE" then
							if field.value == "WARRANT" then
								iThereOffense = true
								oList["BOLO"] = "Registered Owner has a Active Warrant."
								goto skip
							end
						elseif field.label == "REASON FOR THE BOLO" then
							iThereOffense = true
							oList["BOLO"] = field.value
							goto skip
						end
					end
				end
			end
		end

		::skip::
	end

	if iThereOffense then
		return true, oList
	else
		return false, nil
	end
end

Citizen.CreateThread(function()
	while true do
		Wait(50)
		local playerPed = PlayerPedId()
		local playerVehicle = GetVehiclePedIsIn(playerPed, false)

		if playerVehicle ~= 0 and GetVehicleNumberPlateTextIndex(playerVehicle) ~= 4 then
			local playerCoords = GetEntityCoords(playerPed)
			local nearestCamera = getNearestCamera(playerCoords)
			local cPostal = exports["nearest-postal"]:getPostal()

			if nearestCamera and cPostal ~= nil and cPostal ~= lPostal then
				-- Set Postal
				lPostal = cPostal

				-- Get Offense Data
				local isThereOffense, offenseData = isOffense(playerVehicle)

				if isThereOffense then
					-- Street Data
					local hStreet, hCross = GetStreetNameAtCoord(playerCoords[1], playerCoords[2], playerCoords[3])
					local streetName, crossStreet = GetStreetNameFromHashKey(hStreet), GetStreetNameFromHashKey(hCross)
					local street

					if crossStreet then street = streetName .. " / " .. crossStreet else street = streetName end

					-- Perform API
					TriggerServerEvent("triggerTrafficCam911",
						cPostal,
						street,
						streetName,
						GetVehicleNumberPlateText(playerVehicle),
						generateVehicleData(playerVehicle),
						offenseData
					)

					Wait(2000)
				end
			end
		end
	end
end)

local function addSpacesBetweenCharacters(input)
	local output = input:gsub(".", "%0 ")

	return output:sub(1, -2) -- Remove the trailing space
end

local streetTypes = {
	["St"] = "Street",
	["Ave"] = "Avenue",
	["Rd"] = "Road",
	["Blvd"] = "Boulevard",
	["Ct"] = "Court",
	["Dr"] = "Drive",
}

local function convertStreetName(input)
	local streetType = input:match("%s(%a+)$")
	local convertedType = streetTypes[streetType] or streetType

	return input:gsub("%s%a+$", " " .. convertedType)
end

RegisterNetEvent("triggerTrafficCamAlert", function(cPostal, primaryStreet, offenseData)
	if GetVehicleClass(GetVehiclePedIsIn(PlayerPedId(), false)) == 18 then
		exports["xsound"]:TextToSpeech("trafficcamalert", "en-US",
			"TRAFFIC ALERT. " .. addSpacesBetweenCharacters(cPostal) .. " " .. convertStreetName(primaryStreet), 0.75)

		for label, dataString in pairs(offenseData) do
			exports["xsound"]:TextToSpeech("trafficcamalert", "en-US", label .. ". " .. dataString, 0.75)
		end
	end
end)
