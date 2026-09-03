local Emulator = {}

--Important things
local ffi = require("ffi")
local bit = require("bit")
local bnot, band, bor, bxor, lshift, rshift, truncate = bit.bnot, bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift, math.modf

--CPU
local ProgramCounter = 0 --Where is the cpu reading
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

local DataBus = 0 --The most recently read value
local DataLatch = 0 --Temporary value
local AddressBus = 0 --Where is the cpu reading/writing
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
--TODO: Organize Instructions
--TODO: Add Unnoficial Instructions
--Site i used for cycle info: https://www.atarihq.com/danb/files/64doc.txt
local InstData = {
  [0x00] = function() --BRK
    if CycleTick == 1 then
      if not DoNMI and not DoIRQ then
        Read(ProgramCounter) --Dummy Read :) (Not sure if the dummy read only happens here)
        ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
      end
    elseif CycleTick == 2 then
      Write(0x100 + SP, rshift(ProgramCounter, 8))
      SP = band(SP - 1, 0xFF)
    elseif CycleTick == 3 then
      Write(0x100 + SP, band(ProgramCounter, 0xFF))
      SP = band(SP - 1, 0xFF)
    elseif CycleTick == 4 then
      local Temp = 0
      Temp = Temp + (CarryFlag and 1 or 0)
      Temp = Temp + (ZeroFlag and 2 or 0)
      Temp = Temp + (InterruptFlag and 4 or 0)
      Temp = Temp + (DecimalFlag and 8 or 0)
      Temp = Temp + ((DoNMI or DoIRQ) and 0 or 0x10)
      Temp = Temp + 0x20
      Temp = Temp + (OverflowFlag and 0x40 or 0)
      Temp = Temp + (NegativeFlag and 0x80 or 0)
      
      Write(0x100 + SP, Temp)
      SP = band(SP - 1, 0xFF)
    elseif CycleTick == 5 then
      --Is this here? Will look this later i guess.
      if DoIRQ then
        IntereuptFlag = true
      end
      DataLatch = Read(DoNMI and 0xFFFA or 0xFFFE)
    elseif CycleTick == 6 then
      Read(DoNMI and 0xFFFB or 0xFFFF)
      ProgramCounter = bor(lshift(DataBus, 8), DataLatch)
      
      DoNMI = false
      DoIRQ = false
      
      EndInstruction()
    end
  end,
  --Read-Modify-Write----------------------------
  [0x06] = function() --ASL <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpASL(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x0A] = function() --ASL A
    Read(ProgramCounter)
    OpASLImpl()
    
    EndInstruction()
  end,
  [0x0E] = function() --ASL $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpASL(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x16] = function() --ASL <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpASL(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x1E] = function() --ASL $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpASL(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  -----------------------------------------------
  --Only Read------------------------------------
  [0x61] = function() --ADC (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      OpADC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x65] = function() --ADC <$??
    getAddrZP()
    if CycleTick == 2 then
      OpADC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x69] = function() --ADC #$??
    getAddrImm()
    OpADC(Read(AddressBus))
    
    EndInstruction()
  end,
  [0x6D] = function() --ADC $????
    getAddrAbs()
    if CycleTick == 3 then
      OpADC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x71] = function() --ADC (<$??), Y
    getAddrIndY(true)
    if CycleTick == 5 then
      OpADC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x75] = function() --ADC <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      OpADC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x79] = function() --ADC $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      OpADC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x7D] = function() --ADC $????, X
    getAddrAbsOffX(true)
    if CycleTick == 4 then
      OpADC(Read(AddressBus))
      EndInstruction()
    end
  end,
  -------------------------------------------
  [0x21] = function() --AND (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      OpAND(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x25] = function() --AND <$??
    getAddrZP()
    if CycleTick == 2 then
      OpAND(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x29] = function() --AND #$??
    getAddrImm()
    OpAND(Read(AddressBus))
    
    EndInstruction()
  end,
  [0x2D] = function() --AND $????
    getAddrAbs()
    if CycleTick == 3 then
      OpAND(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x31] = function() --AND (<$??), Y
    getAddrIndY(true)
    if CycleTick == 5 then
      OpAND(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x35] = function() --AND <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      OpAND(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x39] = function() --AND $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      OpAND(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x3D] = function() --AND $????, X
    getAddrAbsOffX(true)
    if CycleTick == 4 then
      OpAND(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xC1] = function() --CMP (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      OpCMP(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xC5] = function() --CMP <$??
    getAddrZP()
    if CycleTick == 2 then
      OpCMP(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xC9] = function() --CMP #$??
    getAddrImm()
    OpCMP(Read(AddressBus))
    
    EndInstruction()
  end,
  [0xCD] = function() --CMP $????
    getAddrAbs()
    if CycleTick == 3 then
      OpCMP(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xD1] = function() --CMP (<$??), Y
    getAddrIndY(true)
    if CycleTick == 5 then
      OpCMP(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xD5] = function() --CMP <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      OpCMP(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xD9] = function() --CMP $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      OpCMP(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xDD] = function() --CMP $????, X
    getAddrAbsOffX(true)
    if CycleTick == 4 then
      OpCMP(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x24] = function() --BIT <$??
    getAddrZP()
    if CycleTick == 2 then
      OpBIT(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x2C] = function() --BIT $????
    getAddrAbs()
    if CycleTick == 3 then
      OpBIT(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xE0] = function() --CPX #$??
    getAddrImm()
    OpCPX(Read(AddressBus))
    
    EndInstruction()
  end,
  [0xE4] = function() --CPX <$??
    getAddrZP()
    if CycleTick == 2 then
      OpCPX(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xEC] = function() --CPX $????
    getAddrAbs()
    if CycleTick == 3 then
      OpCPX(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xC0] = function() --CPY #$??
    getAddrImm()
    OpCPY(Read(AddressBus))
    
    EndInstruction()
  end,
  [0xC4] = function() --CPY <$??
    getAddrZP()
    if CycleTick == 2 then
      OpCPY(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xCC] = function() --CPY $????
    getAddrAbs()
    if CycleTick == 3 then
      OpCPY(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xC6] = function() --DEC <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDEC(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xCE] = function() --DEC $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDEC(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xD6] = function() --DEC <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDEC(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xDE] = function() --DEC $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDEC(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xCA] = function() --DEX
    Read(ProgramCounter) --Dummy Read :)
    X = band(X - 1, 0xFF)
    
    ZeroFlag = X == 0
    NegativeFlag = X > 127
    
    EndInstruction()
  end,
  [0x88] = function() --DEY
    Read(ProgramCounter) --Dummy Read :)
    Y = band(Y - 1, 0xFF)
    
    ZeroFlag = Y == 0
    NegativeFlag = Y > 127
    
    EndInstruction()
  end,
  [0x41] = function() --EOR (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      OpEOR(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x45] = function() --EOR <$??
    getAddrZP()
    if CycleTick == 2 then
      OpEOR(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x49] = function() --EOR #$??
    getAddrImm()
    OpEOR(Read(AddressBus))
    
    EndInstruction()
  end,
  [0x4D] = function() --EOR $????
    getAddrAbs()
    if CycleTick == 3 then
      OpEOR(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x51] = function() --EOR (<$??), Y
    getAddrIndY(true)
    if CycleTick == 5 then
      OpEOR(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x55] = function() --EOR <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      OpEOR(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x59] = function() --EOR $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      OpEOR(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x5D] = function() --EOR $????, X
    getAddrAbsOffX(true)
    if CycleTick == 4 then
      OpEOR(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xE6] = function() --INC <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpINC(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xEE] = function() --INC $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpINC(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xF6] = function() --INC <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpINC(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xFE] = function() --INC $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpINC(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xE8] = function() --INX
    Read(ProgramCounter) --Dummy Read :)
    X = band(X + 1, 0xFF)
    
    ZeroFlag = X == 0
    NegativeFlag = X > 127
    
    EndInstruction()
  end,
  [0xC8] = function() --INY
    Read(ProgramCounter) --Dummy Read :)
    Y = band(Y + 1, 0xFF)
    
    ZeroFlag = Y == 0
    NegativeFlag = Y > 127
    
    EndInstruction()
  end,
  [0x4C] = function() --JMP $????
    if CycleTick == 1 then
      DataLatch = Read(ProgramCounter)
      ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
    else
      Read(ProgramCounter)
      ProgramCounter = bor(lshift(DataBus, 8), DataLatch)
      
      EndInstruction()
    end
  end,
  [0x6C] = function() --JMP ($????)
    if CycleTick == 1 then
      DataLatch = Read(ProgramCounter)
      ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
    elseif CycleTick == 2 then
      Read(ProgramCounter)
      AddressBus = bor(lshift(DataBus, 8), DataLatch)
    elseif CycleTick == 3 then
      DataLatch = Read(AddressBus)
    else
      --Apparently there's a mistake i guess when crossing a page boundary
      --The high byte of the Address Bus is not updated
      Read(bor(band(AddressBus, 0xFF00), band(AddressBus + 1, 0xFF)))
      ProgramCounter = bor(lshift(DataBus, 8), DataLatch)
      
      EndInstruction()
    end
  end,
  [0x20] = function() --JSR $????
    if CycleTick == 1 then
      DataLatch = Read(ProgramCounter)
      ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
    elseif CycleTick == 2 then
      --Its said in the site i used that this is a internal operation
      Read(0x100 + SP) --Dummy Read i guess
    elseif CycleTick == 3 then
      Write(0x100 + SP, rshift(ProgramCounter, 8))
      SP = band(SP - 1, 0xFF)
    elseif CycleTick == 4 then
      Write(0x100 + SP, band(ProgramCounter, 0xFF))
      SP = band(SP - 1, 0xFF)
    else
      Read(ProgramCounter)
      ProgramCounter = bor(lshift(DataBus, 8), DataLatch)
      
      EndInstruction()
    end
  end,
  [0xA1] = function() --LDA (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      A = Read(AddressBus) 

      NegativeFlag = A > 127 
      ZeroFlag = A == 0
      EndInstruction()
    end
  end,
  [0xA5] = function() --LDA <$??
    getAddrZP()
    if CycleTick == 2 then
      A = Read(AddressBus) 

      NegativeFlag = A > 127 
      ZeroFlag = A == 0
      EndInstruction()
    end
  end,
  [0xA9] = function() --LDA #$??
    getAddrImm()
    
    A = Read(AddressBus) 
    NegativeFlag = A > 127 
    ZeroFlag = A == 0
    
    EndInstruction()
  end,
  [0xAD] = function() --LDA $????
    getAddrAbs()
    if CycleTick == 3 then
      A = Read(AddressBus) 

      NegativeFlag = A > 127 
      ZeroFlag = A == 0
      EndInstruction()
    end
  end,
  [0xB1] = function() --LDA (<$??), Y
    getAddrIndY(true)
    if CycleTick == 5 then
      A = Read(AddressBus) 

      NegativeFlag = A > 127 
      ZeroFlag = A == 0
      EndInstruction()
    end
  end,
  [0xB5] = function() --LDA <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      A = Read(AddressBus) 

      NegativeFlag = A > 127 
      ZeroFlag = A == 0
      EndInstruction()
    end
  end,
  [0xB9] = function() --LDA $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      A = Read(AddressBus) 

      NegativeFlag = A > 127 
      ZeroFlag = A == 0
      EndInstruction()
    end
  end,
  [0xBD] = function() --LDA $????, X
    getAddrAbsOffX(true)
    if CycleTick == 4 then
      A = Read(AddressBus) 

      NegativeFlag = A > 127 
      ZeroFlag = A == 0
      EndInstruction()
    end
  end,
  [0xA2] = function() --LDX #$??
    getAddrImm()
    
    X = Read(AddressBus) 
    NegativeFlag = X > 127 
    ZeroFlag = X == 0
    
    EndInstruction()
  end,
  [0xA6] = function() --LDX <$??
    getAddrZP()
    if CycleTick == 2 then
      X = Read(AddressBus) 

      NegativeFlag = X > 127 
      ZeroFlag = X == 0
      EndInstruction()
    end
  end,
  [0xAE] = function() --LDX $????
    getAddrAbs()
    if CycleTick == 3 then
      X = Read(AddressBus) 

      NegativeFlag = X > 127 
      ZeroFlag = X == 0
      EndInstruction()
    end
  end,
  [0xB6] = function() --LDX <$??, Y
    getAddrZPOffY()
    if CycleTick == 3 then
      X = Read(AddressBus) 

      NegativeFlag = X > 127 
      ZeroFlag = X == 0
      EndInstruction()
    end
  end,
  [0xBE] = function() --LDX $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      X = Read(AddressBus) 

      NegativeFlag = X > 127 
      ZeroFlag = X == 0
      EndInstruction()
    end
  end,
  [0xA0] = function() --LDY #$??
    getAddrImm()
    
    Y = Read(AddressBus) 
    NegativeFlag = Y > 127 
    ZeroFlag = Y == 0
    
    EndInstruction()
  end,
  [0xA4] = function() --LDY <$??
    getAddrZP()
    if CycleTick == 2 then
      Y = Read(AddressBus) 

      NegativeFlag = Y > 127 
      ZeroFlag = Y == 0
      EndInstruction()
    end
  end,
  [0xAC] = function() --LDY $????
    getAddrAbs()
    if CycleTick == 3 then
      Y = Read(AddressBus) 

      NegativeFlag = Y > 127 
      ZeroFlag = Y == 0
      EndInstruction()
    end
  end,
  [0xB4] = function() --LDY <$??, Y
    getAddrZPOffY()
    if CycleTick == 3 then
      Y = Read(AddressBus) 

      NegativeFlag = Y > 127 
      ZeroFlag = Y == 0
      EndInstruction()
    end
  end,
  [0xBC] = function() --LDY $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      Y = Read(AddressBus) 

      NegativeFlag = Y > 127 
      ZeroFlag = Y == 0
      EndInstruction()
    end
  end,
  [0x46] = function() --LSR <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpLSR(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x4A] = function() --LSR A
    Read(ProgramCounter)
    OpLSRImpl()
    
    EndInstruction()
  end,
  [0x4E] = function() --LSR $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpASL(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x56] = function() --LSR <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpLSR(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x5E] = function() --LSR $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpLSR(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x61] = function() --ORA (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x65] = function() --ORA <$??
    getAddrZP()
    if CycleTick == 2 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x69] = function() --ORA #$??
    getAddrImm()
    OpADC(Read(AddressBus))
    
    EndInstruction()
  end,
  [0x6D] = function() --ORA $????
    getAddrAbs()
    if CycleTick == 3 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x71] = function() --ORA (<$??), Y
    getAddrIndY(true)
    if CycleTick == 5 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x75] = function() --ORA <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x79] = function() --ORA $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      OpADC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x7D] = function() --ORA $????, X
    getAddrAbsOffX(true)
    if CycleTick == 4 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x48] = function() --PHA
    if CycleTick == 1 then
      Read(ProgramCounter)
    else
      Write(0x100 + SP, A)
      SP = band(SP - 1, 0xFF)
      EndInstruction()
    end
  end,
  [0x08] = function() --PHP
    if CycleTick == 1 then
      Read(ProgramCounter)
    else
      local Temp = 0
      Temp = Temp + (CarryFlag and 1 or 0)
      Temp = Temp + (ZeroFlag and 2 or 0)
      Temp = Temp + (InterruptFlag and 4 or 0)
      Temp = Temp + (DecimalFlag and 8 or 0)
      Temp = Temp + 0x10
      Temp = Temp + 0x20
      Temp = Temp + (OverflowFlag and 0x40 or 0)
      Temp = Temp + (NegativeFlag and 0x80 or 0)
      
      Write(0x100 + SP, Temp)
      SP = band(SP - 1, 0xFF)
      EndInstruction()
    end
  end,
  [0x68] = function() --PLA
    if CycleTick == 1 then
      Read(ProgramCounter)
    elseif CycleTick == 2 then
      SP = band(SP + 1, 0xFF)
    else
      A = Read(0x100 + SP)
      EndInstruction()
    end
  end,
  [0x28] = function() --PLP
    if CycleTick == 1 then
      Read(ProgramCounter)
    elseif CycleTick == 2 then
      SP = band(SP + 1, 0xFF)
    else
      local Temp = Read(0x100 + SP)
      
      CarryFlag = band(Temp, 1) ~= 0
      ZeroFlag = band(Temp, 2) ~= 0
      InterruptFlag = band(Temp, 4) ~= 0
      DecimalFlag = band(Temp, 8) ~= 0
      OverflowFlag = band(Temp, 0x40) ~= 0
      NegativeFlag = band(Temp, 0x80) ~= 0
    
      EndInstruction()
    end
  end,
  [0x26] = function() --ROL <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpROL(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x2A] = function() --ROL A
    Read(ProgramCounter)
    OpROLImpl()
    
    EndInstruction()
  end,
  [0x2E] = function() --ROL $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpROL(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x36] = function() --ROL <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpROL(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x3E] = function() --ROL $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpROL(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x66] = function() --ROR <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpROR(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x6A] = function() --ROR A
    Read(ProgramCounter)
    OpRORImpl()
    
    EndInstruction()
  end,
  [0x6E] = function() --ROR $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpROR(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x76] = function() --ROR <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpROR(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x7E] = function() --ROR $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpROR(DataBus)
    else
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x40] = function() --RTI
    if CycleTick == 1 then
      Read(ProgramCounter) --Dummy Read :)
    elseif CycleTick == 2 then
      SP = band(SP + 1, 0xFF)
    elseif CycleTick == 3 then
      local Temp = Read(0x100 + SP)
      
      CarryFlag = band(Temp, 1) ~= 0
      ZeroFlag = band(Temp, 2) ~= 0
      InterruptFlag = band(Temp, 4) ~= 0
      DecimalFlag = band(Temp, 8) ~= 0
      OverflowFlag = band(Temp, 0x40) ~= 0
      NegativeFlag = band(Temp, 0x80) ~= 0
      SP = band(SP + 1, 0xFF)
    elseif CycleTick == 4 then
      DataLatch = Read(0x100 + SP)
      SP = band(SP + 1, 0xFF)
    else
      Read(0x100 + SP)
      ProgramCounter = bor(lshift(DataBus, 8), DataLatch)
    end
  end,
  [0x60] = function() --RTS
    if CycleTick == 1 then
      Read(ProgramCounter) --Dummy Read :)
    elseif CycleTick == 2 then
      SP = band(SP + 1, 0xFF)
    elseif CycleTick == 3 then
      DataLatch = Read(0x100 + SP)
      SP = band(SP + 1, 0xFF)
    elseif CycleTick == 4 then
      Read(0x100 + SP)
      ProgramCounter = bor(lshift(DataBus, 8), DataLatch)
    else
      ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
    end
  end,
  [0xE1] = function() --SBC (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      OpSBC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xE5] = function() --SBC <$??
    getAddrZP()
    if CycleTick == 2 then
      OpSBC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xE9] = function() --SBC #$??
    getAddrImm()
    OpSBC(Read(AddressBus))
    
    EndInstruction()
  end,
  [0xED] = function() --SBC $????
    getAddrAbs()
    if CycleTick == 3 then
      OpSBC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xF1] = function() --SBC (<$??), Y
    getAddrIndY(true)
    if CycleTick == 5 then
      OpSBC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xF5] = function() --SBC <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      OpSBC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xF9] = function() --SBC $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      OpSBC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0xFD] = function() --SBC $????, X
    getAddrAbsOffX(true)
    if CycleTick == 4 then
      OpSBC(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x81] = function() --STA (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      Write(AddressBus, A)
      EndInstruction()
    end
  end,
  [0x84] = function() --STY <$??
    getAddrZP()
    if CycleTick == 2 then
      Write(AddressBus, Y)
      EndInstruction()
    end
  end,
  [0x85] = function() --STA <$??
    getAddrZP()
    if CycleTick == 2 then
      Write(AddressBus, A)
      EndInstruction()
    end
  end,
  [0x86] = function() --STX <$??
    getAddrZP()
    if CycleTick == 2 then
      Write(AddressBus, X)
      EndInstruction()
    end
  end,
  [0x8C] = function() --STY $????
    getAddrAbs()
    if CycleTick == 3 then
      Write(AddressBus, Y)
      EndInstruction()
    end
  end,
  [0x8D] = function() --STA $????
    getAddrAbs()
    if CycleTick == 3 then
      Write(AddressBus, A)
      EndInstruction()
    end
  end,
  [0x8E] = function() --STX $????
    getAddrAbs()
    if CycleTick == 3 then
      Write(AddressBus, X)
      EndInstruction()
    end
  end,
  [0x91] = function() --STA (<$??), Y
    getAddrIndY(true)
    if CycleTick == 5 then
      Write(AddressBus, A)
      EndInstruction()
    end
  end,
  [0x94] = function() --STY <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Write(AddressBus, Y)
      EndInstruction()
    end
  end,
  [0x95] = function() --STA <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Write(AddressBus, A)
      EndInstruction()
    end
  end,
  [0x96] = function() --STX <$??, Y
    getAddrZPOffY()
    if CycleTick == 3 then
      Write(AddressBus, X)
      EndInstruction()
    end
  end,
  [0x99] = function() --STA $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      Write(AddressBus, A)
      EndInstruction()
    end
  end,
  [0x9D] = function() --STA $????, X
    getAddrAbsOffX(true)
    if CycleTick == 4 then
      Write(AddressBus, A)
      EndInstruction()
    end
  end,
  [0x90] = function() --BCC $????
    getAddrRel(not CarryFlag)
  end,
  [0xB0] = function() --BCS $????
    getAddrRel(CarryFlag)
  end,
  [0xF0] = function() --BEQ $????
    getAddrRel(ZeroFlag)
  end,
  [0x30] = function() --BMI $????
    getAddrRel(NegativeFlag)
  end,
  [0xD0] = function() --BNE $????
    getAddrRel(not ZeroFlag)
  end,
  [0x10] = function() --BPL $????
    getAddrRel(not NegativeFlag)
  end,
  [0x50] = function() --BVC $????
    getAddrRel(not OverflowFlag)
  end,
  [0x70] = function() --BVS $????
    getAddrRel(OverflowFlag)
  end,
  [0x18] = function() --CLC
    Read(ProgramCounter)
    CarryFlag = false
    
    EndInstruction()
  end,
  [0x38] = function() --SEC
    Read(ProgramCounter)
    CarryFlag = true
    
    EndInstruction()
  end,
  [0xD8] = function() --CLD
    Read(ProgramCounter)
    DecimalFlag = false
    
    EndInstruction()
  end,
  [0xF8] = function() --SED
    Read(ProgramCounter)
    DecimalFlag = true
    
    EndInstruction()
  end,
  [0x58] = function() --CLI
    Read(ProgramCounter)
    InterruptFlag = false
    
    EndInstruction()
  end,
  [0x78] = function() --SEI
    Read(ProgramCounter)
    InterruptFlag = true
    
    EndInstruction()
  end,
  [0xB8] = function() --CLV
    Read(ProgramCounter)
    OverflowFlag = false
    
    EndInstruction()
  end,
  [0xEA] = function() --NOP
    Read(ProgramCounter)
    
    EndInstruction()
  end,
  [0xAA] = function() --TAX
    Read(ProgramCounter) --Dummy Read :)
    X = A
    
    ZeroFlag = X == 0
    NegativeFlag = X > 127
    
    EndInstruction()
  end,
  [0xA8] = function() --TAY
    Read(ProgramCounter) --Dummy Read :)
    Y = A
    
    ZeroFlag = Y == 0
    NegativeFlag = Y > 127
    
    EndInstruction()
  end,
  [0xBA] = function() --TSX
    Read(ProgramCounter) --Dummy Read :)
    X = SP
    
    ZeroFlag = X == 0
    NegativeFlag = X > 127
    
    EndInstruction()
  end,
  [0x8A] = function() --TXA
    Read(ProgramCounter) --Dummy Read :)
    A = X
    
    ZeroFlag = A == 0
    NegativeFlag = A > 127
    
    EndInstruction()
  end,
  [0x9A] = function() --TSX
    Read(ProgramCounter) --Dummy Read :)
    SP = X
    
    EndInstruction()
  end,
  [0x98] = function() --TYA
    Read(ProgramCounter) --Dummy Read :)
    A = Y
    
    ZeroFlag = A == 0
    NegativeFlag = A > 127
    
    EndInstruction()
  end,
  [0x100] = function() --RESET
    EndInstruction()
  end
}
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
--Official Opcodes
function OpADC(value)
  local sum = value + A + (CarryFlag and 1 or 0)
  
  local xor1 = bnot(bxor(A, value))
  local xor2 = bxo3(A, sum)
  
  OverflowFlag = band(band(xor1, xor2), 0x80) ~= 0
  CarryFlag = sum > 0xFF
  A = band(sum, 0xFF)
  NegativeFlag = A > 127
  ZeroFlag = A == 0
end
function OpAND(value)
  A = band(A, value)
  
  NegativeFlag = A > 127
  ZeroFlag = A == 0
end
function OpASLImpl()
  CarryFlag = A > 127
  A = band(lshift(A, 1), 0xFF)
  
  NegativeFlag = A > 127
  ZeroFlag = A == 0
end
function OpASL(value)
  CarryFlag = value > 127
  value = band(lshift(value, 1), 0xFF)
  
  NegativeFlag = value > 127
  ZeroFlag = value == 0
  
  DataLatch = value
end
function OpBIT(value)
  ZeroFlag = band(A, value) == 0
  NegativeFlag = band(value, 0x80) ~= 0
  OverflowFlag = band(value, 0x40) ~= 0
end
function OpCMP(value)
  CarryFlag = A >= value
  ZeroFlag = A == value
  NegativeFlag = band(A - value, 0xFF) > 127
end
function OpCPX(value)
  CarryFlag = X >= value
  ZeroFlag = X == value
  NegativeFlag = band(X - value, 0xFF) > 127
end
function OpCPY(value)
  CarryFlag = Y >= value
  ZeroFlag = Y == value
  NegativeFlag = band(A - value, 0xFF) > 127
end
function OpDEC(value)
  value = band(value - 1, 0xFF)
  DataLatch = value
  
  ZeroFlag = value == 0
  NegativeFlag = value > 127
end
function OpEOR(value)
  A = bxor(A, value)
  
  NegativeFlag = A > 127
  ZeroFlag = A == 0
end
function OpINC(value)
  value = band(value + 1, 0xFF)
  DataLatch = value
  
  ZeroFlag = value == 0
  NegativeFlag = value > 127
end
function OpLSRImpl()
  CarryFlag = band(A, 1) == 1
  A = band(rshift(A, 1), 0xFF)
  
  ZeroFlag = A == 0
  NegativeFlag = A > 127
end
function OpLSR(value)
  CarryFlag = band(value, 1) == 1
  value = band(rshift(value, 1), 0xFF)
  
  ZeroFlag = value == 0
  NegativeFlag = value > 127
  
  DataLatch = value
end
function OpORA(value)
  A = bor(A, value)
  
  ZeroFlag = A == 0
  NegativeFlag = A > 127
end
function OpROLImpl()
  local carry = A > 127
  A = band(lshift(A, 1), 0xFF)
  A = CarryFlag and bor(A, 1) or A
  
  CarryFlag = carry
  NegativeFlag = A > 127
  ZeroFlag = A == 0
end
function OpROL(value)
  local carry = value > 127
  value = band(lshift(value, 1), 0xFF)
  value = CarryFlag and bor(value, 1) or value
  
  CarryFlag = carry
  NegativeFlag = value > 127
  ZeroFlag = value == 0
  
  DataLatch = value
end
function OpRORImpl()
  local carry = A > 127
  A = band(rshift(A, 1), 0xFF)
  A = CarryFlag and bor(A, 0x80) or A
  
  CarryFlag = carry
  NegativeFlag = A > 127
  ZeroFlag = A == 0
end
function OpROR(value)
  local carry = value > 127
  value = band(rshift(value, 1), 0xFF)
  value = CarryFlag and bor(value, 0x80) or value
  
  CarryFlag = carry
  NegativeFlag = value > 127
  ZeroFlag = value == 0
  
  DataLatch = value
end
function OpSBC(value)
  local sum = A - value - (CarryFlag and 0 or 1)
  
  local xor1 = bxor(A, value)
  local xor2 = bxor(A, sum)
  
  OverflowFlag = band(band(xor1, xor2), 0x80) ~= 0
  CarryFlag = sum >= 0
  A = band(sum, 0xFF)
  NegativeFlag = A > 127
  ZeroFlag = A == 0
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
    Read(AddressBus) --Dummy Read :)
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
    TempAddr = band(ProgramCounter + DataLatch, 0xFFFF)
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
  --Poll Interrupts Here For Now
  --Log Instructions Here
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
  --TODO: Add RESET Flag and "Instruction"
  local ROMToLoad = "Super Mario Bros. (World).nes"
  LoadROM("roms/" .. ROMToLoad)
  
  local AddrLow = Read(0xFFFC)
  local AddrHigh = Read(0xFFFD)
  ProgramCounter = bor(lshift(AddrHigh, 8), AddrLow)
end

return Emulator