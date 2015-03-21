-- Some global variables
local progVer = "0.4.0"
local progName = "EZ-NUKE"
local sideClick, xClick, yClick = nil, 0, 0
local loopTime = 2
local controlRodAdjustAmount = 1 -- Default Reactor Rod Control % adjustment amount
local flowRateAdjustAmount = 25 -- Default Turbine Flow Rate in mB adjustment amount
local debugMode = false
-- End multi-reactor cleanup section
local minStoredEnergyPercent = nil -- Max energy % to store before activate
local maxStoredEnergyPercent = nil -- Max energy % to store before shutdown
local monitorList = {} -- Empty monitor array
local monitorNames = {} -- Empty array of monitor names
local reactorList = {} -- Empty reactor array
local reactorNames = {} -- Empty array of reactor names
local turbineList = {} -- Empty turbine array
local turbineNames = {} -- Empty array of turbine names
local turbineMonitorOffset = 0 -- Turbines are assigned monitors after reactors
local knowlinglyOverride = true -- Issue #39 Allow the user to override safe values, currently only enabled for actively cooled reactor min/max temperature

term.clear()
term.setCursorPos(2,1)
write("Initializing program...\n")


-- File needs to exist for append "a" later and zero it out if it already exists
-- Always initalize this file to avoid confusion with old files and the latest run
local logFile = fs.open("reactorcontrol.log", "w")
if logFile then
	logFile.writeLine("Minecraft time: Day "..os.day().." at "..textutils.formatTime(os.time(),true))
	logFile.close()
else
	error("Could not open file reactorcontrol.log for writing.")
end


-- Helper functions

local function termRestore()
  local ccVersion = nil
  ccVersion = os.version()

	if ccVersion == "CraftOS 1.7" then
		term.native()
	elseif ccVersion == "CraftOS 1.5" then
		term.restore()
	else -- Default to older term.restore
		printLog("Unsupported CraftOS found. Reported version is \""..ccVersion.."\".")
		term.restore()
	end -- if ccVersion
end -- function termRestore()

local function printLog(printStr)
	if debugMode then
		-- If multiple monitors, use the last monitor for debugging if debug is enabled
		if #monitorList > 1 then
			term.redirect(monitorList[#monitorList]) -- Redirect to last monitor for debugging
			monitorList[#monitorList].setTextScale(0.5) -- Fit more logs on screen
			write(printStr.."\n")   -- May need to use term.scroll(x) if we output too much, not sure
			termRestore()
		end -- if #monitorList > 1 then

		local logFile = fs.open("reactorcontrol.log", "a") -- See http://computercraft.info/wiki/Fs.open
		if logFile then
			logFile.writeLine(printStr)
			logFile.close()
		else
			error("Cannot open file reactorcontrol.log for appending!")
		end -- if logFile then
	end -- if debugMode then
end -- function printLog(printStr)

-- Trim a string
function stringTrim(s)
	assert(s ~= nil, "String can't be nil")
	return(string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

config = {}

-- Save a table into a config file
-- path: path of the file to write
-- tab: table to save
config.save = function(path, tab)
	printLog("Save function called for config for "..path.." EOL")
	assert(path ~= nil, "Path can't be nil")
	assert(type(tab) == "table", "Second parameter must be a table")
	local f = io.open(path, "w")
	local i = 0
	for key, value in pairs(tab) do
		if i ~= 0 then
			f:write("\n")
		end
		f:write("["..key.."]".."\n")
		for key2, value2 in pairs(tab[key]) do
			key2 = stringTrim(key2)
			--doesn't like boolean values
			if (type(value2) ~= "boolean") then
			value2 = stringTrim(value2)
			else
			value2 = tostring(value2)
			end
			key2 = key2:gsub(";", "\\;")
			key2 = key2:gsub("=", "\\=")
			value2 = value2:gsub(";", "\\;")
			value2 = value2:gsub("=", "\\=")	
			f:write(key2.."="..value2.."\n")
		end
		i = i + 1
	end
	f:close()
end --config.save = function(path, tab)

-- Load a config file
-- path: path of the file to read
config.load = function(path)
	printLog("Load function called for config for "..path.." EOL")
	assert(path ~= nil, "Path can't be nil")
	local f = fs.open(path, "r")
	if f ~= nil then
		local tab = {}
		local line = ""
		local newLine
		local i
		local currentTag = nil
		local found = false
		local pos = 0
		while line ~= nil do
			found = false		
			line = line:gsub("\\;", "#_!36!_#") -- to keep \;
			line = line:gsub("\\=", "#_!71!_#") -- to keep \=
			if line ~= "" then
				-- Delete comments
				newLine = line
				line = ""
				for i=1, string.len(newLine) do				
					if string.sub(newLine, i, i) ~= ";" then
						line = line..newLine:sub(i, i)						
					else				
						break
					end
				end
				line = stringTrim(line)
				-- Find tag			
				if line:sub(1, 1) == "[" and line:sub(line:len(), line:len()) == "]" then
					currentTag = stringTrim(line:sub(2, line:len()-1))
					tab[currentTag] = {}
					found = true							
				end
				-- Find key and values
				if not found and line ~= "" then				
					pos = line:find("=")				
					if pos == nil then
						error("Bad INI file structure")
					end
					line = line:gsub("#_!36!_#", ";")
					line = line:gsub("#_!71!_#", "=")
					tab[currentTag][stringTrim(line:sub(1, pos-1))] = stringTrim(line:sub(pos+1, line:len()))
					found = true			
				end			
			end
			line = f.readLine()
		end
		
		f:close()
		
		return tab
	else
		return nil
	end
end --config.load = function(path)



-- round() function from mechaet
local function round(num, places)
	local mult = 10^places
	local addon = nil
	if ((num * mult) < 0) then
		addon = -.5
	else
		addon = .5
	end

	local integer, decimal = math.modf(num*mult+addon)
	newNum = integer/mult
	printLog("Called round(num="..num..",places="..places..") returns \""..newNum.."\".")
	return newNum
end -- function round(num, places)


local function print(printParams)
	-- Default to xPos=1, yPos=1, and first monitor
	setmetatable(printParams,{__index={xPos=1, yPos=1, monitorIndex=1}})
	local printString, xPos, yPos, monitorIndex =
		printParams[1], -- Required parameter
		printParams[2] or printParams.xPos,
		printParams[3] or printParams.yPos,
		printParams[4] or printParams.monitorIndex

	local monitor = nil
	monitor = monitorList[monitorIndex]

	if not monitor then
		printLog("monitor["..monitorIndex.."] in print() is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	monitor.setCursorPos(xPos, yPos)
	monitor.write(printString)
end -- function print(printParams)


-- Replaces the one from FC_API (http://pastebin.com/A9hcbZWe) and adding multi-monitor support
local function printCentered(printString, yPos, monitorIndex)
	local monitor = nil
	monitor = monitorList[monitorIndex]

	if not monitor then
		printLog("monitor["..monitorIndex.."] in printCentered() is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	local width, height = monitor.getSize()
	local monitorNameLength = 0

	-- Special changes for title bar
	if yPos == 1 then
		-- Add monitor name to first line
		monitorNameLength = monitorNames[monitorIndex]:len()

		-- Leave room for "offline" and "online" on the right except for overall status display
		if (#monitorList ~= 1) and (monitorIndex ~= 1) then
			width = width - 7
		end
	end

	monitor.setCursorPos(math.floor(width/2) - math.ceil(printString:len()/2) +  monitorNameLength/2, yPos)
	monitor.clearLine()
	monitor.write(printString)

	monitor.setTextColor(colors.blue)
	print{monitorNames[monitorIndex], 1, 1, monitorIndex}
	monitor.setTextColor(colors.white)
end -- function printCentered(printString, yPos, monitorIndex)


-- Print text padded from the left side
-- Clear the left side of the screen
local function printLeft(printString, yPos, monitorIndex)
	local monitor = nil
	monitor = monitorList[monitorIndex]

	if not monitor then
		printLog("monitor["..monitorIndex.."] in printLeft() is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	local gap = 1
	local width = monitor.getSize()

	-- Clear left-half of the monitor

	for curXPos = 1, (width / 2) do
		monitor.setCursorPos(curXPos, yPos)
		monitor.write(" ")
	end

	-- Write our string left-aligned
	monitor.setCursorPos(1+gap, yPos)
	monitor.write(printString)
end


-- Print text padded from the right side
-- Clear the right side of the screen
local function printRight(printString, yPos, monitorIndex)
	local monitor = nil
	monitor = monitorList[monitorIndex]

	if not monitor then
		printLog("monitor["..monitorIndex.."] in printRight() is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	-- Make sure printString is a string
	printString = tostring(printString)

	local gap = 1
	local width = monitor.getSize()

	-- Clear right-half of the monitor
	for curXPos = (width/2), width do
		monitor.setCursorPos(curXPos, yPos)
		monitor.write(" ")
	end

	-- Write our string right-aligned
	monitor.setCursorPos(math.floor(width) - math.ceil(printString:len()+gap), yPos)
	monitor.write(printString)
end


-- Replaces the one from FC_API (http://pastebin.com/A9hcbZWe) and adding multi-monitor support
local function clearMonitor(printString, monitorIndex)
	local monitor = nil
	monitor = monitorList[monitorIndex]

	printLog("Called as clearMonitor(printString="..printString..",monitorIndex="..monitorIndex..").")

	if not monitor then
		printLog("monitor["..monitorIndex.."] in clearMonitor(printString="..printString..",monitorIndex="..monitorIndex..") is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	local gap = 2
	monitor.clear()
	local width, height = monitor.getSize()
	monitor.setTextScale(1.0) -- Make sure scale is correct

	printCentered(printString, 1, monitorIndex)
	monitor.setTextColor(colors.blue)
	print{monitorNames[monitorIndex], 1, 1, monitorIndex}
	monitor.setTextColor(colors.white)

	for i=1, width do
		monitor.setCursorPos(i, gap)
		monitor.write("-")
	end

	monitor.setCursorPos(1, gap+1)
end -- function clearMonitor(printString, monitorIndex)


-- Return a list of all connected (including via wired modems) devices of "deviceType"
local function getDevices(deviceType)
	printLog("Called as getDevices(deviceType="..deviceType..")")

	local deviceName = nil
	local deviceIndex = 1
	local deviceList, deviceNames = {}, {} -- Empty array, which grows as we need
	local peripheralList = peripheral.getNames() -- Get table of connected peripherals

	deviceType = deviceType:lower() -- Make sure we're matching case here

	for peripheralIndex = 1, #peripheralList do
		-- Log every device found
		-- printLog("Found "..peripheral.getType(peripheralList[peripheralIndex]).."["..peripheralIndex.."] attached as \""..peripheralList[peripheralIndex].."\".")
		if (string.lower(peripheral.getType(peripheralList[peripheralIndex])) == deviceType) then
			-- Log devices found which match deviceType and which device index we give them
			printLog("Found "..peripheral.getType(peripheralList[peripheralIndex]).."["..peripheralIndex.."] as index \"["..deviceIndex.."]\" attached as \""..peripheralList[peripheralIndex].."\".")
			write("Found "..peripheral.getType(peripheralList[peripheralIndex]).."["..peripheralIndex.."] as index \"["..deviceIndex.."]\" attached as \""..peripheralList[peripheralIndex].."\".\n")
			deviceNames[deviceIndex] = peripheralList[peripheralIndex]
			deviceList[deviceIndex] = peripheral.wrap(peripheralList[peripheralIndex])
			deviceIndex = deviceIndex + 1
		end
	end -- for peripheralIndex = 1, #peripheralList do

	return deviceList, deviceNames
end -- function getDevices(deviceType)

-- Draw a line across the entire x-axis
local function drawLine(yPos, monitorIndex)
	local monitor = nil
	monitor = monitorList[monitorIndex]

	if not monitor then
		printLog("monitor["..monitorIndex.."] in drawLine() is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	local width, height = monitor.getSize()

	for i=1, width do
		monitor.setCursorPos(i, yPos)
		monitor.write("-")
	end
end -- function drawLine(yPos,monitorIndex)


-- Display a solid bar of specified color
local function drawBar(startXPos, startYPos, endXPos, endYPos, color, monitorIndex)
	local monitor = nil
	monitor = monitorList[monitorIndex]

	if not monitor then
		printLog("monitor["..monitorIndex.."] in drawBar() is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	-- PaintUtils only outputs to term., not monitor.
	-- See http://www.computercraft.info/forums2/index.php?/topic/15540-paintutils-on-a-monitor/
	term.redirect(monitor)
	paintutils.drawLine(startXPos, startYPos, endXPos, endYPos, color)
	monitor.setBackgroundColor(colors.black) -- PaintUtils doesn't restore the color
	termRestore()
end -- function drawBar(startXPos, startYPos,endXPos,endYPos,color,monitorIndex)


-- Display single pixel color
local function drawPixel(xPos, yPos, color, monitorIndex)
	local monitor = nil
	monitor = monitorList[monitorIndex]

	if not monitor then
		printLog("monitor["..monitorIndex.."] in drawPixel() is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	-- PaintUtils only outputs to term., not monitor.
	-- See http://www.computercraft.info/forums2/index.php?/topic/15540-paintutils-on-a-monitor/
	term.redirect(monitor)
	paintutils.drawPixel(xPos, yPos, color)
	monitor.setBackgroundColor(colors.black) -- PaintUtils doesn't restore the color
	termRestore()
end -- function drawPixel(xPos, yPos, color, monitorIndex)


-- End helper functions


-- Then initialize the monitors
local function findMonitors()
	-- Empty out old list of monitors
	monitorList = {}

	printLog("Finding monitors...")
	monitorList, monitorNames = getDevices("monitor")

	if #monitorList == 0 then
		printLog("No monitors found!")
		error("Can't find any monitors!")
	else
		for monitorIndex = 1, #monitorList do
			local monitor, monitorX, monitorY = nil, nil, nil
			monitor = monitorList[monitorIndex]

			if not monitor then
				printLog("monitorList["..monitorIndex.."] in findMonitors() is NOT a valid monitor.")

				table.remove(monitorList, monitorIndex) -- Remove invalid monitor from list
				if monitorIndex ~= #monitorList then    -- If we're not at the end, clean up
					monitorIndex = monitorIndex - 1 -- We just removed an element
				end -- if monitorIndex == #monitorList then
				break -- Invalid monitorIndex
			else -- valid monitor
				monitorX, monitorY = monitor.getSize()
				if (monitorX == nil) or (monitorY == nil) then -- somehow a valid monitor, but non-existent sizes? Maybe fixes Issue #3
					printLog("monitorList["..monitorIndex.."] in findMonitors() is NOT a valid sized monitor.")

					table.remove(monitorList, monitorIndex) -- Remove invalid monitor from list
					if monitorIndex ~= #monitorList then    -- If we're not at the end, clean up
						monitorIndex = monitorIndex - 1 -- We just removed an element
					end -- if monitorIndex == #monitorList then
					break -- Invalid monitorIndex

				-- Check for minimum size to allow for monitor.setTextScale(0.5) to work for 3x2 debugging monitor, changes getSize()
				elseif monitorX < 29 or monitorY < 12 then
					term.redirect(monitor)
					monitor.clear()
					printLog("Removing monitor "..monitorIndex.." for being too small.")
					monitor.setCursorPos(1,2)
					write("Monitor is the wrong size!\n")
					write("Needs to be at least 3x2.")
					termRestore()

					table.remove(monitorList, monitorIndex) -- Remove invalid monitor from list
					if monitorIndex == #monitorList then    -- If we're at the end already, break from loop
						break
					else
						monitorIndex = monitorIndex - 1 -- We just removed an element
					end -- if monitorIndex == #monitorList then

				end -- if monitorX < 29 or monitorY < 12 then
			end -- if not monitor then

			printLog("Monitor["..monitorIndex.."] named \""..monitorNames[monitorIndex].."\" is a valid monitor of size x:"..monitorX.." by y:"..monitorY..".")
		end -- for monitorIndex = 1, #monitorList do
	end -- if #monitorList == 0 then

	printLog("Found "..#monitorList.." monitor(s) in findMonitors().")
end -- local function findMonitors()


-- Initialize all Big Reactors - Reactors
local function findReactors()
	-- Empty out old list of reactors
	newReactorList = {}
	printLog("Finding reactors...")
	newReactorList, reactorNames = getDevices("BigReactors-Reactor")

	if #newReactorList == 0 then
		printLog("No reactors found!")
		error("Can't find any reactors!")
	else  -- Placeholder
		for reactorIndex = 1, #newReactorList do
			local reactor = nil
			reactor = newReactorList[reactorIndex]

			if not reactor then
				printLog("reactorList["..reactorIndex.."] in findReactors() is NOT a valid Big Reactor.")

				table.remove(newReactorList, reactorIndex) -- Remove invalid reactor from list
				if reactorIndex ~= #newReactorList then    -- If we're not at the end, clean up
					reactorIndex = reactorIndex - 1 -- We just removed an element
				end -- reactorIndex ~= #newReactorList then
				return -- Invalid reactorIndex
			else
				printLog("reactor["..reactorIndex.."] in findReactors() is a valid Big Reactor.")
				--initialize the default table
				_G[reactorNames[reactorIndex]] = {}
				_G[reactorNames[reactorIndex]]["ReactorOptions"] = {}
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["baseControlRodLevel"] = 80
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["lastTempPoll"] = 0
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["autoStart"] = true
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["activeCooled"] = true
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMaxTemp"] = 1400 --set for passive-cooled, the active-cooled subroutine will correct it
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMinTemp"] = 1000
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"] = false
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorName"] = reactorNames[reactorIndex]
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorCruising"] = false
				if reactor.getConnected() then
					printLog("reactor["..reactorIndex.."] in findReactors() is connected.")
				else
					printLog("reactor["..reactorIndex.."] in findReactors() is NOT connected.")
					return -- Disconnected reactor
				end
			end
			
			--failsafe
			local tempTable = _G[reactorNames[reactorIndex]]
			
			--check to make sure we get a valid config
			if (config.load(reactorNames[reactorIndex]..".options")) ~= nil then
				tempTable = config.load(reactorNames[reactorIndex]..".options")
			else
				--if we don't have a valid config from disk, make a valid config
				config.save(reactorNames[reactorIndex]..".options", _G[reactorNames[reactorIndex]])
			end
			
			--load values from tempTable, checking for nil values along the way
			if tempTable["ReactorOptions"]["baseControlRodLevel"] ~= nil then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["baseControlRodLevel"] = tempTable["ReactorOptions"]["baseControlRodLevel"]
			end
			
			if tempTable["ReactorOptions"]["lastTempPoll"] ~= nil then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["lastTempPoll"] = tempTable["ReactorOptions"]["lastTempPoll"]
			end
			
			if tempTable["ReactorOptions"]["autoStart"] ~= nil then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["autoStart"] = tempTable["ReactorOptions"]["autoStart"]
			end
			
			if tempTable["ReactorOptions"]["activeCooled"] ~= nil then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["activeCooled"] = tempTable["ReactorOptions"]["activeCooled"]
			end
			
			if tempTable["ReactorOptions"]["reactorMaxTemp"] ~= nil then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMaxTemp"] = tempTable["ReactorOptions"]["reactorMaxTemp"]
			end
			
			if tempTable["ReactorOptions"]["reactorMinTemp"] ~= nil then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMinTemp"] = tempTable["ReactorOptions"]["reactorMinTemp"]
			end
			
			if tempTable["ReactorOptions"]["rodOverride"] ~= nil then
				printLog("Got value from config file for Rod Override, the value is: "..tostring(tempTable["ReactorOptions"]["rodOverride"]).." EOL")
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"] = tempTable["ReactorOptions"]["rodOverride"]
			end
			
			if tempTable["ReactorOptions"]["reactorName"] ~= nil then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorName"] = tempTable["ReactorOptions"]["reactorName"]
			end
			
			if tempTable["ReactorOptions"]["reactorCruising"] ~= nil then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorCruising"] = tempTable["ReactorOptions"]["reactorCruising"]
			end
			
			--stricter typing, let's set these puppies up with the right type of value.
			_G[reactorNames[reactorIndex]]["ReactorOptions"]["baseControlRodLevel"] = tonumber(_G[reactorNames[reactorIndex]]["ReactorOptions"]["baseControlRodLevel"])
			
			_G[reactorNames[reactorIndex]]["ReactorOptions"]["lastTempPoll"] = tonumber(_G[reactorNames[reactorIndex]]["ReactorOptions"]["lastTempPoll"])
			
			if (tostring(_G[reactorNames[reactorIndex]]["ReactorOptions"]["autoStart"]) == "true") then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["autoStart"] = true
			else
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["autoStart"] = false
			end
			
			if (tostring(_G[reactorNames[reactorIndex]]["ReactorOptions"]["activeCooled"]) == "true") then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["activeCooled"] = true
			else
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["activeCooled"] = false
			end
			
			_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMaxTemp"] = tonumber(_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMaxTemp"])
			
			_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMinTemp"] = tonumber(_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMinTemp"])
			
			if (tostring(_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"]) == "true") then
				printLog("Setting Rod Override for  "..reactorNames[reactorIndex].." to true because value was "..tostring(_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"]).." EOL")
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"] = true
			else
				printLog("Setting Rod Override for  "..reactorNames[reactorIndex].." to false because value was "..tostring(_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"]).." EOL")
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"] = false
			end
			
			if (tostring(_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorCruising"]) == "true") then
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorCruising"] = true
			else
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorCruising"] = false
			end
						
			--save one more time, in case we didn't have a complete config file before
			config.save(reactorNames[reactorIndex]..".options", _G[reactorNames[reactorIndex]])
		end -- for reactorIndex = 1, #newReactorList do
	end -- if #newReactorList == 0 then

	-- Overwrite old reactor list with the now updated list
	reactorList = newReactorList

	-- Start turbine monitor offset after reactors get monitors
	-- This assumes that there is a monitor for each turbine and reactor, plus the overall monitor display
	turbineMonitorOffset = #reactorList + 1 -- #turbineList will start at "1" if turbines found and move us just beyond #reactorList and status monitor range

	printLog("Found "..#reactorList.." reactor(s) in findReactors().")
	printLog("Set turbineMonitorOffset to "..turbineMonitorOffset.." in findReactors().")
end -- function findReactors()


-- Initialize all Big Reactors - Turbines
local function findTurbines()
	-- Empty out old list of turbines
	newTurbineList = {}

	printLog("Finding turbines...")
	newTurbineList, turbineNames = getDevices("BigReactors-Turbine")

	if #newTurbineList == 0 then
		printLog("No turbines found") -- Not an error
	else
		for turbineIndex = 1, #newTurbineList do
			local turbine = nil
			turbine = newTurbineList[turbineIndex]

			if not turbine then
				printLog("turbineList["..turbineIndex.."] in findTurbines() is NOT a valid Big Reactors Turbine.")

				table.remove(newTurbineList, turbineIndex) -- Remove invalid turbine from list
				if turbineIndex ~= #newTurbineList then    -- If we're not at the end, clean up
					turbineIndex = turbineIndex - 1 -- We just removed an element
				end -- turbineIndex ~= #newTurbineList then

				return -- Invalid turbineIndex
			else
			
				_G[turbineNames[turbineIndex]] = {}
				_G[turbineNames[turbineIndex]]["TurbineOptions"] = {}
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastSpeed"] = 0
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["BaseSpeed"] = 2726
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["autoStart"] = true
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastFlow"] = 2000 --open up with all the steam wide open
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"] = false
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["turbineName"] = turbineNames[turbineIndex]
				printLog("turbineList["..turbineIndex.."] in findTurbines() is a valid Big Reactors Turbine.")
				if turbine.getConnected() then
					printLog("turbine["..turbineIndex.."] in findTurbines() is connected.")
				else
					printLog("turbine["..turbineIndex.."] in findTurbines() is NOT connected.")
					return -- Disconnected turbine
				end
			end
			
			--failsafe
			local tempTable = _G[turbineNames[turbineIndex]]
			
			--check to make sure we get a valid config
			if (config.load(turbineNames[turbineIndex]..".options")) ~= nil then
				tempTable = config.load(turbineNames[turbineIndex]..".options")
			else
				--if we don't have a valid config from disk, make a valid config
				config.save(turbineNames[turbineIndex]..".options", _G[turbineNames[turbineIndex]])
			end
			
			--load values from tempTable, checking for nil values along the way
			if tempTable["TurbineOptions"]["LastSpeed"] ~= nil then
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastSpeed"] = tempTable["TurbineOptions"]["LastSpeed"]
			end
			
			if tempTable["TurbineOptions"]["BaseSpeed"] ~= nil then
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["BaseSpeed"] = tempTable["TurbineOptions"]["BaseSpeed"]
			end
			
			if tempTable["TurbineOptions"]["autoStart"] ~= nil then
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["autoStart"] = tempTable["TurbineOptions"]["autoStart"]
			end
			
			if tempTable["TurbineOptions"]["LastFlow"] ~= nil then
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastFlow"] = tempTable["TurbineOptions"]["LastFlow"]
			end
			
			if tempTable["TurbineOptions"]["flowOverride"] ~= nil then
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"] = tempTable["TurbineOptions"]["flowOverride"]
			end
			
			if tempTable["TurbineOptions"]["turbineName"] ~= nil then
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["turbineName"] = tempTable["TurbineOptions"]["turbineName"]
			end
			
			--save once more just to make sure we got it
			config.save(turbineNames[turbineIndex]..".options", _G[turbineNames[turbineIndex]])
		end -- for turbineIndex = 1, #newTurbineList do

		-- Overwrite old turbine list with the now updated list
		turbineList = newTurbineList
	end -- if #newTurbineList == 0 then

	printLog("Found "..#turbineList.." turbine(s) in findTurbines().")
end -- function findTurbines()


-- Return current energy buffer in a specific reactor by %
local function getReactorStoredEnergyBufferPercent(reactor)
	printLog("Called as getReactorStoredEnergyBufferPercent(reactor).")

	if not reactor then
		printLog("getReactorStoredEnergyBufferPercent() did NOT receive a valid Big Reactor Reactor.")
		return -- Invalid reactorIndex
	else
		printLog("getReactorStoredEnergyBufferPercent() did receive a valid Big Reactor Reactor.")
	end

	local energyBufferStorage = reactor.getEnergyStored()
	return round(energyBufferStorage/100000, 1) -- (buffer/10000000 RF)*100%
end -- function getReactorStoredEnergyBufferPercent(reactor)


-- Return current energy buffer in a specific Turbine by %
local function getTurbineStoredEnergyBufferPercent(turbine)
	printLog("Called as getTurbineStoredEnergyBufferPercent(turbine)")

	if not turbine then
		printLog("getTurbineStoredEnergyBufferPercent() did NOT receive a valid Big Reactor Turbine.")
		return -- Invalid reactorIndex
	else
		printLog("getTurbineStoredEnergyBufferPercent() did receive a valid Big Reactor Turbine.")
	end

	local energyBufferStorage = turbine.getEnergyStored()
	return round(energyBufferStorage/10000, 1) -- (buffer/1000000 RF)*100%
end -- function getTurbineStoredEnergyBufferPercent(turbine)

local function reactorCruise(cruiseMaxTemp, cruiseMinTemp, reactorIndex)
	printLog("Called as reactorCruise(cruiseMaxTemp="..cruiseMaxTemp..",cruiseMinTemp="..cruiseMinTemp..",lastPolledTemp=".._G[reactorNames[reactorIndex]]["ReactorOptions"]["lastTempPoll"]..",reactorIndex="..reactorIndex..").")
	
	--sanitization
	local lastPolledTemp = tonumber(_G[reactorNames[reactorIndex]]["ReactorOptions"]["lastTempPoll"])
	cruiseMaxTemp = tonumber(cruiseMaxTemp)
	cruiseMinTemp = tonumber(cruiseMinTemp)
	
	if ((lastPolledTemp < cruiseMaxTemp) and (lastPolledTemp > cruiseMinTemp)) then
		local reactor = nil
		reactor = reactorList[reactorIndex]
		if not reactor then
			printLog("reactor["..reactorIndex.."] in reactorCruise(cruiseMaxTemp="..cruiseMaxTemp..",cruiseMinTemp="..cruiseMinTemp..",lastPolledTemp="..lastPolledTemp..",reactorIndex="..reactorIndex..") is NOT a valid Big Reactor.")
			return -- Invalid reactorIndex
		else
			printLog("reactor["..reactorIndex.."] in reactorCruise(cruiseMaxTemp="..cruiseMaxTemp..",cruiseMinTemp="..cruiseMinTemp..",lastPolledTemp="..lastPolledTemp..",reactorIndex="..reactorIndex..") is a valid Big Reactor.")
			if reactor.getConnected() then
				printLog("reactor["..reactorIndex.."] in reactorCruise(cruiseMaxTemp="..cruiseMaxTemp..",cruiseMinTemp="..cruiseMinTemp..",lastPolledTemp="..lastPolledTemp..",reactorIndex="..reactorIndex..") is connected.")
			else
				printLog("reactor["..reactorIndex.."] in reactorCruise(cruiseMaxTemp="..cruiseMaxTemp..",cruiseMinTemp="..cruiseMinTemp..",lastPolledTemp="..lastPolledTemp..",reactorIndex="..reactorIndex..") is NOT connected.")
				return -- Disconnected reactor
			end -- if reactor.getConnected() then
		end -- if not reactor then

		local rodPercentage = math.ceil(reactor.getControlRodLevel(0))
		local reactorTemp = math.ceil(reactor.getFuelTemperature())
		_G[reactorNames[reactorIndex]]["ReactorOptions"]["baseControlRodLevel"] = rodPercentage
		
		if ((reactorTemp < cruiseMaxTemp) and (reactorTemp > cruiseMinTemp)) then
			if (reactorTemp < lastPolledTemp) then
				rodPercentage = (rodPercentage - 1)
				--Boundary check
				if rodPercentage < 0 then
					reactor.setAllControlRodLevels(0)
				else
					reactor.setAllControlRodLevels(rodPercentage)
				end
			else
				rodPercentage = (rodPercentage + 1)
				--Boundary check
				if rodPercentage > 99 then
					reactor.setAllControlRodLevels(99)
				else
					reactor.setAllControlRodLevels(rodPercentage)
				end
			end -- if (reactorTemp > lastPolledTemp) then
		else
			--disengage cruise, we've fallen out of the ideal temperature range
			_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorCruising"] = false
		end -- if ((reactorTemp < cruiseMaxTemp) and (reactorTemp > cruiseMinTemp)) then
	else
		--I don't know how we'd get here, but let's turn the cruise mode off
		_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorCruising"] = false
	end -- if ((lastPolledTemp < cruiseMaxTemp) and (lastPolledTemp > cruiseMinTemp)) then
	_G[reactorNames[reactorIndex]]["ReactorOptions"]["lastTempPoll"] = reactorTemp
	_G[reactorNames[reactorIndex]]["ReactorOptions"]["activeCooled"] = true
	_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMaxTemp"] = cruiseMaxTemp
	_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMinTemp"] = cruiseMinTemp
	config.save(reactorNames[reactorIndex]..".options", _G[reactorNames[reactorIndex]])
end -- function reactorCruise(cruiseMaxTemp, cruiseMinTemp, lastPolledTemp, reactorIndex)

-- Modify reactor control rod levels to keep temperature with defined parameters, but
-- wait an in-game half-hour for the temperature to stabalize before modifying again
local function temperatureControl(reactorIndex)
	printLog("Called as temperatureControl(reactorIndex="..reactorIndex..")")

	local reactor = nil
	reactor = reactorList[reactorIndex]
	if not reactor then
		printLog("reactor["..reactorIndex.."] in temperatureControl(reactorIndex="..reactorIndex..") is NOT a valid Big Reactor.")
		return -- Invalid reactorIndex
	else
		printLog("reactor["..reactorIndex.."] in temperatureControl(reactorIndex="..reactorIndex..") is a valid Big Reactor.")

		if reactor.getConnected() then
			printLog("reactor["..reactorIndex.."] in temperatureControl(reactorIndex="..reactorIndex..") is connected.")
		else
			printLog("reactor["..reactorIndex.."] in temperatureControl(reactorIndex="..reactorIndex..") is NOT connected.")
			return -- Disconnected reactor
		end -- if reactor.getConnected() then
	end

	local reactorNum = reactorIndex
	local rodPercentage = math.ceil(reactor.getControlRodLevel(0))
	local reactorTemp = math.ceil(reactor.getFuelTemperature())
	local localMinReactorTemp, localMaxReactorTemp = _G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMinTemp"], _G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMaxTemp"]

	--bypass if the reactor itself is set to not be auto-controlled
	if ((not _G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"]) or (_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"] == "false")) then
		-- No point modifying control rod levels for temperature if the reactor is offline
		if reactor.getActive() then
			-- Actively cooled reactors should range between 0^C-300^C
			-- Actually, active-cooled reactors should range between 300 and 420C (Mechaet)
			-- Accordingly I changed the below lines
			if reactor.isActivelyCooled() and not knowlinglyOverride then
				-- below was 0
				localMinReactorTemp = 300
				-- below was 300
				localMaxReactorTemp = 420
			else
				localMinReactorTemp = _G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMinTemp"]
				localMaxReactorTemp = _G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorMaxTemp"]
			end
			local lastTempPoll = _G[reactorNames[reactorIndex]]["ReactorOptions"]["lastTempPoll"]
			if _G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorCruising"] then
				--let's bypass all this math and hit the much-more-subtle cruise feature
				--printLog("min: "..localMinReactorTemp..", max: "..localMaxReactorTemp..", lasttemp: "..lastTempPoll..", ri: "..reactorIndex.."  EOL")
				reactorCruise(localMaxReactorTemp, localMinReactorTemp, reactorIndex)
			else
				-- Don't bring us to 100, that's effectively a shutdown
				if (reactorTemp > localMaxReactorTemp) and (rodPercentage ~= 99) then
					--increase the rods, but by how much?
					if (reactorTemp > lastTempPoll) then
						--we're climbing, we need to get this to decrease
						if ((reactorTemp - lastTempPoll) > 100) then
							--we're climbing really fast, arrest it
							if (rodPercentage + (10 * controlRodAdjustAmount)) > 99 then
								reactor.setAllControlRodLevels(99)
							else
								reactor.setAllControlRodLevels(rodPercentage + (10 * controlRodAdjustAmount))
							end
						else
							--we're not climbing by leaps and bounds, let's give it a rod adjustment based on temperature increase
							local diffAmount = reactorTemp - lastTempPoll
							diffAmount = (round(diffAmount/10, 0))/5
							controlRodAdjustAmount = diffAmount
							if (rodPercentage + controlRodAdjustAmount) > 99 then
								reactor.setAllControlRodLevels(99)
							else
								reactor.setAllControlRodLevels(rodPercentage + controlRodAdjustAmount)
							end
						end --if ((reactorTemp - lastTempPoll) > 100) then
					elseif (reactorTemp == lastTempPoll) then
						--temperature has stagnated, kick it very lightly
						local controlRodAdjustment = 1
						if (rodPercentage + controlRodAdjustment) > 99 then
							reactor.setAllControlRodLevels(99)
						else
							reactor.setAllControlRodLevels(rodPercentage + controlRodAdjustment)
						end
					end --if (reactorTemp > lastTempPoll) then
						--worth noting that if we're above temp but decreasing, we do nothing. let it continue decreasing.

				elseif (reactorTemp < localMinReactorTemp) and (rodPercentage ~=0) then
					--we're too cold. time to warm up, but by how much?
					if (reactorTemp < lastTempPoll) then
						--we're descending, let's stop that.
						if ((lastTempPoll - reactorTemp) > 100) then
							--we're headed for a new ice age, bring the heat
							if (rodPercentage - (10 * controlRodAdjustAmount)) < 0 then
								reactor.setAllControlRodLevels(0)
							else
								reactor.setAllControlRodLevels(rodPercentage - (10 * controlRodAdjustAmount))
							end
						else
							--we're not descending quickly, let's bump it based on descent rate
							local diffAmount = lastTempPoll - reactorTemp
							diffAmount = (round(diffAmount/10, 0))/5
							controlRodAdjustAmount = diffAmount
							if (rodPercentage - controlRodAdjustAmount) < 0 then
								reactor.setAllControlRodLevels(0)
							else
								reactor.setAllControlRodLevels(rodPercentage - controlRodAdjustAmount)
							end
						end --if ((lastTempPoll - reactorTemp) > 100) then
					elseif (reactorTemp == lastTempPoll) then
						--temperature has stagnated, kick it very lightly
						local controlRodAdjustment = 1
						if (rodPercentage - controlRodAdjustment) < 0 then
							reactor.setAllControlRodLevels(0)
						else
							reactor.setAllControlRodLevels(rodPercentage - controlRodAdjustment)
						end --if (rodPercentage - controlRodAdjustment) < 0 then

					end --if (reactorTemp < lastTempPoll) then
					--if we're below temp but increasing, do nothing and let it continue to rise.
				end --if (reactorTemp > localMaxReactorTemp) and (rodPercentage ~= 99) then

				if ((reactorTemp > localMinReactorTemp) and (reactorTemp < localMaxReactorTemp)) then
					--engage cruise mode
					_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorCruising"] = true
				end -- if ((reactorTemp > localMinReactorTemp) and (reactorTemp < localMaxReactorTemp)) then
			end -- if reactorCruising then
			--always set this number
			_G[reactorNames[reactorIndex]]["ReactorOptions"]["lastTempPoll"] = reactorTemp
			config.save(reactorNames[reactorIndex]..".options", _G[reactorNames[reactorIndex]])
		end -- if reactor.getActive() then
	else
		printLog("Bypassed temperature control due to rodOverride being "..tostring(_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"]).." EOL")
	end -- if not _G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"] then
end -- function temperatureControl(reactorIndex)

-- Load saved reactor parameters if ReactorOptions file exists
local function loadReactorOptions()
	local reactorOptions = fs.open("ReactorOptions", "r") -- See http://computercraft.info/wiki/Fs.open

	if reactorOptions then
		-- The following values were added by Lolmer
		minStoredEnergyPercent = reactorOptions.readLine()
		maxStoredEnergyPercent = reactorOptions.readLine()
		--added by Mechaet
		-- If we succeeded in reading a string, convert it to a number

		if minStoredEnergyPercent ~= nil then
			minStoredEnergyPercent = tonumber(minStoredEnergyPercent)
		end

		if maxStoredEnergyPercent ~= nil then
			maxStoredEnergyPercent = tonumber(maxStoredEnergyPercent)
		end

		reactorOptions.close()
	end -- if reactorOptions then

	-- Set default values if we failed to read any of the above
	if minStoredEnergyPercent == nil then
		minStoredEnergyPercent = 15
	end

	if maxStoredEnergyPercent == nil then
		maxStoredEnergyPercent = 85
	end

end -- function loadReactorOptions()


-- Save our reactor parameters
local function saveReactorOptions()
	local reactorOptions = fs.open("ReactorOptions", "w") -- See http://computercraft.info/wiki/Fs.open

	-- If we can save the files, save them
	if reactorOptions then
		local reactorIndex = 1
		-- The following values were added by Lolmer
		reactorOptions.writeLine(minStoredEnergyPercent)
		reactorOptions.writeLine(maxStoredEnergyPercent)
		reactorOptions.close()
	else
		printLog("Failed to open file ReactorOptions for writing!")
	end -- if reactorOptions then
end -- function saveReactorOptions()


local function displayReactorBars(barParams)
	-- Default to first reactor and first monitor
	setmetatable(barParams,{__index={reactorIndex=1, monitorIndex=1}})
	local reactorIndex, monitorIndex =
		barParams[1] or barParams.reactorIndex,
		barParams[2] or barParams.monitorIndex

	printLog("Called as displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..").")

	-- Grab current monitor
	local monitor = nil
	monitor = monitorList[monitorIndex]
	if not monitor then
		printLog("monitor["..monitorIndex.."] in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	-- Grab current reactor
	local reactor = nil
	reactor = reactorList[reactorIndex]
	if not reactor then
		printLog("reactor["..reactorIndex.."] in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is NOT a valid Big Reactor.")
		return -- Invalid reactorIndex
	else
		printLog("reactor["..reactorIndex.."] in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is a valid Big Reactor.")
		if reactor.getConnected() then
			printLog("reactor["..reactorIndex.."] in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is connected.")
		else
			printLog("reactor["..reactorIndex.."] in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is NOT connected.")
			return -- Disconnected reactor
		end -- if reactor.getConnected() then
	end -- if not reactor then

	-- Draw border lines
	local width, height = monitor.getSize()
	printLog("Size of monitor is "..width.."w x"..height.."h in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..")")

	for i=3, 5 do
		monitor.setCursorPos(22, i)
		monitor.write("|")
	end

	drawLine(2, monitorIndex)
	drawLine(6, monitorIndex)

	-- Draw some text
	local fuelString = "Fuel: "
	local tempString = "Temp: "
	local energyBufferString = ""

	if reactor.isActivelyCooled() then
		energyBufferString = "Steam: "
	else
		energyBufferString = "Energy: "
	end

	local padding = math.max(string.len(fuelString), string.len(tempString), string.len(energyBufferString))

	local fuelPercentage = round(reactor.getFuelAmount()/reactor.getFuelAmountMax()*100,1)
	print{fuelString,2,3,monitorIndex}
	print{fuelPercentage.." %",padding+2,3,monitorIndex}

	local reactorTemp = math.ceil(reactor.getFuelTemperature())
	print{tempString,2,5,monitorIndex}
	print{reactorTemp.." C",padding+2,5,monitorIndex}

	local rodPercentage = math.ceil(reactor.getControlRodLevel(0))
	printLog("Current Rod Percentage for reactor["..reactorIndex.."] is "..rodPercentage.."% in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..").")
	-- Allow controlling Reactor Control Rod Level from GUI
	-- Decrease rod button: 23X, 4Y
	-- Increase rod button: 28X, 4Y
	if (xClick == 23) and (yClick == 4) and (sideClick == monitorNames[monitorIndex]) then
		printLog("Decreasing Rod Levels in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..").")
		--Decrease rod level by amount
		newRodPercentage = rodPercentage - (5 * controlRodAdjustAmount)
		if newRodPercentage < 0 then
			newRodPercentage = 0
		end
		sideClick, xClick, yClick = 0, 0, 0

		printLog("Setting reactor["..reactorIndex.."] Rod Levels to "..newRodPercentage.."% in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..").")
		reactor.setAllControlRodLevels(newRodPercentage)
		_G[reactorNames[reactorIndex]]["ReactorOptions"]["baseControlRodLevel"] = newRodPercentage

		-- Save updated rod percentage
		config.save(reactorNames[reactorIndex]..".options", _G[reactorNames[reactorIndex]])
		rodPercentage = newRodPercentage
	elseif (xClick == 29) and (yClick == 4) and (sideClick == monitorNames[monitorIndex]) then
		printLog("Increasing Rod Levels in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..").")
		--Increase rod level by amount
		newRodPercentage = rodPercentage + (5 * controlRodAdjustAmount)
		if newRodPercentage > 100 then
			newRodPercentage = 100
		end
		sideClick, xClick, yClick = 0, 0, 0

		printLog("Setting reactor["..reactorIndex.."] Rod Levels to "..newRodPercentage.."% in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..").")
		reactor.setAllControlRodLevels(newRodPercentage)
		_G[reactorNames[reactorIndex]]["ReactorOptions"]["baseControlRodLevel"] = newRodPercentage
		
		-- Save updated rod percentage
		config.save(reactorNames[reactorIndex]..".options", _G[reactorNames[reactorIndex]])
		rodPercentage = round(newRodPercentage,0)
	else
		printLog("No change to Rod Levels requested by "..progName.." GUI in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..").")
	end -- if (xClick == 29) and (yClick == 4) and (sideClick == monitorNames[monitorIndex]) then

	print{"Rod (%)",23,3,monitorIndex}
	print{"<     >",23,4,monitorIndex}
	print{stringTrim(rodPercentage),25,4,monitorIndex}


	-- getEnergyProducedLastTick() is used for both RF/t (passively cooled) and mB/t (actively cooled)
	local energyBuffer = reactor.getEnergyProducedLastTick()
	if reactor.isActivelyCooled() then
		printLog("reactor["..reactorIndex.."] produced "..energyBuffer.." mB last tick in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..").")
	else
		printLog("reactor["..reactorIndex.."] produced "..energyBuffer.." RF last tick in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..").")
	end

	print{energyBufferString,2,4,monitorIndex}

	-- Actively cooled reactors do not produce energy, only hot fluid mB/t to be used in a turbine
	-- still uses getEnergyProducedLastTick for mB/t of hot fluid generated
	if not reactor.isActivelyCooled() then
		printLog("reactor["..reactorIndex.."] in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is NOT an actively cooled reactor.")

		-- Draw stored energy buffer bar
		drawBar(2,8,28,8,colors.gray,monitorIndex)

		local curStoredEnergyPercent = getReactorStoredEnergyBufferPercent(reactor)
		if curStoredEnergyPercent > 4 then
			drawBar(2, 8, math.floor(26*curStoredEnergyPercent/100)+2, 8, colors.yellow, monitorIndex)
		elseif curStoredEnergyPercent > 0 then
			drawPixel(2, 8, colors.yellow, monitorIndex)
		end -- if curStoredEnergyPercent > 4 then

		print{"Energy Buffer",2,7,monitorIndex}
		print{curStoredEnergyPercent, width-(string.len(curStoredEnergyPercent)+2),7,monitorIndex}
		print{"%",28,7,monitorIndex}

		print{math.ceil(energyBuffer).." RF/t",padding+2,4,monitorIndex}
	else
		printLog("reactor["..reactorIndex.."] in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is an actively cooled reactor.")
		print{math.ceil(energyBuffer).." mB/t",padding+2,4,monitorIndex}
	end -- if not reactor.isActivelyCooled() then

	-- Print rod override status
	local reactorRodOverrideStatus = ""

	print{"Rod Auto-adjust:",2,9,monitorIndex}

	if not _G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"] then
		printLog("Reactor Rod Override status is: "..tostring(_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"]).." EOL")
		reactorRodOverrideStatus = "Enabled"
		monitor.setTextColor(colors.green)
	else
		printLog("Reactor Rod Override status is: "..tostring(_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"]).." EOL")
		reactorRodOverrideStatus = "Disabled"
		monitor.setTextColor(colors.red)
	end -- if not reactorRodOverride then
	printLog("reactorRodOverrideStatus is \""..reactorRodOverrideStatus.."\" in displayReactorBars(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..").")

	print{reactorRodOverrideStatus, width - string.len(reactorRodOverrideStatus) - 1, 9, monitorIndex}
	monitor.setTextColor(colors.white)

	print{"Reactivity: "..math.ceil(reactor.getFuelReactivity()).." %", 2, 10, monitorIndex}
	print{"Fuel: "..round(reactor.getFuelConsumedLastTick(),3).." mB/t", 2, 11, monitorIndex}
	print{"Waste: "..reactor.getWasteAmount().." mB", width-(string.len(reactor.getWasteAmount())+10), 11, monitorIndex}

	monitor.setTextColor(colors.blue)
	printCentered(_G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorName"],12,monitorIndex)
	monitor.setTextColor(colors.white)
end -- function displayReactorBars(barParams)


local function reactorStatus(statusParams)
	-- Default to first reactor and first monitor
	setmetatable(statusParams,{__index={reactorIndex=1, monitorIndex=1}})
	local reactorIndex, monitorIndex =
		statusParams[1] or statusParams.reactorIndex,
		statusParams[2] or statusParams.monitorIndex
	printLog("Called as reactorStatus(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..")")

	-- Grab current monitor
	local monitor = nil
	monitor = monitorList[monitorIndex]
	if not monitor then
		printLog("monitor["..monitorIndex.."] in reactorStatus(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	-- Grab current reactor
	local reactor = nil
	reactor = reactorList[reactorIndex]
	if not reactor then
		printLog("reactor["..reactorIndex.."] in reactorStatus(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is NOT a valid Big Reactor.")
		return -- Invalid reactorIndex
	else
		printLog("reactor["..reactorIndex.."] in reactorStatus(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is a valid Big Reactor.")
	end

	local width, height = monitor.getSize()
	local reactorStatus = ""

	if reactor.getConnected() then
		printLog("reactor["..reactorIndex.."] in reactorStatus(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is connected.")

		if reactor.getActive() then
			reactorStatus = "ONLINE"

			-- Set "ONLINE" to blue if the actively cooled reactor is both in cruise mode and online
			if _G[reactorNames[reactorIndex]]["ReactorOptions"]["reactorCruising"] and reactor.isActivelyCooled() then
				monitor.setTextColor(colors.blue)
			else
				monitor.setTextColor(colors.green)
			end -- if reactorCruising and reactor.isActivelyCooled() then
		else
			reactorStatus = "OFFLINE"
			monitor.setTextColor(colors.red)
		end -- if reactor.getActive() then

		if xClick >= (width - string.len(reactorStatus) - 1) and xClick <= (width-1) and (sideClick == monitorNames[monitorIndex]) then
			if yClick == 1 then
				reactor.setActive(not reactor.getActive()) -- Toggle reactor status
				_G[reactorNames[reactorIndex]]["ReactorOptions"]["autoStart"] = reactor.getActive()
				config.save(reactorNames[reactorIndex]..".options", _G[reactorNames[reactorIndex]])
				sideClick, xClick, yClick = 0, 0, 0 -- Reset click after we register it

				-- If someone offlines the reactor (offline after a status click was detected), then disable autoStart
				if not reactor.getActive() then
					_G[reactorNames[reactorIndex]]["ReactorOptions"]["autoStart"] = false
				end
			end -- if yClick == 1 then
		end -- if (xClick >= (width - string.len(reactorStatus) - 1) and xClick <= (width-1)) and (sideClick == monitorNames[monitorIndex]) then

		-- Allow disabling rod level auto-adjust and only manual rod level control
		if ((xClick > 23 and xClick < 28 and yClick == 4)
				or (xClick > 20 and xClick < 27 and yClick == 9))
				and (sideClick == monitorNames[monitorIndex]) then
			_G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"] = not _G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"]
			config.save(reactorNames[reactorIndex]..".options", _G[reactorNames[reactorIndex]])
			sideClick, xClick, yClick = 0, 0, 0 -- Reset click after we register it
		end -- if (xClick > 23) and (xClick < 28) and (yClick == 4) and (sideClick == monitorNames[monitorIndex]) then

	else
		printLog("reactor["..reactorIndex.."] in reactorStatus(reactorIndex="..reactorIndex..",monitorIndex="..monitorIndex..") is NOT connected.")
		reactorStatus = "DISCONNECTED"
		monitor.setTextColor(colors.red)
	end -- if reactor.getConnected() then

	print{reactorStatus, width - string.len(reactorStatus) - 1, 1, monitorIndex}
	monitor.setTextColor(colors.white)
end -- function reactorStatus(statusParams)


-- Display all found reactors' status to monitor 1
-- This is only called if multiple reactors and/or a reactor plus at least one turbine are found
local function displayAllStatus()
	local reactor, turbine = nil, nil
	local onlineReactor, onlineTurbine = 0, 0
	local totalReactorRF, totalReactorSteam, totalTurbineRF = 0, 0, 0
	local totalReactorFuelConsumed = 0
	local totalCoolantStored, totalSteamStored, totalEnergy, totalMaxEnergyStored = 0, 0, 0, 0 -- Total turbine and reactor energy buffer and overall capacity
	local maxSteamStored = (2000*#turbineList)+(5000*#reactorList)
	local maxCoolantStored = (2000*#turbineList)+(5000*#reactorList)

	local monitor, monitorIndex = nil, 1
	monitor = monitorList[monitorIndex]
	if not monitor then
		printLog("monitor["..monitorIndex.."] in displayAllStatus() is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	for reactorIndex = 1, #reactorList do
		reactor = reactorList[reactorIndex]
		if not reactor then
			printLog("reactor["..reactorIndex.."] in displayAllStatus() is NOT a valid Big Reactor.")
			break -- Invalid reactorIndex
		else
			printLog("reactor["..reactorIndex.."] in displayAllStatus() is a valid Big Reactor.")
		end -- if not reactor then

		if reactor.getConnected() then
			printLog("reactor["..reactorIndex.."] in displayAllStatus() is connected.")
			if reactor.getActive() then
				onlineReactor = onlineReactor + 1
				totalReactorFuelConsumed = totalReactorFuelConsumed + reactor.getFuelConsumedLastTick()
			end -- reactor.getActive() then

			-- Actively cooled reactors do not produce or store energy
			if not reactor.isActivelyCooled() then
				totalMaxEnergyStored = totalMaxEnergyStored + 10000000 -- Reactors store 10M RF
				totalEnergy = totalEnergy + reactor.getEnergyStored()
				totalReactorRF = totalReactorRF + reactor.getEnergyProducedLastTick()
			else
				totalReactorSteam = totalReactorSteam + reactor.getEnergyProducedLastTick()
				totalSteamStored = totalSteamStored + reactor.getHotFluidAmount()
				totalCoolantStored = totalCoolantStored + reactor.getCoolantAmount()
			end -- if not reactor.isActivelyCooled() then
		else
			printLog("reactor["..reactorIndex.."] in displayAllStatus() is NOT connected.")
		end -- if reactor.getConnected() then
	end -- for reactorIndex = 1, #reactorList do

	for turbineIndex = 1, #turbineList do
		turbine = turbineList[turbineIndex]
		if not turbine then
			printLog("turbine["..turbineIndex.."] in displayAllStatus() is NOT a valid Turbine.")
			break -- Invalid turbineIndex
		else
			printLog("turbine["..turbineIndex.."] in displayAllStatus() is a valid Turbine.")
		end -- if not turbine then

		if turbine.getConnected() then
			printLog("turbine["..turbineIndex.."] in displayAllStatus() is connected.")
			if turbine.getActive() then
				onlineTurbine = onlineTurbine + 1
			end

			totalMaxEnergyStored = totalMaxEnergyStored + 1000000 -- Turbines store 1M RF
			totalEnergy = totalEnergy + turbine.getEnergyStored()
			totalTurbineRF = totalTurbineRF + turbine.getEnergyProducedLastTick()
			totalSteamStored = totalSteamStored + turbine.getInputAmount()
			totalCoolantStored = totalCoolantStored + turbine.getOutputAmount()
		else
			printLog("turbine["..turbineIndex.."] in displayAllStatus() is NOT connected.")
		end -- if turbine.getConnected() then
	end -- for turbineIndex = 1, #turbineList do

	print{"Reactors online/found: "..onlineReactor.."/"..#reactorList, 2, 3, monitorIndex}
	print{"Turbines online/found: "..onlineTurbine.."/"..#turbineList, 2, 4, monitorIndex}

	if totalReactorRF ~= 0 then
		monitor.setTextColor(colors.blue)
		printRight("Reactor", 9, monitorIndex)
		monitor.setTextColor(colors.white)
		printRight(math.ceil(totalReactorRF).." (RF/t)", 10, monitorIndex)
	end

	if #turbineList then
		-- Display liquids
		monitor.setTextColor(colors.blue)
		printLeft("Steam (mB)", 6, monitorIndex)
		monitor.setTextColor(colors.white)
		printLeft(math.ceil(totalSteamStored).."/"..maxSteamStored, 7, monitorIndex)
		printLeft(math.ceil(totalReactorSteam).." mB/t", 8, monitorIndex)
		monitor.setTextColor(colors.blue)
		printRight("Coolant (mB)", 6, monitorIndex)
		monitor.setTextColor(colors.white)
		printRight(math.ceil(totalCoolantStored).."/"..maxCoolantStored, 7, monitorIndex)

		monitor.setTextColor(colors.blue)
		printLeft("Turbine", 9, monitorIndex)
		monitor.setTextColor(colors.white)
		printLeft(math.ceil(totalTurbineRF).." RF/t", 10, monitorIndex)
	end -- if #turbineList then

	printCentered("Fuel: "..round(totalReactorFuelConsumed,3).." mB/t", 11, monitorIndex)
	print{"Buffer: "..math.ceil(totalEnergy,3).."/"..totalMaxEnergyStored.." RF", 2, 12, monitorIndex}
end -- function displayAllStatus()


-- Get turbine status
local function displayTurbineBars(turbineIndex, monitorIndex)
	printLog("Called as displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..").")

	-- Grab current monitor
	local monitor = nil
	monitor = monitorList[monitorIndex]
	if not monitor then
		printLog("monitor["..monitorIndex.."] in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..") is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	-- Grab current turbine
	local turbine = nil
	turbine = turbineList[turbineIndex]
	if not turbine then
		printLog("turbine["..turbineIndex.."] in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..") is NOT a valid Big Turbine.")
		return -- Invalid turbineIndex
	else
		printLog("turbine["..turbineIndex.."] in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..") is a valid Big Turbine.")
		if turbine.getConnected() then
			printLog("turbine["..turbineIndex.."] in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..") is connected.")
		else
			printLog("turbine["..turbineIndex.."] in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..") is NOT connected.")
			return -- Disconnected turbine
		end -- if turbine.getConnected() then
	end -- if not turbine then

	--local variable to match the view on the monitor
	local turbineBaseSpeed = tonumber(_G[turbineNames[turbineIndex]]["TurbineOptions"]["BaseSpeed"])

	-- Draw border lines
	local width, height = monitor.getSize()

	for i=3, 6 do
		monitor.setCursorPos(21, i)
		monitor.write("|")
	end

	drawLine(2,monitorIndex)
	drawLine(7,monitorIndex)

	-- Allow controlling Turbine Flow Rate from GUI
	-- Decrease flow rate button: 22X, 4Y
	-- Increase flow rate button: 28X, 4Y
	local turbineFlowRate = tonumber(_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastFlow"])
	if (xClick == 22) and (yClick == 4) and (sideClick == monitorNames[monitorIndex]) then
		printLog("Decrease to Flow Rate requested by "..progName.." GUI in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..").")
		--Decrease rod level by amount
		newTurbineFlowRate = turbineFlowRate - flowRateAdjustAmount
		if newTurbineFlowRate < 0 then
			newTurbineFlowRate = 0
		end
		sideClick, xClick, yClick = 0, 0, 0

		-- Check bounds [0,2000]
		if newTurbineFlowRate > 2000 then
			newTurbineFlowRate = 2000
		elseif newTurbineFlowRate < 0 then
			newTurbineFlowRate = 25 -- Don't go to zero, might as well power off
		end

		turbine.setFluidFlowRateMax(newTurbineFlowRate)
		_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastFlow"] = newTurbineFlowRate
		-- Save updated Turbine Flow Rate
		turbineFlowRate = newTurbineFlowRate
		config.save(turbineNames[turbineIndex]..".options", _G[turbineNames[turbineIndex]])
	elseif (xClick == 29) and (yClick == 4) and (sideClick == monitorNames[monitorIndex]) then
		printLog("Increase to Flow Rate requested by "..progName.." GUI in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..").")
		--Increase rod level by amount
		newTurbineFlowRate = turbineFlowRate + flowRateAdjustAmount
		if newTurbineFlowRate > 2000 then
			newTurbineFlowRate = 2000
		end
		sideClick, xClick, yClick = 0, 0, 0

		-- Check bounds [0,2000]
		if newTurbineFlowRate > 2000 then
			newTurbineFlowRate = 2000
		elseif newTurbineFlowRate < 0 then
			newTurbineFlowRate = 25 -- Don't go to zero, might as well power off
		end

		turbine.setFluidFlowRateMax(newTurbineFlowRate)
		
		-- Save updated Turbine Flow Rate
		turbineFlowRate = math.ceil(newTurbineFlowRate)
		_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastFlow"] = turbineFlowRate
		config.save(turbineNames[turbineIndex]..".options", _G[turbineNames[turbineIndex]])
	else
		printLog("No change to Flow Rate requested by "..progName.." GUI in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..").")
	end -- if (xClick == 29) and (yClick == 4) and (sideClick == monitorNames[monitorIndex]) then

	if (xClick == 22) and (yClick == 6) and (sideClick == monitorNames[monitorIndex]) then
		printLog("Decrease to Turbine RPM requested by "..progName.." GUI in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..").")
		rpmRateAdjustment = 909
		newTurbineBaseSpeed = turbineBaseSpeed - rpmRateAdjustment
		if newTurbineBaseSpeed < 908 then
			newTurbineBaseSpeed = 908
		end
		sideClick, xClick, yClick = 0, 0, 0
		_G[turbineNames[turbineIndex]]["TurbineOptions"]["BaseSpeed"] = newTurbineBaseSpeed
		config.save(turbineNames[turbineIndex]..".options", _G[turbineNames[turbineIndex]])
	elseif (xClick == 29) and (yClick == 6) and (sideClick == monitorNames[monitorIndex]) then
		printLog("Increase to Turbine RPM requested by "..progName.." GUI in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..").")
		rpmRateAdjustment = 909
		newTurbineBaseSpeed = turbineBaseSpeed + rpmRateAdjustment
		if newTurbineBaseSpeed > 2726 then
			newTurbineBaseSpeed = 2726
		end
		sideClick, xClick, yClick = 0, 0, 0
		_G[turbineNames[turbineIndex]]["TurbineOptions"]["BaseSpeed"] = newTurbineBaseSpeed
		config.save(turbineNames[turbineIndex]..".options", _G[turbineNames[turbineIndex]])
	else
		printLog("No change to Turbine RPM requested by "..progName.." GUI in displayTurbineBars(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..").")
	end -- if (xClick == 29) and (yClick == 4) and (sideClick == monitorNames[monitorIndex]) then
	print{"  mB/t",22,3,monitorIndex}
	print{"<      >",22,4,monitorIndex}
	print{stringTrim(turbineFlowRate),24,4,monitorIndex}
	print{"  RPM",22,5,monitorIndex}
	print{"<      >",22,6,monitorIndex}
	print{stringTrim(tonumber(_G[turbineNames[turbineIndex]]["TurbineOptions"]["BaseSpeed"])),24,6,monitorIndex}
	local rotorSpeedString = "Speed: "
	local energyBufferString = "Energy: "
	local padding = math.max(string.len(rotorSpeedString), string.len(energyBufferString))

	local energyBuffer = turbine.getEnergyProducedLastTick()
	print{energyBufferString,1,4,monitorIndex}
	print{math.ceil(energyBuffer).." RF/t",padding+1,4,monitorIndex}

	local rotorSpeed = math.ceil(turbine.getRotorSpeed())
	print{rotorSpeedString,1,5,monitorIndex}
	print{rotorSpeed.." RPM",padding+1,5,monitorIndex}

	-- PaintUtils only outputs to term., not monitor.
	-- See http://www.computercraft.info/forums2/index.php?/topic/15540-paintutils-on-a-monitor/

	-- Draw stored energy buffer bar
	drawBar(1,9,28,9,colors.gray,monitorIndex)

	local curStoredEnergyPercent = getTurbineStoredEnergyBufferPercent(turbine)
	if curStoredEnergyPercent > 4 then
		drawBar(1, 9, math.floor(26*curStoredEnergyPercent/100)+2, 9, colors.yellow,monitorIndex)
	elseif curStoredEnergyPercent > 0 then
		drawPixel(1, 9, colors.yellow, monitorIndex)
	end -- if curStoredEnergyPercent > 4 then

	print{"Energy Buffer",1,8,monitorIndex}
	print{curStoredEnergyPercent, width-(string.len(curStoredEnergyPercent)+2),8,monitorIndex}
	print{"%",28,8,monitorIndex}

	-- Print rod override status
	local turbineFlowRateOverrideStatus = ""

	print{"Flow Auto-adjust:",2,10,monitorIndex}

	if ((not _G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"]) or (_G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"] == "false")) then
		turbineFlowRateOverrideStatus = "Enabled"
		monitor.setTextColor(colors.green)
	else
		turbineFlowRateOverrideStatus = "Disabled"
		monitor.setTextColor(colors.red)
	end -- if not reactorRodOverride then

	print{turbineFlowRateOverrideStatus, width - string.len(turbineFlowRateOverrideStatus) - 1, 10, monitorIndex}
	monitor.setTextColor(colors.white)

	monitor.setTextColor(colors.blue)
	printCentered(_G[turbineNames[turbineIndex]]["TurbineOptions"]["turbineName"],12,monitorIndex)
	monitor.setTextColor(colors.white)

	-- Need equation to figure out rotor efficiency and display
end -- function displayTurbineBars(statusParams)


-- Display turbine status
local function turbineStatus(turbineIndex, monitorIndex)
	-- Grab current monitor
	local monitor = nil

	printLog("Called as turbineStatus(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..").")

	monitor = monitorList[monitorIndex]
	if not monitor then
		printLog("monitor["..monitorIndex.."] in turbineStatus(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..") is NOT a valid monitor.")
		return -- Invalid monitorIndex
	end

	-- Grab current turbine
	local turbine = nil
	turbine = turbineList[turbineIndex]
	if not turbine then
		printLog("turbine["..turbineIndex.."] in turbineStatus(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..") is NOT a valid Big Turbine.")
		return -- Invalid turbineIndex
	else
		printLog("turbine["..turbineIndex.."] in turbineStatus(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..") is a valid Big Turbine.")
	end

	local width, height = monitor.getSize()
	local turbineStatus = ""

	if turbine.getConnected() then
		printLog("turbine["..turbineIndex.."] in turbineStatus(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..") is connected.")
		if turbine.getActive() then
			turbineStatus = "ONLINE"
			monitor.setTextColor(colors.green)
		else
			turbineStatus = "OFFLINE"
			monitor.setTextColor(colors.red)
		end -- if turbine.getActive() then

		if (xClick >= (width - string.len(turbineStatus) - 1)) and (xClick <= (width-1)) and (sideClick == monitorNames[monitorIndex]) then
			if yClick == 1 then
				turbine.setActive(not turbine.getActive()) -- Toggle turbine status
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["autoStart"] = turbine.getActive()
				config.save(turbineNames[turbineIndex]..".options", _G[turbineNames[turbineIndex]])
				sideClick, xClick, yClick = 0, 0, 0 -- Reset click after we register it
			end -- if yClick == 1 then
		end -- if (xClick >= (width - string.len(turbineStatus) - 1)) and (xClick <= (width-1)) and (sideClick == monitorNames[monitorIndex]) then

		-- Allow disabling/enabling flow rate auto-adjust
		if (xClick > 23 and xClick < 28 and yClick == 4) and (sideClick == monitorNames[monitorIndex]) then
			_G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"] = true
			sideClick, xClick, yClick = 0, 0, 0 -- Reset click after we register it
		elseif (xClick > 20 and xClick < 27 and yClick == 10) and (sideClick == monitorNames[monitorIndex]) then
			
			if ((_G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"]) or (_G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"] == "true")) then
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"] = false
			else
				_G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"] = true
			end
			sideClick, xClick, yClick = 0, 0, 0 -- Reset click after we register it
		end
		config.save(turbineNames[turbineIndex]..".options", _G[turbineNames[turbineIndex]])

	else
		printLog("turbine["..turbineIndex.."] in turbineStatus(turbineIndex="..turbineIndex..",monitorIndex="..monitorIndex..") is NOT connected.")
		turbineStatus = "DISCONNECTED"
		monitor.setTextColor(colors.red)
	end -- if turbine.getConnected() then

	print{turbineStatus, width - string.len(turbineStatus) - 1, 1, monitorIndex}
	monitor.setTextColor(colors.white)
end -- function function turbineStatus(turbineIndex, monitorIndex)


-- Maintain Turbine flow rate at 900 or 1,800 RPM
local function flowRateControl(turbineIndex)
	if ((not _G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"]) or (_G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"] == "false")) then
		
		printLog("Called as flowRateControl(turbineIndex="..turbineIndex..").")

		-- Grab current turbine
		local turbine = nil
		turbine = turbineList[turbineIndex]

		-- assign for the duration of this run
		local lastTurbineSpeed = tonumber(_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastSpeed"])
		local turbineBaseSpeed = tonumber(_G[turbineNames[turbineIndex]]["TurbineOptions"]["BaseSpeed"])

		if not turbine then
			printLog("turbine["..turbineIndex.."] in flowRateControl(turbineIndex="..turbineIndex..") is NOT a valid Big Turbine.")
			return -- Invalid turbineIndex
		else
			printLog("turbine["..turbineIndex.."] in flowRateControl(turbineIndex="..turbineIndex..") is a valid Big Turbine.")

			if turbine.getConnected() then
				printLog("turbine["..turbineIndex.."] in flowRateControl(turbineIndex="..turbineIndex..") is connected.")
			else
				printLog("turbine["..turbineIndex.."] in flowRateControl(turbineIndex="..turbineIndex..") is NOT connected.")
			end -- if turbine.getConnected() then
		end -- if not turbine then

		-- No point modifying control rod levels for temperature if the turbine is offline
		if turbine.getActive() then
			printLog("turbine["..turbineIndex.."] in flowRateControl(turbineIndex="..turbineIndex..") is active.")

			local flowRate = tonumber(_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastFlow"])
			local flowRateUserMax = math.ceil(turbine.getFluidFlowRateMax())
			local rotorSpeed = math.ceil(turbine.getRotorSpeed())
			local newFlowRate = 0

			-- Going to control the turbine based on target RPM since changing the target flow rate bypasses this function
			if (rotorSpeed < turbineBaseSpeed) then
				printLog("BELOW COMMANDED SPEED")
				if (rotorSpeed > lastTurbineSpeed) then
					--we're still increasing, let's let it level off
					--also lets the first control pass go by on startup
				elseif (rotorSpeed < lastTurbineSpeed) then
					--we're decreasing where we should be increasing, do something
					if ((lastTurbineSpeed - rotorSpeed) > 100) then
						--kick it harder
						newFlowRate = 2000
						printLog("HARD KICK")
					else
						--let's adjust based on proximity
						flowAdjustment = (turbineBaseSpeed - rotorSpeed)/5
						newFlowRate = flowRate + flowAdjustment
						printLog("Light Kick: new flow rate is "..newFlowRate.." mB/t and flowAdjustment was "..flowAdjustment.." EOL")
					end
				else
					--we've stagnated, kick it.
					flowAdjustment = (turbineBaseSpeed - lastTurbineSpeed)
					newFlowRate = flowRate + flowAdjustment
					printLog("Stagnated: new flow rate is "..newFlowRate.." mB/t and flowAdjustment was "..flowAdjustment.." EOL")
				end --if (rotorSpeed > lastTurbineSpeed) then
			else
				--we're above commanded turbine speed
				printLog("ABOVE COMMANDED SPEED")
				if (rotorSpeed < lastTurbineSpeed) then
				--we're decreasing, let it level off
				--also bypasses first control pass on startup
				elseif (rotorSpeed > lastTurbineSpeed) then
					--we're above and ascending.
					if ((rotorSpeed - lastTurbineSpeed) > 100) then
						--halt
						newFlowRate = 25
					else
						--let's adjust based on proximity
						flowAdjustment = (rotorSpeed - turbineBaseSpeed)/5
						newFlowRate = flowRate - flowAdjustment
						printLog("Light Kick: new flow rate is "..newFlowRate.." mB/t and flowAdjustment was "..flowAdjustment.." EOL")
					end
				else
					--we've stagnated, kick it.
					flowAdjustment = (lastTurbineSpeed - turbineBaseSpeed)
					newFlowRate = flowRate - flowAdjustment
					printLog("Stagnated: new flow rate is "..newFlowRate.." mB/t and flowAdjustment was "..flowAdjustment.." EOL")
				end --if (rotorSpeed < lastTurbineSpeed) then
			end --if (rotorSpeed < turbineBaseSpeed)

			--check to make sure an adjustment was made
			if (newFlowRate == 0) then
				--do nothing, we didn't ask for anything this pass
			else
				--boundary check
				if newFlowRate > 2000 then
					newFlowRate = 2000
				elseif newFlowRate < 25 then
					newFlowRate = 25 -- Don't go to zero, might as well power off
				end -- if newFlowRate > 2000 then
				--no sense running an adjustment if it's not necessary
				if ((newFlowRate < flowRate) or (newFlowRate > flowRate)) then
					printLog("turbine["..turbineIndex.."] in flowRateControl(turbineIndex="..turbineIndex..") is being commanded to "..newFlowRate.." mB/t flow")
					newFlowRate = round(newFlowRate, 0)
					turbine.setFluidFlowRateMax(newFlowRate)
					_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastFlow"] = newFlowRate
					config.save(turbineNames[turbineIndex]..".options", _G[turbineNames[turbineIndex]])
				end
			end
			--always set this
			_G[turbineNames[turbineIndex]]["TurbineOptions"]["LastSpeed"] = rotorSpeed
			config.save(turbineNames[turbineIndex]..".options", _G[turbineNames[turbineIndex]])
		else
			printLog("turbine["..turbineIndex.."] in flowRateControl(turbineIndex="..turbineIndex..") is NOT active.")
		end -- if turbine.getActive() then
	else
		printLog("turbine["..turbineIndex.."] has flow override set to "..tostring(_G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"])..", bypassing flow control.")
	end -- if not _G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"] then
end -- function flowRateControl(turbineIndex)


function main()
	-- Load reactor parameters and initialize systems
	loadReactorOptions()
	term.clear()
	term.setCursorPos(1,1)

	-- Get our initial list of connected monitors and reactors
	-- and initialize every cycle in case the connected devices change
	findMonitors()
	findReactors()
	findTurbines()

	while not finished do
		local reactor = nil
		local monitorIndex = 1

		-- For multiple reactors/monitors, monitor #1 is reserved for overall status
		-- or for multiple reactors/turbines and only one monitor
		if ( ( ((#reactorList + #turbineList) > 1) and (#monitorList >= 1) )   or
		     ( ((#reactorList + #turbineList) >=1) and (#monitorList >  1) ) ) then
			local monitor = nil
			monitor = monitorList[monitorIndex]
			if not monitor then
				printLog("monitor["..monitorIndex.."] in main() is NOT a valid monitor.")
				return -- Invalid monitorIndex
			end

			clearMonitor(progName.." "..progVer, monitorIndex) -- Clear monitor and draw borders
			printCentered(progName.." "..progVer, 1, monitorIndex)
			displayAllStatus()
			monitorIndex = 2 -- Next monitor, #1 is reserved for overall status
		end

		-- Iterate through reactors, continue to run even if not enough monitors are connected
		for reactorIndex = 1, #reactorList do
			local monitor = nil
			local reactorMonitorIndex = monitorIndex + reactorIndex - 1 -- reactorIndex starts at 1

			printLog("Attempting to display reactor["..reactorIndex.."] on monitor["..reactorMonitorIndex.."]...")

			reactor = reactorList[reactorIndex]
			if not reactor then
				printLog("reactor["..reactorIndex.."] in main() is NOT a valid Big Reactor.")
				break -- Invalid reactorIndex
			else
				printLog("reactor["..reactorIndex.."] in main() is a valid Big Reactor.")
			end --  if not reactor then

			-- Only attempt to assign a monitor if we have a monitor for this reactor
			if (reactorMonitorIndex <= #monitorList) then
				printLog("Displaying reactor["..reactorIndex.."] on monitor["..reactorMonitorIndex.."].")
				monitor = monitorList[reactorMonitorIndex]

				if not monitor then
					printLog("monitor["..reactorMonitorIndex.."] in main() is NOT a valid monitor.")
				else
					clearMonitor(progName, reactorMonitorIndex) -- Clear monitor and draw borders
					printCentered(progName, 1, reactorMonitorIndex)

					-- Display reactor status, includes "Disconnected" but found reactors
					reactorStatus{reactorIndex, reactorMonitorIndex}

					-- Draw the borders and bars for the current reactor on the current monitor
					displayReactorBars{reactorIndex, reactorMonitorIndex}
				end -- if not monitor
			else
				printLog("You may want "..(#reactorList + #turbineList + 1).." monitors for your "..#reactorList.." connected reactors and "..#turbineList.." connected turbines.")
			end -- if (#monitorList ~= 1) and (reactorMonitorIndex < #monitorList) then

			if reactor.getConnected() then
				printLog("reactor["..reactorIndex.."] is connected.")
				local curStoredEnergyPercent = getReactorStoredEnergyBufferPercent(reactor)

				-- Shutdown reactor if current stored energy % is >= desired level, otherwise activate
				-- First pass will have curStoredEnergyPercent=0 until displayBars() is run once
				if curStoredEnergyPercent >= maxStoredEnergyPercent then
					reactor.setActive(false)
				-- Do not auto-start the reactor if it was manually powered off (autoStart=false)
				elseif (curStoredEnergyPercent <= minStoredEnergyPercent) and (_G[reactorNames[reactorIndex]]["ReactorOptions"]["autoStart"] == true) then
					reactor.setActive(true)
				end -- if curStoredEnergyPercent >= maxStoredEnergyPercent then

				-- Don't try to auto-adjust control rods if manual control is requested
				if not _G[reactorNames[reactorIndex]]["ReactorOptions"]["rodOverride"] then
					temperatureControl(reactorIndex)
				end -- if not reactorRodOverride then
			else
				printLog("reactor["..reactorIndex.."] is NOT connected.")
			end -- if reactor.getConnected() then
		end -- for reactorIndex = 1, #reactorList do

		-- Monitors for turbines start after turbineMonitorOffset
		for turbineIndex = 1, #turbineList do
			local monitor = nil
			local turbineMonitorIndex = turbineIndex + turbineMonitorOffset

			printLog("Attempting to display turbine["..turbineIndex.."] on monitor["..turbineMonitorIndex.."]...")

			-- Only attempt to assign a monitor if we found a monitor for this turbine
			if (turbineMonitorIndex <= #monitorList) then
				printLog("Displaying turbine["..turbineIndex.."] on monitor["..turbineMonitorIndex.."].")
				monitor = monitorList[turbineMonitorIndex]
				if not monitor then
					printLog("monitor["..turbineMonitorIndex.."] in main() is NOT a valid monitor.")
				else
					clearMonitor(progName, turbineMonitorIndex) -- Clear monitor and draw borders
					printCentered(progName, 1, turbineMonitorIndex)

					-- Display turbine status, includes "Disconnected" but found turbines
					turbineStatus(turbineIndex, turbineMonitorIndex)

					-- Draw the borders and bars for the current turbine on the current monitor
					displayTurbineBars(turbineIndex, turbineMonitorIndex)
				end -- if not monitor
			else
				printLog("You may want "..(#reactorList + #turbineList + 1).." monitors for your "..#reactorList.." connected reactors and "..#turbineList.." connected turbines.")
			end -- if (#monitorList ~= 1) and (turbineMonitorIndex < #monitorList) then

			turbine = turbineList[turbineIndex]
			if not turbine then
				printLog("turbine["..turbineIndex.."] in main() is NOT a valid Big Turbine.")
				break -- Invalid turbineIndex
			else
				printLog("turbine["..turbineIndex.."] in main() is a valid Big Turbine.")
			end -- if not turbine then

			if turbine.getConnected() then
				printLog("turbine["..turbineIndex.."] is connected.")

				if not _G[turbineNames[turbineIndex]]["TurbineOptions"]["flowOverride"] then
					flowRateControl(turbineIndex)
				end -- if not turbineFlowRateOverride[turbineIndex] then
			else
				printLog("turbine["..turbineIndex.."] is NOT connected.")
			end -- if turbine.getConnected() then
		end -- for reactorIndex = 1, #reactorList do

		sleep(loopTime) -- Sleep
		saveReactorOptions()
	end -- while not finished do
end -- main()


local function eventHandler()
	while not finished do
		-- http://computercraft.info/wiki/Os.pullEvent
		-- http://www.computercraft.info/forums2/index.php?/topic/1516-ospullevent-what-is-it-and-how-is-it-useful/
		event, arg1, arg2, arg3 = os.pullEvent()

		if event == "monitor_touch" then
			sideClick, xClick, yClick = arg1, math.floor(arg2), math.floor(arg3)
			printLog("Side: "..arg1.." Monitor touch X: "..xClick.." Y: "..yClick)
		elseif event == "char" and not inManualMode then
			local ch = string.lower(arg1)
			if ch == "q" then
				finished = true
			elseif ch == "r" then
				finished = true
				os.reboot()
			end -- if ch == "q" then
		end -- if event == "monitor_touch" then
	end -- while not finished do
end -- function eventHandler()


while not finished do
	parallel.waitForAny(eventHandler, main)
	sleep(loopTime)
end -- while not finished do


-- Clear up after an exit
term.clear()
term.setCursorPos(1,1)
