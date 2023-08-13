local PLATES = {}

local function roundToNearestHundred(postalCode)
	local divided = postalCode / 100
	local block = math.floor(divided) * 100
	return block
end

local function ExtractIDFromString(inputString)
	local idString = inputString:match("ID: (%d+)")
	if idString then
		return tonumber(idString)
	else
		return nil
	end
end

local function GetCardinalDirection(entity)
	local heading = GetEntityHeading(entity)
	local directions = { "North", "North-East", "East", "South-East", "South", "South-West", "West", "North-West" }
	local index = math.floor(((heading + 22.5) % 360) / 45) + 1
	return directions[index]
end

local function generateDispatchDescription(vehicleData, offenseData, postal, streetName)
	local dispatchDesc = "Traffic Cam Alert from " .. postal .. ".\nVehicle Information:\n"

	dispatchDesc = dispatchDesc ..
	"Vehicle is a " ..
	vehicleData.model ..
	", with a 10-28 of " ..
	vehicleData.plate ..
	". Currently headed " ..
	GetCardinalDirection(NetworkGetEntityFromNetworkId(vehicleData.entity)) .. " on " .. streetName .. ".\n"
	dispatchDesc = dispatchDesc .. "\nAlert Information:\n"

	for offense, value in pairs(offenseData) do
		dispatchDesc = dispatchDesc .. offense .. ": " .. value .. "\n"
	end

	return dispatchDesc
end

local function generateDispatchNote(vehicleData, offenseData, postal, streetName)
	local dispatchDesc = "Update from " .. postal .. " Traffic Cam.\nVehicle is now "

	dispatchDesc = dispatchDesc ..
	"headed " .. GetCardinalDirection(NetworkGetEntityFromNetworkId(vehicleData.entity)) .. " on " .. streetName .. ".\n"
	dispatchDesc = dispatchDesc .. "\nAlert Information:\n"

	for offense, value in pairs(offenseData) do
		if offense == "Speeding" then
			dispatchDesc = dispatchDesc .. offense .. ": " .. value .. "\n"
		end
	end

	return dispatchDesc
end


RegisterNetEvent("triggerTrafficCam911", function(cPostal, street, primaryStreet, vehiclePlate, vehicleData, offenseData)
	local function emptycb() end

	local function registerCallId(call)
		local callId = ExtractIDFromString(call)

		repeat
			Wait(0)
		until PLATES[vehiclePlate] == "TEMP"

		PLATES[vehiclePlate] = callId
	end

	if not PLATES[vehiclePlate] then
		exports["sonorancad"]:performApiRequest({ {
			["serverId"] = GetConvar("sonoran_serverId", 1),
			["origin"] = 1,
			["status"] = 0,
			["priority"] = 3,
			["block"] = roundToNearestHundred(cPostal),
			["address"] = street,
			["postal"] = cPostal,
			["code"] = "10-66 - RECKLESS DRIVER",
			["title"] = "Traffic Cam Alert",
			["description"] = generateDispatchDescription(vehicleData, offenseData, cPostal, primaryStreet),
			["notes"] = {},
			["units"] = {},
			["primary"] = nil,
			["trackPrimary"] = false,
			["metaData"] = {
				["plate"] = vehiclePlate,
			},
		} }, "NEW_DISPATCH", registerCallId)

		PLATES[vehiclePlate] = "TEMP"

		TriggerClientEvent("triggerTrafficCamAlert", -1, cPostal, primaryStreet, offenseData)
	else
		repeat
			Wait(0)
		until PLATES[vehiclePlate] ~= "TEMP"
		exports["sonorancad"]:performApiRequest({ {
			["serverId"] = GetConvar("sonoran_serverId", 1),
			["callId"] = tonumber(PLATES[vehiclePlate]),
			["label"] = tonumber(cPostal) < 5000 and "BCTCN" or "LSTCN",
			["note"] = generateDispatchNote(vehicleData, offenseData, cPostal, primaryStreet)
		} }, "ADD_CALL_NOTE", emptycb)
	end
end)

RegisterNetEvent("tcApiPlateReq", function(plate)
	local src = source
	local function returnData(call)
		TriggerClientEvent("tcApiPlateReturn", src, call)
	end

	exports["sonorancad"]:performApiRequest({ {
		["serverId"] = GetConvar("sonoran_serverId", 1),
		["types"] = { 3, 5 },
		["first"] = "",
		["last"] = "",
		["mi"] = "",
		["plate"] = plate,
	} }, "LOOKUP", returnData)
end)
