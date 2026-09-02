local Emulator = {}

--Important things
local ffi = require("ffi")
local bit = require("bit")
local bnot, band, bor, bxor, lshift, rshift, truncate = bit.bnot, bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift, math.modf

--CPU
local ProgramCounter = 0 
local A = 0 
local X = 0 
local Y = 0
local SP = 0xFD 
local RAM = ffi.new("uint8_t[0x800]")
local ROM = {}
local Header = ffi.new("uint8_t[16]")
local DoNMI = false
local DoIRQ = false

local CarryFlag = false
local ZeroFlag = false
local DecimalFlag = false
local InterruptFlag = true
local OverflowFlag = false
local NegativeFlag = false

local DataBus = 0
local DataLatch = 0
local AddressBus = 0
local CycleTick = 0 --What cycle is this instruction on
local TempAddr = 0 --Temporary address for some addressing modes

function Read(address)
  if address < 0x2000 then
    DataBus = RAM[band(address, 0x7FF)]
  elseif address >= 0x8000 then
    --TODO: Add Mapper Chips
    DataBus = ROM[band(address - 0x8000, 0x4000 * Header[4] - 1)]
  end
  return DataBus
end
function Write(address, value)
  --TODO: Add Mapper Chips
  if address < 0x2000 then
    RAM[band(address, 0x7FF)] = value
  end
end
local InstData = {}
local opcode = 0
function EmulateCPU()
  if CycleTick == 0 then
    opcode = Read(ProgramCounter)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
    CycleTick = CycleTick + 1
  else
    InstData[opcode]()
    CycleTick = CycleTick + 1
  end
end
--Addressing Modes
function getAddrImm()
  AddressBus = ProgramCounter
  ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
end
function getAddrZP()
  if CycleTick == 1 then
    AddressBus = Read(ProgramCounter)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
  end
end
function getAddrAbs()
  if CycleTick == 1 then
    DataLatch = Read(ProgramCounter)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
  elseif CycleTick == 2 then
    Read(ProgramCounter)
    AddressBus = bor(lshift(DataBus, 8), DataLatch)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
  end
end
function getAddrZPOffX()
  if CycleTick == 1 then
    AddressBus = Read(ProgramCounter)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
  elseif CycleTick == 2 then
    Read(AddressBus) --Dummy Read :)
    AddressBus = band(AddressBus + X, 0xFF)
  end
end
function getAddrZPOffY()
  if CycleTick == 1 then
    AddressBus = Read(ProgramCounter)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
  elseif CycleTick == 2 then
    Read(AddressBus) --Dummy Read :)
    AddressBus = band(AddressBus + Y, 0xFF)
  end
end
function getAddrAbsOffX(isRead)
  if CycleTick == 1 then
    DataLatch = Read(ProgramCounter)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
  elseif CycleTick == 2 then
    Read(ProgramCounter)
    TempAddr = band(bor(lshift(DataBus, 8), DataLatch) + X, 0xFFFF)
    AddressBus = bor(lshift(DataBus, 8), band(DataLatch + X, 0xFF))
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
    if band(TempAddr, 0xFF00) == band(AddressBus, 0xFF00) and isRead then
      CycleTick = CycleTick + 1
    end
  elseif CycleTick == 3 then
    Read(AddressBus)
    AddressBus = TempAddr
  end
end
function getAddrAbsOffY(isRead)
  if CycleTick == 1 then
    DataLatch = Read(ProgramCounter)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
  elseif CycleTick == 2 then
    Read(ProgramCounter)
    TempAddr = band(bor(lshift(DataBus, 8), DataLatch) + Y, 0xFFFF)
    AddressBus = bor(lshift(DataBus, 8), band(DataLatch + Y, 0xFF))
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
    if band(TempAddr, 0xFF00) == band(AddressBus, 0xFF00) and isRead then
      CycleTick = CycleTick + 1
    end
  elseif CycleTick == 3 then
    Read(AddressBus)
    AddressBus = TempAddr
  end
end
function getAddrIndX()
  if CycleTick == 1 then
    AddressBus = Read(ProgramCounter)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
  elseif CycleTick == 2 then
    Read(AddressBus)
    AddressBus = band(AddressBus + X, 0xFF)
  elseif CycleTick == 3 then
    DataLatch = Read(AddressBus)
  elseif CycleTick == 4 then
    Read(band(AddressBus + 1, 0xFF))
    AddressBus = bor(lshift(DataBus, 8), DataLatch)
  end
end
function getAddrIndY(isRead)
  if CycleTick == 1 then
    AddressBus = Read(ProgramCounter)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
  elseif CycleTick == 2 then
    DataLatch = Read(AddressBus)
  elseif CycleTick == 3 then
    Read(band(AddressBus + 1, 0xFF))
    TempAddr = band(bor(lshift(DataBus, 8), DataLatch) + Y, 0xFFFF)
    AddressBus = bor(lshift(DataBus, 8), band(DataLatch + Y, 0xFF))
    if band(TempAddr, 0xFF00) == band(AddressBus, 0xFF00) and isRead then
      CycleTick = CycleTick + 1
    end
  elseif CycleTick == 4 then
    Read(AddressBus)
    AddressBus = TempAddr
  end
end
function getAddrRel(takeBranch)
  if CycleTick == 1 then
    DataLatch = Read(ProgramCounter)
    ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
    if not takeBranch then
      EndInstruction()
    end
  elseif CycleTick == 2 then
    Read(ProgramCounter) --Dummy Read :)
    if DataLatch > 127 then
      DataLatch = DataLatch - 0x100
    end
    TempAddr = ProgramCounter + DataLatch
    ProgramCounter = bor(band(ProgramCounter, 0xFF00), band(ProgramCounter + DataLatch, 0xFF))
    if band(TempAddr, 0xFF00) == band(ProgramCounter, 0xFF00) then
      EndInstruction()
    end
  else
    Read(ProgramCounter) --Dummy Read 2 :)
    ProgramCounter = TempAddr
    EndInstruction()
  end
end
function EndInstruction()
  CycleTick = 0
  --Poll Interrupts Here
  --Log Instruction Here
end
function LoadROM(filepath)
  local data, message = love.filesystem.read(filepath)
  
  if not data then
    error(message)
    return
  end
  for i = 1, 16 do
    Header[i - 1] = string.byte(data, i, i)
  end
  ROM = ffi.new("uint8_t[?]", #data - 0x10)
  for i = 1, #data - 0x10 do
    ROM[i - 1] = string.byte(data, i + 0x10, i + 0x10)
  end
  --TODO: Add NES 2.0 Support
end
function RESET()
  local ROMToLoad = "Super Mario Bros. (World).nes"
  LoadROM("roms/" .. ROMToLoad)
  
  local AddrLow = Read(0xFFFC)
  local AddrHigh = Read(0xFFFD)
  ProgramCounter = bor(lshift(AddrHigh, 8), AddrLow)
end

return Emulator