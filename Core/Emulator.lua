local Emulator = {}

Emulator.Controller1 = 0

--Important things
local ffi = require("ffi")
local bit = require("bit")
local bnot, band, bor, bxor, lshift, rshift, truncate = bit.bnot, bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift, math.modf

--CPU Things
local ProgramCounter = 0 --Where is the cpu reading
local A = 0 
local X = 0 
local Y = 0
local SP = 0xFD 
local RAM = ffi.new("uint8_t[0x800]")
local PRGRAM = ffi.new("uint8_t[0x2000]")
local ROM = {}
local Header = ffi.new("uint8_t[16]")

local DoNMI = false
local DoIRQ = false
local DoRESET = false

local CarryFlag = false
local ZeroFlag = false
local DecimalFlag = false
local InterruptFlag = true
local OverflowFlag = false
local NegativeFlag = false

local DataBus = 0 --The most recently read/written value
local DataLatch = 0 --Temporary value
local AddressBus = 0 --Where is the cpu reading/writing after a addressing mode
local CycleTick = 0 --What cycle is this instruction on
local TempAddr = 0 --Temporary address for some addressing modes

local Controller1ShiftReg = 0
local Controller2ShiftReg = 0

local PPUBuffer = 0
local TempVRAMAddress = 0

local CPUClock = 0

--PPU Things
ffi.cdef([[
  typedef struct {
    uint8_t r, g, b, a;
  } Image_Pixel;
]])

local DrawFrame = false

local WriteLatch = false
local VRAMAddress = 0
local TransferAddress = 0
local VRAMInc32Mode = false

local PPUDataBus = 0
local CHRData = ffi.new("uint8_t[0x2000]")
local VRAM = ffi.new("uint8_t[0x800]")
local PaletteRAM = ffi.new("uint8_t[32]")

local Scanline = 0
local Dot = 0
local Vblank = false
local FineX = 0

local Grayscale = false
local EmphasisColor = 0
local Mask8PxBg = false
local Mask8PxSprites = false
local RenderBg = false
local RenderSprites = false

local NametableSelect = 0
local SpritePatternTable = false
local BgPatternTable = false
local Use8x16Sprites = false
local NMIEnabled = false

--TODO: Find the crash due to buffer overflow (PRIORITY)
--local OAM = ffi.new("uint8_t[256]")
--local SecondaryOAM = ffi.new("uint8_t[32]")
local OAM = {}
for i = 0, 255 do
  OAM[i] = 0
end
local SecondaryOAM = {}
for i = 0, 31 do
  SecondaryOAM[i] = 0
end
local SpriteZeroHit = false
local SpriteOverflow = false
local IsSpriteZero = false
local SprDataLatch = 0
local SecondaryOAMAddress = 0
local SecondaryOAMSize = 0
local SecondaryOAMFull = false
local OAMAddress = 0
local SpriteEvalTick = 0
local EvalOAMOverflowed = false

local ShiftRegL = ffi.new("uint8_t[8]")
local ShiftRegH = ffi.new("uint8_t[8]")
local ShiftRegAttr = ffi.new("uint8_t[8]")
local ShiftRegPatt = ffi.new("uint8_t[8]")
local ShiftRegXPos = ffi.new("uint8_t[8]")
local ShiftRegYPos = ffi.new("uint8_t[8]")

--Taken from 100'th Coin's "TriCNES" emulator. Because im too lazy to get the colors
--TODO: Replace this with a ".pal" file i guess
local Pal = {
0xFF656565, 0xFF002A84, 0xFF1513A2, 0xFF3A019E, 0xFF59007A, 0xFF6A003E, 0xFF680800, 0xFF531D00, 0xFF323400, 0xFF0D4600, 0xFF004F00, 0xFF004C09, 0xFF003F4B, 0xFF000000, 0xFF000000, 0xFF000000,
0xFFAEAEAE, 0xFF175FD6, 0xFF4341FF, 0xFF7529FA, 0xFF9E1DCA, 0xFFB4207B, 0xFFB13322, 0xFF964E00, 0xFF6A6C00, 0xFF398400, 0xFF0F9000, 0xFF008D33, 0xFF007B8C, 0xFF000000, 0xFF000000, 0xFF000000,
0xFFFEFEFE, 0xFF66AFFF, 0xFF9390FF, 0xFFC578FF, 0xFFEE6CFF, 0xFFFF6FCA, 0xFFFF8271, 0xFFE69E25, 0xFFBABC00, 0xFF88D501, 0xFF5EE132, 0xFF47DD82, 0xFF4ACBDC, 0xFF4E4E4E, 0xFF000000, 0xFF000000,
0xFFFEFEFE, 0xFFC0DEFF, 0xFFD2D1FF, 0xFFE7C7FF, 0xFFF8C2FF, 0xFFFFC3E9, 0xFFFFCBC4, 0xFFF5D7A5, 0xFFE2E394, 0xFFCEED96, 0xFFBCF2AA, 0xFFB3F1CB, 0xFFB4E9F0, 0xFFB6B6B6, 0xFF000000, 0xFF000000,
--emphasize red:
0xFF66423E, 0xFF000D58, 0xFF150075, 0xFF380075, 0xFF560058, 0xFF670027, 0xFF680000, 0xFF530D00, 0xFF341E00, 0xFF102B00, 0xFF003000, 0xFF002B00, 0xFF001C24, 0xFF000000, 0xFF000000, 0xFF000000,
0xFFAF7E78, 0xFF19379A, 0xFF4320C1, 0xFF720FC1, 0xFF9A089A, 0xFFB10F59, 0xFFB2220F, 0xFF963700, 0xFF6C4D00, 0xFF3D5F00, 0xFF166500, 0xFF005F0C, 0xFF004B55, 0xFF000000, 0xFF000000, 0xFF000000,
0xFFFFC0B8, 0xFF6878DB, 0xFF9361FF, 0xFFC24FFF, 0xFFEA49DB, 0xFFFF4F99, 0xFFFF634E, 0xFFE77808, 0xFFBC8F00, 0xFF8DA000, 0xFF65A708, 0xFF4DA04A, 0xFF4C8D95, 0xFF4F2F2B, 0xFF000000, 0xFF000000,
0xFFFFC0B8, 0xFFC1A2C6, 0xFFD399D6, 0xFFE792D6, 0xFFF78FC6, 0xFFFF92AB, 0xFFFF9A8C, 0xFFF6A26F, 0xFFE4AC5F, 0xFFD1B35F, 0xFFC0B66F, 0xFFB7B38B, 0xFFB6ABA9, 0xFFB7857E, 0xFF000000, 0xFF000000,
--emphasize green:
0xFF395D2C, 0xFF002452, 0xFF000D6A, 0xFF140064, 0xFF2D0041, 0xFF3E0010, 0xFF3F0300, 0xFF301800, 0xFF162F00, 0xFF004200, 0xFF004C00, 0xFF004700, 0xFF003924, 0xFF000000, 0xFF000000, 0xFF000000,
0xFF71A360, 0xFF005691, 0xFF1939B1, 0xFF4020A9, 0xFF61127B, 0xFF78183A, 0xFF792C00, 0xFF654800, 0xFF426600, 0xFF1B7E00, 0xFF008D00, 0xFF00860A, 0xFF007254, 0xFF000000, 0xFF000000, 0xFF000000,
0xFFAEF099, 0xFF32A3CB, 0xFF5684EB, 0xFF7E6BE3, 0xFF9E5DB5, 0xFFB66472, 0xFFB77728, 0xFFA39400, 0xFF7FB200, 0xFF57CB00, 0xFF37D900, 0xFF1FD342, 0xFF1EBF8D, 0xFF27471C, 0xFF000000, 0xFF000000,
0xFFAEF099, 0xFF7BD0AD, 0xFF8AC3BA, 0xFF9AB9B7, 0xFFA8B3A4, 0xFFB1B689, 0xFFB2BE6A, 0xFFAACA50, 0xFF9BD643, 0xFF8BE146, 0xFF7DE65A, 0xFF74E475, 0xFF73DC94, 0xFF77AA65, 0xFF000000, 0xFF000000,
--emphasize red + green:
0xFF3F3F25, 0xFF000B46, 0xFF00005D, 0xFF18005A, 0xFF2F003F, 0xFF40000E, 0xFF410000, 0xFF320A00, 0xFF191A00, 0xFF002800, 0xFF002F00, 0xFF002A00, 0xFF001B1C, 0xFF000000, 0xFF000000, 0xFF000000,
0xFF797A55, 0xFF003581, 0xFF201F9F, 0xFF450D9C, 0xFF640478, 0xFF7B0A36, 0xFF7C1E00, 0xFF683200, 0xFF474900, 0xFF225B00, 0xFF036400, 0xFF005D00, 0xFF004A4A, 0xFF000000, 0xFF000000, 0xFF000000,
0xFFBABB8B, 0xFF3E75B7, 0xFF605ED6, 0xFF854CD2, 0xFFA443AE, 0xFFBB4A6C, 0xFFBD5D21, 0xFFA87200, 0xFF878900, 0xFF619B00, 0xFF42A400, 0xFF2B9D34, 0xFF2A8A7F, 0xFF2C2D15, 0xFF000000, 0xFF000000,
0xFFBABB8B, 0xFF879E9D, 0xFF9595AA, 0xFFA48DA8, 0xFFB18999, 0xFFBB8C7E, 0xFFBB945F, 0xFFB39D48, 0xFFA5A63B, 0xFF96AE3D, 0xFF89B14C, 0xFF7FAF67, 0xFF7FA686, 0xFF80805A, 0xFF000000, 0xFF000000,
--emphasize blue:
0xFF47477C, 0xFF001A8C, 0xFF0B0AA9, 0xFF2900A3, 0xFF410081, 0xFF4D004A, 0xFF49000D, 0xFF340400, 0xFF141500, 0xFF002800, 0xFF003300, 0xFF00331B, 0xFF002A58, 0xFF000000, 0xFF00000A, 0xFF00000A,
0xFF8584CD, 0xFF0B49E2, 0xFF3533FF, 0xFF5D1AFF, 0xFF7D0CD4, 0xFF8D0B8B, 0xFF86173A, 0xFF6B2C00, 0xFF414200, 0xFF195B00, 0xFF006904, 0xFF006A4C, 0xFF005E9E, 0xFF00000A, 0xFF00000A, 0xFF00000A,
0xFFC9C8FF, 0xFF4E8CFF, 0xFF7876FF, 0xFFA05CFF, 0xFFC14EFF, 0xFFD14DE4, 0xFFCB5A92, 0xFFAF6E4C, 0xFF848525, 0xFF5C9E2D, 0xFF3BAD5B, 0xFF2BADA5, 0xFF32A1F7, 0xFF343362, 0xFF00000A, 0xFF00000A,
0xFFC9C8FF, 0xFF96AFFF, 0xFFA8A6FF, 0xFFB89BFF, 0xFFC696FF, 0xFFCC95FF, 0xFFCA9AEA, 0xFFBEA3CD, 0xFFACACBD, 0xFF9CB7C0, 0xFF8FBDD3, 0xFF88BDF2, 0xFF8BB8FF, 0xFF8B8AD6, 0xFF00000A, 0xFF00000A,
--emphasize red + blue:
0xFF46344C, 0xFF00085C, 0xFF0B007A, 0xFF260077, 0xFF3D005C, 0xFF4A0030, 0xFF480000, 0xFF340000, 0xFF140F00, 0xFF001D00, 0xFF002400, 0xFF002200, 0xFF001829, 0xFF000000, 0xFF000000, 0xFF000000,
0xFF846B8C, 0xFF0A30A1, 0xFF3419C8, 0xFF5907C5, 0xFF7800A1, 0xFF880166, 0xFF860E23, 0xFF6B2300, 0xFF403900, 0xFF1C4C00, 0xFF005400, 0xFF00521A, 0xFF00445C, 0xFF000000, 0xFF000000, 0xFF000000,
0xFFC7A7D2, 0xFF4C6BE8, 0xFF7754FF, 0xFF9C42FF, 0xFFBB39E7, 0xFFCC3CAB, 0xFFCA4968, 0xFFAE5E23, 0xFF837500, 0xFF5E8700, 0xFF3F9023, 0xFF2E8E5F, 0xFF3080A2, 0xFF332338, 0xFF000000, 0xFF000000,
0xFFC7A7D2, 0xFF948EDB, 0xFFA685EB, 0xFFB57DEA, 0xFFC27ADB, 0xFFC97BC2, 0xFFC880A7, 0xFFBD898A, 0xFFAB927A, 0xFF9C9A7B, 0xFF8F9D8A, 0xFF889CA3, 0xFF8997BE, 0xFF8A7093, 0xFF000000, 0xFF000000,
--emphasize green + blue:
0xFF304144, 0xFF00155A, 0xFF000471, 0xFF11006B, 0xFF2A0049, 0xFF36001C, 0xFF350000, 0xFF250300, 0xFF0C1300, 0xFF002600, 0xFF003100, 0xFF002F00, 0xFF002531, 0xFF000000, 0xFF000000, 0xFF000000,
0xFF647D80, 0xFF00429E, 0xFF152CBC, 0xFF3C13B4, 0xFF5C0586, 0xFF6D074B, 0xFF6B1509, 0xFF572900, 0xFF364000, 0xFF0E5900, 0xFF006700, 0xFF006424, 0xFF005766, 0xFF000000, 0xFF000000, 0xFF000000,
0xFF9EBEC3, 0xFF2D83E1, 0xFF4E6CFF, 0xFF7653F8, 0xFF9745C9, 0xFFA7478D, 0xFFA5554A, 0xFF916A12, 0xFF6F8100, 0xFF479A00, 0xFF27A82A, 0xFF16A566, 0xFF1898A9, 0xFF1F2E30, 0xFF000000, 0xFF000000,
0xFF9EBEC3, 0xFF6FA6CF, 0xFF7D9CDC, 0xFF8E92D8, 0xFF9B8CC5, 0xFFA28DAD, 0xFFA19391, 0xFF999C7A, 0xFF8BA56D, 0xFF7AAF70, 0xFF6DB584, 0xFF66B49C, 0xFF67AEB8, 0xFF6A8386, 0xFF000000, 0xFF000000,
--emphasize red + green + blue:
0xFF343434, 0xFF00084B, 0xFF000061, 0xFF14005F, 0xFF2B0044, 0xFF380017, 0xFF360000, 0xFF270000, 0xFF0E0F00, 0xFF001D00, 0xFF002400, 0xFF002200, 0xFF001721, 0xFF000000, 0xFF000000, 0xFF000000,
0xFF6A6A6A, 0xFF003088, 0xFF1B19A7, 0xFF4007A3, 0xFF5F007F, 0xFF6F0144, 0xFF6D0E02, 0xFF592300, 0xFF383900, 0xFF134B00, 0xFF005400, 0xFF00520F, 0xFF004451, 0xFF000000, 0xFF000000, 0xFF000000,
0xFFA6A6A6, 0xFF356BC5, 0xFF5654E3, 0xFF7B42E0, 0xFF9B39BB, 0xFFAB3C80, 0xFFA9493D, 0xFF955E04, 0xFF737500, 0xFF4E8700, 0xFF2F900E, 0xFF1E8E4A, 0xFF20808D, 0xFF232323, 0xFF000000, 0xFF000000,
0xFFA6A6A6, 0xFF788EB3, 0xFF8585C0, 0xFF957DBE, 0xFFA279AF, 0xFFA87A96, 0xFFA8807B, 0xFF9F8964, 0xFF919257, 0xFF829A59, 0xFF759D68, 0xFF6E9C80, 0xFF6F979C, 0xFF707070, 0xFF000000, 0xFF000000,
}
local ColorData = ffi.new("Image_Pixel[512]")
for i = 0, 511 do
  ColorData[i].r = rshift(band(Pal[i + 1], 0xFF0000), 16)
  ColorData[i].g = rshift(band(Pal[i + 1], 0x00FF00), 8)
  ColorData[i].b = band(Pal[i + 1], 0x0000FF)
  ColorData[i].a = 0xFF
end

local ShiftRegAttrLow = 0
local ShiftRegAttrHigh = 0
local ShiftRegPattLow = 0
local ShiftRegPattHigh = 0

local LowBitPlane = 0
local HighBitPlane = 0
local AttributePlane = 0
local NextTile = 0
local PPUAddressBus = 0
local PPUDataLatch = 0

local ImageData = love.image.newImageData(32 * 8, 30 * 8)
local ImagePointer = ffi.cast("Image_Pixel*", ImageData:getFFIPointer())
local Image = love.graphics.newImage(ImageData)

--APU Things (Side Note: I have no ideia what the majority of the terminology means, i may research this some day)
--All lookups are taken from nesdev (Just go look each APU Channel for the specifics)
local RateLUT = ffi.new("uint16_t[16]", {[0] = 428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106,  84,  72,  54})

ffi.cdef([[
  typedef struct {
    bool IRQEnabled, Loop, Silence, Empty;
    uint8_t SampleBuffer, BitsRemaining, ShiftRegister, Output;
    uint16_t Rate, Period, SampleAddress, SampleLength, BytesRemaining, Address;
  } APU_DMC;
]])

local DMC = ffi.new("APU_DMC")
local DMCInterruptFlag = false

local SoundData = love.sound.newSoundData(44100 / 60 + 1, 44100, 16, 1)
local SoundQueue = love.audio.newQueueableSource(44100, 16, 1)

--CPU Functions
--TODO: Possibly if it is faster replace the ppu if checks with a jump table.
function Read(address)
  if address < 0x2000 then
    DataBus = RAM[band(address, 0x7FF)]
  elseif address < 0x4000 then
    address = band(address, 0x2007)
    if address == 0x2002 then
      PPUDataBus = band(PPUDataBus, 0x1F)
      PPUDataBus = bor(PPUDataBus, Vblank and 0x80 or 0)
      PPUDataBus = bor(PPUDataBus, SpriteZeroHit and 0x40 or 0)
      PPUDataBus = bor(PPUDataBus, SpriteOverflow and 0x20 or 0)
      
      Vblank = false
      WriteLatch = false
      
      DataBus = PPUDataBus
    elseif address == 0x2007 then
      local temp = PPUBuffer
      if VRAMAddress >= 0x3F00 then
        temp = ReadPPU(VRAMAddress)
        PPUBuffer = ReadPPU(VRAMAddress - 0x1000)
      else
        PPUBuffer = ReadPPU(VRAMAddress)
      end
      
      VRAMAddress = VRAMAddress + (VRAMInc32Mode and 32 or 1)
      VRAMAddress = band(VRAMAddress, 0x3FFF)
      
      DataBus = temp
    else
      DataBus = PPUDataBus
    end
  elseif address == 0x4016 then
    local cbit = rshift(band(Controller1ShiftReg, 0x80), 7)
    Controller1ShiftReg = lshift(Controller1ShiftReg, 1)
    
    DataBus = bor(band(DataBus, 0xE0), cbit)
  elseif address == 0x4017 then
    local cbit = rshift(band(Controller2ShiftReg, 0x80), 7)
    Controller2ShiftReg = lshift(Controller2ShiftReg, 1)
    
    DataBus = bor(band(DataBus, 0xE0), cbit)
  elseif band(Header[6], 2) == 1 and address >= 0x6000 and address < 0x8000 then
    DataBus = PRGRAM[address - 0x6000]
  elseif address >= 0x8000 then
    --TODO: Add Mapper Chips
    DataBus = ROM[band(address - 0x8000, 0x4000 * Header[4] - 1)]
  end
  return DataBus
end
local APUAddressTable = {
  [0x4010] = function(value)
    DMC.IRQEnabled = band(value, 0x80) == 1
    DMC.Loop = band(value, 0x40) == 1
    DMC.Rate = RateLUT[band(value, 0x0F)]
    
    if not DMC.IRQEnabled then
      DMCInterruptFlag = false
    end
  end,
  [0x4011] = function(value)
    --Apparently sometimes this does not work correctly if outputting a clock
    --TODO: See if this is accurate due to the above comment (Its probably not correct)
    DMC.Output = band(value, 0x7F)
  end,
  [0x4012] = function(value)
    --Taken from nesdev (https://www.nesdev.org/wiki/APU_DMC)
    DMC.SampleAddress = 0xC000 + (value * 64)
  end,
  [0x4013] = function(value)
    --Same as above
    DMC.SampleLength = (value * 16) + 1
  end,
  [0x4014] = function(value)
    --OAM DMA (simplified)
    --TODO: un-sinplify this
    for i = 0, 255 do
      OAM[i] = Read(lshift(value, 8) + i)
    end
  end,
  [0x4015] = function(value)
    local EnableDMC = band(value, 0x20) == 1
    if EnableDMC and DMC.BytesRemaining == 0 then
      DMC.Address = DMC.SampleAddress
      DMC.BytesRemaining = DMC.SampleLength
    else
      DMC.BytesRemaining = 0
    end
    DMCInterruptFlag = false
  end,
  [0x4016] = function(value)
    Controller1ShiftReg = Emulator.Controller1
    Controller2ShiftReg = 0
  end,
  [0x4017] = function(value)
  end
}
function Write(address, value)
  --TODO: Add Mapper Chips
  if address < 0x2000 then
    RAM[band(address, 0x7FF)] = value
  elseif address < 0x4000 then
    address = band(address, 0x2007)
    if address == 0x2000 then  --PPUCTRL
      NametableSelect = band(value, 3)
      VRAMInc32Mode = band(value, 4) ~= 0
      SpritePatternTable = band(value, 8) ~= 0
      BgPatternTable = band(value, 0x10) ~= 0
      Use8x16Sprites = band(value, 0x20) ~= 0
      NMIEnabled = band(value, 0x80) ~= 0
      TransferAddress = bor(band(TransferAddress, bnot(0xC00)), lshift(band(NametableSelect, 3), 10))
      
      PPUDataBus = value
    elseif address == 0x2001 then  --PPUMASK
      Grayscale = band(value, 1) ~= 0
      Mask8pxBg = band(value, 2) ~= 0
      Mask8pxSprites = band(value, 4) ~= 0
      RenderBg = band(value, 8) ~= 0
      RenderSprites = band(value, 0x10) ~= 0
      EmphasisColor = band(rshift(value, 5), 7)
      
      PPUDataBus = value
    elseif address == 0x2002 then  --PPUSTATUS
      PPUDataBus = value
    elseif address == 0x2003 then  --OAMADDR
      PPUDataBus = value
    elseif address == 0x2004 then  --OAMDATA
      PPUDataBus = value
    elseif address == 0x2005 then  --PPUSCROLL
      if not WriteLatch then
        FineX = band(value, 7)
        --0b0111111111100000 = 0x7FE0
        TempVRAMAddress = band(bor(band(TempVRAMAddress, 0x7FE0), rshift(value, 3)), 0xFFFF)
      else
        --0b0000110000011111 = 0x0C1F
        TransferAddress = bor(bor(lshift(band(value, 0xF8), 2), lshift(band(value, 7), 12)), band(TempVRAMAddress, 0x0C1F))
        TransferAddress = band(TransferAddress, 0xFFFF)
      end
      WriteLatch = not WriteLatch
      PPUDataBus = value
    elseif address == 0x2006 then  --PPUADDR
      if not WriteLatch then
        TempVRAMAddress = band(lshift(band(value, 0x3F), 8), 0xFFFF)
      else
        VRAMAddress = band(bor(TempVRAMAddress, value), 0xFFFF)
        TransferAddress = VRAMAddress 
      end
      WriteLatch = not WriteLatch
      PPUDataBus = value
    elseif address == 0x2007 then  --PPUDATA
      if VRAMAddress < 0x2000 then --Write to pattern table (if possible)
        if Header[5] == 0 then
          CHRData[VRAMAddress] = value
        end
      elseif VRAMAddress < 0x3F00 then --Write to nametables
        if band(Header[6], 1) == 0 then
          --"Vertical mirroing"
          VRAM[bor(band(VRAMAddress, 0x3FF), rshift(band(VRAMAddress, 0x800), 1))] = value
        else
          --"Horizontal mirroing"
          VRAM[band(VRAMAddress, 0x7FF)] = value
        end
      else --Write to palettes
        if band(VRAMAddress, 3) == 0 then
          PaletteRAM[band(VRAMAddress, 0x0F)] = value
        else
          PaletteRAM[band(VRAMAddress, 0x1F)] = value
        end    
      end
      VRAMAddress = VRAMAddress + (VRAMInc32Mode and 32 or 1)
      VRAMAddress = band(VRAMAddress, 0x3FFF)
      
      PPUDataBus = value
    end
  elseif address <= 0x4017 then
    local func = APUAddressTable[address]
    if func ~= nil then
      func(value)
    end
  elseif band(Header[6], 2) == 1 and address >= 0x6000 and address < 0x8000 then
    PRGRAM[address - 0x6000] = value
  end
  DataBus = value --I did not know that even writing updated the data bus bruh
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
  [0x06] = function() --ASL <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpASL(DataBus)
    elseif CycleTick == 4 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
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
    elseif CycleTick == 4 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 6 then
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
    elseif CycleTick == 4 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 6 then
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
    elseif CycleTick == 4 then
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
    elseif CycleTick == 5 then
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
  [0xB4] = function() --LDY <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Y = Read(AddressBus) 

      NegativeFlag = Y > 127 
      ZeroFlag = Y == 0
      EndInstruction()
    end
  end,
  [0xBC] = function() --LDY $????, X
    getAddrAbsOffX(true)
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
    elseif CycleTick == 4 then
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
      OpLSR(DataBus)
    elseif CycleTick == 5 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x01] = function() --ORA (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x05] = function() --ORA <$??
    getAddrZP()
    if CycleTick == 2 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x09] = function() --ORA #$??
    getAddrImm()
    OpORA(Read(AddressBus))
    
    EndInstruction()
  end,
  [0x0D] = function() --ORA $????
    getAddrAbs()
    if CycleTick == 3 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x11] = function() --ORA (<$??), Y
    getAddrIndY(true)
    if CycleTick == 5 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x15] = function() --ORA <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x19] = function() --ORA $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x1D] = function() --ORA $????, X
    getAddrAbsOffX(true)
    if CycleTick == 4 then
      OpORA(Read(AddressBus))
      EndInstruction()
    end
  end,
  [0x48] = function() --PHA
    if CycleTick == 1 then
      Read(ProgramCounter)
    elseif CycleTick == 2 then
      Write(0x100 + SP, A)
      SP = band(SP - 1, 0xFF)
      EndInstruction()
    end
  end,
  [0x08] = function() --PHP
    if CycleTick == 1 then
      Read(ProgramCounter)
    elseif CycleTick == 2 then
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
    elseif CycleTick == 3 then
      A = Read(0x100 + SP)
      
      ZeroFlag = A == 0
      NegativeFlag = A > 127
      
      EndInstruction()
    end
  end,
  [0x28] = function() --PLP
    if CycleTick == 1 then
      Read(ProgramCounter)
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
    elseif CycleTick == 4 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 6 then
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
    elseif CycleTick == 4 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 5 then
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
    elseif CycleTick == 6 then
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
    elseif CycleTick == 5 then
      Read(0x100 + SP)
      ProgramCounter = bor(lshift(DataBus, 8), DataLatch)
      EndInstruction()
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
    elseif CycleTick == 5 then
      ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
      EndInstruction()
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
  [0x4B] = function() --ALR #??
    getAddrImm()
    
    OpAND(Read(AddressBus))
    OpLSRImpl()
    
    EndInstruction()
  end,
  [0x0B] = function() --ANC #??
    getAddrImm()
    
    OpAND(Read(AddressBus))
    CarryFlag = A > 127
    
    EndInstruction()
  end,
  [0x2B] = function() --ANC #??
    getAddrImm()
    
    OpAND(Read(AddressBus))
    CarryFlag = A > 127
    
    EndInstruction()
  end,
  [0x8B] = function() --ANE #??
    getAddrImm()
       
    Read(AddressBus)
    --Side note: 0xEE is a "magic" value
    A = band(band(bor(A, 0xEE), X), DataBus)
    NegativeFlag = A > 127
    ZeroFlag = A == 0
    
    EndInstruction()
  end,
  [0x6B] = function() --ARR #??
    getAddrImm()
       
    OpAND(Read(AddressBus))
    OpRORImpl()
    
    CarryFlag = rshift(band(A, 0x40), 6) == 1
    OverflowFlag = bxor(rshift(band(A, 0x20), 5), rshift(band(A, 0x40), 6)) == 1
    
    EndInstruction()
  end,
  [0xBB] = function() --LAS #??
    getAddrAbsOffY(true)
    
    if CycleTick == 4 then  
      Read(AddressBus)
      DataLatch = band(DataBus, SP)
      A = DataLatch
      X = DataLatch
      SP = DataLatch
    
      ZeroFlag = X == 0
      NegativeFlag = X > 127
    
      EndInstruction()
    end
  end,
  [0xAB] = function() --LXA #??
    getAddrImm()
       
    Read(AddressBus)
    --Side note: Same "magic" value as opcode 0x8B (ANE)
    DataLatch = band(bor(A, 0xEE), DataBus)
    A = DataLatch
    X = DataLatch
    
    ZeroFlag = X == 0
    NegativeFlag = X > 127
    
    EndInstruction()
  end,
  [0xCB] = function() --SBX #??
    getAddrImm()
       
    Read(AddressBus)
    X = band(X, A)
    CarryFlag = X >= DataBus
    X = band(X - DataBus, 0xFF)
    ZeroFlag = X == 0
    NegativeFlag = X > 127
    
    EndInstruction()
  end,
  [0x9F] = function() --SHA $????, Y
    getAddrAbsOffY(false)
    if CycleTick == 4 then
      local HiAddr = band(rshift(band(AddressBus + 1, 0xFF00), 8), 0xFF)
      
      DataLatch = band(band(A, X), HiAddr)
      Write(AddressBus, DataLatch)
      
      EndInstruction()
    end
  end,
  [0x93] = function() --SHA ($??), Y
    getAddrIndY(false)
    if CycleTick == 5 then
      local HiAddr = band(rshift(band(AddressBus + 1, 0xFF00), 8), 0xFF)
      
      DataLatch = band(band(A, X), HiAddr)
      Write(AddressBus, DataLatch)
      
      EndInstruction()
    end
  end,
  [0x9E] = function() --SHX $????, Y
    getAddrAbsOffY(false)
    if CycleTick == 4 then
      local HiAddr = band(rshift(band(AddressBus + 1, 0xFF00), 8), 0xFF)
      
      DataLatch = band(X, HiAddr)
      Write(AddressBus, DataLatch)
      
      EndInstruction()
    end
  end,
  [0x9C] = function() --SHY $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      local HiAddr = band(rshift(band(AddressBus + 1, 0xFF00), 8), 0xFF)
      
      DataLatch = band(Y, HiAddr)
      Write(AddressBus, DataLatch)
      
      EndInstruction()
    end
  end,
  [0x9B] = function() --TAS $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      SP = band(A, X)
      local HiAddr = band(rshift(band(AddressBus + 1, 0xFF00), 8), 0xFF)
      
      DataLatch = band(band(A, X), HiAddr)
      Write(AddressBus, DataLatch)
      
      EndInstruction()
    end
  end,
  [0xEB] = function() --USBC #$??
    getAddrImm()
    OpSBC(Read(AddressBus))
    
    EndInstruction()
  end,
  [0xC3] = function() --DCP ($??, X)
    getAddrIndX()
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDCP(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xC7] = function() --DCP <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDCP(DataBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xCF] = function() --DCP $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDCP(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xD3] = function() --DCP ($??), Y
    getAddrIndY(false)
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDCP(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xD7] = function() --DCP <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDCP(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xDB] = function() --DCP $????, Y
    getAddrAbsOffY(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDCP(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xDF] = function() --DCP $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpDCP(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xE3] = function() --ISC ($??, X)
    getAddrIndX()
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpISC(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xE7] = function() --ISC <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpISC(DataBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xEF] = function() --ISC $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpISC(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xF3] = function() --ISC ($??), Y
    getAddrIndY(false)
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpISC(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xF7] = function() --ISC <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpISC(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xFB] = function() --ISC $????, Y
    getAddrAbsOffY(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpISC(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xFF] = function() --ISC $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpISC(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x23] = function() --RLA ($??, X)
    getAddrIndX()
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRLA(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x27] = function() --RLA <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRLA(DataBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x2F] = function() --RLA $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRLA(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x33] = function() --RLA ($??), Y
    getAddrIndY(false)
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRLA(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x37] = function() --RLA <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRLA(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x3B] = function() --RLA $????, Y
    getAddrAbsOffY(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRLA(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x3F] = function() --RLA $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRLA(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x63] = function() --RRA ($??, X)
    getAddrIndX()
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRRA(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x67] = function() --RRA <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRRA(DataBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x6F] = function() --RRA $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRRA(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x73] = function() --RRA ($??), Y
    getAddrIndY(false)
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRRA(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x77] = function() --RRA <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRRA(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x7B] = function() --RRA $????, Y
    getAddrAbsOffY(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRRA(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x7F] = function() --RRA $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpRRA(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x03] = function() --SLO ($??, X)
    getAddrIndX()
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSLO(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x07] = function() --SLO <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSLO(DataBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x0F] = function() --SLO $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSLO(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x13] = function() --SLO ($??), Y
    getAddrIndY(false)
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSLO(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x17] = function() --SLO <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSLO(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x1B] = function() --SLO $????, Y
    getAddrAbsOffY(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSLO(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x1F] = function() --SLO $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSLO(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x43] = function() --SRE ($??, X)
    getAddrIndX()
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSRE(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x47] = function() --SRE <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    elseif CycleTick == 3 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSRE(DataBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x4F] = function() --SRE $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSRE(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x53] = function() --SRE ($??), Y
    getAddrIndY(false)
    if CycleTick == 5 then
      Read(AddressBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSRE(DataBus)
    elseif CycleTick == 7 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x57] = function() --SRE <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    elseif CycleTick == 4 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSRE(DataBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x5B] = function() --SRE $????, Y
    getAddrAbsOffY(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSRE(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0x5F] = function() --SRE $????, X
    getAddrAbsOffX(false)
    if CycleTick == 4 then
      Read(AddressBus)
    elseif CycleTick == 5 then
      Write(AddressBus, DataBus) --Dummy Write :)
      OpSRE(DataBus)
    elseif CycleTick == 6 then
      Write(AddressBus, DataLatch)
      EndInstruction()
    end
  end,
  [0xA3] = function() --LAX (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      A = Read(AddressBus) 
      X = Read(AddressBus)
      
      NegativeFlag = X > 127 
      ZeroFlag = X == 0
      EndInstruction()
    end
  end,
  [0xA7] = function() --LAX <$??
    getAddrZP()
    if CycleTick == 2 then
      A = Read(AddressBus) 
      X = Read(AddressBus) 

      NegativeFlag = X > 127 
      ZeroFlag = X == 0
      EndInstruction()
    end
  end,
  [0xAF] = function() --LAX $????
    getAddrAbs()
    if CycleTick == 3 then
      A = Read(AddressBus) 
      X = Read(AddressBus)

      NegativeFlag = X > 127 
      ZeroFlag = X == 0
      EndInstruction()
    end
  end,
  [0xB3] = function() --LAX (<$??), Y
    getAddrIndY(true)
    if CycleTick == 5 then
      A = Read(AddressBus) 
      X = Read(AddressBus)

      NegativeFlag = X > 127 
      ZeroFlag = X == 0
      EndInstruction()
    end
  end,
  [0xB7] = function() --LAX <$??, Y
    getAddrZPOffY()
    if CycleTick == 3 then
      A = Read(AddressBus) 
      X = Read(AddressBus)
      
      NegativeFlag = X > 127 
      ZeroFlag = X == 0
      EndInstruction()
    end
  end,
  [0xBF] = function() --LAX $????, Y
    getAddrAbsOffY(true)
    if CycleTick == 4 then
      A = Read(AddressBus) 
      X = Read(AddressBus)

      NegativeFlag = X > 127 
      ZeroFlag = X == 0
      EndInstruction()
    end
  end,
  [0x83] = function() --SAX (<$??, X)
    getAddrIndX()
    if CycleTick == 5 then
      Write(AddressBus, band(A, X))
      EndInstruction()
    end
  end,
  [0x87] = function() --SAX <$??
    getAddrZP()
    if CycleTick == 2 then
      Write(AddressBus, band(A, X))
      EndInstruction()
    end
  end,
  [0x8F] = function() --SAX $????
    getAddrAbs()
    if CycleTick == 3 then
      Write(AddressBus, band(A, X))
      EndInstruction()
    end
  end,
  [0x97] = function() --SAX <$??, Y
    getAddrZPOffY()
    if CycleTick == 3 then
      Write(AddressBus, band(A, X))
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
  [0x1A] = function() --NOP
    Read(ProgramCounter)
    
    EndInstruction()
  end,
  [0x3A] = function() --NOP
    Read(ProgramCounter)
    
    EndInstruction()
  end,
  [0x5A] = function() --NOP
    Read(ProgramCounter)
    
    EndInstruction()
  end,
  [0x7A] = function() --NOP
    Read(ProgramCounter)
    
    EndInstruction()
  end,
  [0xDA] = function() --NOP
    Read(ProgramCounter)
    
    EndInstruction()
  end,
  [0xFA] = function() --NOP
    Read(ProgramCounter)
    
    EndInstruction()
  end,
  [0x80] = function() --NOP #??
    getAddrImm()
    Read(AddressBus)
    
    EndInstruction()
  end,
  [0x82] = function() --NOP #??
    getAddrImm()
    Read(AddressBus)
    
    EndInstruction()
  end,
  [0x89] = function() --NOP #??
    getAddrImm()
    Read(AddressBus)
    
    EndInstruction()
  end,
  [0xC2] = function() --NOP #??
    getAddrImm()
    Read(AddressBus)
    
    EndInstruction()
  end,
  [0xE2] = function() --NOP #??
    getAddrImm()
    Read(AddressBus)
    
    EndInstruction()
  end,
  [0x04] = function() --NOP <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x44] = function() --NOP <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x64] = function() --NOP <$??
    getAddrZP()
    if CycleTick == 2 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x14] = function() --NOP <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x34] = function() --NOP <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x54] = function() --NOP <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x74] = function() --NOP <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0xD4] = function() --NOP <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0xF4] = function() --NOP <$??, X
    getAddrZPOffX()
    if CycleTick == 3 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x0C] = function() --NOP $????
    getAddrAbs()
    if CycleTick == 3 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x1C] = function() --NOP $????, X
    getAddrAbsOffX()
    if CycleTick == 4 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x3C] = function() --NOP $????, X
    getAddrAbsOffX()
    if CycleTick == 4 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x5C] = function() --NOP $????, X
    getAddrAbsOffX()
    if CycleTick == 4 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x7C] = function() --NOP $????, X
    getAddrAbsOffX()
    if CycleTick == 4 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0xDC] = function() --NOP $????, X
    getAddrAbsOffX()
    if CycleTick == 4 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0xFC] = function() --NOP $????, X
    getAddrAbsOffX()
    if CycleTick == 4 then
      Read(AddressBus)
    
      EndInstruction()
    end
  end,
  [0x100] = function() --OAM DMA
    EndInstruction()
  end,
  [0x101] = function() --DMC DMA
    EndInstruction()
  end
}
local opcode = 0
function EmulateCPU()
  if CycleTick == 0 then
    if not DoNMI then
      opcode = Read(ProgramCounter)
      ProgramCounter = band(ProgramCounter + 1, 0xFFFF)
    else
      opcode = 0
    end
    CycleTick = CycleTick + 1
  else
    local opcode = InstData[opcode]    
    opcode()
    
    CycleTick = CycleTick + 1
  end
end
--Official Opcodes
function OpADC(value)
  local sum = value + A + (CarryFlag and 1 or 0)
  
  local xor1 = bnot(bxor(A, value))
  local xor2 = bxor(A, sum)
  
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
  NegativeFlag = band(Y - value, 0xFF) > 127
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
  local carry = band(A, 1) ~= 0
  A = band(rshift(A, 1), 0xFF)
  A = CarryFlag and bor(A, 0x80) or A
  
  CarryFlag = carry
  NegativeFlag = A > 127
  ZeroFlag = A == 0
end
function OpROR(value)
  local carry = band(value, 1) ~= 0
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

--Unnoficial Opcodes
function OpDCP(value)
  OpDEC(value)
  OpCMP(DataLatch)
end
function OpISC(value)
  OpINC(value)
  OpSBC(DataLatch)
end
function OpRLA(value)
  OpROL(value)
  OpAND(DataLatch)
end
function OpRRA(value)
  OpROR(value)
  OpADC(DataLatch)
end
function OpSLO(value)
  OpASL(value)
  OpORA(DataLatch)
end
function OpSRE(value)
  OpLSR(value)
  OpEOR(DataLatch)
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
    Read(AddressBus) --Dummy Read :)
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
local NMIDetector = false
function EndInstruction()
  CycleTick = -1
  
  --Poll Interrupts Here For Now
  local PreviousNMI = NMIDetector
  if NMIEnabled and Vblank then
    NMIDetector = true
  else
    NMIDetector = false
  end
  if not PreviousNMI and NMIDetector then
    DoNMI = true
  end
  --TODO: Add IRQs
  --Log Instructions Here
end

--PPU Functions
function EmulatePPU()
  if Dot == 1 and Scanline == 241 then
    Vblank = true
    DrawFrame = true
  elseif Dot == 1 and Scanline == 261 then
    Vblank = false
    SpriteZeroHit = false
    SpriteOverflow = false
  end
  
  if Scanline < 240 or Scanline == 261 then
    if Scanline ~= 261 and (RenderBg or RenderSprites) then
      EvaluateSprites()
    end
    if (Dot > 0 and Dot <= 256) or (Dot > 320 and Dot <= 336) then
      if RenderBg or RenderSprites then
        if RenderBg then
          ShiftRegPattLow = lshift(ShiftRegPattLow, 1)
          ShiftRegPattHigh = lshift(ShiftRegPattHigh, 1)
          ShiftRegAttrLow = lshift(ShiftRegAttrLow, 1)
          ShiftRegAttrHigh = lshift(ShiftRegAttrHigh, 1)
        end
        if Dot > 1 and Dot <= 256 then
          for i = 0, 7 do
            if ShiftRegXPos[i] > 0 then
               ShiftRegXPos[i] = ShiftRegXPos[i] - 1
            else
               ShiftRegL[i] = lshift(ShiftRegL[i], 1)
               ShiftRegH[i] = lshift(ShiftRegH[i], 1)
            end
          end
        end
        local PPUCycleTick = band(Dot - 1, 7)
        if PPUCycleTick == 0 then
          ShiftRegPattLow = band(bor(band(ShiftRegPattLow, 0xFF00), LowBitPlane), 0xFFFF)
          ShiftRegPattHigh = band(bor(band(ShiftRegPattHigh, 0xFF00), HighBitPlane), 0xFFFF)
          ShiftRegAttrLow = band(bor(band(ShiftRegAttrLow, 0xFF00), band(AttributePlane, 1) == 1 and 0xFF or 0), 0xFFFF)
          ShiftRegAttrHigh = band(bor(band(ShiftRegAttrHigh, 0xFF00), band(AttributePlane, 2) == 2 and 0xFF or 0), 0xFFFF)
          PPUAddressBus = 0x2000 + band(VRAMAddress, 0x0FFF)
          PPUDataLatch = ReadPPU(PPUAddressBus)
        elseif PPUCycleTick == 1 then
          NextTile = PPUDataLatch
        elseif PPUCycleTick == 2 then
          PPUAddressBus = bor(bor(bor(0x23C0, band(VRAMAddress, 0x0C00)), band(rshift(VRAMAddress, 4), 0x38)), band(rshift(VRAMAddress, 2), 0x07))
          PPUAddressBus = band(PPUAddressBus, 0xFFFF)
          PPUDataLatch = ReadPPU(PPUAddressBus)
        elseif PPUCycleTick == 3 then
          AttributePlane = PPUDataLatch
          if band(VRAMAddress, 3) >= 2 then
            --This is a byte/uint8
            AttributePlane = band(rshift(AttributePlane, 2), 0xFF)
          end
          --0b0000001111100000 = 0x03E0
          if band(rshift(band(VRAMAddress, 0x03E0), 5), 3) >= 2 then
            --This is also a byte/uint8
            AttributePlane = band(rshift(AttributePlane, 4), 0xFF)
          end
          AttributePlane = band(AttributePlane, 3)
        elseif PPUCycleTick == 4 then
          --0b0111000000000000 = 0x7000
          --also don't ask
          PPUAddressBus = bor(bor(rshift(band(VRAMAddress, 0x7000), 12), NextTile * 16), BgPatternTable and 0x1000 or 0)
          PPUAddressBus = band(PPUAddressBus, 0xFFFF)
          PPUDataLatch = ReadPPU(PPUAddressBus)
        elseif PPUCycleTick == 5 then
          LowBitPlane = PPUDataLatch
          PPUAddressBus = band(PPUAddressBus + 8, 0xFFFF)
        elseif PPUCycleTick == 6 then
          PPUDataLatch = ReadPPU(PPUAddressBus)
        elseif PPUCycleTick == 7 then
          HighBitPlane = PPUDataLatch
          if band(VRAMAddress, 0x001F) == 31 then
            VRAMAddress = band(VRAMAddress, 0xFFE0)
            VRAMAddress = bxor(VRAMAddress, 0x0400)
          else
            VRAMAddress = band(VRAMAddress + 1, 0xFFFF)
          end
        end
      end
    end
    if RenderBg then
      if Dot == 256 then
        IncrementYScroll()
      elseif Dot == 257 then
        ResetXScroll()
      elseif Dot >= 280 and Dot <= 304 and Scanline == 261 then
        ResetYScroll()
      end
    end
  end
  if Scanline < 240 and Dot > 0 and Dot <= 256 then
    local PalHigh = 0
    local PalLow = 0
    if RenderBg and (Dot > 8 or Mask8pxSprites) then
      local color0 = band(rshift(ShiftRegPattLow, 15 - FineX), 1)
      local color1 = band(rshift(ShiftRegPattHigh, 15 - FineX), 1)
      PalLow = bor(lshift(color1, 1), color0)
      
      local palette0 = band(rshift(ShiftRegAttrLow, 15 - FineX), 1)
      local palette1 = band(rshift(ShiftRegAttrHigh, 15 - FineX), 1)
      PalHigh = bor(lshift(palette1, 1), palette0)
      
      if PalLow == 0 and PalHigh ~= 0 then
        PalHigh = 0
      end
    end
    local SpritePalLow = 0
    local SpritePalHigh = 0
    local SpritePriority = false
    if RenderSprites and (Dot > 8 or Mask8pxSprites) then
      for i = 0, 7 do
        if ShiftRegXPos[i] == 0 and i < truncate(SecondaryOAMSize / 4) then
          local pxLow = band(ShiftRegL[i], 0x80) ~= 0
          local pxHigh = band(ShiftRegH[i], 0x80) ~= 0
          SpritePalLow = 0
          if pxLow then SpritePalLow = 1 end
          if pxHigh then SpritePalLow = bor(SpritePalLow, 2) end
        
          SpritePalHigh = bor(band(ShiftRegAttr[i], 3), 4)
          SpritePriority = band(rshift(ShiftRegAttr[i], 5), 1) == 0
        else
          goto continue
        end
        if SpritePalLow ~= 0 then
          if i == 0 and IsSpriteZero and SpritePalLow ~= 0 and PalLow ~= 0 and RenderBg and Dot < 256 then
            SpriteZeroHit = true
          end
          break
        end
        ::continue::
      end
    end 
    if (SpritePriority and SpritePalLow ~= 0) or PalLow == 0 then
      PalLow = SpritePalLow
      PalHigh = SpritePalHigh
      if PalLow == 0 then
        PalHigh = 0
      end
    end
    local palidx = 0
    if not RenderSprites and not RenderBg then
      if VRAMAddress >= 0x3F00 and VRAMAddress <= 0x3FFF then
        palidx = PaletteRAM[band(VRAMAddress, 0x1F)]
      else
        palidx = PaletteRAM[PalLow + PalHigh * 4]
      end
    else
      palidx = PaletteRAM[PalLow + PalHigh * 4]
    end
    if Grayscale then
      palidx = band(palidx, 0x30)
    end
    local coloridx = (EmphasisColor * 32 + palidx)
    local pixel = (Dot - 1 + (Scanline * 256))
    
    ImagePointer[pixel].r = ColorData[coloridx].r
    ImagePointer[pixel].g = ColorData[coloridx].g
    ImagePointer[pixel].b = ColorData[coloridx].b
    ImagePointer[pixel].a = ColorData[coloridx].a
  end
  Dot = Dot + 1
  if Dot > 341 then
    Dot = 0
    Scanline = Scanline + 1
    if Scanline > 261 then
      Scanline = 0
    end
  end
end
function ReadPPU(address)
  if address < 0x2000 then --Read from pattern table (if possible)
    return CHRData[address]
  elseif address < 0x3F00 then --Read from nametable
    if band(Header[6], 1) == 0 then
      --"Vertical mirroing"
      return VRAM[bor(band(address, 0x3FF), rshift(band(address, 0x800), 1))]
    else
      --"Horizontal mirroing"
      return VRAM[band(address, 0x7FF)]    
    end
  else --Read from palettes
    if band(address, 3) == 0 then
      return PaletteRAM[band(address, 0x0F)]
    else
      return PaletteRAM[band(address, 0x1F)]
    end    
  end
end
function IncrementYScroll()
  if band(VRAMAddress, 0x7000) ~= 0x7000 then
    VRAMAddress = VRAMAddress + 0x1000
  else
    VRAMAddress = band(VRAMAddress, 0x0FFF)
    local y = rshift(band(VRAMAddress, 0x03E0), 5)
    if y == 29 then
      y = 0
      VRAMAddress = bxor(VRAMAddress, 0x0800)
    else
      y = y + 1
      y = band(y, 0x1F)
    end
    VRAMAddress = band(bor(band(VRAMAddress, 0xFC1F), lshift(y, 5)), 0xFFFF)
  end
end
function ResetXScroll()
  --0b0111101111100000 = 0x7BE0
  --0b0000010000011111 = 0x041F
  VRAMAddress = band(bor(band(VRAMAddress, 0x7BE0), band(TransferAddress, 0x041F)), 0xFFFF)
end
function ResetYScroll()
  --0b0000010000011111 = 0x041F
  --0b0111101111100000 = 0x7BE0
  VRAMAddress = band(bor(band(VRAMAddress, 0x041F), band(TransferAddress, 0x7BE0)), 0xFFFF)
end
function EvaluateSprites()
  if Dot == 0 then
    SecondaryOAMAddress = 0
    SecondaryOAMFull = false
    EvalOAMOverflowed = false
  elseif Dot > 0 and Dot <= 64 then
    if band(Dot, 1) == 1 then
      SprDataLatch = 0xFF
    else
      SecondaryOAM[SecondaryOAMAddress] = SprDataLatch
      SecondaryOAMAddress = SecondaryOAMAddress + 1
      SecondaryOAMAddress = band(SecondaryOAMAddress, 0x1F)
    end
  elseif Dot > 64 and Dot <= 256 then
    if band(Dot, 1) == 1 then
      SprDataLatch = OAM[OAMAddress]
    else
      if not EvalOAMOverflowed then
        if not SecondaryOAMFull then
          SecondaryOAM[SecondaryOAMAddress] = SprDataLatch 
        end
        if SpriteEvalTick == 0 then
          if Scanline - SprDataLatch >= 0 and Scanline - SprDataLatch < (Use8x16Sprites and 16 or 8) then
            if not SecondaryOAMFull then
              SecondaryOAMAddress = SecondaryOAMAddress + 1
              OAMAddress = band(OAMAddress + 1, 0xFF)
              if Dot == 66 then
                IsSpriteZero = true
              end
            else
              SpriteOverflow = true
            end
            SpriteEvalTick = SpriteEvalTick + 1
          else
            OAMAddress = band(OAMAddress + 4, 0xFF)
          end
        else
          SecondaryOAMAddress = SecondaryOAMAddress + 1
          OAMAddress = band(OAMAddress + 1, 0xFF)
          if SecondaryOAMAddress == 0x20 then
            SecondaryOAMFull = true
          end
          SpriteEvalTick = SpriteEvalTick + 1
          SpriteEvalTick = band(SpriteEvalTick, 3)
        end
        if OAMAddress == 0 then
          EvalOAMOverflowed = true
        end
      end
    end
  elseif Dot > 256 and Dot <= 320 then
    OAMAddress = 0
    if Dot == 257 then
      SecondaryOAMSize = SecondaryOAMAddress
      SecondaryOAMAddress = 0
      SpriteEvalTick = 0
    end
    if SpriteEvalTick == 0 then
      ShiftRegYPos[truncate(SecondaryOAMAddress / 4)] = SecondaryOAM[SecondaryOAMAddress]
      SecondaryOAMAddress = SecondaryOAMAddress + 1
    elseif SpriteEvalTick == 1 then
      ShiftRegPatt[truncate(SecondaryOAMAddress / 4)] = SecondaryOAM[SecondaryOAMAddress]
      SecondaryOAMAddress = SecondaryOAMAddress + 1
    elseif SpriteEvalTick == 2 then
      ShiftRegAttr[truncate(SecondaryOAMAddress / 4)] = SecondaryOAM[SecondaryOAMAddress]
      SecondaryOAMAddress = SecondaryOAMAddress + 1
    elseif SpriteEvalTick == 3 then
      ShiftRegXPos[truncate(SecondaryOAMAddress / 4)] = SecondaryOAM[SecondaryOAMAddress]
    elseif SpriteEvalTick == 4 then
      PPUAddressBus = FindCharacterAddress(truncate(SecondaryOAMAddress / 4))
    elseif SpriteEvalTick == 5 then
      SprDataLatch = ReadPPU(PPUAddressBus)
      if Scanline == 261 then
        SprDataLatch = 0
      end
      if band(rshift(ShiftRegAttr[truncate(SecondaryOAMAddress / 4)], 6), 1) == 1 then
        SprDataLatch = band(bor(rshift(band(SprDataLatch, 0xF0), 4), lshift(band(SprDataLatch, 0x0F), 4)), 0xFF)
        SprDataLatch = band(bor(rshift(band(SprDataLatch, 0xCC), 2), lshift(band(SprDataLatch, 0x33), 2)), 0xFF)
        SprDataLatch = band(bor(rshift(band(SprDataLatch, 0xAA), 1), lshift(band(SprDataLatch, 0x55), 1)), 0xFF)
      end
      ShiftRegL[truncate(SecondaryOAMAddress / 4)] = SprDataLatch
    elseif SpriteEvalTick == 6 then
      PPUAddressBus = PPUAddressBus + 8
    elseif SpriteEvalTick == 7 then
      SprDataLatch = ReadPPU(PPUAddressBus)
      if Scanline == 261 then
        SprDataLatch = 0
      end
      if band(rshift(ShiftRegAttr[truncate(SecondaryOAMAddress / 4)], 6), 1) == 1 then
        SprDataLatch = band(bor(rshift(band(SprDataLatch, 0xF0), 4), lshift(band(SprDataLatch, 0x0F), 4)), 0xFF)
        SprDataLatch = band(bor(rshift(band(SprDataLatch, 0xCC), 2), lshift(band(SprDataLatch, 0x33), 2)), 0xFF)
        SprDataLatch = band(bor(rshift(band(SprDataLatch, 0xAA), 1), lshift(band(SprDataLatch, 0x55), 1)), 0xFF)
      end
      ShiftRegH[truncate(SecondaryOAMAddress / 4)] = SprDataLatch
      SecondaryOAMAddress = SecondaryOAMAddress + 1
    end
   
    SpriteEvalTick = SpriteEvalTick + 1
    SpriteEvalTick = band(SpriteEvalTick, 7)
  end
end
function FindCharacterAddress(slot) 
  if not Use8x16Sprites then --8x8
    if band(rshift(ShiftRegAttr[slot], 7), 1) == 0 then
      return (SpritePatternTable and 0x1000 or 0) + lshift(ShiftRegPatt[slot], 4) + (Scanline - ShiftRegYPos[slot])
    else
      return (SpritePatternTable and 0x1000 or 0) + lshift(ShiftRegPatt[slot], 4) + band((7 - (Scanline - ShiftRegYPos[slot])), 7)
    end
  else --8x16 (stupid)
    if band(rshift(ShiftRegAttr[slot], 7), 1) == 0 then
      if Scanline - ShiftRegYPos[slot] < 8 then
        return bor((band(ShiftRegPatt[slot], 1) == 1 and 0x1000 or 0), lshift(band(ShiftRegPatt[slot], 0xFE), 4) + (Scanline - ShiftRegYPos[slot])) 
      else
        return bor((band(ShiftRegPatt[slot], 1) == 1 and 0x1000 or 0), (lshift(band(ShiftRegPatt[slot], 0xFE), 4) + 16) + band(Scanline - ShiftRegYPos[slot], 7)) 
      end
    else
      if Scanline - ShiftRegYPos[slot] < 8 then
        return bor((band(ShiftRegPatt[slot], 1) == 1 and 0x1000 or 0), (lshift(band(ShiftRegPatt[slot], 0xFE), 4) + 16) - (band(Scanline - ShiftRegYPos[slot], 7)) + 7) 
      else
        return bor((band(ShiftRegPatt[slot], 1) == 1 and 0x1000 or 0), (lshift(band(ShiftRegPatt[slot], 0xFE), 4) + 7) - band(Scanline - ShiftRegYPos[slot], 7)) 
      end
    end
  end
end

--APU Functions
function EmulateAPU()
  --TODO: Fix DMC Channel (Why is this broken???????????)
  ClockDMC()
  --TODO: Add the missing channels and sound
end
function ClockDMC()
  --TODO: Do an actual DMA instead of faking it
  if DMC.Empty and DMC.BytesRemaining > 0 then
    --DMC DMA but bad
    DMC.SampleBuffer = Read(DMC.Address)
    DMC.Address = DMC.Address + 1
    if DMC.Address > 0xFFFF then
      DMC.Address = 0x8000
    end
    DMC.BytesRemaining = DMC.BytesRemaining - 1
    if DMC.BytesRemaining == 0 and DMC.Loop then
      DMC.Address = DMC.SampleAddress
      DMC.BytesRemaining = DMC.SampleLength
      DMC.Empty = false
    elseif DMC.BytesRemaining == 0 and DMC.IRQEnabled then
      DMCInterruptFlag = true
      DMC.Empty = true
    end
  end
  
  if DMC.Period > 0 then
    DMC.Period = DMC.Period - 1
    return
  else
    DMC.Period = DMC.Rate
  end
  
  if not DMC.Silence then
    local bit = band(DMC.ShiftRegister, 1)
    if bit == 1 and DMC.Output + 2 <= 127 then
      DMC.Output = DMC.Output + 2
    elseif DMC.Output - 2 >= 0 then
      DMC.Output = DMC.Output - 2
    end
  end
  DMC.ShiftRegister = rshift(DMC.ShiftRegister, 1)
  DMC.BitsRemaining = DMC.BitsRemaining - 1
  
  if DMC.BitsRemaining == 0 then
    DMC.BitsRemaining = 8
    if DMC.Empty then
      DMC.Silence = true
    else
      DMC.Silence = false
      DMC.ShiftRegister = DMC.SampleBuffer
    
      DMC.Empty = true
    end
  end
end

--Other Functions
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
function CopyCHRData(address, length)
  for i = address, address + length do
    CHRData[i - address] = ROM[i]
  end
end
local ROMToLoad = "Bomberman (USA).nes"
function RESET()
  --TODO: Add RESET Flag and "Instruction"
  LoadROM("roms/" .. ROMToLoad)
  if Header[5] ~= 0 then
    CopyCHRData(0x4000 * Header[4], 0x2000)
  end
  
  local AddrLow = Read(0xFFFC)
  local AddrHigh = Read(0xFFFD)
  ProgramCounter = bor(lshift(AddrHigh, 8), AddrLow)
end

RESET()

function Emulator.Run()
  while true do
    if CPUClock == 11 then
      EmulateCPU()
    end
    if CPUClock % 4 == 3 then
      EmulatePPU()
    end
    if CPUClock == 11 then
      EmulateAPU()
    end
    CPUClock = (CPUClock + 1) % 12
    
    if DrawFrame then
      DrawFrame = false
      
      SoundQueue:queue(SoundData)
      SoundQueue:play()
      
      break
    end
  end
  
  --TODO: Remove this placeholder thing
  return Image, ImageData, DMC.BytesRemaining
end

return Emulator