--[[
radio frameId: set = 0x31, get = 0x30
msrc frameId: 0x32. dataId DIY: 5100 - 52FF (to get into lua environment)

cmd        | sender | frameId | dataId  | value (4B)    | sensorId
-----------|--------|---------|---------|---------------|---------
set var    | radio  | 0x33    | 0x51nn  | value         |
get var    | radio  | 0x34    | 0x51nn  | 0             |
send var   | msrc   | 0x32    | 0x51nn  | value         |
ack        | msrc   | 0x32    | 0x5201  | ack=1, nack=0 |
ack        | radio  | 0x??    | 0x5201  | ack=1, nack=0 |
start save | radio  | 0x35    | 0x5201  | 0             |
end save   | radio  | 0x35    | 0x5201  | 1             |
]]
--

local scriptVersion = "v1.1"
local firmwareVersion
local sensorIdTx = 18
local page = 0
local pageLong = false
local pagePos = 1
local isSelected = false
local statusEnum = {
	maintOn = 1,
	getConfig = 2,
	config = 3,
	saveConfig = 4,
	startSave = 5,
	maintOff = 6,
	exitScr = 7,
	exit = 8,
}
local status = statusEnum.maintOn
local saveChanges = true
local ts = 0
local newValue = true
local varIndex = 1
local drawPage

local onOffStr = { "Off", "On" }

local pageName = {
	"Sensor Id",
	"Refresh rate",
	"Average elements",
	"ESC",
	"GPS",
	"Vario",
	"Fuel meter",
	"GPIO",
	"Analog rate",
	"Temperature analog",
	"Voltage analog",
	"Current analog",
	"Airspeed analog",
}

-- Page 1 - SensorId
--                 str, val, min, max, incr, dataId
local sensorId = { "Sensor Id", nil, 1, 28, 1, 0x5128 }
local page_sensorId = { sensorId }

-- Page 2 - Refresh interval (ms 1-2000)
local rateRpm = { "RPM", nil, 1, 2000, 1, 0x513A }
local rateVolt = { "Voltage", nil, 1, 2000, 1, 0x5113 }
local rateCurr = { "Current", nil, 1, 2000, 1, 0x5114 }
local rateTemp = { "Temperature", nil, 1, 2000, 1, 0x5115 }
local rateGps = { "GPS", nil, 1, 2000, 1, 0x5116 }
local rateCons = { "Consumption", nil, 1, 2000, 1, 0x5117 }
local rateVario = { "Vario", nil, 1, 2000, 1, 0x5118 }
local rateAirspeed = { "Airspeed", nil, 1, 2000, 1, 0x5119 }

local page_rate = { rateRpm, rateVolt, rateCurr, rateTemp, rateGps, rateCons, rateVario, rateAirspeed }

-- Page 3 - Averaging elements (1-16)
local avgRpm = { "RPM", nil, 1, 16, 1, 0x510C }
local avgVolt = { "Voltage", nil, 1, 16, 1, 0x510D }
local avgCurr = { "Current", nil, 1, 16, 1, 0x510E }
local avgTemp = { "Temperature", nil, 1, 16, 1, 0x510F }
local avgVario = { "Vario", nil, 1, 16, 1, 0x5110 }
local avgAirspeed = { "Airspeed", nil, 1, 16, 1, 0x5111 }

local page_avg = { avgRpm, avgVolt, avgCurr, avgTemp, avgVario, avgAirspeed }

-- Page 4 - ESC
local pairPoles = { "Pair of Poles", nil, 1, 16, 1, 0x5122 }
local mainGear = { "Main Gear", nil, 1, 16, 1, 0x5123 }
local pinionGear = { "Pinion Gear", nil, 1, 16, 1, 0x5124 }
local escProtocolStr = {
	"None",
	"Hobbywing V3",
	"Hobbywing V4",
	"PWM",
	"Castle Link",
	"Kontronik",
	"Kiss",
	"APD HV",
	"HobbyWing V5",
	"Smart ESC/BAT",
	"OMP M4",
	"ZTW",
}
local escProtocol = { "Protocol", nil, 0, 11, 1, 0x5103, escProtocolStr }
local hw4InitDelay = { "Init Delay", nil, 0, 1, 1, 0x512E, onOffStr }
local hw4AutoDetect = { "Auto detect", nil, 0, 1, 1, 0x514B, onOffStr }

local hw4VoltMult = { "Volt divisor", nil, 0, 1000, 1, 0x5131 }
local hw4CurrMult = { "Curr mult", nil, 0, 1000, 1, 0x5132 }
local hw4AutoOffset = { "Auto offset", nil, 0, 1, 1, 0x5135, onOffStr }
local hw4Offset = { "Offset", nil, 0, 2000, 1, 0x5139 }

local smartEscConsumption = { "Calc cons", nil, 0, 1, 1, 0x5145, onOffStr }

local page_esc = {
	pairPoles,
	mainGear,
	pinionGear,
	escProtocol,
	hw4InitDelay,
	hw4AutoDetect,
	hw4VoltMult,
	hw4CurrMult,
	hw4AutoOffset,
	hw4Offset,
	smartEscConsumption,
}

-- Page 5 - GPS
local gpsEnable = { "Enable", nil, 0, 1, 1, 0x5104, onOffStr }
local gpsProtocolStr = { "UBLOX", "NMEA" } --
local gpsProtocol = { "Protocol", nil, 0, 1, 1, 0x5149, gpsProtocolStr }
local gpsBaudrateVal = { 9600, 38400, 57600, 115200 }
local gpsBaudrate = { "Baudrate", nil, 0, 3, 1, 0x5105, gpsBaudrateVal }
local gpsRateVal = { 1, 5, 10, 20 }
local gpsRate = { "Rate", nil, 0, 3, 1, 0x5147, gpsRateVal }

local page_gps = { gpsEnable, gpsProtocol, gpsBaudrate, gpsRate }

-- Page 6 - Vario
local varioModelStr = { "None", "BMP280", "MS5611", "BMP180" }
local varioModel = { "Model", nil, 0, 3, 1, 0x510A, varioModelStr }
local varioAddress = { "Address", nil, 0x76, 0x77, 1, 0x510B }
local varioFilterStr = { "Low", "Medium", "High" }
local varioFilter = { "Filter", nil, 1, 3, 1, 0x5126, varioFilterStr }

local page_vario = { varioModel, varioAddress, varioFilter }

-- Page 7 - Fuel meter
local fuelMeter = { "Enable", nil, 0, 1, 1, 0x5142, onOffStr }
local mlPulse = { "ml/pulse", nil, 1, 100, 0.1, 0x5141 }

local page_fuelmeter = { fuelMeter, mlPulse }

-- Page 8 - GPIO
local gpioInterval = { "Interval(ms)", nil, 10, 10000, 1, 0x511D }
local gpio17 = { "17", nil, 0, 1, 1, 0x5138, onOffStr }
local gpio18 = { "18", 0, 0, 1, 1, 0, onOffStr }
local gpio19 = { "19", 0, 0, 1, 1, 0, onOffStr }
local gpio20 = { "20", 0, 0, 1, 1, 0, onOffStr }
local gpio21 = { "21", 0, 0, 1, 1, 0, onOffStr }
local gpio22 = { "22", 0, 0, 1, 1, 0, onOffStr }

local page_gpio = { gpioInterval, gpio17, gpio18, gpio19, gpio20, gpio21, gpio22 }

-- Page 9 - Analog rate
local analogRate = { "Rate(Hz)", nil, 1, 100, 1, 0x5136 }

local page_analogRate = { analogRate }

-- Page 10 - Temperature analog
local analogTemp = { "Enable", nil, 0, 1, 1, 0x5108, onOffStr }

local page_analogTemp = { analogTemp }

-- Page 11 - Voltage analog
local analogVolt = { "Enable", nil, 0, 1, 1, 0x5106, onOffStr }
local analogVoltMult = { "Multiplier", nil, 1, 1000, 0.1, 0x511B }

local page_analogVolt = { analogVolt, analogVoltMult }

-- Page 12 - Current analog
local analogCurr = { "Enable", nil, 0, 1, 1, 0x5107, onOffStr }
local analogCurrTypeStr = { "Hall Effect", "Shunt Resistor" }
local analogCurrType = { "Type", nil, 0, 1, 1, 0x512D, analogCurrTypeStr }
local analogCurrMult = { "Mult", nil, 0, 100, 0.1, 0x512E }
local analogCurrSens = { "Sens(mV/A)", 0, 0, 100, 0.1, 0 }
local analogCurrAutoOffset = { "Auto Offset", nil, 0, 1, 1, 0x5121, onOffStr }
local analogCurrOffset = { "Offset", nil, 0, 99, 0.1, 0x5120 }

local page_analogCurr = { analogCurr, analogCurrType, analogCurrMult, analogCurrAutoOffset, analogCurrOffset }

-- Page 13 - Airspeed analog
local analogAirspeed = { "Enable", nil, 0, 1, 1, 0x5109, onOffStr }
local analogAirspeedVcc = { "Vcc", nil, 3.3, 5.25, 0.01, 0x5140 }
local analogAirspeedOffset = { "Offset", nil, -1000, 1000, 1, 0x513F }

local page_analogAirspeed = { analogAirspeed, analogAirspeedVcc, analogAirspeedOffset }

local vars = {
	page_sensorId,
	page_rate,
	page_avg,
	page_esc,
	page_gps,
	page_vario,
	page_fuelmeter,
	page_gpio,
	page_analogRate,
	page_analogTemp,
	page_analogVolt,
	page_analogCurr,
	page_analogAirspeed,
}

local function getTextFlags(itemPos)
	local value = 0
	if itemPos == pagePos then
		value = INVERS
		if isSelected == true then
			value = value + BLINK
		end
	end
	return value
end

local function changeValue(isIncremented)
	if isIncremented == true then
		vars[page][pagePos][2] = vars[page][pagePos][2] + vars[page][pagePos][5]
		if vars[page][pagePos][2] > vars[page][pagePos][4] then
			vars[page][pagePos][2] = vars[page][pagePos][4]
		end
	else
		vars[page][pagePos][2] = vars[page][pagePos][2] - vars[page][pagePos][5]
		if vars[page][pagePos][2] < vars[page][pagePos][3] then
			vars[page][pagePos][2] = vars[page][pagePos][3]
		end
	end
end

local function getValue(list, index)
	if index > #list then
		return list[1]
	end
	return list[index]
end

local function getIndex(list, value)
	for i = 1, #list do
		if value == list[i] then
			return i
		end
	end
	return 1
end

local function handleEvents(event)
	-- Check one-time script
	if event == nil then
		return 2
	end
	-- Handle events
	if page == 0 then
		if event == EVT_PAGE_BREAK or event == 513 then
			page = 1
			status = statusEnum.getConfig
		end
	elseif event == EVT_EXIT_BREAK then
		if isSelected == true then
			isSelected = false
		else
			status = statusEnum.exitScr
		end
	elseif (event == EVT_PAGE_BREAK or event == 513) and (status ~= statusEnum.exitScr) then
		if pageLong then
			page = page - 1
		else
			page = page + 1
		end
		if page > #vars then
			page = 1
		elseif page < 1 then
			page = #vars
		end
		pageLong = false
		pagePos = 1
		isSelected = false
		status = statusEnum.getConfig
		ts = 0
		varIndex = 1
	elseif event == EVT_PAGE_LONG or event == 2049 then
		pageLong = true
	elseif event == EVT_ROT_RIGHT then
		if status == statusEnum.exitScr then
			saveChanges = not saveChanges
		elseif isSelected == false then
			pagePos = pagePos + 1
			if pagePos > #vars[page] then
				pagePos = 1
			end
		else
			changeValue(true)
		end
	elseif event == EVT_ROT_LEFT then
		if status == statusEnum.exitScr then
			saveChanges = not saveChanges
		end
		if isSelected == false then
			pagePos = pagePos - 1
			if pagePos < 1 then
				pagePos = #vars[page]
			end
		else
			changeValue(false)
		end
	elseif event == EVT_ROT_BREAK then
		if status == statusEnum.exitScr then
			if saveChanges == true then
				status = statusEnum.saveConfig
				page = 1
				varIndex = 1
			else
				saveChanges = true
				status = statusEnum.getConfig
                varIndex = 1
			end
		else
			isSelected = not isSelected
		end
	end
end

local function getConfig()
	local sensor, frameId, dataId, value = sportTelemetryPop()
	if firmwareVersion == nil then
		if dataId ~= nil and dataId == 0x5101 then
			firmwareVersion = "v"
				.. bit32.rshift(value, 16)
				.. "."
				.. bit32.band(bit32.rshift(value, 8), 0xF)
				.. "."
				.. bit32.band(value, 0xF)
			status = statusEnum.config
		elseif (getTime() - ts > 200) and sportTelemetryPush(sensorIdTx - 1, 0x30, 0x5101, 1) then
			ts = getTime()
		end
	elseif dataId ~= nil and dataId == vars[page][varIndex][6] then
		if dataId == 0x5131 or dataId == 0x5132 or dataId == 0x5140 or dataId == 0x511B or dataId == 0x5120 then
			vars[page][varIndex][2] = value / 100
		elseif dataId == 0x5141 then
			vars[page][varIndex][2] = value / 10000
		elseif dataId == 0x512E then
			analogCurrSens[2] = 1000 / value
		elseif dataId == 0x5105 then
			vars[page][varIndex][2] = getIndex(gpsBaudrateVal, value) - 1
		elseif dataId == 0x5147 then
			vars[page][varIndex][2] = getIndex(gpsRateVal, value) - 1
		elseif dataId == 0x5138 then
			gpio17[2] = bit32.extract(value, 0)
			gpio18[2] = bit32.extract(value, 1)
			gpio19[2] = bit32.extract(value, 2)
			gpio20[2] = bit32.extract(value, 3)
			gpio21[2] = bit32.extract(value, 4)
			gpio22[2] = bit32.extract(value, 5)
		elseif dataId == 0x5126 then
			vars[page][varIndex][2] = value - 1
		elseif dataId == 0x5135 then
			if value == 0 then
				vars[page][varIndex][2] = 1
			else
				vars[page][varIndex][2] = 0
			end
		elseif dataId == 0x5131 or dataId == 0x5132 then
			vars[page][varIndex][2] = math.trunc(value * 10000)
        else
			vars[page][varIndex][2] = value
		end
		varIndex = varIndex + 1
		ts = 0
		if varIndex > #vars[page] then
			status = statusEnum.config
		end
	elseif vars[page][varIndex][2] ~= nil then
		varIndex = varIndex + 1
		ts = 0
		if varIndex > #vars[page] then
			status = statusEnum.config
		end
	elseif (getTime() - ts > 200) and sportTelemetryPush(sensorIdTx - 1, 0x30, vars[page][varIndex][6], 1) then
		ts = getTime()
	end
end

local function saveConfig()
	if status == statusEnum.saveConfig then
		if sportTelemetryPush(sensorIdTx - 1, 0x31, 0x5201, 0) then
			status = statusEnum.startSave
		end
		return
	end
	if page > #vars then
		if sportTelemetryPush(sensorIdTx - 1, 0x31, 0x5201, 1) then
			status = statusEnum.maintOff
		end
		return
	end
	local value = vars[page][varIndex][2]
	local dataId = vars[page][varIndex][6]
	if value ~= nil and dataId ~= 0 then
		if dataId == 0x5131 or dataId == 0x5132 or dataId == 0x5140 or dataId == 0x511B then
			value = value * 100
		elseif dataId == 0x5141 then
			value = value * 10000
		elseif dataId == 0x5105 then
			value = getValue(gpsBaudrateVal, vars[page][varIndex][2])
		elseif dataId == 0x5147 then
			value = getValue(gpsRateVal, vars[page][varIndex][2])
		elseif dataId == 0x5138 then
			value = gpio17[2] -- bit 1
			value = bit32.bor(value, bit32.lshift(gpio18[2], 1)) -- bit 2
			value = bit32.bor(value, bit32.lshift(gpio19[2], 2)) -- bit 3
			value = bit32.bor(value, bit32.lshift(gpio20[2], 3)) -- bit 4
			value = bit32.bor(value, bit32.lshift(gpio21[2], 4)) -- bit 5
			value = bit32.bor(value, bit32.lshift(gpio22[2], 5)) -- bit 6
		elseif dataId == 0x5126 then
			value = vars[page][varIndex][2] + 1
		elseif dataId == 0x5135 then
			if vars[page][varIndex][2] == 1 then
				value = 0
			else
				value = 1
			end
		elseif dataId == 0x5131 or dataId == 0x5132 then
			value = vars[page][varIndex][2] / 10000
        end
		if sportTelemetryPush(sensorIdTx - 1, 0x31, dataId, value) then
			varIndex = varIndex + 1
		end
	else
		varIndex = varIndex + 1
	end
	if varIndex > #vars[page] then
		page = page + 1
		varIndex = 1
	end
end

local function setPageItems()
	if page == 4 then -- ESC
		if escProtocol[2] + 1 > #escProtocolStr then
			escProtocol[2] = 0
		end
		if hw4AutoDetect[2] + 1 > #onOffStr then
			hw4AutoDetect[2] = 0
		end
		if hw4AutoOffset[2] + 1 > #onOffStr then
			hw4AutoOffset[2] = 0
		end
		vars[page] = { pairPoles, mainGear, pinionGear, escProtocol }
		if escProtocolStr[escProtocol[2] + 1] == "Hobbywing V4" then
			vars[page] = {
				pairPoles,
				mainGear,
				pinionGear,
				escProtocol,
				hw4InitDelay,
				hw4AutoDetect,
			}
			if getValue(onOffStr, hw4AutoDetect[2] + 1) == "Off" then
				vars[page] = {
					pairPoles,
					mainGear,
					pinionGear,
					escProtocol,
					hw4InitDelay,
					hw4AutoDetect,
					hw4VoltMult,
					hw4CurrMult,
					hw4AutoOffset,
				}
				if getValue(onOffStr, hw4AutoOffset[2] + 1) == "Off" then
					vars[page] = {
						pairPoles,
						mainGear,
						pinionGear,
						escProtocol,
						hw4InitDelay,
						hw4AutoDetect,
						hw4VoltMult,
						hw4CurrMult,
						hw4AutoOffset,
						hw4Offset,
					}
				end
			end
		elseif escProtocolStr[escProtocol[2] + 1] == "Smart ESC/BAT" then
			vars[page] = { pairPoles, mainGear, pinionGear, escProtocol, smartEscConsumption }
		end
	elseif page == 6 then -- Vario
        if varioModel[2] + 1 > #varioModelStr then
			varioModel[2] = 0
		end
		if varioModelStr[varioModel[2] + 1] == "BMP280" then
			vars[page] = { varioModel, varioAddress, varioFilter }
		else
			vars[page] = { varioModel, varioAddress }
		end
	elseif page == 12 then -- Analog current
        if analogCurrType[2] + 1 > #analogCurrTypeStr then
			analogCurrType[2] = 0
		end
        if analogCurrAutoOffset[2] + 1 > #onOffStr then
			analogCurrAutoOffset[2] = 0
		end
		if analogCurrTypeStr[analogCurrType[2] + 1] == "Hall Effect" then
			vars[page] = { analogCurr, analogCurrType, analogCurrSens, analogCurrAutoOffset }
			if getValue(onOffStr, analogCurrAutoOffset[2] + 1) == "Off" then
				vars[page] = { analogCurr, analogCurrType, analogCurrSens, analogCurrAutoOffset, analogCurrOffset }
			end
		else
			vars[page] = { analogCurr, analogCurrType, analogCurrMult }
		end
	end
end

local function drawTitle(str, page, pages)
	if LCD_H == 64 then
		lcd.drawScreenTitle(str, page, pages)
	else
		lcd.drawText(1, 1, str)
		if page ~= 0 and pages ~= 0 then
			lcd.drawText(200, 1, page .. "/" .. pages)
		end
	end
end

local function drawPage()
	lcd.clear()
	if page == 0 then
		drawTitle("MSRC " .. scriptVersion, 0, 0)
		if firmwareVersion ~= nil then
			lcd.drawText(1, 20, "Firmware " .. firmwareVersion, SMLSIZE)
			lcd.drawText(1, 35, "Press Page", SMLSIZE)
		end
	elseif status == statusEnum.getConfig then
		drawTitle(pageName[page], page, #vars)
		lcd.drawText(60, 30, varIndex .. "/" .. #vars[page], 0)
	elseif status == statusEnum.config then
		drawTitle(pageName[page], page, #vars)
		if LCD_H == 64 then
			local scroll = pagePos - 8
			if scroll < 0 then
				scroll = 0
			end
			for i = 1, #vars[page] - scroll do
				lcd.drawText(1, 9 + 7 * (i - 1), vars[page][i + scroll][1], SMLSIZE)
				if #vars[page][i + scroll] == 6 then
					lcd.drawText(60, 9 + 7 * (i - 1), vars[page][i + scroll][2], SMLSIZE + getTextFlags(i + scroll))
				elseif #vars[page][i + scroll] == 7 then
					lcd.drawText(
						60,
						9 + 7 * (i - 1),
						getValue(vars[page][i + scroll][7], vars[page][i + scroll][2] + 1),
						SMLSIZE + getTextFlags(i + scroll)
					)
				end
			end
		else
			for i = 1, #vars[page] do
				lcd.drawText(1, 20 + 15 * (i - 1), vars[page][i][1], SMLSIZE)
				if #vars[page][i] == 6 then
					lcd.drawText(200, 20 + 15 * (i - 1), vars[page][i][2], SMLSIZE + getTextFlags(i))
				elseif #vars[page][i] == 7 then
					lcd.drawText(
						200,
						20 + 15 * (i - 1),
						getValue(vars[page][i][7], vars[page][i][2] + 1),
						SMLSIZE + getTextFlags(i)
					)
				end
			end
		end
	elseif status == statusEnum.exitScr then
		drawTitle("Exit", 0, 0)
		lcd.drawText(1, 20, "Save changes?", SMLSIZE)
		local flag_yes = 0
		local flag_cancel = 0
		if saveChanges == true then
			flag_yes = INVERS
		else
			flag_cancel = INVERS
		end
		lcd.drawText(1, 30, "Yes", SMLSIZE + flag_yes)
		lcd.drawText(60, 30, "Cancel", SMLSIZE + flag_cancel)
	elseif status == statusEnum.startSave then
		drawTitle("Saving ", 0, 0)
		if page <= #vars then
			lcd.drawText(1, 20, "Send dataId " .. vars[page][varIndex][6], SMLSIZE)
		end
	elseif status == statusEnum.exit then
		drawTitle("MSRC " .. scriptVersion, 0, 0)
		lcd.drawText(1, 20, "Completed!", SMLSIZE)
		lcd.drawText(1, 40, "Reboot MSRC to apply changes.", SMLSIZE)
	end
end

local function run_func(event)
	if status == statusEnum.maintOn then
		if sportTelemetryPush(sensorIdTx - 1, 0x21, 0xFFFF, 0x80) then
			status = statusEnum.getConfig
		end
	elseif status == statusEnum.getConfig then
		handleEvents(event)
		getConfig()
	elseif status == statusEnum.config or status == statusEnum.exitScr then
		handleEvents(event)
		if status == statusEnum.config then setPageItems() end
	elseif status == statusEnum.saveConfig or status == statusEnum.startSave then
		saveConfig()
	elseif status == statusEnum.maintOff then
		if sportTelemetryPush(sensorIdTx - 1, 0x20, 0xFFFF, 0x80) then
			status = statusEnum.exit
		end
	end
	drawPage()
	return 0
end

return { run = run_func }
