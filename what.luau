local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local EncodingService = game:GetService("EncodingService")



GAME_SOUND_IDS = {
	Jump = "78501822595374",
	DropDash = "104203114483905",
	SpindashCharge = "110065598023907",
	AbilityRelease = "138103047115340",
}
activeGameLoopSounds = {}

function playGameSound(name, looped)
	local assetId = GAME_SOUND_IDS[name]
	if not assetId then return nil end
	if looped then
		local previous = activeGameLoopSounds[name]
		if previous and previous.Parent then
			previous:Stop()
			previous:Destroy()
		end
	end
	local sound = Instance.new("Sound")
	sound.Name = "RSDK_" .. name
	sound.SoundId = "rbxassetid://" .. assetId
	sound.Volume = 0.7
	sound.Looped = looped == true
	sound.Parent = game:GetService("SoundService")
	if looped then activeGameLoopSounds[name] = sound end
	sound:Play()
	if not looped then game:GetService("Debris"):AddItem(sound, 8) end
	return sound
end

function stopGameLoopSound(name)
	local sound = activeGameLoopSounds[name]
	if sound then
		activeGameLoopSounds[name] = nil
		if sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end
end

--============================================================
-- CONFIG YES I AM HANDSOME!!
--============================================================

local WIDTH = 424
local HEIGHT = 240
local CANVAS_ORIGIN = Vector2.zero
local CANVAS_SIZE = Vector2.new(WIDTH, HEIGHT)
local FRAME_BYTE_LENGTH = WIDTH * HEIGHT * 4
local MAX_IMAGE_SIZE = 1024
local FIXED_DT = 1 / 60
local SHOW_COLLISION_DEBUG = false


local ROLL_DRAW_OFFSET = 4

local ACTIVE_LEVEL_NAME = "GHZ1_Act1"

local SPRITE_OFFSET_X = 0
local SPRITE_OFFSET_Y = 0

local RING_ANIMATION_SPEED_MULTIPLIER = 2



local ACCEL = 12 / 256
local DECEL = 128 / 256
local FRICTION = 12 / 256
local AIR_ACCEL = 24 / 256
local TOP_SPEED = 6
local GRAVITY = 56 / 256
local SLOPE_GRAVITY = 32 / 256
local JUMP_FORCE = 6.5
local WIDTH_RADIUS = 9
local HEIGHT_RADIUS = 19

local SLOPE_START_X = 35
local SLOPE_BOTTOM_X = 85
local SLOPE_UP_END_X = 185
local TRACK_START_Y = 214
local TRACK_VALLEY_Y = 231
local TRACK_LOOP_Y = 202

local LOOP_CENTER_X = 332
local LOOP_CENTER_Y = 148
local LOOP_RADIUS = 54
local LOOP_PLAYER_RADIUS = LOOP_RADIUS - HEIGHT_RADIUS

local DROP_DASH_CHARGE_STATE = 22 
local DROP_DASH_SPEED = 8
local DROP_DASH_SPEED_CAP = 12


local IS_SUPER_FORM = false
if IS_SUPER_FORM then
	DROP_DASH_SPEED = 12
	DROP_DASH_SPEED_CAP = 13
end


local SPINDASH_REV_STEP = 2
local SPINDASH_REV_MAX = 8
local SPINDASH_START_SPEED = 8

local BLACK = Color3.fromRGB(0, 0, 0)
local GREEN = Color3.fromRGB(0, 170, 0)
local GREEN_BG = {0, 255, 0}
local GROUND = {35, 90, 35}
local GROUND_TOP = {230, 230, 230}
local SONIC_TEMP = {0, 0, 255}
local WHITE = {255, 255, 255}
local YELLOW = {255, 255, 0}
local CYAN = {0, 255, 255}
local ORANGE = {255, 150, 0}


local RSDK = ReplicatedStorage:WaitForChild("RSDK")
local PNG = require(RSDK:WaitForChild("PNG"))
local RSDKLevelParser = require(RSDK:WaitForChild("RSDKLevelParser"))
assert(type(RSDKLevelParser.Sense) == "function", "RSDKLevelParser.Sense is missing")
assert(type(RSDKLevelParser.GetSurfaceAngleAtPixel) == "function", "Install the rebuilt RSDKLevelParser with native angle support")
local PreviewPNGData = require(RSDK:WaitForChild("PreviewPNGData"))
local AnimationParser = require(RSDK:WaitForChild("AnimationParser"))
local AnimationData = require(RSDK:WaitForChild("AnimationData"))

function decodeAssetBuffer(input)
	if typeof(input) == "buffer" then
		return input
	end

	local encoding = "base64"
	if type(input) == "table" then
		encoding = input.Encoding or "base64"
		input = input.Data
	end

	assert(type(input) == "string", "Expected Base64 data or a buffer")

	if encoding == "raw" then
		return buffer.fromstring(input)
	end

	assert(encoding == "base64", "Unsupported encoding: " .. tostring(encoding))

	local prefix = input:match("^data:[^,]*;base64,")
	if prefix then
		input = input:sub(#prefix + 1)
	end

	input = input:gsub("%s+", "")
	assert(#input > 0, "Base64 data is empty")

	return EncodingService:Base64Decode(buffer.fromstring(input))
end

print("[RSDK] Decoding Sonic sprite sheet")
local spriteSheet = PNG.decode(decodeAssetBuffer(PreviewPNGData))
assert(spriteSheet.width > 0 and spriteSheet.height > 0, "Invalid PNG dimensions")
assert(
	buffer.len(spriteSheet.pixels) >= spriteSheet.width * spriteSheet.height * 4,
	"PNG RGBA pixel buffer is too small"
)
print(string.format("[RSDK] PNG: %d x %d", spriteSheet.width, spriteSheet.height))


function applyColorKey(image, r, g, b, tolerance)
	tolerance = tolerance or 0
	local pixels = image.pixels
	local count = 0
	for offset = 0, image.width * image.height * 4 - 4, 4 do
		if math.abs(buffer.readu8(pixels, offset) - r) <= tolerance
			and math.abs(buffer.readu8(pixels, offset + 1) - g) <= tolerance
			and math.abs(buffer.readu8(pixels, offset + 2) - b) <= tolerance then
			buffer.writeu8(pixels, offset + 3, 0)
			count += 1
		end
	end
	return count
end

applyColorKey(spriteSheet, 0x00, 0xF0, 0x00) -- Sonic: 00F000 = transparent


local activeLevel = nil
local activeTileset = nil
local activeLevelConfig = {
	StartX = 96,
	StartY = 80,
	CollisionLayerNames = { "FG Low", "FG High" },
	CollisionPlane = 0,
	AutoDetectCollisionPlane = true,
	AutoDetectCollisionLayers = false,
}
local usingRSDKLevel = false
local levelCollisionLayer = nil 
local levelCollisionLayers = {}
local showCollisionOverlay = false
local lastCollisionOverlayCameraX = nil
local lastCollisionOverlayCameraY = nil
local lastCollisionOverlayLevel = nil
local lastCollisionOverlayLayers = nil
local lastCollisionOverlayPlane = nil
local collisionOverlayPixels = nil
local menuOpen = true
local selectedLevelName = nil

-- Raw 16-byte MD5 of the lonley LayerSwitcher object name

local OPT = {
	layerSwitcherRaw = (("8B5FAD2EF3AB80024394193506407A27"):gsub("%x%x", function(h)
		return string.char(tonumber(h, 16))
	end)),
	layerSwitchers = {},
	pendingLayerSwitchers = {},
	circleCache = {},
	airPushRows = { -3, 3, 6 },
	groundPushRows = { 0, -3, 3 },
	safeX = nil,
	safeY = nil,
	water = {
		enabled = false,
		configured = false,
		baseLevel = nil,
		surfaceY = nil,
		levelSpace = "world",
		showDebugHud = true,
		waveAmplitude = 1.25,
		waveSpeed = math.pi / 128,
		tintColor = {28, 78, 138},
		tintStrength = 0.38,
		surfaceColor = {74, 190, 236},
		highlightColor = {180, 238, 255},
		shadowColor = {22, 104, 164},
		groundSpeedScale = 0.50,
		groundAccelScale = 0.50,
		groundDecelScale = 0.50,
		groundFrictionScale = 0.50,
		rollingFrictionScale = 0.50,
		airAccelScale = 0.50,
		gravityScale = 32 / 88,
		terminalSpeedScale = 1.0,
		jumpForceScale = 3.5 / 6.5,
		entryHorizontalScale = 0.50,
		entryVerticalScale = 0.25,
		bubbleInterval = 52,
		bubbleTimer = 0,
		tick = 0,
		underwater = false,
		bubbles = {},
		splashes = {},
	},
	hud = { ticks = 0, score = 0, lives = 3, visible = true },
	titleCard = { active = false, phase = "hidden", timer = 0, zoneName = "UNTITLED", actNumber = 1 },
	waterNameHashRaw = (("27634FF8002B12E75D98E07CCD005D18"):gsub("%x%x", function(h)
		return string.char(tonumber(h, 16))
	end)),
	waterNameHashSwapped = "\248\79\99\39\231\18\43\0\124\224\152\93\24\93\0\205",
}



local activeEntities = {}
local ringPickupEffects = {} -- RSDK Ring.bin sparkle-sprite entities created when Sonic collects a ring.
local objectRegistry = {}
-- Global function defined below.
local ringSpriteSheet = nil
local ringAnimation = nil
local ringAnimations = {} -- RSDK Global/Ring.bin order: Normal, Big, Sparkle1, Sparkle2, Sparkle3.
-- Global function defined below.

-- RSDK scene entities store the MD5 of their object name. These are MD5("Ring")
-- in the normal and per-32-bit-word byte-swapped layouts used by this parser.
local RING_NAME_HASHES = {
	["\212\219\23\124\148\115\139\114\191\156\230\30\152\138\177\241"] = true,
	["\124\23\219\212\114\139\115\148\30\230\156\191\241\177\138\152"] = true,
}
-- MD5("Bridge") / MD5("Motobug"), raw and per-word byte-swapped.
local OBJECT_NAME_HASHES = {
	["\222\133\4\183\62\162\40\208\234\155\188\230\151\82\9\46"] = "Bridge",
	["\183\4\133\222\208\40\162\62\230\188\155\234\46\9\82\151"] = "Bridge",
	["\243\112\20\47\127\218\30\27\33\178\114\242\186\215\198\191"] = "Motobug",
	["\47\20\112\243\27\30\218\127\242\114\178\33\191\198\215\186"] = "Motobug",
	["\051\190\206\235\199\022\039\237\089\191\254\247\022\183\155\148"] = "PimPom",
	["\235\206\190\051\237\039\022\199\247\254\191\089\148\155\183\022"] = "PimPom",
	["\056\000\141\216\028\047\077\121\133\236\246\224\206\138\241\209"] = "Spring",
	["\216\141\000\056\121\077\047\028\224\246\236\133\209\241\138\206"] = "Spring",
	["\172\114\115\191\093\162\026\235\111\151\071\168\060\208\251\234"] = "DDWrecker",
	["\191\115\114\172\235\026\162\093\168\071\151\111\234\251\208\060"] = "DDWrecker",
}

function spawnLevelEntities(level)
	activeEntities = {}
	OPT.entitySlotPos = OPT.entitySlotPos or {}
	table.clear(OPT.entitySlotPos)
	if type(level) ~= "table" or type(level.entities) ~= "table" then
		warn("[RSDK] Cannot spawn entities: parsed level has no entities table")
		return
	end

	local recognizedRings, recognizedSprings, recognizedDDWreckers = 0, 0, 0
	for _, rawEntity in ipairs(level.entities) do
		-- RSDK positions are signed 16.16 fixed-point values.
		local rawX = tonumber(rawEntity.xRaw) or 0
		local rawY = tonumber(rawEntity.yRaw) or 0
		if rawX >= 0x80000000 then rawX -= 0x100000000 end
		if rawY >= 0x80000000 then rawY -= 0x100000000 end
		local worldX = rawX / 65536
		local worldY = rawY / 65536

		OPT.entitySlotPos[rawEntity.objectID] = { x = worldX, y = worldY }

		-- Do not guess an objectID. Match the actual RSDK object-name hash.
		local objectName = RING_NAME_HASHES[rawEntity.nameHash] and "Ring" or OBJECT_NAME_HASHES[rawEntity.nameHash]
		local classDef = objectName and objectRegistry[objectName] or nil
		if classDef then
			local newEntity = {
				x = worldX,
				y = worldY,
				def = classDef,
				id = rawEntity.objectID,
				nameHash = rawEntity.nameHash,
			}
			if objectName == "Bridge" then
				local row = OPT.bridgeData[rawEntity.objectID]
				newEntity.length = row and row.length or rawEntity.length or 12
				newEntity.burnable = row and row.burnable or rawEntity.burnable
			elseif objectName == "Motobug" then
				newEntity.direction = rawEntity.direction
			elseif objectName == "Spring" then
				-- The compact SceneData parser does not expose Spring's editor
				-- properties. Do NOT read rawEntity.type/direction here: those
				-- fields can describe unrelated entity metadata and can turn an
				-- upward spring into a diagonal (45-degree) spring by accident.
				-- SpringData is the authoritative per-object property source.
				local row = OPT.springData[rawEntity.objectID] or {}
				local packed = tonumber(row.propertyValue or row.properties)
				local springType = tonumber(row.type or row.springType)
				local flipFlag = tonumber(row.flipFlag or row.flip)
				if packed then
					if springType == nil then springType = bit32.band(packed, 0xFF) end
					if flipFlag == nil then flipFlag = bit32.band(bit32.rshift(packed, 8), 0xFF) end
				end
				-- No exported properties means the safe Mania default:
				-- type 0 = yellow vertical spring, flipFlag 0 = launches upward.
				newEntity.springType = math.clamp(math.floor(springType or 0), 0, 5)
				newEntity.flipFlag = math.clamp(math.floor(flipFlag or 0), 0, 3)
				newEntity.planeFilter = tonumber(row.planeFilter) or 0
				newEntity.onGround = row.onGround == true
			elseif objectName == "DDWrecker" then
				local row = OPT.ddwreckerData and OPT.ddwreckerData[rawEntity.objectID]
				newEntity.bossHealth = tonumber(row and row.health) or 6
			elseif objectName == "PimPom" then
				local row = OPT.pimPomData[rawEntity.objectID] or {}
				local amp = type(row.amplitude) == "table" and row.amplitude or {}
				newEntity.ppType = tonumber(row.type)
				newEntity.color = tonumber(row.color)
				newEntity.direction = tonumber(row.direction)
				newEntity.angleProp = tonumber(row.angle)
				newEntity.spinSpeed = tonumber(row.spinSpeed)
				newEntity.moveType = tonumber(row.moveType)
				newEntity.ampX = tonumber(amp.x or amp[1] or row.amplitudeX)
				newEntity.ampY = tonumber(amp.y or amp[2] or row.amplitudeY)
				newEntity.speed = tonumber(row.speed)
				newEntity.angleM = tonumber(row.angleM)
				newEntity.length = tonumber(row.length)
				newEntity.gap = tonumber(row.gap)
				newEntity.numChildren = tonumber(row.numChildren)
			end
			if classDef.init then classDef.init(newEntity) end
			table.insert(activeEntities, newEntity)
			if objectName == "Ring" then recognizedRings += 1 end
			if objectName == "Spring" then recognizedSprings += 1 end
			if objectName == "DDWrecker" then recognizedDDWreckers += 1 end
		end
	end
	OPT.pp.linkChildren()
	print(string.format("[RSDK] Spawned %d active entities (%d Rings, %d Springs, %d DDWreckers recognized by name hash)", #activeEntities, recognizedRings, recognizedSprings, recognizedDDWreckers))
end

-- Template for a Green Hill Object
objectRegistry["Ring"] = {
	init = function(entity)
		entity.frameID = 0
		entity.frameTimer = 0
		entity.frameDuration = 1
		entity.animation = ringAnimation
		if ringAnimation and ringAnimation.frames and ringAnimation.frames[1] then
			entity.frameDuration = math.max(1, tonumber(ringAnimation.frames[1].duration) or 1)
		end
		entity.radius = 8
		entity.collectible = true
	end,

	update = function(entity, _dt)
		local animation = entity.animation
		if not animation or type(animation.frames) ~= "table" or #animation.frames == 0 then
			return
		end

		-- RSDK animationSpeed/frame duration use animation ticks, not seconds.
		entity.frameTimer += (tonumber(animation.animationSpeed) or 128)
			* RING_ANIMATION_SPEED_MULTIPLIER
		local safety = 0
		while entity.frameTimer > entity.frameDuration do
			safety += 1
			if safety > 128 then
				warn("[RSDK] Ring animation safety limit reached")
				break
			end
			entity.frameTimer -= entity.frameDuration
			entity.frameID += 1
			if entity.frameID >= #animation.frames then
				entity.frameID = math.clamp(tonumber(animation.loopIndex) or 0, 0, #animation.frames - 1)
			end
			local nextFrame = animation.frames[entity.frameID + 1]
			entity.frameDuration = math.max(1, tonumber(nextFrame.duration) or 1)
		end
	end,

	-- drawSpriteFrame is assigned after its definition; this initial fallback
	-- safely does nothing until the RSDK ring assets are loaded.
	draw = function() end,
}

-- Mania PlaneSwitch `flags`: bit3 = lane (A/B) for the RIGHT side of the line,
-- bit2 = lane for the LEFT side. Angle is Mania's 256-unit angle; the line
-- length is size * 8 pixels and it is 24px thick (0x180000 in 16.16).
OPT.planeRightBit = 3
OPT.planeLeftBit = 1

function OPT.buildSwitcher(entity, data)
	local switcher = {
		x = entity.xRaw / 65536,
		y = entity.yRaw / 65536,
		cos = 1,
		sin = 0,
		halfLength = 64,
		groundOnly = false,
	}
	if data then
		local size = tonumber(data.size) or 8
		-- negAngle = -angle: rotate the player INTO the switch's frame.
		local rad = -(tonumber(data.angle) or 0) * (2 * math.pi / 256)
		switcher.cos = math.cos(rad)
		switcher.sin = math.sin(rad)
		switcher.halfLength = size * 8
		switcher.groundOnly = (tonumber(data.onPath) or 0) ~= 0
		local flags = tonumber(data.flags)
		if flags then
			switcher.planeRight = bit32.extract(flags, OPT.planeRightBit)
			switcher.planeLeft = bit32.extract(flags, OPT.planeLeftBit)
		end
	end
	switcher.reach = math.max(switcher.halfLength, 24) + 2
	return switcher
end


print("[RSDK] Parsing AnimationData")
local parsed = AnimationParser.Parse(AnimationData)
assert(#parsed.animations > 0, "AnimationData contains no animations")
print(string.format("[RSDK] Parsed %d animations and %d frames", parsed.animationCount, parsed.declaredFrameCount))

for _, animation in ipairs(parsed.animations) do
	print(string.format(
		"[RSDK] %s | frames=%d | speed=%d | loop=%d",
		animation.name,
		animation.frameCount,
		animation.animationSpeed,
		animation.loopIndex
		))
end

--============================================================
-- ANIMATION LOOKUP
--============================================================

function normalizeName(name)
	return string.lower(name):gsub("[%s%p]", "")
end

function findAnimation(...)
	local aliases = {...}

	for _, alias in ipairs(aliases) do
		local wanted = normalizeName(alias)
		for _, animation in ipairs(parsed.animations) do
			if normalizeName(animation.name) == wanted then
				return animation
			end
		end
	end

	for _, alias in ipairs(aliases) do
		local wanted = normalizeName(alias)
		for _, animation in ipairs(parsed.animations) do
			local name = normalizeName(animation.name)
			if name:sub(1, #wanted) == wanted then
				return animation
			end
		end
	end

	return nil
end

-- Optional Modules expected under ReplicatedStorage.RSDK:
--   RingPNGData        = PNG sheet encoded like PreviewPNGData
--   RingAnimationData  = animation data accepted by AnimationParser.Parse
-- These must come from a sprite asset set you are authorized to use. They are
-- intentionally separate from Sonic's PreviewPNGData/AnimationData.
do
	local ringPngModule = RSDK:FindFirstChild("RingPNGData")
	local ringAnimModule = RSDK:FindFirstChild("RingAnimationData")
	if ringPngModule and ringAnimModule then
		local ok, loadedSheet, loadedAnimationData = pcall(function()
			local sheet = PNG.decode(decodeAssetBuffer(require(ringPngModule)))
			assert(sheet.width > 0 and sheet.height > 0, "Ring PNG has invalid dimensions")
			assert(buffer.len(sheet.pixels) >= sheet.width * sheet.height * 4, "Ring PNG pixel buffer is too small")

			-- Use the exact chroma key used for imported level tilesets:
			-- RGB FF00FE, with a tolerance of 2 per channel. This removes the
			-- ring-sheet background while preserving the sprite's own alpha.
			local ringKeyedPixels = applyColorKey(sheet, 0xFF, 0x00, 0xFE, 2)
			if ringKeyedPixels > 0 then
				print(string.format("[RSDK] Ring sheet pixels made transparent (FF00FE): %d", ringKeyedPixels))
			else
				warn("[RSDK] Ring sheet contains no FF00FE color-key pixels; existing PNG alpha was preserved")
			end

			local animationData = AnimationParser.Parse(require(ringAnimModule))
			assert(type(animationData.animations) == "table" and #animationData.animations > 0,
				"RingAnimationData contains no animations")
			return sheet, animationData
		end)

		if ok then
			ringSpriteSheet = loadedSheet
			ringAnimations = loadedAnimationData.animations
			-- Sonic Mania's RingTypes enum is Normal=0, Big=1, Sparkle1=2,
			-- Sparkle2=3, Sparkle3=4. AnimationParser stores that order at 1..5.
			ringAnimation = ringAnimations[1]
			if not ringAnimation or type(ringAnimation.frames) ~= "table" or #ringAnimation.frames == 0 then
				ringAnimation = nil
				ringSpriteSheet = nil
				ringAnimations = {}
				warn("[RSDK] Ring.bin is missing its Normal animation; ring sprites are disabled")
			else
				print(string.format("[RSDK] Ring sprites loaded: %dx%d, normal animation '%s', %d frames",
					ringSpriteSheet.width, ringSpriteSheet.height, ringAnimation.name, #ringAnimation.frames))
				if #ringAnimations < 5 then
					warn(string.format("[RSDK] Ring.bin has %d animations; expected 5 (Normal, Big, Sparkle1-3). Ring pickup sprite animations are unavailable.", #ringAnimations))
				end
			end
		else
			warn("[RSDK] Could not load RingPNGData/RingAnimationData: " .. tostring(loadedSheet))
		end
	else
		warn("[RSDK] Real ring art is not installed. Add RSDK.RingPNGData and RSDK.RingAnimationData ModuleScripts to enable authentic ring sprites.")
	end
end

-- Faithful structure of Sonic Mania's Ring_Collect(): spawn four short-lived
-- sprite entities using Ring.bin animation IDs Sparkle1, Sparkle2 and Sparkle3.
-- The normal ring's 2x spin multiplier is deliberately not applied to these.
function spawnRingPickupAnimation(worldX, worldY)
	if not ringSpriteSheet or #ringAnimations < 5 then
		return
	end

	for i = 0, 3 do
		local animationIndex = 3 + (i % 3) -- Lua index 3..5 = RSDK animation IDs 2..4.
		local animation = ringAnimations[animationIndex]
		if animation and type(animation.frames) == "table" and #animation.frames > 0 then
			local frameCount = #animation.frames
			local additive = animationIndex == 3 -- RING_TYPE_SPARKLE1 has Mania's additive overlay pass.
			if additive then
				frameCount = math.max(1, math.floor(frameCount / 2))
			end
			local firstFrame = animation.frames[1]
			table.insert(ringPickupEffects, {
				x = worldX + math.random(-8, 8),
				y = worldY + math.random(-8, 8),
				animation = animation,
				animationIndex = animationIndex,
				frameID = 0,
				frameTimer = 0,
				frameDuration = math.max(1, tonumber(firstFrame.duration) or 1),
				animationSpeed = math.random(6, 8),
				maxFrameCount = frameCount - 1,
				additive = additive,
				delay = 2 * i,
				visible = false,
			})
		end
	end
end

function requiredAnimation(label, ...)
	local animation = findAnimation(...)
	assert(animation, "[RSDK] Required animation is missing: " .. label)
	return animation
end

local Anim = {
	Idle = requiredAnimation("Idle", "Idle"),
	Bored1 = findAnimation("Bored 1", "Bored1"),
	Bored2 = findAnimation("Bored 2", "Bored2"),
	LookUp = requiredAnimation("Look Up", "Look Up", "LookUp"),
	Crouch = requiredAnimation("Crouch", "Crouch", "Duck"),
	Walk = requiredAnimation("Walk", "Walk"),
	AirWalk = findAnimation("Air Walk", "AirWalk"),
	Jog = requiredAnimation("Jog", "Jog"),
	Run = requiredAnimation("Run", "Run"),
	Dash = findAnimation("Dash"),
	Jump = requiredAnimation("Jump", "Jump"),
	Skid = requiredAnimation("Skid", "Skid"),
	SkidTurn = findAnimation("Skid Turn", "SkidTurn"),
	SpinDash = findAnimation("Spindash", "Spin Dash"),
	DropDash = requiredAnimation("Drop Dash", "DropDash", "Drop Dash"),
	Push = findAnimation("Push", "Pushing"),
}

print("[RSDK] Animation mapping:")
for name, animation in pairs(Anim) do
	print(string.format("[RSDK] %-10s -> %s", name, animation and animation.name or "not present"))
end

--============================================================
-- RSDK ANIMATOR
--============================================================

local animator = {
	animation = nil,
	frameID = 0,
	speed = 0,
	timer = 0,
	frameDuration = 1,
	loopIndex = 0,
}

function setSpriteAnimation(animation, forceApply, frameID)
	if not animation or #animation.frames == 0 then
		return
	end

	if animator.animation == animation and not forceApply then
		return
	end

	local startFrame = math.clamp(math.floor(frameID or 0), 0, #animation.frames - 1)
	animator.animation = animation
	animator.timer = 0
	animator.frameID = startFrame
	animator.frameDuration = math.max(1, animation.frames[startFrame + 1].duration)
	animator.speed = animation.animationSpeed
	animator.loopIndex = animation.loopIndex
end

function processAnimation()
	local animation = animator.animation
	if not animation or #animation.frames == 0 then
		return
	end

	animator.timer += animator.speed
	local iterations = 0

	while animator.timer > animator.frameDuration do
		iterations += 1
		if iterations > 4096 then
			warn("[RSDK] Animation safety limit reached")
			break
		end

		local oldDuration = animator.frameDuration
		if oldDuration <= 0 then
			break
		end

		animator.frameID += 1
		animator.timer -= oldDuration

		if animator.frameID >= #animation.frames then
			animator.frameID = animator.loopIndex
		end

		if animator.frameID < 0 or animator.frameID >= #animation.frames then
			animator.frameID = 0
		end

		animator.frameDuration = math.max(1, animation.frames[animator.frameID + 1].duration)
	end
end

--============================================================
-- GUI AND EDITABLE IMAGES
--============================================================

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("RSDKScreen")
if oldGui then oldGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RSDKScreen"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

function fillImage(image, width, height, color)
	local pixels = buffer.create(width * height * 4)
	local packed = math.round(color.R * 255) + math.round(color.G * 255) * 256
		+ math.round(color.B * 255) * 65536 + 255 * 16777216
	for offset = 0, width * height * 4 - 4, 4 do
		buffer.writeu32(pixels, offset, packed)
	end

	image:WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), pixels)
end

local backgroundLabel = Instance.new("ImageLabel")
backgroundLabel.Name = "Background"
backgroundLabel.Size = UDim2.fromScale(1, 1)
backgroundLabel.Position = UDim2.fromScale(0, 0)
backgroundLabel.BackgroundColor3 = BLACK
backgroundLabel.BorderSizePixel = 0
backgroundLabel.ImageTransparency = 0
backgroundLabel.ScaleType = Enum.ScaleType.Fit
backgroundLabel.ZIndex = 1
backgroundLabel.Parent = screenGui

local backgroundImage = nil

function updateBackground()
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local viewport = camera.ViewportSize
	if viewport.X < 1 or viewport.Y < 1 then return end

	local scale = math.min(1, MAX_IMAGE_SIZE / viewport.X, MAX_IMAGE_SIZE / viewport.Y)
	local width = math.max(1, math.floor(viewport.X * scale))
	local height = math.max(1, math.floor(viewport.Y * scale))

	if backgroundImage and backgroundImage.Size.X == width and backgroundImage.Size.Y == height then
		return
	end

	local success, newImage = pcall(function()
		return AssetService:CreateEditableImage({Size = Vector2.new(width, height)})
	end)

	if not success or not newImage then
		warn("[RSDK] Could not create background EditableImage")
		return
	end

	fillImage(newImage, width, height, BLACK)
	backgroundLabel.ImageContent = Content.fromObject(newImage)

	if backgroundImage then backgroundImage:Destroy() end
	backgroundImage = newImage
end

local canvasImage = AssetService:CreateEditableImage({Size = Vector2.new(WIDTH, HEIGHT)})
if not canvasImage then error("[RSDK] Could not create canvas EditableImage") end
fillImage(canvasImage, WIDTH, HEIGHT, GREEN)

local canvasLabel = Instance.new("ImageLabel")
canvasLabel.Name = "Canvas"
canvasLabel.AnchorPoint = Vector2.new(0.5, 0.5)
canvasLabel.Position = UDim2.fromScale(0.5, 0.5)
canvasLabel.Size = UDim2.fromOffset(WIDTH, HEIGHT)
canvasLabel.BackgroundTransparency = 1
canvasLabel.BorderSizePixel = 0
canvasLabel.ImageTransparency = 0
canvasLabel.ScaleType = Enum.ScaleType.Fit
canvasLabel.ResampleMode = Enum.ResamplerMode.Pixelated
canvasLabel.ImageContent = Content.fromObject(canvasImage)
canvasLabel.ZIndex = 2
canvasLabel.Parent = screenGui
canvasLabel.Visible = false

local canvasScale = Instance.new("UIScale")
canvasScale.Name = "CanvasScale"
canvasScale.Scale = 1
canvasScale.Parent = canvasLabel

--============================================================
-- SONIC MANIA MAIN MENU + STAGE SELECT
--
-- Menu art is loaded from ReplicatedStorage.MENU_ASSETS. The folder may
-- contain nested folders that mirror the original sprites directory.
-- Atlas ModuleScripts return JSON-like text mapping logical sprite names to
-- { File, Rect, Center }. The referenced PNG sheets are separate ModuleScripts
-- whose names omit .png and whose return value is Base64 PNG text, commonly
-- `return [[ ... ]]`. Atlas comments and trailing commas are supported.
--============================================================

local levelButtonRecords = {}
local menuSelectedIndex = 1
local menuStatusText = "SELECT STAGE"
local menuStatusIsError = false
local framePixels -- Forward declaration; allocated with the gameplay buffers below.

local ManiaMenu = {
	screen = "Main", -- Main, StageSelect, Extras, Competition
	selected = 0,
	selectedTimer = 0,
	selectedTimer2 = 0,
	selectedOffset = 0,
	scrollOffset = 0,
	confirmWait = 32,
	frame = 0,
	stageStatus = "SELECT STAGE",
	extraSelected = 1,
	menuAccumulator = 0,
	menuRenderDivider = 0, -- Render the menu canvas at 30 Hz while preview simulation updates at 60 Hz.
	-- Player-two preview state mirrors the Mania menu easter egg. Velocities and
	-- position use the same signed 8.8 fixed-point units as the reference logic.
	previewPlayer = {
		manual = false, hsp = 0, vsp = 0, state = 0, frame = 0, tick = 0,
		dir = 1, y = 0, jumpHeld = false,
	},
	previewMask = nil,
	previewMaskAttempted = false,
	assetFolder = ReplicatedStorage:FindFirstChild("MENU_ASSETS"),
	assetIndex = {},
	assetModules = {},
	assetIndexReady = false,
	spriteDefinitions = {},
	spriteDefinitionsReady = false,
	assetCache = {},
	sheetCache = {},
	assetWarnings = {},
	music = nil,
	compPage = "Browse", -- Browse, Create, Lobby, Results
	compSelected = 1,
	compRooms = {},
	compRoom = nil,
	compResults = nil,
	compNotice = "FIND A ROOM OR CREATE ONE",
	compOptions = {
		mode = "Race",
		stageIndex = 1,
		maxPlayers = 8,
		stocks = 3,
		timeLimit = 3,
	},
	achievementNames = {
		"Attracted to shiny things",
		"Double dose of stars",
		"Old-fashioned life insurance",
		"Going Hyper",
		"Score millionaire",
		"Electrofishing",
		"Longplay",
		"Tidied up the place",
		"Is there an exit up there",
		"Jackpot",
		"Bursting through the jungle",
		"Attracted to giant shiny things",
		"Greedy snowboarder",
		"Once see the sunrise",
		"Fluffy fur must not get wet",
		"Display smasher",
		"Squirrels on a plane",
		"No touchy",
	},
}

local PIXEL_FONT = {
	A={"01110","10001","10001","11111","10001","10001","10001"},
	B={"11110","10001","10001","11110","10001","10001","11110"},
	C={"01111","10000","10000","10000","10000","10000","01111"},
	D={"11110","10001","10001","10001","10001","10001","11110"},
	E={"11111","10000","10000","11110","10000","10000","11111"},
	F={"11111","10000","10000","11110","10000","10000","10000"},
	G={"01111","10000","10000","10111","10001","10001","01111"},
	H={"10001","10001","10001","11111","10001","10001","10001"},
	I={"11111","00100","00100","00100","00100","00100","11111"},
	J={"00111","00010","00010","00010","10010","10010","01100"},
	K={"10001","10010","10100","11000","10100","10010","10001"},
	L={"10000","10000","10000","10000","10000","10000","11111"},
	M={"10001","11011","10101","10101","10001","10001","10001"},
	N={"10001","11001","10101","10011","10001","10001","10001"},
	O={"01110","10001","10001","10001","10001","10001","01110"},
	P={"11110","10001","10001","11110","10000","10000","10000"},
	Q={"01110","10001","10001","10001","10101","10010","01101"},
	R={"11110","10001","10001","11110","10100","10010","10001"},
	S={"01111","10000","10000","01110","00001","00001","11110"},
	T={"11111","00100","00100","00100","00100","00100","00100"},
	U={"10001","10001","10001","10001","10001","10001","01110"},
	V={"10001","10001","10001","10001","10001","01010","00100"},
	W={"10001","10001","10001","10101","10101","10101","01010"},
	X={"10001","10001","01010","00100","01010","10001","10001"},
	Y={"10001","10001","01010","00100","00100","00100","00100"},
	Z={"11111","00001","00010","00100","01000","10000","11111"},
	["0"]={"01110","10001","10011","10101","11001","10001","01110"},
	["1"]={"00100","01100","00100","00100","00100","00100","01110"},
	["2"]={"01110","10001","00001","00010","00100","01000","11111"},
	["3"]={"11110","00001","00001","01110","00001","00001","11110"},
	["4"]={"00010","00110","01010","10010","11111","00010","00010"},
	["5"]={"11111","10000","10000","11110","00001","00001","11110"},
	["6"]={"01110","10000","10000","11110","10001","10001","01110"},
	["7"]={"11111","00001","00010","00100","01000","01000","01000"},
	["8"]={"01110","10001","10001","01110","10001","10001","01110"},
	["9"]={"01110","10001","10001","01111","00001","00001","01110"},
	[" "]={"00000","00000","00000","00000","00000","00000","00000"},
	["_"]={"00000","00000","00000","00000","00000","00000","11111"},
	["-"]={"00000","00000","00000","11111","00000","00000","00000"},
	["."]={"00000","00000","00000","00000","00000","00110","00110"},
	[":"]={"00000","00110","00110","00000","00110","00110","00000"},
	["/"]={"00001","00010","00010","00100","01000","01000","10000"},
	[">"]={"10000","01000","00100","00010","00100","01000","10000"},
	["?"]={"01110","10001","00001","00010","00100","00000","00100"},
	["*"]={"00000","10101","01110","11111","01110","10101","00000"},
	["!"]={"00100","00100","00100","00100","00100","00000","00100"},
	[","]={"00000","00000","00000","00000","00110","00100","01000"},
	["'"]={"00100","00100","01000","00000","00000","00000","00000"},
	["+"]={"00000","00100","00100","11111","00100","00100","00000"},
	["="]={"00000","00000","11111","00000","11111","00000","00000"},
	["#"]={"01010","01010","11111","01010","11111","01010","01010"},
	["@"]={"01110","10001","10111","10101","10111","10000","01110"},
	["("]={"00010","00100","01000","01000","01000","00100","00010"},
	[")"]={"01000","00100","00010","00010","00010","00100","01000"},
}


-- Convert bitmap strings into compact lit-pixel offsets once. Text appears in
-- the HUD every frame; this avoids dozens of substring calls per glyph.
local PIXEL_GLYPH_OFFSETS = {}
for character, rows in pairs(PIXEL_FONT) do
	local points = {}
	for row = 1, 7 do
		local rowBits = rows[row]
		for column = 1, 5 do
			if string.byte(rowBits, column) == 49 then
				table.insert(points, column - 1)
				table.insert(points, row - 1)
			end
		end
	end
	PIXEL_GLYPH_OFFSETS[character] = points
end

function ManiaMenuNormalizeAssetName(name)
	name = tostring(name or "")
	name = name:gsub("\\", "/")
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	name = string.lower(name)

	-- Strip stacked export suffixes too (for example sprite.png.json).
	for _ = 1, 4 do
		local previous = name
		name = name:gsub("%.json$", "")
		name = name:gsub("%.png$", "")
		name = name:gsub("%.lua$", "")
		if name == previous then break end
	end

	-- Some exporters preserve the original top-level sprites directory.
	name = name:gsub("^sprites/", "")
	return name
end

function ManiaMenuGetInstancePath(item, root)
	local parts = {}
	local current = item
	while current and current ~= root do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, "/")
end

function ManiaMenuBuildAssetIndex(force)
	if ManiaMenu.assetIndexReady and not force then return end
	table.clear(ManiaMenu.assetIndex)
	table.clear(ManiaMenu.assetModules)
	ManiaMenu.assetFolder = ReplicatedStorage:FindFirstChild("MENU_ASSETS")
	if not ManiaMenu.assetFolder then
		warn("[MANIA MENU] ReplicatedStorage.MENU_ASSETS is missing; expected atlas JSON ModuleScripts and PNG-data ModuleScripts")
		ManiaMenu.assetIndexReady = true
		return
	end

	local moduleCount = 0
	local duplicateNames = {}
	for _, item in ipairs(ManiaMenu.assetFolder:GetDescendants()) do
		if item:IsA("ModuleScript") then
			moduleCount += 1
			table.insert(ManiaMenu.assetModules, item)
			local key = ManiaMenuNormalizeAssetName(item.Name)
			if key ~= "" then
				if not ManiaMenu.assetIndex[key] then
					ManiaMenu.assetIndex[key] = item
				elseif ManiaMenu.assetIndex[key] ~= item then
					duplicateNames[key] = true
				end
			end

			local relativePath = ManiaMenuNormalizeAssetName(ManiaMenuGetInstancePath(item, ManiaMenu.assetFolder))
			if relativePath ~= "" and not ManiaMenu.assetIndex[relativePath] then
				ManiaMenu.assetIndex[relativePath] = item
			end
		end
	end

	ManiaMenu.assetIndexReady = true
	local duplicates = {}
	for name in pairs(duplicateNames) do table.insert(duplicates, name) end
	table.sort(duplicates)
	print(string.format("[MANIA MENU] Indexed %d ModuleScripts under ReplicatedStorage.MENU_ASSETS", moduleCount))
	if #duplicates > 0 then
		warn("[MANIA MENU] Duplicate ModuleScript basenames (first match is used): " .. table.concat(duplicates, ", "))
	end
	if moduleCount == 0 then
		warn("[MANIA MENU] MENU_ASSETS contains no ModuleScripts. Expected JSON atlas ModuleScripts and PNG sheet ModuleScripts.")
	end
end

local function ManiaMenuInvalidateAssetCatalog()
	ManiaMenu.assetIndexReady = false
	ManiaMenu.spriteDefinitionsReady = false
	table.clear(ManiaMenu.assetCache)
	table.clear(ManiaMenu.sheetCache)
	table.clear(ManiaMenu.spriteDefinitions)
end

if ManiaMenu.assetFolder then
	ManiaMenu.assetFolder.DescendantAdded:Connect(ManiaMenuInvalidateAssetCatalog)
end
ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "MENU_ASSETS" then
		ManiaMenu.assetFolder = child
		ManiaMenuInvalidateAssetCatalog()
		child.DescendantAdded:Connect(ManiaMenuInvalidateAssetCatalog)
	end
end)

local function ManiaMenuIsByteArray(value)
	if type(value) ~= "table" or #value == 0 then return false end
	for index = 1, #value do
		local byteValue = tonumber(value[index])
		if not byteValue or byteValue < 0 or byteValue > 255 or byteValue % 1 ~= 0 then
			return false
		end
	end
	return true
end

local function ManiaMenuByteArrayToBuffer(values)
	assert(ManiaMenuIsByteArray(values), "Expected an array of byte values")
	local result = buffer.create(#values)
	for index, value in ipairs(values) do
		buffer.writeu8(result, index - 1, math.floor(tonumber(value)))
	end
	return result
end

-- The exported atlas files are JSON-like text inside a ModuleScript string.
-- The source format permits // and /* */ comments plus trailing commas, which
-- HttpService.JSONDecode rejects. Strip those extensions without touching
-- comment markers that appear inside quoted strings.
local function ManiaMenuStripJSONComments(source)
	local output = table.create(#source)
	local index = 1
	local inString = false
	local escaped = false
	local lineComment = false
	local blockComment = false
	while index <= #source do
		local char = source:sub(index, index)
		local nextChar = source:sub(index + 1, index + 1)
		if inString then
			table.insert(output, char)
			if escaped then
				escaped = false
			elseif char == "\\" then
				escaped = true
			elseif char == '"' then
				inString = false
			end
			index += 1
		elseif lineComment then
			if char == "\n" then
				lineComment = false
				table.insert(output, char)
			end
			index += 1
		elseif blockComment then
			if char == "*" and nextChar == "/" then
				blockComment = false
				index += 2
			else
				if char == "\n" then table.insert(output, char) end
				index += 1
			end
		else
			if char == '"' then
				inString = true
				table.insert(output, char)
				index += 1
			elseif char == "/" and nextChar == "/" then
				lineComment = true
				index += 2
			elseif char == "/" and nextChar == "*" then
				blockComment = true
				index += 2
			else
				table.insert(output, char)
				index += 1
			end
		end
	end
	return table.concat(output)
end

local function ManiaMenuRemoveTrailingJSONCommas(source)
	local output = table.create(#source)
	local index = 1
	local inString = false
	local escaped = false
	while index <= #source do
		local char = source:sub(index, index)
		if inString then
			table.insert(output, char)
			if escaped then
				escaped = false
			elseif char == "\\" then
				escaped = true
			elseif char == '"' then
				inString = false
			end
			index += 1
		elseif char == '"' then
			inString = true
			table.insert(output, char)
			index += 1
		elseif char == "," then
			local look = index + 1
			while look <= #source and source:sub(look, look):match("%s") do look += 1 end
			local following = source:sub(look, look)
			if following == "}" or following == "]" then
				index += 1
			else
				table.insert(output, char)
				index += 1
			end
		else
			table.insert(output, char)
			index += 1
		end
	end
	return table.concat(output)
end

local function ManiaMenuDecodeJSONText(source)
	if type(source) ~= "string" then return nil, "JSON source is not a string" end
	local trimmed = source:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed:sub(1, 1) ~= "{" and trimmed:sub(1, 1) ~= "[" then
		return nil, "does not begin with a JSON object/array"
	end
	local sanitized = ManiaMenuStripJSONComments(trimmed)
	sanitized = ManiaMenuRemoveTrailingJSONCommas(sanitized)
	local ok, decoded = pcall(function()
		return game:GetService("HttpService"):JSONDecode(sanitized)
	end)
	if not ok then return nil, tostring(decoded) end
	return decoded
end

local function ManiaMenuParseTuple(value)
	if type(value) == "table" then
		local a = tonumber(value[1] or value.x or value.X)
		local b = tonumber(value[2] or value.y or value.Y)
		local c = tonumber(value[3] or value.width or value.Width or value.w)
		local d = tonumber(value[4] or value.height or value.Height or value.h)
		return a, b, c, d
	end
	if type(value) ~= "string" then return nil end
	local numbers = {}
	for part in value:gmatch("[^,]+") do
		table.insert(numbers, tonumber(part:match("^%s*(.-)%s*$")))
	end
	return numbers[1], numbers[2], numbers[3], numbers[4]
end

local function ManiaMenuReadAtlasModule(module)
	local ok, exported = pcall(require, module)
	if not ok then return nil, tostring(exported) end
	if type(exported) == "table" then return exported end
	if type(exported) ~= "string" then return nil, "atlas ModuleScript must return a JSON string or table" end
	return ManiaMenuDecodeJSONText(exported)
end

function ManiaMenuLoadSpriteDefinitions()
	if ManiaMenu.spriteDefinitionsReady then return end
	ManiaMenuBuildAssetIndex(false)
	table.clear(ManiaMenu.spriteDefinitions)
	local totalDefinitions = 0
	local atlasCount = 0
	for _, module in ipairs(ManiaMenu.assetModules) do
		-- PNG sheet ModuleScripts can contain very large Base64 strings. Atlas
		-- descriptors are the .json ModuleScripts (for example test.json), so
		-- inspect those only instead of requiring every image up front.
		if module.Name:lower():match("%.json$") then
			local exported, parseError = ManiaMenuReadAtlasModule(module)
			if type(exported) == "table" then
				local rows = exported.Sprites or exported.sprites or exported
				local countInAtlas = 0
				for spriteName, metadata in pairs(rows) do
					if type(spriteName) == "string" and type(metadata) == "table" then
						local fileName = metadata.File or metadata.file or metadata.Image or metadata.image
						if type(fileName) == "string" and fileName ~= "" then
							local key = ManiaMenuNormalizeAssetName(spriteName)
							if key ~= "" and not ManiaMenu.spriteDefinitions[key] then
								local rx, ry, rw, rh = ManiaMenuParseTuple(metadata.Rect or metadata.rect)
								local cx, cy = ManiaMenuParseTuple(metadata.Center or metadata.center)
								ManiaMenu.spriteDefinitions[key] = {
									name = spriteName,
									file = fileName,
									rectX = rx, rectY = ry, rectW = rw, rectH = rh,
									pivotX = cx, pivotY = cy,
									atlasModule = module,
								}
								countInAtlas += 1
							end
						end
					end
				end
				if countInAtlas > 0 then
					atlasCount += 1
					totalDefinitions += countInAtlas
					print(string.format("[MANIA MENU] Read %d sprite entries from atlas '%s' (%s)",
						countInAtlas, module.Name, ManiaMenuGetInstancePath(module, ManiaMenu.assetFolder)))
				end
			elseif parseError then
				if not ManiaMenu.assetWarnings["atlas:" .. module:GetFullName()] then
					ManiaMenu.assetWarnings["atlas:" .. module:GetFullName()] = true
					warn("[MANIA MENU] Could not parse atlas ModuleScript '" .. ManiaMenuGetInstancePath(module, ManiaMenu.assetFolder)
						.. "': " .. tostring(parseError))
				end
			end
		end
	end
	ManiaMenu.spriteDefinitionsReady = true
	print(string.format("[MANIA MENU] Loaded %d sprite definitions from %d atlas ModuleScript(s)", totalDefinitions, atlasCount))
	if totalDefinitions == 0 then
		warn("[MANIA MENU] No atlas definitions found. Expected a ModuleScript returning entries like [\"mania_menu_header\"] = { File = \"misc ui.png\", Rect = \"1,14,214,40\" }.")
	end
end

local function ManiaMenuResolveImageModule(fileName, atlasModule)
	ManiaMenuBuildAssetIndex(false)
	local rawPath = tostring(fileName or ""):gsub("\\", "/")
	local normalizedPath = ManiaMenuNormalizeAssetName(rawPath)
	local basename = normalizedPath:match("([^/]+)$") or normalizedPath

	-- Prefer the referenced PNG next to the atlas ModuleScript, then try its
	-- explicit relative path, and finally search all nested folders by basename.
	if atlasModule then
		local parent = atlasModule.Parent
		if parent then
			local sibling = parent:FindFirstChild(basename)
			if sibling and sibling:IsA("ModuleScript") then return sibling end
			local siblingWithPNG = parent:FindFirstChild(basename .. ".png")
			if siblingWithPNG and siblingWithPNG:IsA("ModuleScript") then return siblingWithPNG end
			local parentPath = ManiaMenuGetInstancePath(parent, ManiaMenu.assetFolder)
			if parentPath ~= "" then
				local combined = ManiaMenuNormalizeAssetName(parentPath .. "/" .. rawPath)
				if ManiaMenu.assetIndex[combined] then return ManiaMenu.assetIndex[combined] end
			end
		end
	end
	if ManiaMenu.assetIndex[normalizedPath] then return ManiaMenu.assetIndex[normalizedPath] end
	if ManiaMenu.assetIndex[basename] then return ManiaMenu.assetIndex[basename] end
	return nil
end

local function ManiaMenuDecodeImageModule(module, label)
	local cacheKey = ManiaMenuGetInstancePath(module, ManiaMenu.assetFolder)
	if ManiaMenu.sheetCache[cacheKey] ~= nil then
		return ManiaMenu.sheetCache[cacheKey] or nil
	end

	local ok, decodedOrError = pcall(function()
		local exported = require(module)
		local imageBuffer = nil
		local directImage = nil

		if typeof(exported) == "buffer" then
			imageBuffer = exported
		elseif type(exported) == "table" then
			if ManiaMenuIsByteArray(exported) then
				imageBuffer = ManiaMenuByteArrayToBuffer(exported)
			else
				local width = tonumber(exported.Width or exported.width or exported.w)
				local height = tonumber(exported.Height or exported.height or exported.h)
				local pixels = exported.Pixels or exported.pixels or exported.RGBA or exported.rgba
				if width and height and type(pixels) == "table" and ManiaMenuIsByteArray(pixels) then
					directImage = {
						width = math.floor(width), height = math.floor(height),
						pixels = ManiaMenuByteArrayToBuffer(pixels),
					}
				else
					local encoding = tostring(exported.Encoding or exported.encoding or "base64"):lower()
					local payload = exported.Data or exported.data or exported.Base64 or exported.base64
						or exported.PNG or exported.png or exported.ImageData or exported.Image
						or exported.Bytes or exported.bytes or exported.Value or exported.value or exported[1]
					assert(payload ~= nil, "PNG ModuleScript table needs Data/Bytes or Width/Height/Pixels")
					if type(payload) == "table" then
						imageBuffer = ManiaMenuByteArrayToBuffer(payload)
					elseif typeof(payload) == "buffer" then
						imageBuffer = payload
					else
						assert(type(payload) == "string", "PNG data must be Base64 text, bytes, or a buffer")
						payload = payload:gsub("^%s+", ""):gsub("%s+$", "")
						if payload:sub(1, 8) == "\137PNG\r\n\026\n" then
							imageBuffer = buffer.fromstring(payload)
						else
							imageBuffer = decodeAssetBuffer({Encoding = encoding, Data = payload})
						end
					end
				end
			end
		elseif type(exported) == "string" then
			local payload = exported:gsub("^%s+", ""):gsub("%s+$", "")
			if payload:sub(1, 8) == "\137PNG\r\n\026\n" then
				imageBuffer = buffer.fromstring(payload)
			else
				-- Image ModuleScripts use return [[BASE64_PNG_DATA]].
				imageBuffer = decodeAssetBuffer({Encoding = "base64", Data = payload})
			end
		else
			error("Unsupported PNG ModuleScript return type: " .. typeof(exported))
		end

		if directImage then
			assert(directImage.width > 0 and directImage.height > 0, "Direct image dimensions are invalid")
			assert(buffer.len(directImage.pixels) >= directImage.width * directImage.height * 4, "Direct RGBA pixels are too short")
			return directImage
		end
		assert(imageBuffer and buffer.len(imageBuffer) > 0, "PNG data is empty")
		local decoded = PNG.decode(imageBuffer)
		assert(type(decoded) == "table" and decoded.width and decoded.height and decoded.pixels,
			"PNG.decode did not return width/height/pixels")
		assert(decoded.width > 0 and decoded.height > 0, "PNG has invalid dimensions")
		assert(buffer.len(decoded.pixels) >= decoded.width * decoded.height * 4,
			"PNG pixel buffer is too small")
		return decoded
	end)

	if not ok then
		ManiaMenu.sheetCache[cacheKey] = false
		local warningKey = "sheet-decode:" .. cacheKey
		if not ManiaMenu.assetWarnings[warningKey] then
			ManiaMenu.assetWarnings[warningKey] = true
			warn("[MANIA MENU] Could not load PNG sheet '" .. tostring(label) .. "' from ModuleScript '"
				.. cacheKey .. "': " .. tostring(decodedOrError))
		end
		return nil
	end
	ManiaMenu.sheetCache[cacheKey] = decodedOrError
	print(string.format("[MANIA MENU] Loaded PNG sheet '%s' (%dx%d) from %s",
		tostring(label), decodedOrError.width, decodedOrError.height, cacheKey))
	return decodedOrError
end

local function ManiaMenuCropSprite(sheet, definition)
	local x, y, width, height = definition.rectX, definition.rectY, definition.rectW, definition.rectH
	if x == nil and y == nil and width == nil and height == nil then
		x, y, width, height = 0, 0, sheet.width, sheet.height
	end
	x, y = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0)
	width, height = math.floor(tonumber(width) or 0), math.floor(tonumber(height) or 0)
	assert(width > 0 and height > 0, "Sprite Rect must contain x,y,width,height")
	assert(x >= 0 and y >= 0 and x + width <= sheet.width and y + height <= sheet.height,
		string.format("Sprite Rect %d,%d,%d,%d is outside sheet %dx%d", x, y, width, height, sheet.width, sheet.height))

	local croppedPixels = buffer.create(width * height * 4)
	for row = 0, height - 1 do
		buffer.copy(croppedPixels, row * width * 4, sheet.pixels, ((y + row) * sheet.width + x) * 4, width * 4)
	end
	return {
		width = width,
		height = height,
		pixels = croppedPixels,
		pivotX = definition.pivotX,
		pivotY = definition.pivotY,
	}
end

function ManiaMenuGetSprite(name)
	local key = ManiaMenuNormalizeAssetName(name)
	if ManiaMenu.assetCache[key] ~= nil then
		return ManiaMenu.assetCache[key] or nil
	end

	ManiaMenuLoadSpriteDefinitions()
	local definition = ManiaMenu.spriteDefinitions[key]
	if definition then
		local sheetModule = ManiaMenuResolveImageModule(definition.file, definition.atlasModule)
		if not sheetModule then
			ManiaMenu.assetCache[key] = false
			local warningKey = "sheet-missing:" .. key
			if not ManiaMenu.assetWarnings[warningKey] then
				ManiaMenu.assetWarnings[warningKey] = true
				warn(string.format("[MANIA MENU] Atlas entry '%s' references '%s', but no PNG ModuleScript named '%s' was found. The image ModuleScript name should omit .png.",
					definition.name, definition.file, ManiaMenuNormalizeAssetName(definition.file)))
			end
			return nil
		end

		local sheet = ManiaMenuDecodeImageModule(sheetModule, definition.file)
		if not sheet then
			ManiaMenu.assetCache[key] = false
			return nil
		end
		local okCrop, cropped = pcall(ManiaMenuCropSprite, sheet, definition)
		if not okCrop then
			ManiaMenu.assetCache[key] = false
			local warningKey = "crop:" .. key
			if not ManiaMenu.assetWarnings[warningKey] then
				ManiaMenu.assetWarnings[warningKey] = true
				warn("[MANIA MENU] Could not crop sprite '" .. definition.name .. "' from '" .. definition.file .. "': " .. tostring(cropped))
			end
			return nil
		end
		ManiaMenu.assetCache[key] = cropped
		return cropped
	end

	-- Backward compatibility: if no atlas map is supplied, an individual
	-- ModuleScript named after the sprite can still hold one complete PNG.
	local directModule = ManiaMenu.assetIndex[key]
	if directModule then
		local directImage = ManiaMenuDecodeImageModule(directModule, name)
		ManiaMenu.assetCache[key] = directImage or false
		return directImage
	end

	ManiaMenu.assetCache[key] = false
	if not ManiaMenu.assetWarnings["definition-missing:" .. key] then
		ManiaMenu.assetWarnings["definition-missing:" .. key] = true
		warn(string.format("[MANIA MENU] Sprite '%s' has no entry in the imported atlas JSON. Check that the atlas ModuleScript is under MENU_ASSETS and contains this sprite key.", tostring(name)))
	end
	return nil
end

-- The preview border PNG is a hollow, irregular frame. Find its largest enclosed
-- transparent component once, then use it as a per-pixel stencil for every demo
-- layer. This clips scenery to the actual opening instead of a guessed rectangle.
function ManiaMenuBuildPreviewMask()
	if ManiaMenu.previewMaskAttempted then return ManiaMenu.previewMask end
	ManiaMenu.previewMaskAttempted = true

	local border = ManiaMenuGetSprite("mania_menu_previewborder")
	if not border or not border.pixels then
		warn("[MANIA MENU] Cannot build preview-window mask: mania_menu_previewborder did not load")
		return nil
	end

	local width, height = border.width, border.height
	local total = width * height
	if width < 16 or height < 16 or total > 4_000_000 then
		warn(string.format("[MANIA MENU] Preview border dimensions are not usable for masking: %dx%d", width, height))
		return nil
	end

	local pixels = border.pixels
	local visited = buffer.create(total)
	local readu8 = buffer.readu8
	local bestQueue = nil
	local bestCount = 0
	local bestBounds = nil

	local function isTransparent(index)
		return readu8(pixels, index * 4 + 3) <= 8
	end

	for startIndex = 0, total - 1 do
		if readu8(visited, startIndex) == 0 and isTransparent(startIndex) then
			local queue = table.create(256)
			queue[1] = startIndex
			buffer.writeu8(visited, startIndex, 1)
			local head = 1
			local touchesEdge = false
			local minX, minY = width, height
			local maxX, maxY = -1, -1

			while head <= #queue do
				local index = queue[head]
				head += 1
				local x = index % width
				local y = math.floor(index / width)
				if x == 0 or y == 0 or x == width - 1 or y == height - 1 then
					touchesEdge = true
				end
				if x < minX then minX = x end
				if y < minY then minY = y end
				if x > maxX then maxX = x end
				if y > maxY then maxY = y end

				local function addNeighbor(neighbor)
					if readu8(visited, neighbor) == 0 and isTransparent(neighbor) then
						buffer.writeu8(visited, neighbor, 1)
						queue[#queue + 1] = neighbor
					end
				end
				if x > 0 then addNeighbor(index - 1) end
				if x + 1 < width then addNeighbor(index + 1) end
				if y > 0 then addNeighbor(index - width) end
				if y + 1 < height then addNeighbor(index + width) end
			end

			local componentCount = #queue
			local boundsWidth = maxX - minX + 1
			local boundsHeight = maxY - minY + 1
			-- Ignore the exterior transparent background. The real preview aperture
			-- is a large transparent area enclosed by the opaque outline.
			if not touchesEdge and componentCount > bestCount
				and boundsWidth >= 48 and boundsHeight >= 48 then
				bestCount = componentCount
				bestQueue = queue
				bestBounds = {minX, minY, maxX, maxY}
			end
		end
	end

	if not bestQueue then
		warn("[MANIA MENU] Preview border has no enclosed transparent aperture; using its conservative inner rectangle")
		local left, top = 2, 2
		local right, bottom = math.min(width - 3, 298), math.min(height - 3, 156)
		if right <= left or bottom <= top then return nil end
		local maskPixels = buffer.create(total)
		for y = top, bottom do
			for x = left, right do
				buffer.writeu8(maskPixels, y * width + x, 1)
			end
		end
		ManiaMenu.previewMask = {
			width = width, height = height, pixels = maskPixels,
			originX = 0, originY = 64,
			minX = left, minY = top, maxX = right, maxY = bottom,
		}
		return ManiaMenu.previewMask
	end

	local maskPixels = buffer.create(total)
	for _, index in ipairs(bestQueue) do
		buffer.writeu8(maskPixels, index, 1)
	end
	ManiaMenu.previewMask = {
		width = width, height = height, pixels = maskPixels,
		originX = 0, originY = 64,
		minX = bestBounds[1], minY = bestBounds[2],
		maxX = bestBounds[3], maxY = bestBounds[4],
	}
	print(string.format("[MANIA MENU] Preview aperture mask: %dx%d at (%d,%d), %d transparent pixels",
		bestBounds[3] - bestBounds[1] + 1, bestBounds[4] - bestBounds[2] + 1,
		bestBounds[1], bestBounds[2], bestCount))
	return ManiaMenu.previewMask
end

function ManiaMenuGetPreviewWindowClip()
	local mask = ManiaMenuBuildPreviewMask()
	if not mask then
		return {left = 2, top = 66, right = 298, bottom = 220}
	end
	return {
		left = mask.originX + mask.minX,
		top = mask.originY + mask.minY,
		right = mask.originX + mask.maxX,
		bottom = mask.originY + mask.maxY,
		mask = mask,
	}
end

function ManiaMenuClipAllowsPixel(clip, x, y)
	if not clip or not clip.mask then return true end
	local mask = clip.mask
	local mx = x - mask.originX
	local my = y - mask.originY
	if mx < 0 or my < 0 or mx >= mask.width or my >= mask.height then return false end
	return buffer.readu8(mask.pixels, my * mask.width + mx) ~= 0
end

function ManiaMenuDrawRect(x, y, width, height, rgba, clip)
	if not framePixels or width <= 0 or height <= 0 then return end
	local left = math.max(0, math.floor(x), clip and clip.left or 0)
	local top = math.max(0, math.floor(y), clip and clip.top or 0)
	local right = math.min(WIDTH, math.ceil(x + width), clip and (clip.right + 1) or WIDTH)
	local bottom = math.min(HEIGHT, math.ceil(y + height), clip and (clip.bottom + 1) or HEIGHT)
	if left >= right or top >= bottom then return end
	local red = math.clamp(math.floor(tonumber(rgba[1]) or 0), 0, 255)
	local green = math.clamp(math.floor(tonumber(rgba[2]) or 0), 0, 255)
	local blue = math.clamp(math.floor(tonumber(rgba[3]) or 0), 0, 255)
	local alpha = math.clamp(math.floor(tonumber(rgba[4]) or 255), 0, 255)
	if alpha >= 255 and not (clip and clip.mask) then
		OPT.drawFrameRect(left, top, right - left, bottom - top, {red, green, blue, 255})
		return
	end
	if alpha <= 0 then return end
	local inverse = 255 - alpha
	local writeu32, readu8 = buffer.writeu32, buffer.readu8
	local mask = clip and clip.mask
	for py = top, bottom - 1 do
		local offset = (py * WIDTH + left) * 4
		local maskRow = mask and ((py - mask.originY) * mask.width - mask.originX) or nil
		for px = left, right - 1 do
			if not mask or readu8(mask.pixels, maskRow + px) ~= 0 then
				if alpha >= 255 then
					writeu32(framePixels, offset, red + green * 256 + blue * 65536 + 0xFF000000)
				else
					local outR = math.floor((red * alpha + readu8(framePixels, offset) * inverse) / 255 + 0.5)
					local outG = math.floor((green * alpha + readu8(framePixels, offset + 1) * inverse) / 255 + 0.5)
					local outB = math.floor((blue * alpha + readu8(framePixels, offset + 2) * inverse) / 255 + 0.5)
					writeu32(framePixels, offset, outR + outG * 256 + outB * 65536 + 0xFF000000)
				end
			end
			offset += 4
		end
	end
end

function ManiaMenuDrawSprite(name, x, y, scale, tint, opacity, clip, anchorTopLeft, flipX, pivotXOverride, pivotYOverride)
	local sprite = ManiaMenuGetSprite(name)
	if not sprite or not framePixels then return false end

	scale = math.max(0.05, tonumber(scale) or 1)
	opacity = math.clamp(tonumber(opacity) or 1, 0, 1)
	local width, height = sprite.width, sprite.height
	local pivotX = pivotXOverride
	if pivotX == nil then pivotX = sprite.pivotX or (anchorTopLeft and 0 or width / 2) end
	local pivotY = pivotYOverride
	if pivotY == nil then pivotY = sprite.pivotY or (anchorTopLeft and 0 or height / 2) end
	local left = math.floor(x - pivotX * scale + 0.5)
	local top = math.floor(y - pivotY * scale + 0.5)
	local drawWidth = math.max(1, math.floor(width * scale + 0.5))
	local drawHeight = math.max(1, math.floor(height * scale + 0.5))
	local x0 = math.max(0, left, clip and clip.left or 0)
	local y0 = math.max(0, top, clip and clip.top or 0)
	local x1 = math.min(WIDTH - 1, left + drawWidth - 1, clip and clip.right or (WIDTH - 1))
	local y1 = math.min(HEIGHT - 1, top + drawHeight - 1, clip and clip.bottom or (HEIGHT - 1))
	if x0 > x1 or y0 > y1 then return true end

	local tintR, tintG, tintB = 255, 255, 255
	if tint then
		tintR, tintG, tintB = tonumber(tint[1]) or 255, tonumber(tint[2]) or 255, tonumber(tint[3]) or 255
		if tintR <= 1 then tintR *= 255 end
		if tintG <= 1 then tintG *= 255 end
		if tintB <= 1 then tintB *= 255 end
		tintR, tintG, tintB = math.clamp(tintR, 0, 255), math.clamp(tintG, 0, 255), math.clamp(tintB, 0, 255)
	end

	local sourcePixels = sprite.pixels
	local readu8, writeu32 = buffer.readu8, buffer.writeu32
	local mask = clip and clip.mask
	for destY = y0, y1 do
		local sourceY = math.floor((destY - top + 0.5) / scale)
		if sourceY >= 0 and sourceY < height then
			local sourceX = math.floor((x0 - left + 0.5) / scale)
			local destOffset = (destY * WIDTH + x0) * 4
			local maskRow = mask and ((destY - mask.originY) * mask.width - mask.originX) or nil
			for destX = x0, x1 do
				local sourceColumn = math.floor(sourceX)
				local srcX = flipX and (width - 1 - sourceColumn) or sourceColumn
				if srcX >= 0 and srcX < width and (not mask or readu8(mask.pixels, maskRow + destX) ~= 0) then
					local sourceOffset = (sourceY * width + srcX) * 4
					local sr = readu8(sourcePixels, sourceOffset)
					local sg = readu8(sourcePixels, sourceOffset + 1)
					local sb = readu8(sourcePixels, sourceOffset + 2)
					local sa = readu8(sourcePixels, sourceOffset + 3)
					if sa > 0 then
						sr = math.floor(sr * tintR / 255 + 0.5)
						sg = math.floor(sg * tintG / 255 + 0.5)
						sb = math.floor(sb * tintB / 255 + 0.5)
						local alpha = math.floor(sa * opacity + 0.5)
						if alpha >= 255 then
							writeu32(framePixels, destOffset, sr + sg * 256 + sb * 65536 + 0xFF000000)
						elseif alpha > 0 then
							local inv = 255 - alpha
							local dr = readu8(framePixels, destOffset)
							local dg = readu8(framePixels, destOffset + 1)
							local db = readu8(framePixels, destOffset + 2)
							local outR = math.floor((sr * alpha + dr * inv) / 255 + 0.5)
							local outG = math.floor((sg * alpha + dg * inv) / 255 + 0.5)
							local outB = math.floor((sb * alpha + db * inv) / 255 + 0.5)
							writeu32(framePixels, destOffset, outR + outG * 256 + outB * 65536 + 0xFF000000)
						end
					end
				end
				sourceX += 1 / scale
				destOffset += 4
			end
		end
	end
	return true
end

function ManiaMenuDrawNamedSprite(name, x, y, scale, tint, opacity, clip, flipX)
	local normalized = ManiaMenuNormalizeAssetName(name)
	local topLeft = normalized == "mania_menu_previewborder"
		or normalized == "mania_menu_previewfg_mania"
		or normalized:match("^mania_menu_previewbg_mania_%d+$") ~= nil
		or normalized:match("^mania_menu_preview_transition_%d+$") ~= nil
		or normalized:match("^mania_menu_transition_%d+$") ~= nil
	if normalized:match("^mania_menu_previewbg_competition_%d+$") then
		local frameNumber = tonumber(normalized:match("(%d+)$")) or 0
		topLeft = frameNumber <= 17 or frameNumber >= 24
	elseif normalized:match("^mania_menu_previewbg_extras_%d+$") then
		topLeft = true
	end
	-- The button's source x coordinate is its left edge: the button is about
	-- 200px wide and its label is centred at x + 101. Keep the normal centred
	-- Y pivot; only override X to zero. A full top-left pivot would also move
	-- the button vertically, which the source does not request.
	if normalized == "mania_menu_button" then
		return ManiaMenuDrawSprite(name, x, y, scale, tint, opacity, clip, false, flipX, 0, nil)
	end
	return ManiaMenuDrawSprite(name, x, y, scale, tint, opacity, clip, topLeft, flipX)
end

-- Return the visible alpha-bounds center of a sprite relative to its draw pivot.
-- This lets menu labels align by their actual visible pixels instead of guessing
-- a fixed Y offset from the sprite origin.
function ManiaMenuGetSpriteVisibleCenterOffsetY(sprite)
	if not sprite then return 0 end
	if sprite.visibleCenterOffsetY ~= nil then
		return sprite.visibleCenterOffsetY
	end

	local minY = sprite.height
	local maxY = -1
	for y = 0, sprite.height - 1 do
		local rowOffset = y * sprite.width * 4
		for x = 0, sprite.width - 1 do
			if buffer.readu8(sprite.pixels, rowOffset + x * 4 + 3) > 0 then
				minY = math.min(minY, y)
				maxY = math.max(maxY, y)
				break
			end
		end
	end

	local visibleCenterY
	if maxY >= minY then
		visibleCenterY = (minY + maxY + 1) * 0.5
	else
		visibleCenterY = sprite.height * 0.5
	end
	local pivotY = tonumber(sprite.pivotY) or (sprite.height * 0.5)
	sprite.visibleCenterOffsetY = visibleCenterY - pivotY
	return sprite.visibleCenterOffsetY
end

function ManiaMenuClearFrame(color)
	if not framePixels then return end
	OPT.drawFrameRect(0, 0, WIDTH, HEIGHT, color or {0, 0, 0, 255})
end

MENU_SOUND_IDS = {
	mania_menu = "94745738647742",
	mania_menu_confirm = "121590343523926",
	mania_menu_choose = "110217358577339",
	mania_menu_woosh = "115614115425702",
	competition_menu = "126051553565595",
}

function ManiaMenuPlaySound(name, looped)
	local assets = ManiaMenu.assetFolder or ReplicatedStorage:FindFirstChild("MENU_ASSETS")
	local sourceSound = assets and assets:FindFirstChild(name, true)
	local soundId = MENU_SOUND_IDS[name]
	local soundService = game:GetService("SoundService")
	local sound
	if soundId then
		sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. soundId
	elseif sourceSound and sourceSound:IsA("Sound") then
		sound = sourceSound:Clone()
	else
		return
	end

	if looped then
		if ManiaMenu.music and ManiaMenu.music.Parent then
			if ManiaMenu.music.SoundId == sound.SoundId and ManiaMenu.music.IsPlaying then
				sound:Destroy()
				return
			end
			ManiaMenu.music:Stop()
			ManiaMenu.music:Destroy()
		end
		ManiaMenu.music = sound
		sound.Name = "RSDK_MenuMusic"
		sound.Looped = true
		sound.Volume = 0.55
		sound.Parent = soundService
		sound:Play()
	else
		sound.Name = "RSDK_MenuSFX_" .. tostring(name)
		sound.Looped = false
		sound.Volume = 0.7
		sound.Parent = soundService
		sound.Ended:Connect(function()
			if sound.Parent then sound:Destroy() end
		end)
		sound:Play()
	end
end

function ManiaMenuStopMusic()
	if ManiaMenu.music and ManiaMenu.music.Parent then
		ManiaMenu.music:Stop()
		ManiaMenu.music:Destroy()
	end
	ManiaMenu.music = nil
end

function ManiaMenuDrawBackground()
	ManiaMenuDrawRect(0, 0, WIDTH, HEIGHT, {239, 195, 0, 255})
	local frame = ManiaMenu.frame
	local scale = math.sin(frame / 64) / 2 + 1
	ManiaMenuDrawNamedSprite("mania_menu_bg_circles_0", WIDTH / 2, HEIGHT / 2, scale,
		{247, 142, 24}, 1)
	ManiaMenuDrawNamedSprite("mania_menu_bg_circles_3",
		(WIDTH / 2) - math.floor(math.cos(frame * (0.6 / (85.5 * 0.5))) * (scale * 96)) - 4,
		(HEIGHT / 2) - math.floor(math.sin(frame * (0.6 / (85.5 * 0.5))) * (scale * 92)),
		1, {247, 142, 24}, 1)

	scale = math.sin(frame / 48) / 2.9 + 1.5
	ManiaMenuDrawNamedSprite("mania_menu_bg_circles_0", WIDTH / 2, HEIGHT / 2, scale,
		{132, 162, 181}, 1)
	ManiaMenuDrawNamedSprite("mania_menu_bg_circles_3",
		(WIDTH / 2) - math.floor(math.cos(frame * (1 / (85.5 * 0.5))) * (scale * 96)) - 4,
		(HEIGHT / 2) - math.floor(math.sin(frame * (1 / (85.5 * 0.5))) * (scale * 92)),
		1, {132, 162, 181}, 1)
end

local function ManiaMenuTruncDiv(value, divisor)
	-- The source uses signed integer division, which truncates toward zero.
	local quotient = math.modf(value / divisor)
	return quotient
end

local function ManiaMenuCMod(value, divisor)
	-- The original signed C remainder keeps the sign of its dividend.
	local quotient = ManiaMenuTruncDiv(value, divisor)
	return value - quotient * divisor
end

local function ManiaMenuPreviewSpriteExists(name)
	ManiaMenuLoadSpriteDefinitions()
	local key = ManiaMenuNormalizeAssetName(name)
	return ManiaMenu.spriteDefinitions[key] ~= nil or ManiaMenu.assetIndex[key] ~= nil
end

local function ManiaMenuDrawPreviewSonic(offset, clip)
	local preview = ManiaMenu.previewPlayer
	if not preview.manual then
		local frame = math.floor(ManiaMenu.frame / 6) % 12
		ManiaMenuDrawNamedSprite("mania_menu_previewbg_sonic_" .. tostring(frame),
			96, 144 + offset, 1, nil, 1, clip)
		return
	end

	local speed = math.abs(preview.hsp)
	local animation = 0
	if preview.state == 0 then
		if speed <= 0x1a then animation = 0
		elseif speed >= 0x500 then animation = 3
		elseif speed >= 0x300 then animation = 2
		else animation = 1 end
	elseif preview.state == 1 or preview.state == 2 then
		animation = 4
	elseif preview.state == 3 then
		animation = 5
	elseif preview.state == 4 then
		animation = 6
	end

	local spriteName = string.format("mania_menu_sonic_%d_%d", animation, preview.frame)
	if ManiaMenuPreviewSpriteExists(spriteName) then
		ManiaMenuDrawNamedSprite(spriteName, 96, 144 + offset + math.floor(preview.y / 256),
			1, nil, 1, clip, preview.dir < 0)
	else
		-- The supplied title-menu atlas contains the autonomous 12-frame run,
		-- but not the optional player-two action sheets. Preserve the live
		-- movement/flip while gracefully falling back to the available run cycle.
		local fallbackFrame = math.abs(preview.frame) % 12
		ManiaMenuDrawNamedSprite("mania_menu_previewbg_sonic_" .. tostring(fallbackFrame),
			96, 144 + offset + math.floor(preview.y / 256), 1, nil, 1, clip, preview.dir < 0)
	end
end

function ManiaMenuDrawPreview(menuType, offset, clip)
	local frame = ManiaMenu.frame
	-- smenu_scrolloffset is 8.8 fixed point in the source implementation.
	local scroll = math.floor(ManiaMenu.scrollOffset / 256)

	if menuType == 0 then
		-- Software canvas drawing is painter's order: later sprites cover earlier
		-- ones. Build the preview in explicit depth order:
		-- clouds -> distant scenery -> hills -> bushes -> foreground -> Sonic.
		-- Sonic is deliberately the final scene sprite, above the foreground art.
		local cloud0 = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 3) + ManiaMenuTruncDiv(scroll, 5) + ManiaMenuTruncDiv(scroll, 3), 512)
		local cloud1 = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 3) + ManiaMenuTruncDiv(frame, 4), 512)
		local hill = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 4), 512)
		local bush = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 2), 297)
		for _, x in ipairs({-cloud0, -cloud0 + 512, -cloud0 - 512}) do
			ManiaMenuDrawNamedSprite("mania_menu_previewbg_mania_1", x, 32 + offset, 1, nil, 1, clip)
		end
		for _, x in ipairs({-cloud1, -cloud1 + 512, -cloud1 - 512}) do
			ManiaMenuDrawNamedSprite("mania_menu_previewbg_mania_2", x, 48 + offset, 1, nil, 1, clip)
		end
		for _, x in ipairs({-hill, -hill + 512, -hill - 512}) do
			ManiaMenuDrawNamedSprite("mania_menu_previewbg_mania_3", x, 64 + offset, 1, nil, 1, clip)
		end
		for _, x in ipairs({-bush, -bush + 297, -bush - 297}) do
			ManiaMenuDrawNamedSprite("mania_menu_previewbg_mania_4", x, 109 + offset, 1, nil, 1, clip)
		end

		-- Green Hill's foreground canopy is drawn above the terrain first.
		-- Sonic is intentionally drawn AFTER it so he remains visible over the
		-- foreground, as requested for this Roblox canvas port.
		local foregroundScroll = ManiaMenuCMod(scroll, 1024)
		for _, x in ipairs({-foregroundScroll, -foregroundScroll - 1024, -foregroundScroll + 1024}) do
			ManiaMenuDrawNamedSprite("mania_menu_previewfg_mania", x, -64 + offset, 1, nil, 1, clip)
		end

		-- Apply the translucent scene wash before Sonic, never over his sprite.
		ManiaMenuDrawRect(clip.left, clip.top, clip.right - clip.left + 1,
			clip.bottom - clip.top + 1, {32, 0, 160, 55}, clip)
		ManiaMenuDrawPreviewSonic(offset, clip)

	elseif menuType == 1 then
		-- Competition draw sequence follows the source: character and rings,
		-- centre plate and foreground characters, then the moving scenery strips.
		local cloud0 = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 5) + ManiaMenuTruncDiv(scroll, 5) + ManiaMenuTruncDiv(scroll, 3), 512)
		local cloud1 = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 5) + ManiaMenuTruncDiv(frame, 4), 512)
		local cloud2 = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 4), 512)
		local cloud3 = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 5), 512)
		local cloud4 = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 4), 512)
		local cloud5 = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 3), 512)
		local cloud6 = ManiaMenuCMod(ManiaMenuTruncDiv(scroll, 2), 512)

		ManiaMenuDrawNamedSprite("mania_menu_previewbg_competition_" .. tostring(24 + math.floor(frame / 2) % 4),
			105, 64 + offset + math.floor(math.sin(frame / 25) * 4 + 0.5), 1, nil, 1, clip)
		local ringFrame = math.floor(frame / 4) % 16
		for ring = 0, 2 do
			ManiaMenuDrawNamedSprite("mania_menu_preview_ring_" .. tostring(ringFrame),
				171 + ring * 32, 85 + offset, 1, nil, 1, clip)
		end
		ManiaMenuDrawNamedSprite("mania_menu_previewbg_competition_11", 0, 32 + offset, 1, nil, 1, clip)
		local characterY = math.floor(math.sin(frame / 20) * 12 + 0.5)
		ManiaMenuDrawNamedSprite("mania_menu_previewbg_competition_" .. tostring(12 + math.floor(frame / 2) % 6),
			12, 170 + offset + characterY, 1, nil, 1, clip)
		ManiaMenuDrawNamedSprite("mania_menu_previewbg_competition_" .. tostring(18 + math.floor(frame / 4) % 6),
			44, 170 + offset + characterY, 1, nil, 1, clip)

		for _, x in ipairs({-cloud0, -cloud0 + 512}) do
			ManiaMenuDrawNamedSprite("mania_menu_previewbg_competition_2", x, 32 + offset, 1, nil, 1, clip)
		end
		for _, x in ipairs({-cloud1, -cloud1 + 512}) do
			ManiaMenuDrawNamedSprite("mania_menu_previewbg_competition_3", x, 64 + offset, 1, nil, 1, clip)
		end
		for _, data in ipairs({
			{4, cloud2, 80}, {5, cloud3, 96}, {6, cloud4, 112},
			{7, cloud5, 156}, {8, cloud5, 173}, {9, cloud6, 182},
			}) do
			for _, x in ipairs({-data[2], -data[2] + 512}) do
				ManiaMenuDrawNamedSprite("mania_menu_previewbg_competition_" .. tostring(data[1]),
					x, data[3] + offset, 1, nil, 1, clip)
			end
		end
		ManiaMenuDrawRect(clip.left, clip.top, clip.right - clip.left + 1,
			clip.bottom - clip.top + 1, {8, 96, 240, 45}, clip)

	elseif menuType == 2 then
		local lowerFrame = 29 + math.floor(frame / 3) % 11
		local upperFrame = 1 + math.floor(frame / 3) % 28
		ManiaMenuDrawNamedSprite("mania_menu_previewbg_extras_" .. tostring(lowerFrame),
			59, 128 + offset, 1, nil, 1, clip)
		ManiaMenuDrawNamedSprite("mania_menu_previewbg_extras_" .. tostring(upperFrame),
			65, 60 + offset, 1, nil, 1, clip)
		ManiaMenuDrawNamedSprite("mania_menu_previewbg_extras_0", 0, 32 + offset, 1, nil, 1, clip)
		ManiaMenuDrawRect(clip.left, clip.top, clip.right - clip.left + 1,
			clip.bottom - clip.top + 1, {8, 96, 240, 45}, clip)
	end
end
function ManiaMenuDrawTransition()
	local wait = ManiaMenu.confirmWait
	-- confirmWait == 32 is the idle sentinel used by InitMenu. Only draw
	-- the wipe while its 15..30 animation frames are actively running.
	-- The old `wait >= 15` check treated the idle value 32 as frame 17,
	-- leaving the transition pieces permanently stuck on the menu.
	if wait >= 15 and wait < 31 then
		local frame = wait - 15
		ManiaMenuDrawNamedSprite("mania_menu_transition_0", (56 + WIDTH) - frame * 16,
			(-HEIGHT) + frame * 16, 1)
		ManiaMenuDrawNamedSprite("mania_menu_transition_1", frame * 16,
			HEIGHT - frame * 16, 1)
		ManiaMenuDrawNamedSprite("mania_menu_transition_2", (56 + WIDTH) - frame * 16,
			(-HEIGHT) + frame * 16, 1)
	end
end

function renderManiaMainMenuToCanvas()
	ManiaMenuClearFrame({0, 0, 0, 255})
	ManiaMenuDrawBackground()
	ManiaMenuDrawNamedSprite("mania_menu_previewborder", 0, 64, 1)
	ManiaMenuDrawNamedSprite("mania_menu_header", WIDTH / 2, 16, 1)
	if not ManiaMenuDrawNamedSprite("mania_menu_headertext_mainmenu", WIDTH / 2, 8, 1) then
		OPT.drawFrameText("MAIN MENU", WIDTH / 2 - 27, 9, {255, 255, 255})
	end

	local previewClip = ManiaMenuGetPreviewWindowClip()
	ManiaMenuDrawPreview(ManiaMenu.selected, 32, previewClip)
	if ManiaMenu.selectedTimer < 8 then
		ManiaMenuDrawNamedSprite("mania_menu_preview_transition_" .. tostring(ManiaMenu.selectedTimer % 4),
			0, 64, 1, nil, 1, previewClip)
	end
	ManiaMenuDrawNamedSprite("mania_menu_previewborder", 0, 64, 1)

	-- Match the source renderer's TWO calls to the SAME mania_menu_button
	-- sprite for EVERY menu entry. These are not two different sprite names:
	--   A210: black, offset duplicate (the underlay/selection edge)
	--   A200: pulsing tinted face (the visible button body)
	--	For an unselected item offsetY is exactly zero, so both copies occupy
	--	the same position and the tinted face covers its black underlay. For
	--	the selected item the copies separate by -offsetY/+offsetY, producing
	--	the original Mania selection movement. Never omit either copy for an
	--	item; omitting the face makes an inactive button disappear, while
	--	drawing the underlay after the face puts the selection edge on top.
	local cursor = ManiaMenu.selected
	local scrollX = cursor * 32 + ManiaMenu.selectedOffset
	local scrollY = cursor * 32 + ManiaMenu.selectedOffset
	local buttonCenterOffsetY = ManiaMenuGetSpriteVisibleCenterOffsetY(
		ManiaMenuGetSprite("mania_menu_button"))
	local items = table.create(3)
	for i = 0, 2 do
		local offsetY, offsetY2 = 0, 0
		if i == cursor then
			offsetY = math.floor(math.sin(ManiaMenu.selectedTimer * 0.15) * 3.75 + 0.5)
			offsetY2 = math.floor(math.sin(ManiaMenu.selectedTimer2 * 0.15) * 12.5 + 0.5)
		end
		local baseX = (WIDTH - 200 - i * 32) + scrollX
		local baseY = ((HEIGHT - 72) + i * 32) - scrollY
		local textSprite = ManiaMenuGetSprite("mania_menu_buttontext_" .. tostring(i))
		local textCenterOffsetY = ManiaMenuGetSpriteVisibleCenterOffsetY(textSprite)
		items[i + 1] = {
			shadowX = baseX - offsetY,
			shadowY = baseY - offsetY,
			faceX = baseX + offsetY,
			faceY = baseY + offsetY,
			textX = baseX - offsetY + 101,
			-- Center the visible label pixels on the visible pixels of the
			-- top (black selection) button layer, accounting for each atlas pivot.
			textY = baseY - offsetY + buttonCenterOffsetY - textCenterOffsetY,
			-- Keep the fallback font at its original source position if no label
			-- sprite exists in the imported atlas.
			fallbackTextY = baseY - offsetY2 - 4,
		}
	end

	local pulse = math.sin(ManiaMenu.frame / 9) / 2 + 0.5
	local tint = {
		math.floor(240 + (232 - 240) * pulse + 0.5),
		math.floor(240 + (40 - 240) * pulse + 0.5),
		math.floor(240 + (88 - 240) * pulse + 0.5),
	}

	-- Flip only the two button layers. The tinted button is drawn first,
	-- then the black selection copy is drawn over it. Keep every original
	-- position, selected offset, and text offset exactly as supplied.
	for i = 0, 2 do
		local item = items[i + 1]
		ManiaMenuDrawNamedSprite("mania_menu_button", item.faceX, item.faceY,
			1, tint, 1)
	end

	for i = 0, 2 do
		local item = items[i + 1]
		ManiaMenuDrawNamedSprite("mania_menu_button", item.shadowX, item.shadowY,
			1, {0, 0, 0}, 1)
	end
	-- Pass A600: text sits above both button passes. Preserve the source's
	-- per-index blink condition and exact x/y offsets.
	for i = 0, 2 do
		local item = items[i + 1]
		if ((ManiaMenu.confirmWait % 4 < 2 and i == cursor)
			or i ~= cursor or ManiaMenu.confirmWait > 31) then
			local textName = "mania_menu_buttontext_" .. tostring(i)
			if not ManiaMenuDrawNamedSprite(textName, item.textX, item.textY, 1) then
				local labels = {"MANIA MODE", "COMPETITION", "EXTRAS"}
				OPT.drawFrameText(labels[i + 1], item.textX - 53, item.fallbackTextY, {255, 255, 255}, 22)
			end
		end
	end
	-- The transition overlay is intentionally last in the software painter,
	-- matching its highest-priority full-screen plane in the original renderer.
	ManiaMenuDrawTransition()
	canvasImage:WritePixelsBuffer(CANVAS_ORIGIN, CANVAS_SIZE, framePixels)
	canvasLabel.Visible = true
end
function renderManiaStageSelectToCanvas()
	ManiaMenuClearFrame({0, 0, 0, 255})
	ManiaMenuDrawBackground()
	ManiaMenuDrawNamedSprite("mania_menu_header", WIDTH / 2, 16, 1)
	OPT.drawFrameText("MANIA MODE - SELECT STAGE", 104, 9, {255, 255, 255}, 34)
	ManiaMenuDrawRect(10, 40, 202, 178, {0, 12, 48, 235})
	ManiaMenuDrawRect(10, 40, 202, 2, {248, 196, 48, 255})
	ManiaMenuDrawRect(10, 216, 202, 2, {248, 196, 48, 255})
	OPT.drawFrameText(string.format("AVAILABLE STAGES: %03d", #levelButtonRecords), 18, 48, {184, 208, 240}, 30)
	ManiaMenuDrawRect(18, 58, 186, 1, {80, 128, 208, 255})

	local visibleRows = 12
	local maxStart = math.max(1, #levelButtonRecords - visibleRows + 1)
	local firstIndex = math.clamp(menuSelectedIndex - math.floor(visibleRows / 2), 1, maxStart)
	for row = 0, visibleRows - 1 do
		local index = firstIndex + row
		local record = levelButtonRecords[index]
		if record then
			local y = 64 + row * 10
			if index == menuSelectedIndex then
				ManiaMenuDrawRect(15, y - 1, 192, 9, {24, 56, 112, 255})
				OPT.drawFrameText(">", 19, y, {255, 224, 72})
				OPT.drawFrameText(record.DisplayName or record.Key, 30, y, {255, 224, 72}, 28)
			else
				OPT.drawFrameText(record.DisplayName or record.Key, 30, y, {232, 232, 232}, 28)
			end
		end
	end

	ManiaMenuDrawRect(18, 207, 186, 1, {80, 128, 208, 255})
	local statusColor = menuStatusIsError and {255, 104, 104} or {184, 208, 240}
	OPT.drawFrameText(menuStatusText, 18, 194, statusColor, 30)
	OPT.drawFrameText("UP/DOWN MOVE   ENTER PLAY", 18, 222, {255, 255, 255}, 31)
	OPT.drawFrameText("X BACK", 330, 222, {255, 224, 72}, 10)

	-- A quiet preview panel uses the same parallax art as the title screen.
	local clip = {left = 222, top = 40, right = 413, bottom = 217}
	ManiaMenuDrawRect(clip.left, clip.top, clip.right - clip.left + 1,
		clip.bottom - clip.top + 1, {0, 20, 56, 210}, clip)
	ManiaMenuDrawPreview(0, 0, clip)
	ManiaMenuDrawNamedSprite("mania_menu_previewborder", 222, 40, 0.9, nil, 1, clip)
	ManiaMenuDrawTransition()
	canvasImage:WritePixelsBuffer(CANVAS_ORIGIN, CANVAS_SIZE, framePixels)
	canvasLabel.Visible = true
end

function renderManiaExtrasToCanvas()
	ManiaMenuClearFrame({0, 0, 0, 255})
	ManiaMenuDrawBackground()
	ManiaMenuDrawNamedSprite("mania_menu_header", WIDTH / 2, 16, 1)
	if not ManiaMenuDrawNamedSprite("mania_menu_headertext_extras", WIDTH / 2, 8, 1) then
		OPT.drawFrameText("EXTRAS", WIDTH / 2 - 18, 9, {255, 255, 255}, 12)
	end

	local cursor = math.max(0, ManiaMenu.extraSelected - 1)
	local scroll = cursor * 48 + ManiaMenu.selectedOffset
	local pulse = math.sin(ManiaMenu.frame / 9) / 2 + 0.5
	local tint = {
		math.floor(240 + (232 - 240) * pulse + 0.5),
		math.floor(240 + (40 - 240) * pulse + 0.5),
		math.floor(240 + (88 - 240) * pulse + 0.5),
	}

	for i = 0, #ManiaMenu.achievementNames - 1 do
		local offsetY, offsetY2 = 0, 0
		if i == cursor then
			offsetY = math.floor(math.sin(ManiaMenu.selectedTimer * 0.15) * 3.75 + 0.5)
			offsetY2 = math.floor(math.sin(ManiaMenu.selectedTimer2 * 0.15) * 12.5 + 0.5)
		end
		local x = math.floor(WIDTH / 3) - offsetY
		local baseY = (HEIGHT - 72) + i * 48 - scroll
		local iconY = baseY - offsetY2 - 16
		if iconY > -56 and iconY < HEIGHT + 40 then
			-- Achievement art is not in the supplied menu atlas, so retain the
			-- original thumbnail/button geometry with an unintrusive blank tile.
			ManiaMenuDrawRect(x - 82, iconY, 68, 52, {0, 0, 0, 255})
			ManiaMenuDrawRect(x - 80, iconY + 2, 64, 48, {28, 42, 68, 255})
			for _, side in ipairs({-64, 64}) do
				local shadowX = x + side - offsetY
				local faceX = x + side + offsetY
				local buttonYShadow = baseY - offsetY
				local buttonYFace = baseY + offsetY
				ManiaMenuDrawNamedSprite("mania_menu_button", shadowX, buttonYShadow, 1, {0, 0, 0}, 1)
				ManiaMenuDrawNamedSprite("mania_menu_button", faceX, buttonYFace, 1, tint, 1)
			end
			if i == cursor then
				ManiaMenuDrawRect(x - 82, iconY, 68, 52, {248, 196, 48, 255})
				ManiaMenuDrawRect(x - 80, iconY + 2, 64, 48, {28, 42, 68, 255})
			end
			OPT.drawFrameText("LOCKED", 94 - offsetY, baseY - offsetY2 + 4, {255, 255, 255}, 12)
			local name = ManiaMenu.achievementNames[i + 1]
			OPT.drawFrameText(name, 132 - offsetY, baseY - offsetY2 + 4, {255, 255, 255}, 46)
		end
	end
	OPT.drawFrameText("UP/DOWN BROWSE   X BACK", 12, 224, {255, 255, 255}, 32)
	ManiaMenuDrawTransition()
	canvasImage:WritePixelsBuffer(CANVAS_ORIGIN, CANVAS_SIZE, framePixels)
	canvasLabel.Visible = true
end
function renderManiaCompetitionInfoToCanvas()
	ManiaMenuClearFrame({0, 0, 0, 255})
	ManiaMenuDrawBackground()
	ManiaMenuDrawNamedSprite("mania_menu_header", WIDTH / 2, 16, 1)
	OPT.drawFrameText("COMPETITION", 173, 9, {255, 255, 255}, 24)
	ManiaMenuDrawRect(12, 38, 400, 178, {0, 12, 48, 235})
	ManiaMenuDrawRect(12, 38, 400, 2, {248, 196, 48, 255})

	local page = ManiaMenu.compPage or "Browse"
	local selected = ManiaMenu.compSelected or 1
	local function drawRow(index, y, textValue, active)
		if active then
			ManiaMenuDrawRect(22, y - 2, 380, 13, {24, 56, 112, 255})
			OPT.drawFrameText(">", 28, y, {255, 224, 72}, 10)
			OPT.drawFrameText(textValue, 43, y, {255, 224, 72}, 52)
		else
			OPT.drawFrameText(textValue, 43, y, {232, 240, 255}, 52)
		end
	end

	if page == "Browse" then
		OPT.drawFrameText("PUBLIC ROOMS", 28, 47, {184, 208, 240}, 24)
		drawRow(1, 65, "CREATE ROOM", selected == 1)
		drawRow(2, 80, "REFRESH ROOM LIST", selected == 2)
		local rooms = ManiaMenu.compRooms or {}
		if #rooms == 0 then
			OPT.drawFrameText("NO OPEN ROOMS - CREATE ONE!", 46, 111, {255, 224, 72}, 38)
		else
			for i = 1, math.min(#rooms, 7) do
				local room = rooms[i]
				local label = string.format("%s  %s  %d/%d  %s", tostring(room.id),
					string.upper(tostring(room.mode or "RACE")), tonumber(room.playerCount) or 0,
					(tonumber(room.maxPlayers) or 0), tostring(room.stageKey or ""))
				drawRow(i + 2, 99 + (i - 1) * 15, label, selected == i + 2)
			end
		end
		OPT.drawFrameText(ManiaMenu.compNotice or "", 28, 202, {184, 208, 240}, 52)
		OPT.drawFrameText("UP/DOWN SELECT   ENTER JOIN   X BACK", 28, 222, {255, 255, 255}, 42)

	elseif page == "Create" then
		local options = ManiaMenu.compOptions
		local stage = levelButtonRecords[options.stageIndex]
		local stageName = stage and (stage.DisplayName or stage.Key) or "NO STAGES"
		OPT.drawFrameText("CREATE A COMPETITION ROOM", 28, 47, {184, 208, 240}, 39)
		drawRow(1, 66, "MODE: " .. string.upper(options.mode), selected == 1)
		drawRow(2, 82, "STAGE: " .. tostring(stageName), selected == 2)
		drawRow(3, 98, "MAX PLAYERS: " .. tostring(options.maxPlayers), selected == 3)
		if options.mode == "Battle" then
			drawRow(4, 114, "STOCKS: " .. tostring(options.stocks), selected == 4)
		else
			drawRow(4, 114, "RACE GOAL: END OF STAGE", selected == 4)
		end
		drawRow(5, 130, "TIME LIMIT: " .. tostring(options.timeLimit) .. " MIN", selected == 5)
		drawRow(6, 158, "CREATE ROOM", selected == 6)
		drawRow(7, 176, "BACK", selected == 7)
		OPT.drawFrameText("LEFT/RIGHT CHANGE OPTIONS", 28, 202, {184, 208, 240}, 35)
		OPT.drawFrameText("UP/DOWN SELECT   ENTER CONFIRM   X BACK", 28, 222, {255, 255, 255}, 42)

	elseif page == "Lobby" then
		local room = ManiaMenu.compRoom
		if not room then
			OPT.drawFrameText("CONNECTING TO ROOM...", 68, 110, {255, 224, 72}, 36)
		else
			OPT.drawFrameText(string.format("ROOM %s  -  HOST: %s", tostring(room.id), tostring(room.hostName or "PLAYER")), 28, 47, {184, 208, 240}, 43)
			OPT.drawFrameText(string.format("%s  |  %s  |  %d MIN", string.upper(tostring(room.mode or "RACE")), tostring(room.stageKey or ""), tonumber(room.timeLimit) or 3), 28, 62, {255, 224, 72}, 50)
			local members = room.players or {}
			for i = 1, math.min(#members, 6) do
				local member = members[i]
				local status = member.ready and "READY" or "NOT READY"
				local role = member.isHost and "HOST" or status
				local name = string.sub(tostring(member.displayName or "PLAYER"), 1, 16)
				OPT.drawFrameText(string.format("%d. %-16s %s", i, name, role), 35, 82 + (i - 1) * 13,
					member.ready and {120, 255, 150} or {232, 240, 255}, 40)
			end
			drawRow(1, 169, "TOGGLE READY", selected == 1)
			if room.isHost then
				drawRow(2, 185, "START MATCH", selected == 2)
			else
				drawRow(2, 185, "WAITING FOR HOST", selected == 2)
			end
			drawRow(3, 201, "LEAVE ROOM", selected == 3)
			OPT.drawFrameText(ManiaMenu.compNotice or "READY UP WHEN YOU ARE SET", 28, 218, {184, 208, 240}, 44)
		end
		OPT.drawFrameText("UP/DOWN SELECT   ENTER ACTION   X BACK", 28, 232, {255, 255, 255}, 42)

	elseif page == "Results" then
		local results = ManiaMenu.compResults
		OPT.drawFrameText("MATCH RESULTS", 157, 48, {255, 224, 72}, 25)
		if results and type(results.entries) == "table" then
			for i, entry in ipairs(results.entries) do
				if i > 8 then break end
				local detail
				if results.mode == "Race" then
					detail = entry.finished and string.format("%.2f SEC", tonumber(entry.time) or 0) or "DID NOT FINISH"
				else
					detail = string.format("%d KOs  |  %d STOCKS", tonumber(entry.score) or 0, tonumber(entry.stocks) or 0)
				end
				OPT.drawFrameText(string.format("%d. %-16s %s", i, tostring(entry.displayName or "PLAYER"), detail),
					28, 75 + (i - 1) * 16, i == 1 and {255, 224, 72} or {232, 240, 255}, 47)
			end
		else
			OPT.drawFrameText("MATCH FINISHED", 100, 100, {232, 240, 255}, 28)
		end
		OPT.drawFrameText("ENTER: ROOM LIST     X: MAIN MENU", 80, 207, {255, 255, 255}, 36)
	end

	ManiaMenuDrawTransition()
	canvasImage:WritePixelsBuffer(CANVAS_ORIGIN, CANVAS_SIZE, framePixels)
	canvasLabel.Visible = true
end

function renderLevelSelectToCanvas()
	if ManiaMenu.screen == "StageSelect" then
		renderManiaStageSelectToCanvas()
	else
		renderManiaMainMenuToCanvas()
	end
end

function renderManiaMenuScreen()
	if ManiaMenu.screen == "Main" then
		renderManiaMainMenuToCanvas()
	elseif ManiaMenu.screen == "StageSelect" then
		renderManiaStageSelectToCanvas()
	elseif ManiaMenu.screen == "Extras" then
		renderManiaExtrasToCanvas()
	elseif ManiaMenu.screen == "Competition" then
		renderManiaCompetitionInfoToCanvas()
	end
end

function setMenuStatus(text, isError)
	menuStatusText = tostring(text or "")
	menuStatusIsError = isError == true
	if menuOpen and ManiaMenu.screen == "StageSelect" then
		renderManiaStageSelectToCanvas()
	end
end

function ManiaMenuOpenStageSelect(preferredName)
	ManiaMenu.screen = "StageSelect"
	ManiaMenu.previewPlayer.manual = false
	ManiaMenu.previewPlayer.hsp = 0
	ManiaMenu.previewPlayer.vsp = 0
	ManiaMenu.previewPlayer.state = 0
	ManiaMenu.previewPlayer.y = 0
	ManiaMenu.confirmWait = 32
	refreshLevelSelect(preferredName)
	renderManiaStageSelectToCanvas()
end

function ManiaMenuCompetitionRender()
	if menuOpen and ManiaMenu.screen == "Competition" then
		renderManiaCompetitionInfoToCanvas()
	end
end

function ManiaMenuCompetitionRequestRooms()
	local comp = OPT.comp
	if comp and comp.remote then
		comp.remote:FireServer("ListRooms")
		ManiaMenu.compNotice = "UPDATING ROOM LIST..."
	else
		ManiaMenu.compNotice = "SERVER SCRIPT REQUIRED: RSDK MULTIPLAYER"
	end
	ManiaMenuCompetitionRender()
end

function ManiaMenuCompetitionCreateRoom()
	local comp = OPT.comp
	local options = ManiaMenu.compOptions
	local stage = levelButtonRecords[options.stageIndex]
	if not stage or not stage.Folder then
		ManiaMenu.compNotice = "NO VALID STAGES FOUND"
		ManiaMenuCompetitionRender()
		return
	end
	if not comp or not comp.remote then
		ManiaMenu.compNotice = "MULTIPLAYER SERVER SCRIPT IS NOT RUNNING"
		ManiaMenuCompetitionRender()
		return
	end
	ManiaMenu.compNotice = "CREATING ROOM..."
	comp.remote:FireServer("CreateRoom", {
		mode = options.mode,
		stageKey = stage.Key,
		maxPlayers = options.maxPlayers,
		stocks = options.stocks,
		timeLimit = options.timeLimit,
	})
	ManiaMenuCompetitionRender()
end

function ManiaMenuCompetitionAdjust(delta)
	local options = ManiaMenu.compOptions
	if ManiaMenu.compPage ~= "Create" then return end
	if ManiaMenu.compSelected == 1 then
		options.mode = options.mode == "Race" and "Battle" or "Race"
	elseif ManiaMenu.compSelected == 2 then
		local count = math.max(1, #levelButtonRecords)
		options.stageIndex = ((options.stageIndex - 1 + delta) % count) + 1
	elseif ManiaMenu.compSelected == 3 then
		options.maxPlayers = math.clamp(options.maxPlayers + delta, 2, 8)
	elseif ManiaMenu.compSelected == 4 and options.mode == "Battle" then
		options.stocks = math.clamp(options.stocks + delta, 1, 5)
	elseif ManiaMenu.compSelected == 5 then
		options.timeLimit = math.clamp(options.timeLimit + delta, 2, 10)
	end
	ManiaMenuPlaySound("mania_menu_choose")
	ManiaMenuCompetitionRender()
end

function ManiaMenuCompetitionMove(delta)
	local page = ManiaMenu.compPage
	local maxSelection = 1
	if page == "Browse" then
		maxSelection = 2 + math.min(#(ManiaMenu.compRooms or {}), 7)
	elseif page == "Create" then
		maxSelection = 7
	elseif page == "Lobby" then
		maxSelection = 3
	elseif page == "Results" then
		maxSelection = 2
	end
	local nextSelection = math.clamp((ManiaMenu.compSelected or 1) + delta, 1, maxSelection)
	if nextSelection == ManiaMenu.compSelected then return end
	ManiaMenu.compSelected = nextSelection
	ManiaMenuPlaySound("mania_menu_choose")
	ManiaMenuCompetitionRender()
end

function ManiaMenuCompetitionConfirm()
	local page = ManiaMenu.compPage
	local selected = ManiaMenu.compSelected or 1
	local comp = OPT.comp
	if page == "Browse" then
		if selected == 1 then
			ManiaMenu.compPage = "Create"
			ManiaMenu.compSelected = 1
			ManiaMenu.compOptions.stageIndex = math.clamp(menuSelectedIndex, 1, math.max(1, #levelButtonRecords))
			ManiaMenuCompetitionRender()
		elseif selected == 2 then
			ManiaMenuCompetitionRequestRooms()
		else
			local room = ManiaMenu.compRooms[selected - 2]
			if room and comp and comp.remote then
				ManiaMenu.compNotice = "JOINING " .. tostring(room.id) .. "..."
				comp.remote:FireServer("JoinRoom", {roomId = room.id})
				ManiaMenuCompetitionRender()
			end
		end
	elseif page == "Create" then
		if selected == 6 then
			ManiaMenuCompetitionCreateRoom()
		elseif selected == 7 then
			ManiaMenu.compPage = "Browse"
			ManiaMenu.compSelected = 1
			ManiaMenuCompetitionRender()
		else
			ManiaMenuCompetitionAdjust(1)
		end
	elseif page == "Lobby" then
		if not comp or not comp.remote then return end
		if selected == 1 then
			comp.remote:FireServer("SetReady")
		elseif selected == 2 and ManiaMenu.compRoom and ManiaMenu.compRoom.isHost then
			ManiaMenu.compNotice = "PREPARING MATCH..."
			comp.remote:FireServer("StartMatch")
		elseif selected == 3 then
			comp.remote:FireServer("LeaveRoom")
			ManiaMenu.compRoom = nil
			ManiaMenu.compPage = "Browse"
			ManiaMenu.compSelected = 1
			ManiaMenuCompetitionRequestRooms()
		end
		ManiaMenuCompetitionRender()
	elseif page == "Results" then
		if selected == 1 then
			if comp and comp.remote then comp.remote:FireServer("LeaveRoom") end
			ManiaMenu.compRoom = nil
			ManiaMenu.compResults = nil
			ManiaMenu.compPage = "Browse"
			ManiaMenu.compSelected = 1
			ManiaMenu.screen = "Competition"
			ManiaMenuCompetitionRequestRooms()
		else
			if comp and comp.remote then comp.remote:FireServer("LeaveRoom") end
			ManiaMenu.compRoom = nil
			ManiaMenu.compResults = nil
			ManiaMenu.screen = "Main"
			ManiaMenu.compPage = "Browse"
			ManiaMenuPlaySound("mania_menu", true)
			renderManiaMainMenuToCanvas()
		end
	end
end

function ManiaMenuCompetitionBack()
	local comp = OPT.comp
	if ManiaMenu.compPage == "Lobby" then
		if comp and comp.remote then comp.remote:FireServer("LeaveRoom") end
		ManiaMenu.compRoom = nil
		ManiaMenu.compPage = "Browse"
		ManiaMenu.compSelected = 1
		ManiaMenuCompetitionRequestRooms()
	elseif ManiaMenu.compPage == "Create" then
		ManiaMenu.compPage = "Browse"
		ManiaMenu.compSelected = 1
		ManiaMenuCompetitionRender()
	elseif ManiaMenu.compPage == "Results" then
		if comp and comp.remote then comp.remote:FireServer("LeaveRoom") end
		ManiaMenu.compRoom = nil
		ManiaMenu.compResults = nil
		ManiaMenu.screen = "Main"
		ManiaMenu.compPage = "Browse"
		ManiaMenuPlaySound("mania_menu", true)
		renderManiaMainMenuToCanvas()
	else
		ManiaMenu.screen = "Main"
		ManiaMenu.compPage = "Browse"
		ManiaMenu.confirmWait = 32
		ManiaMenuPlaySound("mania_menu", true)
		renderManiaMainMenuToCanvas()
	end
end

function ManiaMenuActivateMainChoice()
	ManiaMenu.confirmWait = 0
	ManiaMenuPlaySound("mania_menu_woosh")
	if ManiaMenu.selected == 0 then
		ManiaMenuOpenStageSelect(selectedLevelName)
	elseif ManiaMenu.selected == 1 then
		ManiaMenu.screen = "Competition"
		ManiaMenu.compPage = "Browse"
		ManiaMenu.compSelected = 1
		ManiaMenu.compRoom = nil
		ManiaMenu.compResults = nil
		ManiaMenuPlaySound("competition_menu", true)
		ManiaMenuCompetitionRequestRooms()
	elseif ManiaMenu.selected == 2 then
		ManiaMenu.screen = "Extras"
		ManiaMenu.previewPlayer.manual = false
		ManiaMenu.extraSelected = 1
		ManiaMenu.selectedTimer = 0
		ManiaMenu.selectedTimer2 = 0
		ManiaMenu.selectedOffset = 0
		ManiaMenu.scrollOffset = 0
		renderManiaExtrasToCanvas()
	end
end

local function ManiaMenuGamepad2Down(keyCode)
	local ok, down = pcall(function()
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad2, keyCode)
	end)
	return ok and down == true
end

local function ManiaMenuGetGamepad2Axes()
	local axisX, axisY = 0, 0
	local ok, states = pcall(function()
		return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad2)
	end)
	if ok and type(states) == "table" then
		for _, state in ipairs(states) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 then
				axisX = state.Position.X
				axisY = state.Position.Y
				break
			end
		end
	end
	return axisX, axisY
end

function ManiaMenuStartPlayerTwoPreview()
	local preview = ManiaMenu.previewPlayer
	if ManiaMenu.screen ~= "Main" or ManiaMenu.selected ~= 0 or preview.manual then return end
	preview.manual = true
	preview.hsp = 0x100
	preview.vsp = 0
	preview.state = 0
	preview.frame = math.floor(ManiaMenu.frame / 6) % 12
	preview.tick = 0
	preview.dir = 1
	preview.y = 0
	preview.jumpHeld = false
end

local function ManiaMenuUpdatePlayerTwoPreview()
	local preview = ManiaMenu.previewPlayer
	if not preview.manual or ManiaMenu.screen ~= "Main" or ManiaMenu.selected ~= 0 then return end

	local axisX, axisY = ManiaMenuGetGamepad2Axes()
	local right = ManiaMenuGamepad2Down(Enum.KeyCode.DPadRight) or axisX > 0.35
	local left = ManiaMenuGamepad2Down(Enum.KeyCode.DPadLeft) or axisX < -0.35
	local down = ManiaMenuGamepad2Down(Enum.KeyCode.DPadDown) or axisY < -0.55
	local up = ManiaMenuGamepad2Down(Enum.KeyCode.DPadUp) or axisY > 0.55
	local jump = ManiaMenuGamepad2Down(Enum.KeyCode.ButtonA)
	local jumpPressed = jump and not preview.jumpHeld
	local horizontal = (right and 1 or 0) - (left and 1 or 0)

	if preview.y >= 0 then
		if preview.state ~= 3 and preview.state ~= 4 then
			if preview.state ~= 2 then
				if preview.vsp ~= 0 then preview.frame = 0 end
				preview.state = 0
			end
		elseif preview.state ~= 4 then
			if not down then preview.state = 0; preview.frame = 0 end
			preview.hsp = 0
		else
			if not up then preview.state = 0; preview.frame = 0 end
			preview.hsp = 0
		end
		preview.vsp = 0
		preview.y = 0
	else
		if not jump and preview.vsp < -0x2a0 then preview.vsp = -0x2a0 end
		preview.vsp += 0x3f
	end

	if jumpPressed and preview.y >= 0 then
		preview.vsp = -0x6a0
		preview.state = 1
	elseif math.abs(preview.hsp) <= 0x1a and preview.state == 2 then
		preview.state = 0
		preview.frame = 0
	end

	if down and preview.y >= 0 and preview.state == 0 and math.abs(preview.hsp) >= 0x07f then
		preview.state = 2
	end
	if down and preview.y >= 0 and preview.state == 0 and math.abs(preview.hsp) <= 0x1a then
		preview.state = 3
		preview.tick = 0
	end
	if up and preview.y >= 0 and preview.state == 0 and math.abs(preview.hsp) <= 0x1a then
		preview.state = 4
		preview.tick = 0
	end

	if preview.hsp > 0 then preview.dir = 1 elseif preview.hsp < 0 then preview.dir = -1 end
	if preview.state ~= 3 and preview.state ~= 4 then
		if math.abs(horizontal) > 0 and horizontal == preview.dir and preview.state ~= 2 then
			preview.hsp = math.clamp(preview.hsp + horizontal * 0x10, -0x05f0, 0x05f0)
		elseif math.abs(horizontal) > 0 and horizontal ~= preview.dir then
			preview.hsp = math.clamp(preview.hsp + horizontal * 0x2f, -0x05f0, 0x05f0)
		elseif (math.abs(preview.hsp / 0x1a) > 0) and (horizontal == 0 or preview.state == 2) then
			local friction = preview.state == 2 and 0x07 or 0x10
			preview.hsp = math.clamp(preview.hsp - friction * preview.dir, -0x05f0, 0x05f0)
		elseif math.abs(preview.hsp) <= 0x1a and horizontal == 0 then
			preview.hsp = 0
		end
	end

	ManiaMenu.scrollOffset += preview.hsp
	preview.y += preview.vsp

	if preview.state == 0 then
		if math.abs(preview.hsp) <= 0x1a then
			preview.frame = 0
			preview.tick = 0
		else
			preview.tick += math.floor(math.abs(preview.hsp) / 8)
			while preview.tick >= 0x150 do
				preview.frame += 1
				preview.tick -= 0x150
			end
			if math.abs(preview.hsp) >= 0x500 then preview.frame %= 8
			elseif math.abs(preview.hsp) >= 0x300 then preview.frame %= 10
			else preview.frame %= 12 end
		end
	elseif preview.state == 1 or preview.state == 2 then
		preview.tick = 0
		preview.frame = (preview.frame + 1) % 16
	elseif preview.state == 3 then
		preview.tick += 0x50
		while preview.tick >= 0x100 do
			preview.frame = math.clamp(preview.frame + 1, 0, 3)
			preview.tick -= 0x100
		end
	elseif preview.state == 4 then
		preview.tick += 0x7f
		while preview.tick >= 0x100 do
			preview.frame = math.clamp(preview.frame + 1, 0, 4)
			preview.tick -= 0x100
		end
	end
	preview.jumpHeld = jump
end

local function ManiaMenuHalfTowardZero(value)
	if value < 0 then return math.ceil(value / 2) end
	return math.floor(value / 2)
end

function updateManiaMenu()
	ManiaMenu.frame += 1
	if ManiaMenu.screen == "Main" then
		if ManiaMenu.previewPlayer.manual then
			ManiaMenuUpdatePlayerTwoPreview()
		else
			ManiaMenu.scrollOffset += 0x100
		end
		if ManiaMenu.selectedTimer < 0x11 then ManiaMenu.selectedTimer += 1 end
		if ManiaMenu.selectedTimer2 < 0x14 then ManiaMenu.selectedTimer2 += 1 end
		if ManiaMenu.selectedTimer > 0 then
			ManiaMenu.selectedOffset = ManiaMenuHalfTowardZero(ManiaMenu.selectedOffset)
		end
		if ManiaMenu.confirmWait >= 1 and ManiaMenu.confirmWait < 31 then
			ManiaMenu.confirmWait += 1
			if ManiaMenu.confirmWait == 15 then ManiaMenuPlaySound("mania_menu_woosh") end
			if ManiaMenu.confirmWait == 31 then
				ManiaMenuActivateMainChoice()
				return
			end
		end
	elseif ManiaMenu.screen == "Extras" then
		if ManiaMenu.selectedTimer < 0x11 then ManiaMenu.selectedTimer += 1 end
		if ManiaMenu.selectedTimer2 < 0x14 then ManiaMenu.selectedTimer2 += 1 end
		if ManiaMenu.selectedOffset ~= 0 then ManiaMenu.selectedOffset = ManiaMenuHalfTowardZero(ManiaMenu.selectedOffset) end
		if ManiaMenu.confirmWait >= 15 and ManiaMenu.confirmWait < 31 then
			ManiaMenu.confirmWait += 1
			if ManiaMenu.confirmWait == 31 then
				ManiaMenu.selected = 2
				ManiaMenu.screen = "Main"
				ManiaMenu.confirmWait = 32
				ManiaMenu.selectedTimer = 0
				ManiaMenu.selectedTimer2 = 0
				ManiaMenu.selectedOffset = 0
				ManiaMenu.menuRenderDivider = 0
				ManiaMenuPlaySound("mania_menu_choose")
				renderManiaMainMenuToCanvas()
				return
			end
		end
	end
end
function ManiaMenuNavigateMain(delta)
	local nextIndex = math.clamp(ManiaMenu.selected + delta, 0, 2)
	if nextIndex == ManiaMenu.selected then return end
	ManiaMenu.selected = nextIndex
	ManiaMenu.previewPlayer.manual = false
	ManiaMenu.previewPlayer.hsp = 0
	ManiaMenu.previewPlayer.vsp = 0
	ManiaMenu.previewPlayer.state = 0
	ManiaMenu.previewPlayer.y = 0
	ManiaMenu.previewPlayer.jumpHeld = false
	ManiaMenu.selectedTimer = 0
	ManiaMenu.selectedTimer2 = 0
	ManiaMenu.selectedOffset = delta < 0 and 32 or -32
	ManiaMenu.scrollOffset = 0
	ManiaMenu.confirmWait = 32
	ManiaMenuPlaySound("mania_menu_choose")
	renderManiaMainMenuToCanvas()
end

function ManiaMenuNavigateExtras(delta)
	local nextIndex = math.clamp(ManiaMenu.extraSelected + delta, 1, #ManiaMenu.achievementNames)
	if nextIndex == ManiaMenu.extraSelected then return end
	ManiaMenu.extraSelected = nextIndex
	ManiaMenu.selectedTimer = 0
	ManiaMenu.selectedTimer2 = 0
	ManiaMenu.selectedOffset = delta < 0 and 32 or -32
	ManiaMenu.scrollOffset = 0
	ManiaMenuPlaySound("mania_menu_choose")
	renderManiaExtrasToCanvas()
end

function ManiaMenuConfirm()
	if ManiaMenu.screen == "Main" then
		if ManiaMenu.confirmWait == 0 or ManiaMenu.confirmWait > 31 then
			ManiaMenuPlaySound("mania_menu_confirm")
			ManiaMenu.confirmWait = 1
		end
	elseif ManiaMenu.screen == "StageSelect" then
		local record = levelButtonRecords[menuSelectedIndex]
		if record and record.Folder and record.Folder.Parent then
			ManiaMenuPlaySound("mania_menu_confirm")
			startLevel(record.Folder)
		elseif #levelButtonRecords == 0 then
			setMenuStatus("NO STAGES FOUND", true)
		end
	elseif ManiaMenu.screen == "Competition" then
		ManiaMenuPlaySound("mania_menu_confirm")
		ManiaMenuCompetitionConfirm()
	end
end

function ManiaMenuBack()
	if ManiaMenu.screen == "Main" then return end
	ManiaMenuPlaySound("mania_menu_woosh")
	if ManiaMenu.screen == "Competition" then
		ManiaMenuCompetitionBack()
		return
	end
	if ManiaMenu.screen == "Extras" then
		-- The reference Extras menu wipes back to the main menu over frames 15-30.
		ManiaMenu.confirmWait = 15
		return
	end
	ManiaMenu.screen = "Main"
	ManiaMenu.confirmWait = 32
	ManiaMenu.menuRenderDivider = 0
	ManiaMenu.previewPlayer.manual = false
	ManiaMenu.previewPlayer.hsp = 0
	ManiaMenu.previewPlayer.vsp = 0
	ManiaMenu.previewPlayer.state = 0
	ManiaMenu.previewPlayer.y = 0
	ManiaMenu.selectedTimer = 0
	ManiaMenu.selectedTimer2 = 0
	ManiaMenu.selectedOffset = 0
	renderManiaMainMenuToCanvas()
end


--============================================================
-- PLAYER STATE / INPUT
--============================================================

-- playerX/playerY are the sprite/entity origin. On regular track,
-- groundTrackX stores the horizontal coordinate of the contact point.
-- Scene entities store an MD5 of the object name. Match "Player" (both the
-- raw digest and the per-word byte-swapped form RSDK may store).
local PLAYER_NAME_HASHES = {
	["\99\109\161\211\94\128\91\0\234\224\252\216\51\63\146\52"] = true,
	["\211\161\109\99\0\91\128\94\216\252\224\234\52\146\63\51"] = true,
}

-- MD5 Name Hashes for GHZ Act 1 Objects (Replace placeholder hashes with actual RSDK hashes)
local GHZ_OBJECT_HASHES = {
	["\x00\x11\x22..."] = "Ring",
	["\x33\x44\x55..."] = "Monitor",
	["\x66\x77\x88..."] = "Spring",
	["\x99\xAA\xBB..."] = "Spikes",
	["\xCC\xDD\xEE..."] = "StarPost",
	["\xFF\x00\x11..."] = "Motobug",
	["\x22\x33\x44..."] = "Crabmeat",
	["\x55\x66\x77..."] = "BuzzBomber",
	["\x88\x99\xAA..."] = "Chopper",
}

-- Map the objects to their sprite chunk data (X, Y, Width, Height, PivotX, PivotY)
-- Adjust sourceX and sourceY to match where they actually live on your specific GHZ1 Tileset PNG.
local GHZ_SPRITE_REGISTRY = {
	["Ring"]       = { sheetIndex = 0, sprX = 16,  sprY = 16, width = 16, height = 16, pivotX = -8,  pivotY = -8 },
	["Monitor"]    = { sheetIndex = 0, sprX = 32,  sprY = 16, width = 32, height = 32, pivotX = -16, pivotY = -16 },
	["Spring"]     = { sheetIndex = 0, sprX = 64,  sprY = 16, width = 32, height = 32, pivotX = -16, pivotY = -16 },
	["Spikes"]     = { sheetIndex = 0, sprX = 96,  sprY = 16, width = 32, height = 32, pivotX = -16, pivotY = -16 },
	["StarPost"]   = { sheetIndex = 0, sprX = 128, sprY = 16, width = 16, height = 48, pivotX = -8,  pivotY = -24 },
	["Motobug"]    = { sheetIndex = 0, sprX = 16,  sprY = 48, width = 40, height = 32, pivotX = -20, pivotY = -16 },
	["Crabmeat"]   = { sheetIndex = 0, sprX = 64,  sprY = 48, width = 48, height = 32, pivotX = -24, pivotY = -16 },
	["BuzzBomber"] = { sheetIndex = 0, sprX = 112, sprY = 48, width = 48, height = 32, pivotX = -24, pivotY = -16 },
	["Chopper"]    = { sheetIndex = 0, sprX = 160, sprY = 48, width = 32, height = 32, pivotX = -16, pivotY = -16 },
}

local levelObjects = {}

function findScenePlayerStart(level)
	if not level or not level.entities then return nil end
	for _, entity in ipairs(level.entities) do
		if PLAYER_NAME_HASHES[entity.nameHash] then
			-- Positions are 16.16 fixed point (treat as signed 32-bit).
			local x, y = entity.xRaw, entity.yRaw
			if x >= 0x80000000 then x -= 0x100000000 end
			if y >= 0x80000000 then y -= 0x100000000 end
			return x / 65536, y / 65536
		end
	end
	return nil
end

local initialWorldX = usingRSDKLevel and (tonumber(activeLevelConfig.StartX) or 96) or 20
local initialWorldY = usingRSDKLevel and (tonumber(activeLevelConfig.StartY) or 80) or (TRACK_START_Y - HEIGHT_RADIUS)
local groundTrackX = initialWorldX
local playerX = initialWorldX
local playerY = initialWorldY
local speedX = 0
local speedY = 0
local grounded = not usingRSDKLevel
local cameraX = 0
local cameraY = 0
local cameraInitialized = false
local lastLevelRenderCameraX = nil
local lastLevelRenderCameraY = nil
local lastLevelRenderFrame = nil
local backgroundScrollFrame = 0

-- Loop angle starts at the bottom and decreases as Sonic travels right.
local onLoop = false
local loopTheta = math.pi / 2
local loopStartTheta = loopTheta
local landingWorldSpeedX = 0

-- RSDK uses a 256-unit surface angle and a 512-unit sprite rotation.
local groundAngleRad = 0
local groundAngle256 = 0
local rotationUnits = 0

local leftHeld = false
local rightHeld = false
local upHeld = false
local downHeld = false
local jumpHeld = false
local jumpQueued = false

local facingRight = true
local playerState = "Ground"
local playerTimer = 0
local skidding = 0
local applyJumpCap = false -- Mania: variable jump height only applies after a real jump
local pushing = 0 -- Mania's self->pushing: counts ticks held against a wall (+right / -left)
local spinRev = 0
local ringCount = 0

-- Debug mode freezes Sonic and lets the player move a free placement cursor.
-- Placed props are visual test objects; they do not add collision or game logic.
local debugMode = false
local debugCursorX = initialWorldX
local debugCursorY = initialWorldY
local debugCycleQueued = false
local debugPlaceQueued = false
local debugObjects = {}
local debugObjectTypes = {
	{Name = "RING", Kind = "Ring"},
	{Name = "MONITOR", Kind = "Monitor"},
	{Name = "SPRING", Kind = "Spring"},
	{Name = "SPIKES", Kind = "Spikes"},
	{Name = "STARPOST", Kind = "StarPost"},
	{Name = "CAPSULE", Kind = "Capsule"},
	{Name = "MOTOBUG", Kind = "Motobug"},
	{Name = "BRIDGE", Kind = "Bridge"},
	{Name = "PIMPOM BALL", Kind = "PimPom"},
	{Name = "PIMPOM BAR", Kind = "PimPom", Extra = {ppType = 1, length = 2, gap = 8}},
	{Name = "PIMPOM SPIN", Kind = "PimPom", Extra = {ppType = 3, length = 1, gap = 16, spinSpeed = 8}},
}
local debugSelectedIndex = 1
local DEBUG_CURSOR_SPEED = 2.5

-- Drop Dash uses the same jump-ability counter as Player_JumpAbility_Sonic.
-- Jump begins at state 2 (jump action's initial state 1, then the first
-- ability tick); holding jump increments it to 22 to enter DropDash.
local jumpAbilityState = 0
local dropDashReady = false

function horizontalInput()
	if leftHeld == rightHeld then return 0 end
	return leftHeld and -1 or 1
end

-- Update scene entities and collect rings when Sonic's collision bounds touch them.
-- Player collision bounds are axis-aligned in this renderer, including on slopes.
function updateEntities(dt)
	if OPT.titleCard.active then return end
	if debugMode then return end
	OPT.bridgeStanding = false
	OPT.stepExplosions()

	-- Advance the actual Ring.bin sparkle sub-animations spawned on collection.
	for index = #ringPickupEffects, 1, -1 do
		local effect = ringPickupEffects[index]
		if effect.delay > 0 then
			effect.delay -= 1
			effect.visible = false
		else
			effect.visible = true
			effect.frameTimer += effect.animationSpeed
			local expired = false
			local safety = 0
			while effect.frameTimer >= effect.frameDuration do
				safety += 1
				if safety > 128 then
					warn("[RSDK] Ring pickup sparkle animation safety limit reached")
					break
				end
				effect.frameTimer -= effect.frameDuration
				effect.frameID += 1
				if effect.frameID >= effect.maxFrameCount then
					expired = true
					break
				end
				local nextFrame = effect.animation.frames[effect.frameID + 1]
				effect.frameDuration = math.max(1, tonumber(nextFrame.duration) or 1)
			end
			if expired then
				table.remove(ringPickupEffects, index)
			end
		end
	end

	for index = #activeEntities, 1, -1 do
		local entity = activeEntities[index]
		local definition = entity.def

		if definition and type(definition.update) == "function" then
			definition.update(entity, dt)
		end
		if entity.dead then
			table.remove(activeEntities, index)
			continue
		end

		if entity.collectible then
			local radius = tonumber(entity.radius) or 8
			local touchingX = math.abs(playerX - entity.x) <= WIDTH_RADIUS + radius
			local touchingY = math.abs(playerY - entity.y) <= HEIGHT_RADIUS + radius

			if touchingX and touchingY then
				ringCount += 1
				OPT.hud.score += 100
				if spawnRingPickupAnimation then
					spawnRingPickupAnimation(entity.x, entity.y)
				end
				table.remove(activeEntities, index)
			end
		end
	end
end

--============================================================
-- PIXEL BUFFERS AND TEST TRACK
--============================================================

local basePixels = buffer.create(WIDTH * HEIGHT * 4)
framePixels = buffer.create(WIDTH * HEIGHT * 4)
collisionOverlayPixels = buffer.create(WIDTH * HEIGHT * 4)

-- Pixel colors are shared tables in this renderer. Cache their packed RGBA
-- representation so hot drawing paths need one u32 write instead of four u8s.
local packedPixelColors = setmetatable({}, { __mode = "k" })
local writePixelU32 = buffer.writeu32

function getPackedPixelColor(color)
	-- Most renderer colors are RGB(A) tables, but the shared BLACK constant is
	-- a Roblox Color3. Color3 indexing expects property names ("R", "G", "B"),
	-- so treating it like color[1] caused the TitleCard intro to error every frame.
	if typeof(color) == "Color3" then
		local red = math.round(color.R * 255)
		local green = math.round(color.G * 255)
		local blue = math.round(color.B * 255)
		return red + green * 256 + blue * 65536 + 255 * 16777216
	end

	assert(type(color) == "table", "Pixel color must be a Color3 or an RGB(A) table")
	local packed = packedPixelColors[color]
	if packed ~= nil then
		return packed
	end

	local red = math.clamp(math.floor(tonumber(color[1]) or 0), 0, 255)
	local green = math.clamp(math.floor(tonumber(color[2]) or 0), 0, 255)
	local blue = math.clamp(math.floor(tonumber(color[3]) or 0), 0, 255)
	local alpha = math.clamp(math.floor(tonumber(color[4]) or 255), 0, 255)
	packed = red + green * 256 + blue * 65536 + alpha * 16777216
	packedPixelColors[color] = packed
	return packed
end

function putPixel(target, x, y, color)
	x = math.floor(x)
	y = math.floor(y)
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT then return end

	local offset = (y * WIDTH + x) * 4
	writePixelU32(target, offset, getPackedPixelColor(color))
end

function pixel(x, y, color)
	putPixel(framePixels, x, y, color)
end

--============================================================
-- MANIA WATER SYSTEM
--
-- Water.c uses a world-space waterLevel, a slow Sin512 movement of the
-- surface, a palette swap below the surface, and separate underwater player
-- physics. This canvas renderer reproduces those core behaviours with a
-- palette-style pixel tint, a repeated animated surface, transition splashes,
-- rising bubbles, and the water physics multipliers below.
--============================================================

function OPT.findSceneWaterLevel(level, wantedObjectID)
	if not level or type(level.entities) ~= "table" then return nil, 0 end
	local foundY = nil
	local foundCount = 0
	for _, entity in ipairs(level.entities) do
		if entity.nameHash == OPT.waterNameHashRaw or entity.nameHash == OPT.waterNameHashSwapped then
			if wantedObjectID == nil or entity.objectID == wantedObjectID then
				foundCount += 1
				local rawY = entity.yRaw
				if rawY >= 0x80000000 then rawY -= 0x100000000 end
				foundY = rawY / 65536
			end
		end
	end
	-- SceneData alone does not contain Water.type or Water.size.x. Only infer
	-- an entity waterline when exactly one candidate exists (or an ID is given).
	if foundCount == 1 then return foundY, foundCount end
	return nil, foundCount
end

-- Return the waterline's base height in stage/world coordinates. In camera
-- space, Level is a screen row and therefore follows the camera as it scrolls.
function OPT.waterBaseWorldY()
	local water = OPT.water
	if water.levelSpace == "camera" then
		return cameraY + water.baseLevel
	end
	return water.baseLevel
end

function OPT.updateWaterSurface()
	local water = OPT.water
	if water.baseLevel == nil then return nil end
	water.surfaceY = OPT.waterBaseWorldY()
		+ math.sin(water.tick * water.waveSpeed) * water.waveAmplitude
	return water.surfaceY
end

function OPT.configureWater(config, level)
	local water = OPT.water
	local source = config and config.Water
	if type(source) == "number" then
		source = {Enabled = true, Level = source}
	elseif type(source) == "boolean" then
		source = {Enabled = source, Level = config and config.WaterLevel}
	elseif type(source) ~= "table" then
		if config and tonumber(config.WaterLevel) then
			source = {Enabled = config.WaterEnabled ~= false, Level = config.WaterLevel}
		else
			source = {}
		end
	end

	local levelSpace = string.lower(tostring(source.LevelSpace or source.CoordinateSpace or "world"))
	if levelSpace == "camera" or levelSpace == "screen" or levelSpace == "viewport" then
		water.levelSpace = "camera"
	else
		water.levelSpace = "world"
	end
	-- ScreenY is an explicit alias that always selects camera-relative mode.
	local configuredLevel = source.Level or source.WaterLevel or (config and config.WaterLevel)
	if tonumber(source.ScreenY) ~= nil then
		configuredLevel = source.ScreenY
		water.levelSpace = "camera"
	end
	local baseLevel = tonumber(configuredLevel)
	local detectedCount = 0
	if baseLevel == nil and source.AutoDetectEntity == true then
		baseLevel, detectedCount = OPT.findSceneWaterLevel(level, tonumber(source.EntityObjectID))
	end

	local enabled = source.Enabled
	if enabled == nil then enabled = baseLevel ~= nil end
	if config and config.WaterEnabled == false then enabled = false end

	water.configured = next(source) ~= nil or baseLevel ~= nil
	water.enabled = enabled == true and baseLevel ~= nil
	water.baseLevel = baseLevel
	water.showDebugHud = source.ShowDebugHud ~= false
	water.waveAmplitude = math.max(0, tonumber(source.WaveAmplitude) or 1.25)
	water.waveSpeed = tonumber(source.WaveSpeed) or (math.pi / 128)
	water.tintStrength = math.clamp(tonumber(source.TintStrength) or 0.38, 0, 0.85)
	water.groundSpeedScale = math.clamp(tonumber(source.GroundSpeedScale) or 0.50, 0.1, 1)
	water.groundAccelScale = math.clamp(tonumber(source.GroundAccelScale) or 0.50, 0.1, 1)
	water.groundDecelScale = math.clamp(tonumber(source.GroundDecelScale) or 0.50, 0.1, 1)
	water.groundFrictionScale = math.clamp(tonumber(source.GroundFrictionScale) or 0.50, 0.1, 1)
	water.rollingFrictionScale = math.clamp(tonumber(source.RollingFrictionScale) or 0.50, 0.1, 1)
	water.airAccelScale = math.clamp(tonumber(source.AirAccelScale) or 0.50, 0.1, 1)
	water.gravityScale = math.clamp(tonumber(source.GravityScale) or (32 / 88), 0.1, 1)
	water.terminalSpeedScale = math.clamp(tonumber(source.TerminalSpeedScale) or 1.0, 0.1, 1)
	water.jumpForceScale = math.clamp(tonumber(source.JumpForceScale) or (3.5 / 6.5), 0.1, 1)
	water.entryHorizontalScale = math.clamp(tonumber(source.EntryHorizontalScale) or 0.50, 0, 1)
	water.entryVerticalScale = math.clamp(tonumber(source.EntryVerticalScale) or 0.25, 0, 1)
	water.bubbleInterval = math.max(12, math.floor(tonumber(source.BubbleInterval) or 52))

	function copyColor(value, fallback)
		if type(value) ~= "table" then return {fallback[1], fallback[2], fallback[3]} end
		return {
			math.clamp(math.floor(tonumber(value[1]) or fallback[1]), 0, 255),
			math.clamp(math.floor(tonumber(value[2]) or fallback[2]), 0, 255),
			math.clamp(math.floor(tonumber(value[3]) or fallback[3]), 0, 255),
		}
	end
	water.tintColor = copyColor(source.TintColor, {28, 78, 138})
	water.surfaceColor = copyColor(source.SurfaceColor, {74, 190, 236})
	water.highlightColor = copyColor(source.HighlightColor, {180, 238, 255})
	water.shadowColor = copyColor(source.ShadowColor, {22, 104, 164})

	-- The tint is constant for a loaded stage. Precompute all 256 possible
	-- channel results once instead of multiplying/flooring three times per pixel.
	local inverseTint = 1 - water.tintStrength
	local tint = water.tintColor
	local tintLookup = { red = table.create(256), green = table.create(256), blue = table.create(256) }
	for channel = 0, 255 do
		local index = channel + 1
		tintLookup.red[index] = math.floor(channel * inverseTint + tint[1] * water.tintStrength + 0.5)
		tintLookup.green[index] = math.floor(channel * inverseTint + tint[2] * water.tintStrength + 0.5)
		tintLookup.blue[index] = math.floor(channel * inverseTint + tint[3] * water.tintStrength + 0.5)
	end
	water.tintLookup = tintLookup
	water.tick = 0
	water.bubbleTimer = 0
	water.underwater = false
	water.surfaceY = baseLevel and OPT.waterBaseWorldY() or nil
	table.clear(water.bubbles)
	table.clear(water.splashes)

	if water.enabled then
		print(string.format("[WATER] Enabled | %s Y %.2f | world Y %.2f | camera Y %.2f | screen Y %.2f",
			water.levelSpace:upper(), baseLevel, water.surfaceY, cameraY, water.surfaceY - cameraY))
		if source.AutoDetectEntity == true and detectedCount == 1 then
			warn("[WATER] Auto-detected a single Water entity, but SceneData omits Water.type and size.x. Confirm this is a waterline, not a pool; set Water.Level for exact placement.")
		end
	elseif detectedCount > 1 then
		warn(string.format("[WATER] Found %d Water entities, but their subtype is not present in SceneData. Set LevelConfig.Water.Level or EntityObjectID.", detectedCount))
	else
		print("[WATER] Disabled for this stage. Set LevelConfig.Water.Level, or use LevelSpace = \"camera\" for a viewport-relative test line; F4 toggles preview water.")
	end
end

function OPT.spawnWaterSplash(worldX, worldY)
	local water = OPT.water
	for i = 1, 7 do
		local spread = (i - 4) / 3
		table.insert(water.splashes, {
			x = worldX + spread * 3,
			y = worldY,
			vx = spread * 1.25,
			vy = -0.45 - (1 - math.abs(spread)) * 1.05,
			age = 0,
		})
	end
end

function OPT.spawnWaterBubble(worldX, worldY)
	local water = OPT.water
	table.insert(water.bubbles, {
		x = worldX,
		y = worldY,
		vx = math.sin(water.tick * 0.31) * 0.12,
		vy = -0.65 - (water.tick % 5) * 0.04,
		age = 0,
		life = 54,
	})
end

function OPT.refreshWaterSubmersion()
	local water = OPT.water
	if not water.enabled or water.surfaceY == nil then
		water.underwater = false
		return
	end

	local submerged = playerY > water.surfaceY
	if submerged ~= water.underwater then
		if submerged then
			-- Water_State_Water halves horizontal speed and quarters vertical
			-- speed on entry, before the underwater physics table is selected.
			speedX *= water.entryHorizontalScale
			speedY *= water.entryVerticalScale
		else
			-- Mania gives a modest upward exit boost when the player is not already
			-- travelling upward quickly.
			if speedY >= -4 then
				speedY *= 2
				if speedY < -16 then speedY = -16 end
			end
		end
		OPT.spawnWaterSplash(playerX, water.surfaceY)
		water.underwater = submerged
		water.bubbleTimer = 0
	end
end

function OPT.stepWater()
	local water = OPT.water
	if not water.enabled or water.baseLevel == nil then return end
	water.tick += 1
	-- Water_State_Water: base level plus size.x * Sin512(2 * Zone->timer).
	OPT.updateWaterSurface()
	OPT.refreshWaterSubmersion()

	if water.underwater then
		water.bubbleTimer += 1
		if water.bubbleTimer >= water.bubbleInterval then
			water.bubbleTimer = 0
			OPT.spawnWaterBubble(playerX + math.sin(water.tick * 0.17) * 6, playerY - 5)
		end
	end

	for i = #water.bubbles, 1, -1 do
		local bubble = water.bubbles[i]
		bubble.x += bubble.vx
		bubble.y += bubble.vy
		bubble.age += 1
		if bubble.age >= bubble.life or bubble.y <= water.surfaceY - 2 then
			table.remove(water.bubbles, i)
		end
	end
	for i = #water.splashes, 1, -1 do
		local drop = water.splashes[i]
		drop.x += drop.vx
		drop.y += drop.vy
		drop.vy += 0.085
		drop.age += 1
		if drop.age >= 20 or drop.y > water.surfaceY + 8 then
			table.remove(water.splashes, i)
		end
	end
end

function OPT.drawWaterEffects(target, cameraX, cameraY)
	local water = OPT.water
	for _, bubble in ipairs(water.bubbles) do
		local x = math.floor(bubble.x - cameraX + 0.5)
		local y = math.floor(bubble.y - cameraY + 0.5)
		putPixel(target, x, y - 1, water.highlightColor)
		putPixel(target, x - 1, y, water.surfaceColor)
		putPixel(target, x + 1, y, water.surfaceColor)
		putPixel(target, x, y + 1, water.shadowColor)
	end
	for _, drop in ipairs(water.splashes) do
		putPixel(target, math.floor(drop.x - cameraX + 0.5), math.floor(drop.y - cameraY + 0.5), water.highlightColor)
	end
end

function OPT.applyWaterVisuals(target, cameraX, cameraY)
	local water = OPT.water
	if not water.enabled or water.surfaceY == nil then return end
	local waveOffset = math.sin(water.tick * water.waveSpeed) * water.waveAmplitude
	local screenSurfaceY
	if water.levelSpace == "camera" then
		-- Do not subtract cameraY: Level is already expressed in viewport pixels.
		screenSurfaceY = water.baseLevel + waveOffset
	else
		screenSurfaceY = water.surfaceY - cameraY
	end
	local firstTintRow = math.max(0, math.ceil(screenSurfaceY))
	if firstTintRow < HEIGHT then
		local readu32, writeu32 = buffer.readu32, buffer.writeu32
		local extract = bit32.extract
		local lookup = water.tintLookup
		local redLookup, greenLookup, blueLookup = lookup.red, lookup.green, lookup.blue
		for y = firstTintRow, HEIGHT - 1 do
			local offset = y * WIDTH * 4
			for _ = 1, WIDTH do
				local packed = readu32(target, offset)
				local red = redLookup[extract(packed, 0, 8) + 1]
				local green = greenLookup[extract(packed, 8, 8) + 1]
				local blue = blueLookup[extract(packed, 16, 8) + 1]
				writeu32(target, offset, red + green * 256 + blue * 65536 + 0xFF000000)
				offset += 4
			end
		end
	end

	OPT.drawWaterEffects(target, cameraX, cameraY)

	if screenSurfaceY >= -2 and screenSurfaceY < HEIGHT + 2 then
		for x = 0, WIDTH - 1 do
			local ripple = math.floor(math.sin((x + water.tick * 2) * 0.045) * 0.65 + 0.5)
			local y = math.floor(screenSurfaceY + ripple + 0.5)
			local phase = (x + water.tick * 2) % 32
			local color = phase < 12 and water.surfaceColor or water.shadowColor
			putPixel(target, x, y, color)
			if phase < 4 then putPixel(target, x, y - 1, water.highlightColor) end
			if phase >= 20 and phase < 24 then putPixel(target, x, y + 1, water.shadowColor) end
		end
	end

	-- Diagnostic readout makes an off-screen world-space line obvious instead
	-- of making it look as though the line is stuck to the top edge.
	if water.showDebugHud then
		local relation = screenSurfaceY < 0 and "ABOVE VIEW"
			or (screenSurfaceY >= HEIGHT and "BELOW VIEW" or "VISIBLE")
		OPT.drawFrameRect(0, 0, 184, 22, {0, 0, 0})
		OPT.drawFrameText(string.format("WATER %s %.0f", water.levelSpace:upper(), water.baseLevel), 4, 2, WHITE, 29)
		OPT.drawFrameText(string.format("SCREEN %.0f %s", screenSurfaceY, relation), 4, 11, CYAN, 29)
	end
end

function OPT.toggleWater()
	local water = OPT.water
	if water.baseLevel == nil then
		-- A useful preview line for stages without Water metadata. Set an exact
		-- Level in LevelConfig for a persistent, correctly placed stage waterline.
		water.baseLevel = math.floor((water.levelSpace == "camera" and (playerY - cameraY) or playerY) + 8)
		water.configured = false
	end
	water.enabled = not water.enabled
	if not water.enabled then
		water.underwater = false
		table.clear(water.bubbles)
		table.clear(water.splashes)
	else
		water.tick = 0
		OPT.updateWaterSurface()
		OPT.refreshWaterSubmersion()
	end
	local screenY = water.surfaceY and (water.surfaceY - cameraY) or nil
	print(string.format("[WATER] %s | %s Y %.1f | screen Y %.1f | [ / ] or PageUp/PageDown move surface",
		water.enabled and "ON" or "OFF", water.levelSpace:upper(), water.baseLevel or 0, screenY or 0))
end

function OPT.adjustWaterLevel(delta)
	local water = OPT.water
	if water.baseLevel == nil then
		water.baseLevel = math.floor((water.levelSpace == "camera" and (playerY - cameraY) or playerY) + 8)
	end
	water.enabled = true
	water.baseLevel += delta
	OPT.updateWaterSurface()
	OPT.refreshWaterSubmersion()
	local screenY = water.levelSpace == "camera" and water.baseLevel or (water.surfaceY - cameraY)
	print(string.format("[WATER] Surface moved | %s Y %.1f | screen Y %.1f | camera Y %.1f",
		water.levelSpace:upper(), water.baseLevel, screenY, cameraY))
end

function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Return the terrain surface Y and dy/dx at X. Positive slope means
-- the ground falls as X increases; negative slope means it rises.
function getGroundSurface(x)
	if x <= SLOPE_START_X then
		return TRACK_START_Y, 0
	elseif x < SLOPE_BOTTOM_X then
		local span = SLOPE_BOTTOM_X - SLOPE_START_X
		local t = (x - SLOPE_START_X) / span
		local y = TRACK_START_Y
			+ (TRACK_VALLEY_Y - TRACK_START_Y) * smoothstep(t)
		local derivative = (TRACK_VALLEY_Y - TRACK_START_Y)
			* 6 * t * (1 - t) / span
		return y, derivative
	elseif x < SLOPE_UP_END_X then
		local span = SLOPE_UP_END_X - SLOPE_BOTTOM_X
		local t = (x - SLOPE_BOTTOM_X) / span
		local y = TRACK_VALLEY_Y
			+ (TRACK_LOOP_Y - TRACK_VALLEY_Y) * smoothstep(t)
		local derivative = (TRACK_LOOP_Y - TRACK_VALLEY_Y)
			* 6 * t * (1 - t) / span
		return y, derivative
	else
		return TRACK_LOOP_Y, 0
	end
end

function setGroundAngleFromRadians(angle)
	groundAngleRad = angle
	local units = (angle / (2 * math.pi)) * 256
	groundAngle256 = math.floor((units % 256) + 0.5) % 256
end

-- Place Sonic one hitbox half-height along the walkable normal.
function placeGroundPlayer()
	local surfaceY, slope = getGroundSurface(groundTrackX)
	local angle = math.atan(slope)
	setGroundAngleFromRadians(angle)

	playerX = groundTrackX + math.sin(angle) * HEIGHT_RADIUS
	playerY = surfaceY - math.cos(angle) * HEIGHT_RADIUS
end

function placeLoopPlayer()
	-- Surface tangent is theta - 90 degrees. The character's origin
	-- stays inside the loop by half the collision-box height.
	local tangentAngle = loopTheta - math.pi / 2
	setGroundAngleFromRadians(tangentAngle)

	playerX = LOOP_CENTER_X + LOOP_PLAYER_RADIUS * math.cos(loopTheta)
	playerY = LOOP_CENTER_Y + LOOP_PLAYER_RADIUS * math.sin(loopTheta)
end

if not usingRSDKLevel then
	-- Draw gradual slopes and the floor beneath them for the standalone test.
	for x = 0, WIDTH - 1 do
		local surfaceY = getGroundSurface(x)
		local surfaceRow = math.clamp(math.floor(surfaceY + 0.5), 0, HEIGHT - 1)

		for y = 0, HEIGHT - 1 do
			local color
			if y < surfaceRow then
				color = GREEN_BG
			elseif y <= surfaceRow + 1 then
				color = GROUND_TOP
			else
				color = GROUND
			end
			putPixel(basePixels, x, y, color)
		end
	end

	-- Draw a visible circular loop for testing.
	for x = LOOP_CENTER_X - LOOP_RADIUS - 5, LOOP_CENTER_X + LOOP_RADIUS + 5 do
		for y = LOOP_CENTER_Y - LOOP_RADIUS - 5, LOOP_CENTER_Y + LOOP_RADIUS + 5 do
			local dx = x - LOOP_CENTER_X
			local dy = y - LOOP_CENTER_Y
			local distance = math.sqrt(dx * dx + dy * dy)
			local difference = math.abs(distance - LOOP_RADIUS)

			if difference <= 4 then
				putPixel(basePixels, x, y, GROUND)
				if difference <= 1.25 then
					putPixel(basePixels, x, y, GROUND_TOP)
				end
			end
		end
	end
else
	RSDKLevelParser.RenderViewport(activeLevel, activeTileset, basePixels, WIDTH, HEIGHT, 0, 0)
end

-- Sprite rotation: faithful port of Player_HandleGroundRotation /
-- Player_HandleAirRotation from Player.c.
--   groundAngle256: 0..255 per turn. rotationUnits: 0..511 per turn.
function stepGroundRotation()
	local angle = groundAngle256
	if angle <= 0x04 or angle >= 0xFC then
		rotationUnits = 0
		return
	end
	local target = 0
	if angle > 0x10 and angle < 0xE8 then target = angle * 2 end
	local rotate = (target - rotationUnits + 256) % 512 - 256
	local shift = (math.abs(speedX) <= 6) and 2 or 1
	rotationUnits = (rotationUnits + math.floor(rotate / 2 ^ shift)) % 512
end

function stepAirRotation()
	if rotationUnits >= 0x100 then
		if rotationUnits < 0x200 then rotationUnits += 4 else rotationUnits = 0 end
	elseif rotationUnits > 0 then
		rotationUnits -= 4
	else
		rotationUnits = 0
	end
	rotationUnits = math.max(0, rotationUnits) % 512
end

function updateGroundRotation() end
function updateAirRotation() end

--============================================================
-- IDLE / GROUND ANIMATION LOGIC
--============================================================

local minJogVelocity = 4
local minRunVelocity = 6
local minDashVelocity = 12

function handleIdleAnimation()
	if not Anim.Bored1 or not Anim.Bored2 then
		setSpriteAnimation(Anim.Idle, false, 0)
		return
	end

	if playerTimer ~= 720 then
		if playerTimer < 240 then
			playerTimer += 1
			setSpriteAnimation(Anim.Idle, false, 0)
		else
			playerTimer += 1
			if animator.animation == Anim.Bored1 then
				if animator.frameID == 41 then playerTimer = 0 end
			else
				setSpriteAnimation(Anim.Bored1, false, 0)
			end
		end
	else
		if animator.animation == Anim.Bored2 then
			if animator.frameID == 67 then playerTimer = 0 end
		else
			setSpriteAnimation(Anim.Bored2, false, 0)
		end
	end
end

function handleGroundAnimation()
	if skidding > 0 then
		if animator.animation ~= Anim.Skid then
			if animator.animation == Anim.SkidTurn then
				if animator.frameID == #Anim.SkidTurn.frames - 1 then
					facingRight = not facingRight
					skidding = 1
					setSpriteAnimation(Anim.Walk, false, 0)
				end
			else
				setSpriteAnimation(Anim.Skid, false, 0)
				if math.abs(speedX) >= 6 then
					animator.speed = math.abs(speedX) >= 10 and 64 or 144
				else
					skidding -= 8
				end
			end
		else
			if not facingRight then
				if speedX >= 0 and Anim.SkidTurn then
					setSpriteAnimation(Anim.SkidTurn, false, 0)
				end
			elseif speedX <= 0 and Anim.SkidTurn then
				setSpriteAnimation(Anim.SkidTurn, false, 0)
			end
		end
		skidding -= 1
		return
	end

	-- Player_HandleGroundAnimation: once pushing reaches +/-3 the Push clip plays.
	if pushing <= -3 or pushing >= 3 then
		pushing = math.clamp(pushing, -3, 3)
		if Anim.Push then
			setSpriteAnimation(Anim.Push, false, 0)
			return
		end
	end

	if speedX ~= 0 then
		playerTimer = 0
		local velocity = math.abs(speedX)
		local velocityShift = math.floor(velocity * 16)

		if velocity < minJogVelocity then
			if animator.animation == Anim.Jog and animator.frameID == 9 then
				setSpriteAnimation(Anim.Walk, false, 9)
			elseif animator.animation == Anim.AirWalk then
				setSpriteAnimation(Anim.Walk, false, animator.frameID)
			else
				setSpriteAnimation(Anim.Walk, false, 0)
			end
			animator.speed = velocityShift + 48
			minJogVelocity = 4

		elseif velocity < minRunVelocity then
			if animator.animation ~= Anim.Walk or animator.frameID == 3 then
				setSpriteAnimation(Anim.Jog, false, 0)
			end
			animator.speed = velocityShift + 0x40
			minJogVelocity = 3.5
			minRunVelocity = 6

		elseif velocity < minDashVelocity then
			if animator.animation == Anim.Dash or animator.animation == Anim.Run then
				setSpriteAnimation(Anim.Run, false, 0)
			else
				setSpriteAnimation(Anim.Run, false, 1)
			end
			animator.speed = math.min(velocityShift + 0x60, 0x200)
			minRunVelocity = 5.5
			minDashVelocity = 12

		else
			if Anim.Dash then
				if animator.animation == Anim.Dash or animator.animation == Anim.Run then
					setSpriteAnimation(Anim.Dash, false, 0)
				else
					setSpriteAnimation(Anim.Dash, false, 1)
				end
			else
				setSpriteAnimation(Anim.Run, false, 0)
			end
			minDashVelocity = 11.5
		end
	else
		minJogVelocity = 4
		minRunVelocity = 6
		minDashVelocity = 12
		handleIdleAnimation()
	end
end

function updateSkidTrigger(moveLeft, moveRight)
	if not grounded then return end

	if moveLeft and speedX > 4 then
		facingRight = true
		skidding = 24
	elseif moveRight and speedX < -4 then
		facingRight = false
		skidding = 24
	end
end

--============================================================
-- SLOPE / LOOP PHYSICS
--============================================================

function landOnTrack()
	-- Keep the air's horizontal velocity for Drop Dash's direction-sensitive
	-- landing calculation, then project velocity onto the ground tangent.
	landingWorldSpeedX = speedX

	local _, slope = getGroundSurface(playerX)
	local angle = math.atan(slope)
	speedX = speedX * math.cos(angle) + speedY * math.sin(angle)
	speedY = 0
	grounded = true
	onLoop = false

	-- Estimate the surface contact point from the entity origin, then
	-- recalculate once using the terrain normal.
	groundTrackX = math.clamp(playerX - math.sin(angle) * HEIGHT_RADIUS, 0, WIDTH - 1)
	local _, correctedSlope = getGroundSurface(groundTrackX)
	local correctedAngle = math.atan(correctedSlope)
	groundTrackX = math.clamp(playerX - math.sin(correctedAngle) * HEIGHT_RADIUS, 0, WIDTH - 1)

	placeGroundPlayer()
	updateGroundRotation()
end

function tryLandOnLoop(previousX, previousY)
	local dx = playerX - LOOP_CENTER_X
	local dy = playerY - LOOP_CENTER_Y
	local distance = math.sqrt(dx * dx + dy * dy)

	local oldDX = previousX - LOOP_CENTER_X
	local oldDY = previousY - LOOP_CENTER_Y
	local oldDistance = math.sqrt(oldDX * oldDX + oldDY * oldDY)

	-- The player runs on the inside of the circular track. During a jump,
	-- attach when falling back outward across the inner contact radius.
	if oldDistance < LOOP_PLAYER_RADIUS
		and distance >= LOOP_PLAYER_RADIUS
		and (playerX >= LOOP_CENTER_X - LOOP_RADIUS - 4)
		and (playerX <= LOOP_CENTER_X + LOOP_RADIUS + 4)
		and playerY >= previousY then

		local theta = math.atan2(dy, dx)
		if theta > math.pi / 2 then
			theta -= 2 * math.pi
		end

		loopTheta = theta
		loopStartTheta = math.pi / 2
		onLoop = true
		grounded = true

		local tangentAngle = loopTheta - math.pi / 2
		landingWorldSpeedX = speedX
		speedX = speedX * math.cos(tangentAngle) + speedY * math.sin(tangentAngle)
		speedY = 0
		placeLoopPlayer()
		updateGroundRotation()
		return true
	end

	return false
end


function advanceGroundPosition()
	if usingRSDKLevel then
		advanceLevelGroundPosition()
		return
	end

	if onLoop then
		local tangentAngle = loopTheta - math.pi / 2
		setGroundAngleFromRadians(tangentAngle)

		-- Gravity accelerates along the tangent. It speeds Sonic up while
		-- descending and slows him while climbing the loop.
		speedX += SLOPE_GRAVITY * math.sin(tangentAngle)

		local oldTheta = loopTheta
		loopTheta -= speedX / LOOP_PLAYER_RADIUS
		placeLoopPlayer()

		local completed = loopTheta <= loopStartTheta - 2 * math.pi
		local reversedComplete = loopTheta >= loopStartTheta + 2 * math.pi

		if (speedX >= 0 and completed) or (speedX < 0 and reversedComplete) then
			-- Exit at the bottom and continue on the flat track to the right
			-- (or left if a full reverse revolution was completed).
			onLoop = false
			if oldTheta > loopTheta then
				groundTrackX = LOOP_CENTER_X + 0.25
			else
				groundTrackX = LOOP_CENTER_X - 0.25
			end
			loopTheta = math.pi / 2
			placeGroundPlayer()
		end
	else
		local _, slope = getGroundSurface(groundTrackX)
		local angle = math.atan(slope)
		setGroundAngleFromRadians(angle)

		-- Gravity projected onto the tangent (the basic equivalent of
		-- Player_HandleGroundMovement's sin(angle) term).
		speedX += SLOPE_GRAVITY * math.sin(angle)

		local previousTrackX = groundTrackX
		local alongTrackSpeed = speedX
		local nextTrackX = math.clamp(
			groundTrackX + alongTrackSpeed * math.cos(angle),
			10,
			WIDTH - 10
		)

		-- A real ramp does not glue Sonic to the track. Integrate the current
		-- tangent for one step and detach if the new surface falls away far
		-- enough that the projected foot would be clear of it.
		local nextSurfaceY, nextSlope = getGroundSurface(nextTrackX)
		local nextAngle = math.atan(nextSlope)
		local projectedX = playerX + alongTrackSpeed * math.cos(angle)
		local projectedY = playerY + alongTrackSpeed * math.sin(angle)
		local projectedFootY = projectedY + math.cos(nextAngle) * HEIGHT_RADIUS
		local DETACH_GAP = 1.0

		if math.abs(alongTrackSpeed) > 0.05
			and projectedFootY < nextSurfaceY - DETACH_GAP then
			playerX = math.clamp(projectedX, 10, WIDTH - 10)
			playerY = projectedY
			speedX = alongTrackSpeed * math.cos(angle)
			speedY = alongTrackSpeed * math.sin(angle)
			groundTrackX = nextTrackX
			grounded = false
			onLoop = false
			updateAirRotation()
			return
		end

		groundTrackX = nextTrackX

		-- Enter the loop only when crossing its bottom entry while moving right.
		if speedX > 0
			and previousTrackX < LOOP_CENTER_X
			and groundTrackX >= LOOP_CENTER_X then

			groundTrackX = LOOP_CENTER_X
			onLoop = true
			loopTheta = math.pi / 2
			loopStartTheta = loopTheta
			placeLoopPlayer()
		else
			placeGroundPlayer()
		end
	end

	updateGroundRotation()
end

--============================================================
-- REBUILT RSDK PLAYER TILE COLLISION
--
-- This replaces the old imported-level slope/360 code as one system.
-- It follows the supplied Sonic Physics Guide sensor layout:
--   A/B = ground sensors, C/D = ceiling sensors, E/F = push sensors.
-- Grounded sensors rotate through Floor / Right Wall / Roof / Left Wall.
-- Air sensors stay axis-aligned and are selected from the movement quadrant.
-- Tile angles come from TileConfigData via GetSurfaceAngleAtPixel().
--============================================================

local SLOPE_ROLL_UP = 0.078125
local SLOPE_ROLL_DOWN = 0.3125
local PUSH_RADIUS = 10
local GROUND_REACH = 14
local TERMINAL_SPEED_Y = 16
local controlLock = 0

local MODE_FLOOR = 1
local MODE_RIGHT_WALL = 2
local MODE_CEILING = 3
local MODE_LEFT_WALL = 4

-- d points from Sonic into the ground. u is the positive Ground Speed axis.
-- These are the guide's four real sensor coordinate transforms.
local MODE_D = {
	[MODE_FLOOR] = { 0, 1 },
	[MODE_RIGHT_WALL] = { 1, 0 },
	[MODE_CEILING] = { 0, -1 },
	[MODE_LEFT_WALL] = { -1, 0 },
}
local MODE_U = {
	[MODE_FLOOR] = { 1, 0 },
	[MODE_RIGHT_WALL] = { 0, -1 },
	[MODE_CEILING] = { -1, 0 },
	[MODE_LEFT_WALL] = { 0, 1 },
}
local MODE_BASE = {
	[MODE_FLOOR] = 0,
	[MODE_RIGHT_WALL] = -math.pi / 2,
	[MODE_CEILING] = math.pi,
	[MODE_LEFT_WALL] = math.pi / 2,
}

local MODE_NEIGHBOURS = {
	[MODE_FLOOR] = { MODE_RIGHT_WALL, MODE_LEFT_WALL },
	[MODE_RIGHT_WALL] = { MODE_FLOOR, MODE_CEILING },
	[MODE_CEILING] = { MODE_RIGHT_WALL, MODE_LEFT_WALL },
	[MODE_LEFT_WALL] = { MODE_CEILING, MODE_FLOOR },
}

function advanceLevelGroundPosition() end -- assigned after the implementation below

function normalizeAngle(angle)
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

function angleDistance(a, b)
	return math.abs(normalizeAngle(a - b))
end

function ccwHex(angleByte)
	return (256 - (math.floor(angleByte + 0.5) % 256)) % 256
end

function pushModeFromAngleByte(angleByte)
	local angle = ccwHex(angleByte)
	if angle >= 225 or angle <= 31 then
		return MODE_FLOOR
	elseif angle <= 96 then
		return MODE_RIGHT_WALL
	elseif angle <= 159 then
		return MODE_CEILING
	else
		return MODE_LEFT_WALL
	end
end

function modeFromAngleByte(angleByte)
	-- Convert RSDK's clockwise screen-space byte into the guide's
	-- counter-clockwise angle before selecting the sensor orientation.
	local angle = ccwHex(angleByte)
	if angle >= 224 or angle <= 32 then
		return MODE_FLOOR
	elseif angle <= 95 then
		return MODE_RIGHT_WALL
	elseif angle <= 160 then
		return MODE_CEILING
	else
		return MODE_LEFT_WALL
	end
end

function modeFromAngle()
	return modeFromAngleByte(groundAngle256)
end

function senseLevel(x, y, dx, dy, kind, maxIn, maxOut)
	return RSDKLevelParser.Sense(
		activeLevel,
		levelCollisionLayers,
		x,
		y,
		dx,
		dy,
		kind,
		activeLevelConfig.CollisionPlane,
		maxIn or 14,
		maxOut or 16
	)
end

function modeCollisionKind(mode)
	return mode == MODE_FLOOR and "top" or "side"
end

-- A and B are at (+/- WidthRadius, HeightRadius) in local player space.
-- Rotating d/u maps them onto the correct wall/roof positions.
function groundSensorHit(mode, side, kind, maxIn, maxOut)
	local pushMode = pushModeFromAngleByte(groundAngle256)
	local d = MODE_D[pushMode]
	local u = MODE_U[pushMode]
	local sx = playerX + d[1] * HEIGHT_RADIUS + u[1] * WIDTH_RADIUS * side
	local sy = playerY + d[2] * HEIGHT_RADIUS + u[2] * WIDTH_RADIUS * side
	local distance, solidX, solidY = senseLevel(sx, sy, d[1], d[2], kind, maxIn, maxOut)
	if distance == nil then
		return nil
	end
	return distance, solidX, solidY,
		solidX + (d[1] < 0 and 1 or 0),
		solidY + (d[2] < 0 and 1 or 0)
end

function resolveNativeSurfaceAngle(mode, angleByte, hitAX, hitAY, hitBX, hitBY)
	-- Native CollisionMask angles provide the slope, but some exporters store
	-- the same tangent with its direction reversed by 180 degrees. Keep the
	-- native angle's slope while choosing the direction that agrees with the
	-- A-to-B sensor chord (positive Ground Speed direction).
	local geometricAngle
	if hitAX ~= nil and hitBX ~= nil then
		local vx = hitBX - hitAX
		local vy = hitBY - hitAY
		if math.abs(vx) + math.abs(vy) >= 2 then
			geometricAngle = math.atan2(vy, vx)
		end
	end

	if angleByte ~= nil then
		local nativeAngle = normalizeAngle((angleByte % 256) * (2 * math.pi / 256))
		local referenceAngle = geometricAngle or MODE_BASE[mode] or groundAngleRad
		local reversedAngle = normalizeAngle(nativeAngle + math.pi)

		-- The two byte values describe the same physical line, but the wrong
		-- tangent direction reverses downhill gravity and sends movement into
		-- the wrong collision sensors. Resolve that ambiguity consistently.
		if referenceAngle ~= nil
			and angleDistance(reversedAngle, referenceAngle) < angleDistance(nativeAngle, referenceAngle) then
			nativeAngle = reversedAngle
		end
		return nativeAngle
	end
	return geometricAngle or groundAngleRad or MODE_BASE[mode]
end


-- Replace the existing measureGroundSurface() with this version.
-- It keeps the normal left/right probes fast, then performs a one-pixel sweep
-- across Sonic's foot width whenever those probes are not near a contact.
function measureGroundSurface(mode, minDistance, maxDistance, maxIn, maxOut)
	local kind = modeCollisionKind(mode)
	local distA, solidAX, solidAY, contactAX, contactAY = groundSensorHit(mode, -1, kind, maxIn, maxOut)
	local distB, solidBX, solidBY, contactBX, contactBY = groundSensorHit(mode, 1, kind, maxIn, maxOut)

	local validA = distA ~= nil and distA >= minDistance and distA <= maxDistance
	local validB = distB ~= nil and distB >= minDistance and distB <= maxDistance
	local bestDist, bestSolidX, bestSolidY
	local angleContactAX = validA and contactAX or nil
	local angleContactAY = validA and contactAY or nil
	local angleContactBX = validB and contactBX or nil
	local angleContactBY = validB and contactBY or nil

	if validA and validB then
		if distA <= distB then
			bestDist, bestSolidX, bestSolidY = distA, solidAX, solidAY
		else
			bestDist, bestSolidX, bestSolidY = distB, solidBX, solidBY
		end
	elseif validA then
		bestDist, bestSolidX, bestSolidY = distA, solidAX, solidAY
	elseif validB then
		bestDist, bestSolidX, bestSolidY = distB, solidBX, solidBY
	end

	-- A/B only cover the two outer foot columns. A thin collision pixel can
	-- sit between them, so sweep every interior pixel column when the outer
	-- sensors miss or are more than half a pixel away from a secure contact.
	-- The offsets are in local surface space, so this also works on walls and
	-- ceilings without changing the existing sensor orientation.
	if bestDist == nil or math.abs(bestDist) > 0.5 then
		for pixelOffset = -WIDTH_RADIUS + 1, WIDTH_RADIUS - 1 do
			local distance, solidX, solidY, contactX, contactY = groundSensorHit(
				mode,
				pixelOffset / WIDTH_RADIUS,
				kind,
				maxIn,
				maxOut
			)
			if distance ~= nil and distance >= minDistance and distance <= maxDistance then
				if bestDist == nil or distance < bestDist then
					bestDist, bestSolidX, bestSolidY = distance, solidX, solidY
				end

				-- Keep the widest available contact chord for the geometric-angle
				-- fallback used by exporters without a native surface angle.
				if pixelOffset < 0 and angleContactAX == nil then
					angleContactAX, angleContactAY = contactX, contactY
				elseif pixelOffset > 0 then
					angleContactBX, angleContactBY = contactX, contactY
				end
			end
		end
	end

	if bestDist == nil then
		return nil
	end

	local nativeAngleByte = RSDKLevelParser.GetSurfaceAngleAtPixel(
		activeLevel,
		levelCollisionLayers,
		bestSolidX,
		bestSolidY,
		mode,
		activeLevelConfig.CollisionPlane
	)
	local angle = resolveNativeSurfaceAngle(
		mode,
		nativeAngleByte,
		angleContactAX,
		angleContactAY,
		angleContactBX,
		angleContactBY
	)
	return bestDist, bestSolidX, bestSolidY, angle
end


function applyGroundContact(mode, distance, angle)
	local d = MODE_D[mode]
	playerX += d[1] * distance
	playerY += d[2] * distance
	setGroundAngleFromRadians(normalizeAngle(angle or MODE_BASE[mode]))
end

local lastGroundProbeReport = "no ground probe yet"
function snapToGroundMode(preferredMode, minDistance, maxDistance)
	-- The normal path intentionally does not build diagnostic strings or tables.
	-- Ground snapping runs once per movement substep, so logging allocations here
	-- created avoidable garbage every frame even when collision was successful.
	local hitDistance, _, _, angle = measureGroundSurface(
		preferredMode,
		minDistance,
		maxDistance,
		14,
		math.ceil(maxDistance)
	)
	if hitDistance ~= nil then
		applyGroundContact(preferredMode, hitDistance, angle)
		return true
	end

	-- Adjacent modes are probed only after the preferred mode misses, preserving
	-- the seam-bridging behavior while keeping the success path allocation-light.
	local fallbackMode, fallbackDistance, fallbackAngle
	local fallbackScore = math.huge
	local neighbours = MODE_NEIGHBOURS[preferredMode]
	for priority = 1, #neighbours do
		local candidateMode = neighbours[priority]
		local candidateDistance, _, _, candidateAngle = measureGroundSurface(
			candidateMode,
			minDistance,
			maxDistance,
			14,
			math.ceil(maxDistance)
		)
		if candidateDistance ~= nil then
			local angleContinuity = angleDistance(candidateAngle, groundAngleRad)
			local score = angleContinuity * 8 + math.abs(candidateDistance) + priority * 0.01
			if score < fallbackScore then
				fallbackMode = candidateMode
				fallbackDistance = candidateDistance
				fallbackAngle = candidateAngle
				fallbackScore = score
			end
		end
	end

	if fallbackMode then
		applyGroundContact(fallbackMode, fallbackDistance, fallbackAngle)
		return true
	end

	-- This string is consumed only by the rare ground-loss warning.
	lastGroundProbeReport = string.format(
		"M%d and adjacent modes %d/%d had no valid ground contact",
		preferredMode,
		neighbours[1],
		neighbours[2]
	)
	return false
end

function pushSensorGround(stepX, stepY, stepSpeed, mode)
	if stepSpeed == 0 then
		return false, stepX, stepY
	end

	local guideAngle = ccwHex(groundAngle256)
	-- Ground push sensors are active only in the forward-facing half-turn.
	if guideAngle > 64 and guideAngle < 192 then
		return false, stepX, stepY
	end

	local d = MODE_D[mode]
	local u = MODE_U[mode]
	local directionSign = stepSpeed > 0 and 1 or -1
	local lift = (groundAngle256 == 0) and 8 or 0
	local pushX = u[1] * directionSign
	local pushY = u[2] * directionSign
	-- ANTI-CLIP: the original probed ONE pixel row. A one-pixel hole in a thin
	-- collision wall at exactly that row let Sonic pass straight through at
	-- certain angles/speeds. Probe up to three rows (stacked along the body);
	-- extra rows are only sensed when the earlier ones found nothing.
	local distance
	local rows = OPT.groundPushRows
	for rowIndex = 1, #rows do
		-- Rows stay within 3px of Mania's single row: probing near the head would
		-- count low tunnel ceilings as walls.
		local rowLift = lift + rows[rowIndex]
		local sensorX = playerX + stepX + u[1] * PUSH_RADIUS * directionSign + d[1] * rowLift
		local sensorY = playerY + stepY + u[2] * PUSH_RADIUS * directionSign + d[2] * rowLift
		distance = senseLevel(sensorX, sensorY, pushX, pushY, "side", 14, 0)
		if distance ~= nil and distance <= 0 then break end
	end
	if distance ~= nil and distance <= 0 then
		-- Back out of the wall, but never past where this step started. Without
		-- the clamp a tiny forward step that crosses a pixel boundary gets
		-- kicked ~1px backwards every few ticks (visible jitter).
		local along = stepX * pushX + stepY * pushY
		local correction = math.max(distance - 1, -along)
		stepX += pushX * correction
		stepY += pushY * correction
		return true, stepX, stepY
	end
	return false, stepX, stepY
end

function stepGroundedSurface(stepSpeed, totalSpeed)
	local mode = modeFromAngle()
	local angle = groundAngleRad
	local stepX = stepSpeed * math.cos(angle)
	local stepY = stepSpeed * math.sin(angle)
	local blocked, adjustedX, adjustedY = pushSensorGround(stepX, stepY, stepSpeed, mode)
	stepX, stepY = adjustedX, adjustedY

	playerX += stepX
	playerY += stepY

	local maxWorldX = math.max(WIDTH_RADIUS, activeLevel.widthPixels - WIDTH_RADIUS)
	local clampedX = math.clamp(playerX, WIDTH_RADIUS, maxWorldX)
	if clampedX ~= playerX then
		playerX = clampedX
		blocked = true
	end

	if OPT.bridgeStanding then
		-- Standing on a Bridge: the bridge object owns the floor height.
		return blocked and "wall" or nil
	end
	local sensorReach = math.min(math.abs(totalSpeed) + 4, GROUND_REACH)
	if not snapToGroundMode(modeFromAngle(), -GROUND_REACH, sensorReach) then
		return "air"
	end
	return blocked and "wall" or nil
end

function advanceLevelGround()
	local totalSpeed = speedX
	local substeps = math.max(1, math.ceil(math.abs(totalSpeed))) -- <= 1px per step; preserves one-pixel edges
	local stepSpeed = totalSpeed / substeps

	for _ = 1, substeps do
		local result = stepGroundedSurface(stepSpeed, totalSpeed)
		if result == "air" then
			local tangent = groundAngleRad
			speedX = totalSpeed * math.cos(tangent)
			speedY = totalSpeed * math.sin(tangent)
			grounded = false
			warn(string.format(
				"[RSDK COLLISION] Ground lost at %.2f, %.2f | angle=%03d | mode=%d | speed=%.3f | %s",
				playerX,
				playerY,
				groundAngle256,
				modeFromAngle(),
				totalSpeed,
				lastGroundProbeReport
				))
			updateAirRotation()
			return
		elseif result == "wall" then
			speedX = 0
			break
		end
	end
	updateGroundRotation()
end

advanceLevelGroundPosition = advanceLevelGround

-- Landing: the native floor/roof angle is applied before projecting velocity.
function landOnGround(mvx, mvy)
	landingWorldSpeedX = mvx
	local angle = ccwHex(groundAngle256)
	local verticalSign = math.sin(groundAngleRad) >= 0 and 1 or -1
	if math.abs(mvx) > math.abs(mvy) or angle >= 240 or angle <= 15 then
		speedX = mvx
	elseif angle >= 224 or angle <= 32 then
		speedX = mvy * 0.5 * verticalSign
	else
		speedX = mvy * verticalSign
	end
	speedY = 0
	grounded = true
	updateGroundRotation()
end

-- Airborne sensors do not rotate with Sonic. They use world-axis A/B, C/D,
-- and E/F positions, exactly as the guide describes.
function airPushWall(directionX, maxIn)
	local sensorX = playerX + directionX * PUSH_RADIUS
	-- ANTI-CLIP: probe several rows (centre, upper body, head, lower body) so a
	-- one-pixel hole in a thin wall cannot line up with a single sensor row.
	local distance = senseLevel(sensorX, playerY, directionX, 0, "side", maxIn or 14, 0)
	if distance == nil or distance > 0 then
		for _, rowOffset in ipairs(OPT.airPushRows) do
			local rowDistance = senseLevel(sensorX, playerY + rowOffset, directionX, 0, "side", maxIn or 14, 0)
			if rowDistance ~= nil and rowDistance <= 0 then
				distance = rowDistance
				break
			end
		end
	end
	if distance ~= nil and distance <= 0 then
		playerX += directionX * (distance - 1)
		if speedX * directionX > 0 then
			speedX = 0
		end
		return true
	end
	return false
end

function airSurfaceSensors(mode, minDistance, maxDistance, maxIn, maxOut)
	local d = MODE_D[mode]
	local u = MODE_U[mode]
	local kind = modeCollisionKind(mode)

	-- The two primary air sensors are evaluated inline. Returning scalar values
	-- avoids allocating a closure and up to three hit tables on every air probe.
	local sxA = playerX - u[1] * WIDTH_RADIUS + d[1] * HEIGHT_RADIUS
	local syA = playerY - u[2] * WIDTH_RADIUS + d[2] * HEIGHT_RADIUS
	local distA = senseLevel(sxA, syA, d[1], d[2], kind, maxIn, maxOut)
	local sxB = playerX + u[1] * WIDTH_RADIUS + d[1] * HEIGHT_RADIUS
	local syB = playerY + u[2] * WIDTH_RADIUS + d[2] * HEIGHT_RADIUS
	local distB = senseLevel(sxB, syB, d[1], d[2], kind, maxIn, maxOut)

	local validA = distA ~= nil and distA >= minDistance and distA <= maxDistance
	local validB = distB ~= nil and distB >= minDistance and distB <= maxDistance
	local bestDist, bestSolidX, bestSolidY
	if validA then
		local px, py = math.floor(sxA), math.floor(syA)
		local solidX = px + d[1] * distA
		local solidY = py + d[2] * distA
		if not validB or distA <= distB then
			bestDist, bestSolidX, bestSolidY = distA, solidX, solidY
		end
	end
	if validB and (bestDist == nil or distB < bestDist) then
		local px, py = math.floor(sxB), math.floor(syB)
		bestDist = distB
		bestSolidX = px + d[1] * distB
		bestSolidY = py + d[2] * distB
	end

	local contactAX, contactAY, contactBX, contactBY
	if validA then
		local px, py = math.floor(sxA), math.floor(syA)
		contactAX = px + d[1] * distA + (d[1] < 0 and 1 or 0)
		contactAY = py + d[2] * distA + (d[2] < 0 and 1 or 0)
	end
	if validB then
		local px, py = math.floor(sxB), math.floor(syB)
		contactBX = px + d[1] * distB + (d[1] < 0 and 1 or 0)
		contactBY = py + d[2] * distB + (d[2] < 0 and 1 or 0)
	end

	if bestDist == nil then
		-- Centre-column fallback only bridges a gap when both primary sensors miss.
		local sxC = playerX + d[1] * HEIGHT_RADIUS
		local syC = playerY + d[2] * HEIGHT_RADIUS
		local distC = senseLevel(sxC, syC, d[1], d[2], kind, maxIn, maxOut)
		if distC == nil or distC < minDistance or distC > maxDistance then
			return nil
		end
		local px, py = math.floor(sxC), math.floor(syC)
		bestDist = distC
		bestSolidX = px + d[1] * distC
		bestSolidY = py + d[2] * distC
	end

	local nativeAngleByte = RSDKLevelParser.GetSurfaceAngleAtPixel(
		activeLevel,
		levelCollisionLayers,
		bestSolidX,
		bestSolidY,
		mode,
		activeLevelConfig.CollisionPlane
	)
	local angle = resolveNativeSurfaceAngle(
		mode,
		nativeAngleByte,
		validA and contactAX or nil,
		validA and contactAY or nil,
		validB and contactBX or nil,
		validB and contactBY or nil
	)
	return bestDist, angle
end

function applyAirSurfaceContact(mode, distance, angle)
	local d = MODE_D[mode]
	playerX += d[1] * distance
	playerY += d[2] * distance
	setGroundAngleFromRadians(normalizeAngle(angle or MODE_BASE[mode]))
end

function jumpClearanceBlocked()
	-- The C/D ceiling sensors oppose the active ground normal. They rotate
	-- with the grounded collision mode, so jumps on walls/ceilings are checked
	-- in the correct direction too.
	local mode = modeFromAngle()
	local d = MODE_D[mode]
	local u = MODE_U[mode]
	-- Numeric iteration avoids allocating a temporary sides table.
	for side = -1, 1, 2 do
		local sx = playerX - d[1] * HEIGHT_RADIUS + u[1] * WIDTH_RADIUS * side
		local sy = playerY - d[2] * HEIGHT_RADIUS + u[2] * WIDTH_RADIUS * side
		local distance = senseLevel(sx, sy, -d[1], -d[2], "side", 6, 6)
		if distance ~= nil and distance < 6 then
			return true
		end
	end
	return false
end

function resolveAirCollisions(mvx, mvy)
	local absX = math.abs(mvx)
	local absY = math.abs(mvy)
	local horizontalDominant = absX >= absY
	-- RSDK's collision sweeps use a 14px minimum-distance/tolerance window.
	-- Movement is already advanced in one-pixel substeps, so using the whole
	-- frame velocity here only widened the probe and caused early wall/floor hits.
	local maxPenetration = 14

	-- Airborne push sensors are axis-aligned. Horizontal motion checks the
	-- leading side; mostly vertical motion checks both sides.
	if horizontalDominant then
		if mvx > 0 then
			airPushWall(1, 14)
		elseif mvx < 0 then
			airPushWall(-1, 14)
		end
	else
		airPushWall(1, 14)
		airPushWall(-1, 14)
	end

	local horizontalSpeedAfterWalls = speedX

	-- In this canvas Y-positive is down: only downward motion can land on a
	-- floor, and only upward motion can hit a ceiling. This preserves top-only
	-- collision as jump-through terrain.
	if mvy >= 0 then
		local floorDistance, floorAngle = airSurfaceSensors(
			MODE_FLOOR, -maxPenetration, 0, maxPenetration, 0
		)
		if floorDistance ~= nil then
			applyAirSurfaceContact(MODE_FLOOR, floorDistance, floorAngle)
			landOnGround(horizontalSpeedAfterWalls, mvy)
			return true
		end
	elseif mvy < 0 then
		local ceilingDistance, ceilingAngle = airSurfaceSensors(
			MODE_CEILING, -maxPenetration, 0, maxPenetration, 0
		)
		if ceilingDistance ~= nil then
			local contactAngle = ceilingAngle or MODE_BASE[MODE_CEILING]
			local contactByte = math.floor((contactAngle / (2 * math.pi)) * 256 + 0.5) % 256
			local guideCeilingAngle = ccwHex(contactByte)
			-- Guide ceiling-flat range: 136  (66) through 225  (191).
			local flatCeiling = guideCeilingAngle >= 66 and guideCeilingAngle <= 191
			if not flatCeiling and absY >= absX then
				applyAirSurfaceContact(MODE_CEILING, ceilingDistance, contactAngle)
				landingWorldSpeedX = horizontalSpeedAfterWalls
				local verticalSign = math.sin(groundAngleRad) >= 0 and 1 or -1
				speedX = mvy * verticalSign
				speedY = 0
				grounded = true
				updateGroundRotation()
				return true
			end

			-- Flat-ceiling bump: only move Sonic out and cancel vertical speed.
			local d = MODE_D[MODE_CEILING]
			playerX += d[1] * ceilingDistance
			playerY += d[2] * ceilingDistance
			speedY = 0
			return true
		end
	end

	return false
end

function updateLevelPhysicsTick(lockHorizontal, rolling)
	if not usingRSDKLevel or #levelCollisionLayers == 0 then
		return
	end

	local water = OPT.water
	local underwater = water.enabled and water.underwater
	local topSpeed = TOP_SPEED * (underwater and water.groundSpeedScale or 1)
	local groundAccel = ACCEL * (underwater and water.groundAccelScale or 1)
	local groundDecel = DECEL * (underwater and water.groundDecelScale or 1)
	local groundFriction = FRICTION * (underwater and water.groundFrictionScale or 1)
	local rollingFriction = (6 / 256) * (underwater and water.rollingFrictionScale or 1)
	local airAccel = AIR_ACCEL * (underwater and water.airAccelScale or 1)
	local gravity = GRAVITY * (underwater and water.gravityScale or 1)
	local terminalSpeed = TERMINAL_SPEED_Y * (underwater and water.terminalSpeedScale or 1)

	local moveLeft = leftHeld and not rightHeld
	local moveRight = rightHeld and not leftHeld
	if lockHorizontal or OPT.hurtLock > 0 then
		moveLeft = false
		moveRight = false
	end

	if grounded then
		-- Mania stores Ground Speed along the surface tangent. Apply the slope
		-- term in the same branch/order as Player_HandleGroundMovement:
		-- control-lock branch, after input acceleration, or after friction when
		-- moving above the small-speed threshold. Applying it unconditionally
		-- before friction made Sonic creep up to speed while pressed against a wall.
		local angleByte = math.floor(groundAngle256 + 0.5) % 256
		local slopeSine = math.sin(groundAngleRad)
		local slopeForce = SLOPE_GRAVITY * slopeSine
		local wasLocked = controlLock > 0

		if wasLocked then
			controlLock -= 1
			speedX += slopeForce
		elseif rolling then
			local direction = moveRight and 1 or (moveLeft and -1 or 0)
			if direction ~= 0 and speedX * direction < 0 then
				speedX += direction * 0.125
			end
			local friction = math.min(math.abs(speedX), rollingFriction)
			speedX -= speedX > 0 and friction or -friction
			local rollFactor = (speedX * slopeSine < 0) and SLOPE_ROLL_UP or SLOPE_ROLL_DOWN
			speedX += rollFactor * slopeSine
			speedX = math.clamp(speedX, -18, 18)
		else
			updateSkidTrigger(moveLeft, moveRight)
			if moveLeft then
				if speedX > 0 then
					speedX = math.max(0, speedX - groundDecel)
				elseif speedX > -topSpeed then
					speedX = math.max(-topSpeed, speedX - groundAccel)
				end
			elseif moveRight then
				if speedX < 0 then
					speedX = math.min(0, speedX + groundDecel)
				elseif speedX < topSpeed then
					speedX = math.min(topSpeed, speedX + groundAccel)
				end
			else
				local friction = math.min(math.abs(speedX), groundFriction)
				speedX -= speedX > 0 and friction or -friction
				if math.abs(speedX) > 0.125 then
					speedX += slopeForce
				end

				-- The two steep-slope control-lock windows in Mania are narrow;
				-- do not apply a broad angle-based slip/fall range to every slope.
				if ((angleByte > 0xC0 and angleByte < 0xE4)
					or (angleByte > 0x1C and angleByte < 0x40))
					and math.abs(speedX) < 1 then
					controlLock = 30
				end
			end

			if moveLeft or moveRight then
				speedX += slopeForce
				if moveRight and not moveLeft
					and angleByte > 0xC0 and angleByte < 0xE4
					and speedX > -2 and speedX < 2.5 then
					controlLock = 30
				elseif moveLeft and not moveRight
					and angleByte > 0x1C and angleByte < 0x40
					and speedX > -2.5 and speedX < 2 then
					controlLock = 30
				end
			end
		end

		-- Mania lets Sonic detach from walls/ceilings only in its defined
		-- 0x40..0xC0 range when tangent speed falls below 2 px/frame.
		if grounded and modeFromAngle() ~= MODE_FLOOR
			and angleByte >= 0x40 and angleByte <= 0xC0
			and math.abs(speedX) < 2 then
			local tangent = groundAngleRad
			local groundSpeed = speedX
			speedX = groundSpeed * math.cos(tangent)
			speedY = groundSpeed * math.sin(tangent)
			grounded = false
			setGroundAngleFromRadians(0)
		end

		if grounded then
			if math.abs(speedX) < 0.001 then
				speedX = 0
			end
			if skidding <= 0 then
				if speedX < -0.1 then facingRight = false end
				if speedX > 0.1 then facingRight = true end
			end
			advanceLevelGround()
			-- Remember the last position that had valid ground under it.
			if grounded then
				OPT.safeX, OPT.safeY = playerX, playerY
			end
		end
	else
		-- SAFETY NET: if Sonic somehow tunnels out of the level, put him back on
		-- the last solid ground instead of falling forever.
		if OPT.safeX and playerY > activeLevel.heightPixels + 48 then
			playerX, playerY = OPT.safeX, OPT.safeY - 4
			speedX, speedY = 0, 0
			cameraInitialized = false
		end
		if moveLeft then
			facingRight = false
		elseif moveRight then
			facingRight = true
		end
		if moveLeft and speedX > -topSpeed then
			speedX = math.max(-topSpeed, speedX - airAccel)
		end
		if moveRight and speedX < topSpeed then
			speedX = math.min(topSpeed, speedX + airAccel)
		end
		if applyJumpCap and not jumpHeld and speedY < -4 then
			speedY = -4
		end

		local frameVelocityX = speedX
		local frameVelocityY = speedY
		-- One-pixel substeps stop narrow collision profiles being skipped at speed.
		local airSteps = math.max(1, math.ceil(math.max(math.abs(frameVelocityX), math.abs(frameVelocityY))))
		local stepScale = 1 / airSteps
		local collided = false

		for _ = 1, airSteps do
			local stepX = speedX * stepScale
			local stepY = speedY * stepScale
			playerX += stepX
			playerY += stepY
			playerX = math.clamp(
				playerX,
				WIDTH_RADIUS,
				math.max(WIDTH_RADIUS, activeLevel.widthPixels - WIDTH_RADIUS)
			)

			if resolveAirCollisions(frameVelocityX, frameVelocityY) then
				collided = true
				break
			end
		end

		if not collided then
			speedY = math.min(speedY + gravity, terminalSpeed)
			updateAirRotation()
		end
	end
end

--============================================================
-- JUMP / DROP DASH ACTIONS
--============================================================

function actionJump()
	if usingRSDKLevel and grounded and jumpClearanceBlocked() then
		return
	end
	playGameSound("Jump", false)
	setSpriteAnimation(Anim.Jump, false, 0)
	animator.speed = math.min(math.floor(math.abs(speedX) * 40) + 48, 0xF0)

	-- Player_Action_Jump projects ground velocity and jump force onto the
	-- current tangent/normal. This makes jumps work from slopes and loops.
	local takeoffAngle = grounded and groundAngleRad or 0
	local groundSpeed = speedX
	local jumpForce = JUMP_FORCE
	if OPT.water.enabled and OPT.water.underwater then
		jumpForce *= OPT.water.jumpForceScale
	end
	local jumpVelX = groundSpeed * math.cos(takeoffAngle)
		+ jumpForce * math.sin(takeoffAngle)
	local jumpVelY = groundSpeed * math.sin(takeoffAngle)
	- jumpForce * math.cos(takeoffAngle)

	speedX = jumpVelX
	speedY = jumpVelY

	grounded = false
	onLoop = false
	skidding = 0
	applyJumpCap = true
	playerState = "Air"

	-- Player_Action_Jump sets jumpAbilityState to 1. A second midair
	-- press can arm the Drop Dash counter.
	jumpAbilityState = 1
	dropDashReady = false
end

function enterDropDash()
	playerState = "DropDash"
	dropDashReady = true
	playGameSound("DropDash", false)
	setSpriteAnimation(Anim.DropDash, false, 0)
	-- AnimationData includes Dropdash at speed 256. The state below
	-- also increases this by 8 while held, capped at 0x100 as in Player.c.
end

function releaseDropDash()
	playGameSound("AbilityRelease", false)
	-- Drop Dash's contact X speed determines which source-code branch is used,
	-- while speedX is the newly projected ground speed on the landing surface.
	local direction = horizontalInput()
	if direction == 1 then facingRight = true end
	if direction == -1 then facingRight = false end

	local xSpeedAtContact = landingWorldSpeedX
	local slopeContact = math.abs(groundAngleRad) > 0.001

	if facingRight then
		if xSpeedAtContact >= 0 then
			speedX = math.min(
				DROP_DASH_SPEED_CAP,
				DROP_DASH_SPEED + speedX * 0.25
			)
		elseif slopeContact then
			speedX = math.min(
				DROP_DASH_SPEED_CAP,
				DROP_DASH_SPEED + speedX * 0.5
			)
		else
			speedX = DROP_DASH_SPEED
		end
	else
		if xSpeedAtContact <= 0 then
			speedX = math.max(
				-DROP_DASH_SPEED_CAP,
				-DROP_DASH_SPEED + speedX * 0.25
			)
		elseif slopeContact then
			speedX = math.max(
				-DROP_DASH_SPEED_CAP,
				-DROP_DASH_SPEED + speedX * 0.5
			)
		else
			speedX = -DROP_DASH_SPEED
		end
	end

	grounded = true
	if usingRSDKLevel then
		-- RSDK collision already snapped Sonic to the imported level surface.
		-- Do not teleport him onto the standalone test track.
	elseif onLoop then
		placeLoopPlayer()
	else
		groundTrackX = math.clamp(groundTrackX, 10, WIDTH - 10)
		placeGroundPlayer()
	end
	updateGroundRotation()
	setSpriteAnimation(Anim.Jump, false, 0)
	playerState = "Roll"
	jumpAbilityState = 0
	dropDashReady = false
	skidding = 0
	landingWorldSpeedX = speedX
end

function updateDropDash()
	if grounded then
		releaseDropDash()
		return
	end

	if not jumpHeld then
		-- Player_State_DropDash cancels to normal Air if Jump is released
		-- before the charged dropdash reaches the ground.
		jumpAbilityState = 0
		dropDashReady = false
		setSpriteAnimation(Anim.Jump, false, 0)
		playerState = "Air"
		updateLevelPhysicsTick(false, false)
		return
	end

	updateLevelPhysicsTick(false, false)
	animator.speed = math.min(animator.speed + 8, 0x100)
end

function updateAirState(jumpPressed)
	-- Handle the jump ability before this frame's movement/collision,
	-- matching the order in Player_State_Air and Player_JumpAbility_Sonic.
	if not grounded then
		if jumpAbilityState == 1 and jumpPressed then
			-- Second jump press arms the counter at 2.
			jumpAbilityState = 2
			dropDashReady = true
		elseif jumpAbilityState >= 2 and jumpHeld then
			jumpAbilityState += 1

			-- Sonic Mania enters DropDash at state 22: 20 frames after 2.
			if jumpAbilityState >= DROP_DASH_CHARGE_STATE then
				enterDropDash()
			end
		end
	end

	updateLevelPhysicsTick(false, false)

	-- If the threshold was reached on the exact landing frame, preserve the
	-- DropDash state so it can process its landing release on the next tick.
	if grounded and playerState ~= "DropDash" then
		playerState = "Ground"
		jumpAbilityState = 0
		dropDashReady = false
	end
end

function updateRollPhysics(jumpPressed)
	if usingRSDKLevel then
		updateLevelPhysicsTick(false, true)
		animator.speed = math.min(math.floor(math.abs(speedX) * 40) + 48, 0xF0)
		if grounded and jumpPressed then
			actionJump()
		elseif not grounded then
			playerState = "Air"
		elseif math.abs(speedX) < 0.1 then
			speedX = 0
			playerState = "Ground"
		end
		return
	end

	if not grounded then
		updateLevelPhysicsTick(false, true)
		if grounded then
			playerState = "Ground"
		end
		return
	end

	local inputDirection = horizontalInput()
	if inputDirection ~= 0 and speedX * inputDirection < 0 then
		speedX += inputDirection * 0.125
	end

	if speedX > 0 then
		speedX = math.max(0, speedX - 0.125)
	elseif speedX < 0 then
		speedX = math.min(0, speedX + 0.125)
	end

	if math.abs(speedX) < 0.1 then
		speedX = 0
		playerState = "Ground"
	end

	-- Rolling uses the same sloped/loop track projection but retains its
	-- own rolling friction rather than standing friction.
	advanceGroundPosition()
	animator.speed = math.min(math.floor(math.abs(speedX) * 40) + 48, 0xF0)

	if jumpPressed then
		actionJump()
	end
end

function actionSpinDash()
	playGameSound("SpindashCharge", true)
	if Anim.SpinDash then
		setSpriteAnimation(Anim.SpinDash, true, 0)
	else
		setSpriteAnimation(Anim.Jump, true, 0)
	end

	-- Beginning the Spindash always resets Spin Rev to zero.
	spinRev = 0
	playerState = "Spindash"
end

function updateSpindash(jumpPressed)
	-- Each additional Z press adds two revolutions, capped at eight.
	-- A button press adds charge; the intervening charge frames apply drag.
	-- This mirrors the source's charge-or-drag branch structure.
	if jumpPressed then
		spinRev = math.min(SPINDASH_REV_MAX, spinRev + SPINDASH_REV_STEP)

		if Anim.SpinDash then
			setSpriteAnimation(Anim.SpinDash, true, 0)
		end
	else
		-- Spin Rev drag, exactly following the supplied integer-div formula:
		-- spinRev -= ((spinRev div 0.125) / 256)
		local drag = math.floor(spinRev / 0.125) / 256
		spinRev = math.max(0, spinRev - drag)
	end

	-- Releasing Down releases the Spindash. Water has no effect here.
	if not downHeld then
		stopGameLoopSound("SpindashCharge")
		playGameSound("AbilityRelease", false)
		local launchSpeed = SPINDASH_START_SPEED + (math.floor(spinRev) / 2)
		speedX = (facingRight and 1 or -1) * launchSpeed
		setSpriteAnimation(Anim.Jump, false, 0)
		playerState = "Roll"
		skidding = 0
		spinRev = 0
	end
end

--============================================================
-- RSDK / SONIC PHYSICS GUIDE CAMERA (ADAPTED TO THIS CANVAS)
-- The guide describes a 320x224 viewport, while our render canvas is 424x240.
-- Do NOT scale every guide value proportionally: these are world-pixel
-- thresholds and px/frame speed caps, not normalized percentages.
--
-- Horizontal: keep the guide's 16px asymmetric dead border, anchored to the
-- new center. Moving right follows at the canvas center; moving left follows
-- 16px left of center, matching the original 160/144 behavior.
-- Vertical: preserve the guide's default focus 16px above viewport center,
-- with look-up/down focus offsets of +/-8px and a +/-32px airborne dead zone.
-- Frame delays and movement speed caps remain unchanged.
--============================================================

local CAMERA_CENTER_X = WIDTH * 0.5
local CAMERA_CENTER_Y = HEIGHT * 0.5
local CAMERA_BORDER_LEFT = CAMERA_CENTER_X - 16
local CAMERA_BORDER_RIGHT = CAMERA_CENTER_X
local CAMERA_FOCUS_DEFAULT = CAMERA_CENTER_Y - 16
local CAMERA_FOCUS_UP = CAMERA_FOCUS_DEFAULT + 8
local CAMERA_FOCUS_DOWN = CAMERA_FOCUS_DEFAULT - 8
local CAMERA_VERTICAL_BORDER = 32
local cameraFocusY = CAMERA_FOCUS_DEFAULT
local cameraLookInput = 0
local cameraLookHoldFrames = 0

function moveToward(current, target, maxStep)
	local delta = target - current
	if delta > maxStep then return current + maxStep end
	if delta < -maxStep then return current - maxStep end
	return target
end

function updateLevelCamera()
	if not usingRSDKLevel then return end

	local maxCameraX = math.max(0, activeLevel.widthPixels - WIDTH)
	local maxCameraY = math.max(0, activeLevel.heightPixels - HEIGHT)

	if not cameraInitialized then
		cameraX = math.clamp(playerX - CAMERA_BORDER_RIGHT, 0, maxCameraX)
		cameraY = math.clamp(playerY - CAMERA_FOCUS_DEFAULT, 0, maxCameraY)
		cameraInitialized = true
	end

	-- Sonic 2 onwards waits 120 frames before scrolling to the look-up/down focus.
	local requestedLook = 0
	if grounded and playerState == "LookUp" and upHeld then
		requestedLook = -1
	elseif grounded and playerState == "Crouch" and downHeld and math.abs(speedX) < 0.1 then
		requestedLook = 1
	end

	if requestedLook == 0 then
		cameraLookInput = 0
		cameraLookHoldFrames = 0
		cameraFocusY = CAMERA_FOCUS_DEFAULT
	else
		if cameraLookInput ~= requestedLook then
			cameraLookInput = requestedLook
			cameraLookHoldFrames = 0
		end
		if cameraLookHoldFrames < 120 then
			cameraLookHoldFrames += 1
		end
		if cameraLookHoldFrames >= 120 then
			cameraFocusY = requestedLook < 0 and CAMERA_FOCUS_UP or CAMERA_FOCUS_DOWN
		else
			cameraFocusY = CAMERA_FOCUS_DEFAULT
		end
	end

	-- Ground Speed is tangent-relative, not world-horizontal. On walls and
	-- ceilings its sign no longer tells the camera which way Sonic is moving.
	-- Project it into world space before selecting the horizontal follow edge.
	local worldVelocityX, worldVelocityY
	if grounded then
		worldVelocityX = speedX * math.cos(groundAngleRad)
		worldVelocityY = speedX * math.sin(groundAngleRad)
	else
		worldVelocityX = speedX
		worldVelocityY = speedY
	end

	-- Keep the 16px asymmetric horizontal dead zone, but follow the actual
	-- world-space tangent so the camera reverses correctly around a loop.
	local screenX = playerX - cameraX
	local targetCameraX = cameraX
	if worldVelocityX > 0.01 then
		if screenX > CAMERA_BORDER_RIGHT then
			targetCameraX = playerX - CAMERA_BORDER_RIGHT
		end
	elseif worldVelocityX < -0.01 then
		if screenX < CAMERA_BORDER_LEFT then
			targetCameraX = playerX - CAMERA_BORDER_LEFT
		end
	else
		-- At the vertical extrema of a loop, horizontal velocity is near zero.
		-- Still recover the player if it has drifted outside the dead zone.
		if screenX < CAMERA_BORDER_LEFT then
			targetCameraX = playerX - CAMERA_BORDER_LEFT
		elseif screenX > CAMERA_BORDER_RIGHT then
			targetCameraX = playerX - CAMERA_BORDER_RIGHT
		end
	end
	cameraX = moveToward(cameraX, targetCameraX, 16)
	cameraX = math.clamp(cameraX, 0, maxCameraX)

	local targetCameraY = cameraY
	local maxVerticalStep = 16
	if grounded then
		-- On a loop, Ground Speed also has a vertical world component. Drive
		-- camera follow from that component rather than the tangent speed's X
		-- magnitude; this avoids a camera that lags or stalls on the side/top.
		targetCameraY = playerY - cameraFocusY
		if math.abs(cameraFocusY - CAMERA_FOCUS_DEFAULT) > 0.01 then
			maxVerticalStep = 2
		else
			maxVerticalStep = math.clamp(math.abs(worldVelocityY) + 2, 6, 16)
		end
	else
		local screenY = playerY - cameraY
		local topBorder = cameraFocusY - CAMERA_VERTICAL_BORDER
		local bottomBorder = cameraFocusY + CAMERA_VERTICAL_BORDER
		if screenY < topBorder then
			targetCameraY = playerY - topBorder
		elseif screenY > bottomBorder then
			targetCameraY = playerY - bottomBorder
		end
	end
	cameraY = moveToward(cameraY, targetCameraY, maxVerticalStep)
	cameraY = math.clamp(cameraY, 0, maxCameraY)
end

--============================================================
-- DYNAMIC LEVEL LOADING / MENU NAVIGATION
--============================================================
function clearMovementInput()
	leftHeld = false
	rightHeld = false
	upHeld = false
	downHeld = false
	jumpHeld = false
	jumpQueued = false
	debugCycleQueued = false
	debugPlaceQueued = false
end

function setMenuSelection(index)
	if #levelButtonRecords == 0 then
		menuSelectedIndex = 1
		renderLevelSelectToCanvas()
		return
	end
	menuSelectedIndex = ((index - 1) % #levelButtonRecords) + 1
	ManiaMenuPlaySound("mania_menu_choose")
	local record = levelButtonRecords[menuSelectedIndex]
	if record then selectedLevelName = record.Key end
	renderLevelSelectToCanvas()
end

function refreshLevelSelect(preferredName)
	table.clear(levelButtonRecords)
	local levelsFolder = RSDK:FindFirstChild("Levels")
	local stages = {}
	if levelsFolder then
		for _, child in ipairs(levelsFolder:GetDescendants()) do
			if (child:IsA("Folder") or child:IsA("Model"))
				and child:FindFirstChild("SceneData")
				and child:FindFirstChild("TilesetData")
				and child:FindFirstChild("TileConfigData") then
				table.insert(stages, child)
			end
		end
	end
	table.sort(stages, function(a, b)
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	for _, stageFolder in ipairs(stages) do
		table.insert(levelButtonRecords, {
			Key = stageFolder.Name,
			DisplayName = stageFolder.Name,
			Folder = stageFolder,
		})
	end

	if #stages == 0 then
		setMenuStatus("NO STAGES FOUND", true)
	else
		setMenuStatus("SELECT STAGE", false)
	end

	local wanted = preferredName or selectedLevelName
	local foundIndex
	if wanted then
		for i, record in ipairs(levelButtonRecords) do
			if record.Key == wanted then foundIndex = i break end
		end
	end
	menuSelectedIndex = foundIndex or 1
	if ManiaMenu.screen == "StageSelect" then
		renderManiaStageSelectToCanvas()
	end
end

-- ===== Menu system host (the logic lives in the MenuSystem ModuleScript) =====
OPT.menu = nil
OPT.menuAccumulator = 0

function OPT.findEntityData(folder)
	local direct = folder:FindFirstChild("EntityData")
	local holder = direct
	if not holder and folder.Parent then
		holder = folder.Parent:FindFirstChild(folder.Name .. "_EntityData")
	end
	if not holder then return nil end
	if holder:IsA("ModuleScript") then return holder end
	return holder:FindFirstChild("EntityData")
end

function OPT.stopMenu()
	OPT.menu = nil
	menuOpen = true
	ManiaMenu.screen = "StageSelect"
	ManiaMenu.confirmWait = 32
	refreshLevelSelect(selectedLevelName)
	if renderManiaStageSelectToCanvas then renderManiaStageSelectToCanvas() end
end

function OPT.drawMenu()
	local menu = OPT.menu
	if not menu then return end
	menu:render()
	canvasImage:WritePixelsBuffer(CANVAS_ORIGIN, CANVAS_SIZE, framePixels)
end

-- Returns true when `folder` is a menu scene that was started as a menu.
function OPT.tryStartMenu(folder)
	local dataModule = OPT.findEntityData(folder)
	if not dataModule then return false end
	local menuModule = RSDK:FindFirstChild("MenuSystem")
	if not menuModule then
		warn("[MENU] ReplicatedStorage.RSDK.MenuSystem ModuleScript is missing")
		return false
	end
	local ok, rows = pcall(function()
		local raw = decodeAssetBuffer(require(dataModule))
		return game:GetService("HttpService"):JSONDecode(buffer.tostring(raw))
	end)
	if not ok or type(rows) ~= "table" then
		warn("[MENU] Could not read EntityData: " .. tostring(rows))
		return false
	end
	local MenuSystem = require(menuModule)

	-- Menu art: RSDK_MenuSprites (made by the exporter) + the SpriteBank module.
	local sprites = nil
	local bankModule = RSDK:FindFirstChild("SpriteBank")
	local spritesFolder = RSDK:FindFirstChild("RSDK_MenuSprites", true)
		or ReplicatedStorage:FindFirstChild("RSDK_MenuSprites", true)
	if bankModule and spritesFolder then
		local okBank, bankOrError = pcall(function()
			return require(bankModule).new(spritesFolder, { png = PNG, decode = decodeAssetBuffer })
		end)
		if okBank then
			sprites = bankOrError
		else
			warn("[MENU] SpriteBank failed: " .. tostring(bankOrError))
		end
	else
		warn("[MENU] Art not loaded: needs ReplicatedStorage.RSDK.SpriteBank and an imported RSDK_MenuSprites folder")
	end

	local menu = MenuSystem.new(rows, {
		width = WIDTH,
		height = HEIGHT,
		view = { buffer = framePixels, width = WIDTH, height = HEIGHT },
		sprites = sprites,
		draw = {
			rect = function(x, y, w, h, color)
				local x0, y0 = math.max(0, math.floor(x)), math.max(0, math.floor(y))
				local x1, y1 = math.min(WIDTH, math.floor(x + w)), math.min(HEIGHT, math.floor(y + h))
				if x1 > x0 and y1 > y0 then
					OPT.drawFrameRect(x0, y0, x1 - x0, y1 - y0, color)
				end
			end,
			text = function(text, x, y, color)
				OPT.drawFrameText(text, x, y, color)
			end,
		},
		onExit = function() OPT.stopMenu() end,
		onLeaveToTitle = function() OPT.stopMenu() end,
	})
	print(menu:describe())
	if not menu:isUsable() then
		warn("[MENU] No UIControl with UIButtons was found in this scene's EntityData. "
			.. "Re-export with the decomp Objects folder so field names resolve.")
		return false
	end
	OPT.menu = menu
	menuOpen = true
	OPT.menuAccumulator = 0
	OPT.drawMenu()
	print("[MENU] Menu scene running. Arrows/WASD move, Enter selects, Backspace/Esc goes back.")
	return true
end

-- Copy this code into SonicRSDK_LevelParser.luau immediately BEFORE function startLevel(stageFolder).
-- It must be inserted into the existing script, not used as a replacement script.

--============================================================
-- RSDK ANIMATED TILES (DrawAniTiles equivalent)
--
-- A zone's AniTilesData ModuleScript contains one decoded PNG sheet.
-- TileAnimationData optionally describes zone-specific frames. GHZ and CPZ
-- have built-in definitions copied from their Setup_StaticUpdate routines.
--
-- DrawAniTiles copies a rectangular 16x16-tile region from a sprite sheet
-- into consecutive destination tile IDs. This writes those tiles directly
-- into activeTileset.pixels, so the existing renderer/map tile IDs stay intact.
--============================================================

local function makeTileAnimationFrames(sourceY, frameStepY, durations)
	local frames = {}
	for index, duration in ipairs(durations) do
		table.insert(frames, {
			SourceX = 0,
			SourceY = sourceY + (index - 1) * frameStepY,
			Duration = duration,
		})
	end
	return frames
end

local GHZ_TILE_ANIMATION_DATA = {
	SheetModule = "AniTilesData",
	Animations = {
		{
			Name = "GHZ Sunflower",
			DestTile = 427,
			Width = 32,
			Height = 32,
			InitialDuration = 30,
			Frames = makeTileAnimationFrames(0, 32, {30, 2, 2, 2, 30, 2, 2, 2}),
		},
		{
			Name = "GHZ Extend Flower",
			DestTile = 431,
			Width = 32,
			Height = 48,
			InitialDuration = 60,
			Frames = makeTileAnimationFrames(256, 48,
				{120, 2, 2, 2, 8, 2, 2, 2, 120, 2, 2, 2, 8, 2, 2, 2}),
		},
	},
}

local function makeCPZConveyorFrames()
	local frames = {
		{SourceX = 109, SourceY = 48, Duration = 4},
	}
	-- CPZ decrements its 4-bit frame counter, so the frame order is 0, 15..1.
	for frame = 15, 1, -1 do
		table.insert(frames, {SourceX = 109, SourceY = 48 + frame, Duration = 4})
	end
	return frames
end

local CPZ_TILE_ANIMATION_DATA = {
	SheetModule = "ObjectsData",
	Animations = {
		{
			Name = "CPZ Conveyor",
			DestTile = 762,
			Width = 16,
			Height = 16,
			InitialDuration = 4,
			Frames = makeCPZConveyorFrames(),
		},
	},
}

local function copyAniTilesRegion(destinationSheet, sourceSheet, destinationTile,
	sourceX, sourceY, pixelWidth, pixelHeight)
	local tileSize = 16
	local bytesPerPixel = 4
	local rowBytes = tileSize * bytesPerPixel

	destinationTile = tonumber(destinationTile)
	sourceX = tonumber(sourceX)
	sourceY = tonumber(sourceY)
	pixelWidth = tonumber(pixelWidth)
	pixelHeight = tonumber(pixelHeight)
	if not destinationTile or not sourceX or not sourceY or not pixelWidth or not pixelHeight then
		return false, "tile animation has a non-numeric coordinate or size"
	end
	if destinationTile < 0 or destinationTile % 1 ~= 0
		or sourceX < 0 or sourceY < 0 or sourceX % 1 ~= 0 or sourceY % 1 ~= 0
		or pixelWidth <= 0 or pixelHeight <= 0
		or pixelWidth % tileSize ~= 0 or pixelHeight % tileSize ~= 0 then
		return false, "tile animation coordinates must be non-negative and dimensions must be multiples of 16"
	end

	local destinationColumns = math.floor(destinationSheet.width / tileSize)
	local destinationRows = math.floor(destinationSheet.height / tileSize)
	local sourceColumns = math.floor(pixelWidth / tileSize)
	local sourceRows = math.floor(pixelHeight / tileSize)
	if sourceX + pixelWidth > sourceSheet.width or sourceY + pixelHeight > sourceSheet.height then
		return false, string.format("source rectangle (%d,%d %dx%d) exceeds animation sheet %dx%d",
			sourceX, sourceY, pixelWidth, pixelHeight, sourceSheet.width, sourceSheet.height)
	end
	local tileCount = sourceColumns * sourceRows
	if destinationTile + tileCount > destinationColumns * destinationRows then
		return false, string.format("destination tiles %d..%d exceed tileset capacity",
			destinationTile, destinationTile + tileCount - 1)
	end

	local sourcePixels = sourceSheet.pixels
	local destinationPixels = destinationSheet.pixels
	for tileIndex = 0, tileCount - 1 do
		local destinationIndex = destinationTile + tileIndex
		local destinationTileX = (destinationIndex % destinationColumns) * tileSize
		local destinationTileY = math.floor(destinationIndex / destinationColumns) * tileSize
		local sourceTileX = sourceX + (tileIndex % sourceColumns) * tileSize
		local sourceTileY = sourceY + math.floor(tileIndex / sourceColumns) * tileSize

		for row = 0, tileSize - 1 do
			local sourceOffset = ((sourceTileY + row) * sourceSheet.width + sourceTileX) * bytesPerPixel
			local destinationOffset = ((destinationTileY + row) * destinationSheet.width + destinationTileX) * bytesPerPixel
			buffer.copy(destinationPixels, destinationOffset, sourcePixels, sourceOffset, rowBytes)
		end
	end
	return true
end

function loadLevelTileAnimations(stageFolder, animationData)
	print("[AniTiles] Animation loader called!")
	print("[AniTiles] Stage:", stageFolder.Name)
	print("[AniTiles] Animation data:", typeof(animationData))

	table.clear(activeTileAnimations)
	tileAnimationsDirty = false

	if type(animationData) ~= "table" then
		warn("[AniTiles] NO ANIMATION DEFINITIONS FOUND!")
		return 0
	end

	print("[AniTiles] Definitions:", # (animationData.Animations or animationData))

	local definitions = animationData.Animations or animationData
	if type(definitions) ~= "table" then
		warn("[RSDK] TileAnimationData must contain an Animations array")
		return 0
	end

	local sheetCache = {}
	local function getAnimationSheet(moduleName)
		moduleName = tostring(moduleName or "AniTilesData")
		if sheetCache[moduleName] ~= nil then
			return sheetCache[moduleName] ~= false and sheetCache[moduleName] or nil
		end

		local sheetModule = stageFolder:FindFirstChild(moduleName) or RSDK:FindFirstChild(moduleName)
		if not sheetModule or not sheetModule:IsA("ModuleScript") then
			warn(string.format("[RSDK] Animated tiles disabled: ModuleScript '%s' is missing", moduleName))
			sheetCache[moduleName] = false
			return nil
		end

		local okSheet, sheetOrError = pcall(function()
			local sheet = PNG.decode(decodeAssetBuffer(require(sheetModule)))
			assert(sheet.width >= 16 and sheet.height >= 16, "animation sheet is smaller than one tile")
			assert(buffer.len(sheet.pixels) >= sheet.width * sheet.height * 4, "animation sheet pixel buffer is truncated")
			return sheet
		end)
		if not okSheet then
			warn(string.format("[RSDK] Could not decode %s: %s", moduleName, tostring(sheetOrError)))
			sheetCache[moduleName] = false
			return nil
		end
		sheetCache[moduleName] = sheetOrError
		return sheetOrError
	end

	local loaded = 0
	for _, definition in ipairs(definitions) do
		if type(definition) == "table" then
			local frames = definition.Frames
			local destinationTile = tonumber(definition.DestTile or definition.DestinationTile)
			local width = tonumber(definition.Width)
			local height = tonumber(definition.Height)
			if type(frames) == "table" and #frames >= 2 and destinationTile and width and height then
				local sheetName = definition.SheetModule or animationData.SheetModule or "AniTilesData"
				local sheet = getAnimationSheet(sheetName)
				local firstFrame = frames[1]
				if sheet and type(firstFrame) == "table" then
					local firstX = math.floor(tonumber(firstFrame.SourceX or firstFrame.X or definition.SourceX) or 0)
					local firstY = math.floor(tonumber(firstFrame.SourceY or firstFrame.Y or definition.SourceY) or 0)
					local copied, copyError = copyAniTilesRegion(
						activeTileset, sheet, destinationTile, firstX, firstY, width, height
					)
					if copied then
						local loopIndex = math.clamp(math.floor(tonumber(definition.LoopIndex) or 1), 1, #frames)
						table.insert(activeTileAnimations, {
							name = tostring(definition.Name or ("Tile animation " .. tostring(loaded + 1))),
							sheet = sheet,
							destinationTile = destinationTile,
							width = width,
							height = height,
							sourceX = firstX,
							sourceY = firstY,
							frames = frames,
							frameIndex = 1,
							loopIndex = loopIndex,
							frameDuration = math.max(1, tonumber(definition.FrameDuration) or 1),
							timer = math.max(1, tonumber(definition.InitialDuration) or tonumber(firstFrame.Duration) or 1),
						})
						loaded += 1
					else
						warn(string.format("[RSDK] %s was not installed: %s", tostring(definition.Name or "Tile animation"), tostring(copyError)))
					end
				end
			end
		end
	end

	if loaded > 0 then
		tileAnimationsDirty = true
		lastLevelRenderCameraX = nil
		lastCollisionOverlayCameraX = nil
		print(string.format("[RSDK] Loaded %d animated tile groups", loaded))
	end
	return loaded
end

function stepLevelTileAnimations()
	if #activeTileAnimations == 0 then return end
	local changed = false
	for _, animation in ipairs(activeTileAnimations) do
		animation.timer -= 1
		if animation.timer <= 0 then
			local nextIndex = animation.frameIndex + 1
			if nextIndex > #animation.frames then nextIndex = animation.loopIndex end
			local frame = animation.frames[nextIndex]
			local sourceX = math.floor(tonumber(frame.SourceX or frame.X) or animation.sourceX)
			local sourceY = math.floor(tonumber(frame.SourceY or frame.Y) or animation.sourceY)
			local copied, copyError = copyAniTilesRegion(
				activeTileset, animation.sheet, animation.destinationTile,
				sourceX, sourceY, animation.width, animation.height
			)
			if copied then
				animation.frameIndex = nextIndex
				animation.timer = math.max(1, tonumber(frame.Duration) or animation.frameDuration)
				changed = true
			else
				animation.timer = math.huge
				warn(string.format("[RSDK] Disabled %s: %s", animation.name, tostring(copyError)))
			end
		end
	end

	if changed then
		tileAnimationsDirty = true
		lastCollisionOverlayCameraX = nil
	end
end


function startLevel(stageFolder)
	if OPT.tryStartMenu(stageFolder) then return end
	stopGameLoopSound("SpindashCharge")
	ManiaMenuStopMusic()
	local ok, levelOrError, tilesetResult, configResult, collisionLayersResult = pcall(function()
		controlLock = 0
		assert(stageFolder and stageFolder.Parent, "The selected level folder is no longer available")
		local sceneModule = stageFolder:FindFirstChild("SceneData")
		local tilesetModule = stageFolder:FindFirstChild("TilesetData")
		local collisionModule = stageFolder:FindFirstChild("TileConfigData")
		assert(sceneModule and sceneModule:IsA("ModuleScript"), "SceneData ModuleScript is missing")
		assert(tilesetModule and tilesetModule:IsA("ModuleScript"), "TilesetData ModuleScript is missing")
		assert(collisionModule and collisionModule:IsA("ModuleScript"),
			"TileConfigData is missing; this stage cannot load with authentic collision")

		local config = {
			StartX = 96,
			StartY = 80,
			-- Standard Mania foreground pairs can both contain collision. A stage
			-- LevelConfig may replace this with its exact Zone collision layer set.
			CollisionLayerNames = { "FG Low", "FG High" },
			CollisionPlane = 0,
			AutoDetectCollisionPlane = true,
			Water = {Enabled = false},
			AutoDetectCollisionLayers = false,
		}
		local configModule = stageFolder:FindFirstChild("LevelConfig")
		if configModule and configModule:IsA("ModuleScript") then
			local customConfig = require(configModule)
			if type(customConfig) == "table" then
				for key, value in pairs(customConfig) do config[key] = value end
				if customConfig.CollisionLayerName and not customConfig.CollisionLayerNames then
					config.CollisionLayerNames = nil
				end
			end
		end
		if config.SceneParsed == false then
			local warnings = config.ExportWarnings
			local detail = type(warnings) == "table" and table.concat(warnings, " | ") or "The exporter could not normalize this native scene variant."
			error("This scene layout is not decoded yet, so it cannot be previewed. Pick a normalized stage such as GHZ1_Act1 or CPZ1_Act1. " .. detail)
		end

		local parsedLevel = RSDKLevelParser.Parse(require(sceneModule), decodeAssetBuffer)
		for i, layer in ipairs(parsedLevel.layers) do
			print(string.format("[RSDK] layer %d: '%s' %dx%d", i, layer.name, layer.width, layer.height))
		end
		--============================================================
		-- DIAGNOSTISK HASH-SCANNER
		--============================================================
		-- OPTIMIZED: one raw-string comparison per entity at load time (no hex
		-- formatting). Layer switchers are collected once into a compact array
		-- with pre-converted pixel coordinates, so the per-tick pass touches
		-- only those few objects instead of scanning every entity.
		local newSwitchers = {}
		local entityList = parsedLevel.entities
		-- Real PlaneSwitch settings come from the exporter's PlaneSwitchData
		-- module (matched by objectID). Older exports lack it: toggle fallback.
		local planeData = {}
		local planeModule = stageFolder:FindFirstChild("PlaneSwitchData")
		if planeModule and planeModule:IsA("ModuleScript") then
			local okData, rows = pcall(require, planeModule)
			if okData and type(rows) == "table" then
				for _, row in ipairs(rows) do planeData[row.objectID] = row end
			end
		end
		local withData = 0
		for entityIndex = 1, #entityList do
			local entity = entityList[entityIndex]
			if entity.nameHash == OPT.layerSwitcherRaw then
				local row = planeData[entity.objectID]
				if row then withData += 1 end
				table.insert(newSwitchers, OPT.buildSwitcher(entity, row))
			end
		end
		print(string.format("[RSDK] PlaneSwitch: %d found, %d with exported settings, PlaneSwitchData module %s",
			#newSwitchers, withData, planeModule and "PRESENT" or "MISSING (re-export levels)"))
		OPT.pendingLayerSwitchers = newSwitchers

		-- Optional exporter module with Bridge entity settings: rows of
		-- { objectID = n, length = n, burnable = bool }. Without it bridges use length 12.
		local newBridgeData = {}
		local bridgeModule = stageFolder:FindFirstChild("BridgeData")
		if bridgeModule and bridgeModule:IsA("ModuleScript") then
			local okBridge, bridgeRows = pcall(require, bridgeModule)
			if okBridge and type(bridgeRows) == "table" then
				for _, row in ipairs(bridgeRows) do newBridgeData[row.objectID] = row end
			end
		end
		OPT.pendingBridgeData = newBridgeData

		-- Spring properties are not stored in the compact SceneData records.
		-- Optional SpringData rows restore the native type/flip/plane settings by objectID.
		local newSpringData = {}
		local springRows = type(config.SpringData) == "table" and config.SpringData or nil
		local springModule = stageFolder:FindFirstChild("SpringData") or RSDK:FindFirstChild("SpringData")
		if springModule and springModule:IsA("ModuleScript") then
			local okSpring, rows = pcall(require, springModule)
			if okSpring and type(rows) == "table" then springRows = rows
			else warn("[RSDK] SpringData could not be read: " .. tostring(rows)) end
		end
		if springRows then
			for key, row in pairs(springRows) do
				if type(row) == "table" then
					local objectID = tonumber(row.objectID or key)
					if objectID then newSpringData[objectID] = row end
				end
			end
		end
		OPT.pendingSpringData = newSpringData
		local springDataCount = 0
		for _ in pairs(newSpringData) do springDataCount += 1 end
		if springDataCount == 0 then
			warn("[RSDK] SpringData has no exported rows; Springs default to upward yellow (type=0, flipFlag=0). Add SpringData rows to configure red/horizontal/diagonal variants.")
		end

		-- Optional DDWreckerData rows may override the default total boss health.
		local newDDWreckerData = {}
		local ddModule = stageFolder:FindFirstChild("DDWreckerData") or RSDK:FindFirstChild("DDWreckerData")
		if ddModule and ddModule:IsA("ModuleScript") then
			local okDD, rows = pcall(require, ddModule)
			if okDD and type(rows) == "table" then
				for key, row in pairs(rows) do
					if type(row) == "table" then
						local objectID = tonumber(row.objectID or key)
						if objectID then newDDWreckerData[objectID] = row end
					end
				end
			else warn("[RSDK] DDWreckerData could not be read: " .. tostring(rows)) end
		end
		OPT.pendingDDWreckerData = newDDWreckerData

		local decodedTileset = PNG.decode(decodeAssetBuffer(require(tilesetModule)))
		local p = decodedTileset.pixels
		print(string.format("[RSDK] Tileset pixel (0,0) = %02X%02X%02X alpha %d",
			buffer.readu8(p, 0), buffer.readu8(p, 1), buffer.readu8(p, 2), buffer.readu8(p, 3)))
		local keyed = applyColorKey(decodedTileset, 0xFF, 0x00, 0xFE, 2)
		if keyed == 0 then
			-- Fallback: RSDK tile 0 is fully transparent, so use its corner pixel as the key.
			keyed = applyColorKey(decodedTileset, buffer.readu8(p, 0), buffer.readu8(p, 1), buffer.readu8(p, 2), 0)
			warn("[RSDK] FF00FE not found in tileset; keyed using tile 0's corner color instead")
		end
		print("[RSDK] Tileset pixels made transparent: " .. keyed)

		assert(decodedTileset.width >= 16 and decodedTileset.height >= 16, "Tileset must contain 16x16 tiles")
		assert(decodedTileset.width % 16 == 0 and decodedTileset.height % 16 == 0,
			"Tileset dimensions must be multiples of 16")

		local collisionResult = RSDKLevelParser.ParseTileConfig(require(collisionModule), decodeAssetBuffer)
		assert(collisionResult and collisionResult.version == 4,
			"TileConfigData is not a valid native collision profile table; refusing to invent block collision")
		parsedLevel.tileConfig = collisionResult

		local collisionPlane = tonumber(config.CollisionPlane) or 0
		collisionPlane = collisionPlane == 1 and 1 or 0
		local requestedLayers = config.CollisionLayerNames or config.CollisionLayerName
		local autoDetectPlane = config.AutoDetectCollisionPlane ~= false
		local autoDetectLayers = config.AutoDetectCollisionLayers == true

		local collisionLayers = RSDKLevelParser.FindCollisionLayers(
			parsedLevel, requestedLayers, collisionPlane
		)

		-- A stage may store its collision flags on the other TileConfig plane.
		-- Retry the SAME configured layer set only; do not silently expand the
		-- layer mask while changing planes.
		if #collisionLayers == 0 and autoDetectPlane then
			local alternatePlane = collisionPlane == 0 and 1 or 0
			local alternateLayers = RSDKLevelParser.FindCollisionLayers(
				parsedLevel, requestedLayers, alternatePlane
			)
			if #alternateLayers > 0 then
				warn(string.format(
					"[RSDK] %s has no flagged tiles in configured layer(s) on plane %d; auto-selecting plane %d.",
					stageFolder.Name, collisionPlane, alternatePlane
					))
				collisionPlane = alternatePlane
				collisionLayers = alternateLayers
			end
		end

		-- Layer discovery can be enabled per stage for unusual layer names, but
		-- is OFF by default: arbitrary foreground layers with solidity bits are
		-- not necessarily part of Mania's Zone->collisionLayers mask.
		-- Fallback: configured names matched nothing, so discover layers by solidity bits.
		if #collisionLayers == 0 then
			for _, plane in ipairs({collisionPlane, collisionPlane == 0 and 1 or 0}) do
				local found = RSDKLevelParser.FindAnyCollisionLayers(parsedLevel, plane)
				if #found == 0 then
					-- Last resort: any layer at all with solidity bits, even if named oddly.
					for _, layer in ipairs(parsedLevel.layers) do
						local one = RSDKLevelParser.FindCollisionLayers(parsedLevel, layer.name, plane)
						if #one > 0 then table.insert(found, layer) end
					end
				end
				if #found > 0 then
					collisionPlane = plane
					collisionLayers = found
					warn(string.format(
						"[RSDK] %s: configured layers [%s] had no solidity; auto-selected plane %d layers. Verify against Zone->collisionLayers.",
						stageFolder.Name, tostring(requestedLayers), plane))
					break
				end
			end
		end

		if #collisionLayers == 0 then
			local diagnostics = RSDKLevelParser.GetCollisionLayerDiagnostics(parsedLevel)
			local requestedText
			if type(requestedLayers) == "table" then
				requestedText = table.concat(requestedLayers, ", ")
			else
				requestedText = tostring(requestedLayers or "(none)")
			end
			error(string.format(
				"No collision flags found in configured layer(s) [%s] on plane %d%s. Set LevelConfig.CollisionLayerNames to the exact layer set used by this stage's Zone->collisionLayers mask, or enable AutoDetectCollisionLayers only for diagnosis. %s",
				requestedText, collisionPlane,
				autoDetectPlane and " or its alternate plane" or "",
				diagnostics
				))
		end

		config.CollisionPlane = collisionPlane
		return parsedLevel, decodedTileset, config, collisionLayers
	end)

	if not ok then
		warn("[RSDK] Failed to load " .. tostring(stageFolder and stageFolder.Name) .. ": " .. tostring(levelOrError))
		setMenuStatus("Couldn't load " .. tostring(stageFolder and stageFolder.Name) .. ": " .. tostring(levelOrError), true)
		menuOpen = true
		ManiaMenu.screen = "StageSelect"
		canvasLabel.Visible = true
		renderManiaStageSelectToCanvas()
		return
	end

	OPT.layerSwitchers = OPT.pendingLayerSwitchers
	OPT.bridgeData = OPT.pendingBridgeData
	OPT.springData = OPT.pendingSpringData or {}
	OPT.ddwreckerData = OPT.pendingDDWreckerData or {}
	OPT.pimPomData = OPT.loadDataRows(stageFolder, "PimPomData")
	OPT.invincible, OPT.hurtLock, OPT.bridgeStanding = 0, 0, false
	table.clear(OPT.fx)
	OPT.pendingLayerSwitchers = {}
	OPT.safeX, OPT.safeY = nil, nil
	activeLevel = levelOrError
	activeTileset = tilesetResult
	activeLevelConfig = configResult
	levelCollisionLayers = collisionLayersResult
	levelCollisionLayer = levelCollisionLayers[1]
	usingRSDKLevel = true
	OPT.configureWater(activeLevelConfig, activeLevel)
	local collisionLayerNames = {}
	for _, layer in ipairs(levelCollisionLayers) do
		table.insert(collisionLayerNames, layer.name)
	end
	print("[RSDK] Collision layer(s): " .. table.concat(collisionLayerNames, ", ")
		.. " | plane " .. tostring(activeLevelConfig.CollisionPlane or 0))
	selectedLevelName = stageFolder.Name

	local startX = tonumber(activeLevelConfig.StartX) or 96
	local startY = tonumber(activeLevelConfig.StartY) or 80
	-- Use the scene's own Player entity as the spawn point. Falls back to the
	-- LevelConfig start only if the scene has no Player object.
	local sceneStartX, sceneStartY = findScenePlayerStart(activeLevel)
	if sceneStartX then
		startX, startY = sceneStartX, sceneStartY
		print(string.format("[RSDK] Spawning at scene Player entity (%.1f, %.1f)", startX, startY))
	else
		warn(string.format("[RSDK] No Player entity found in scene; using fallback start (%d, %d)", startX, startY))
	end
	playerX = startX
	playerY = startY
	groundTrackX = startX
	debugMode = false
	debugCursorX = startX
	debugCursorY = startY
	debugSelectedIndex = 1
	table.clear(debugObjects)
	speedX = 0
	speedY = 0
	grounded = false
	onLoop = false
	loopTheta = math.pi / 2
	loopStartTheta = loopTheta
	landingWorldSpeedX = 0
	jumpAbilityState = 0
	dropDashReady = false
	skidding = 0
	spinRev = 0
	playerTimer = 0
	facingRight = true
	playerState = "Air"
	cameraX = 0
	cameraY = 0
	cameraInitialized = false
	lastLevelRenderCameraX = nil
	lastLevelRenderCameraY = nil
	lastLevelRenderFrame = nil
	backgroundScrollFrame = 0
	lastCollisionOverlayCameraX = nil
	lastCollisionOverlayCameraY = nil
	lastCollisionOverlayLevel = nil
	lastCollisionOverlayLayers = nil
	lastCollisionOverlayPlane = nil
	cameraFocusY = CAMERA_FOCUS_DEFAULT
	cameraLookInput = 0
	cameraLookHoldFrames = 0
	setGroundAngleFromRadians(0)
	rotationUnits = 0
	updateAirRotation()
	clearMovementInput()
	setSpriteAnimation(Anim.Jump, true, 0)
	ringCount = 0
	table.clear(ringPickupEffects)
	OPT.resetHUD()
	OPT.beginTitleCard(activeLevelConfig, stageFolder.Name)

	spawnLevelEntities(activeLevel)
	if ManiaMenu.music and ManiaMenu.music.Parent then
		ManiaMenu.music:Stop()
		ManiaMenu.music:Destroy()
		ManiaMenu.music = nil
	end

	menuOpen = false
	canvasLabel.Visible = true
	updateLevelCamera()
	render()
	print(string.format("[RSDK] Loaded %s: %d layers, %d entities, %dx%d tiles; native TileConfig profiles loaded",
		stageFolder.Name, #activeLevel.layers, #activeLevel.entities, activeLevel.widthTiles, activeLevel.heightTiles))
end

function openLevelMenu()
	clearMovementInput()
	stopGameLoopSound("SpindashCharge")
	menuOpen = true
	OPT.menu = nil
	ManiaMenu.screen = "Main"
	ManiaMenu.selected = 0
	ManiaMenu.selectedTimer = 0
	ManiaMenu.selectedTimer2 = 0
	ManiaMenu.selectedOffset = 0
	ManiaMenu.scrollOffset = 0
	ManiaMenu.confirmWait = 32
	ManiaMenu.frame = 0
	ManiaMenu.menuAccumulator = 0
	ManiaMenuPlaySound("mania_menu", true)
	canvasLabel.Visible = true
	refreshLevelSelect(selectedLevelName)
	renderManiaMainMenuToCanvas()
end

--============================================================
-- PLAYER STATE MACHINE
--============================================================

function updateDebugModeTick()
	-- Sonic himself is the free cursor: he flies around, and when debug mode
	-- ends he simply drops from wherever he is (no teleport back to the start).
	local moveX = (rightHeld and 1 or 0) - (leftHeld and 1 or 0)
	local moveY = (downHeld and 1 or 0) - (upHeld and 1 or 0)
	local magnitude = math.sqrt(moveX * moveX + moveY * moveY)
	if magnitude > 0 then
		moveX /= magnitude
		moveY /= magnitude
		OPT.debugHold = math.min((OPT.debugHold or 0) + 1, 90)
		if moveX ~= 0 then facingRight = moveX > 0 end
	else
		OPT.debugHold = 0
	end
	local speed = DEBUG_CURSOR_SPEED + (OPT.debugHold or 0) * 0.12

	local maxX = usingRSDKLevel and math.max(0, activeLevel.widthPixels - 1) or (WIDTH - 1)
	local maxY = usingRSDKLevel and math.max(0, activeLevel.heightPixels - 1) or (HEIGHT - 1)
	playerX = math.clamp(playerX + moveX * speed, 0, maxX)
	playerY = math.clamp(playerY + moveY * speed, 0, maxY)
	groundTrackX = playerX
	speedX, speedY = 0, 0
	grounded = false
	debugCursorX, debugCursorY = playerX, playerY

	setSpriteAnimation(Anim.Idle, false, 0)
	rotationUnits = 0
	processAnimation()

	if debugCycleQueued then
		debugSelectedIndex = (debugSelectedIndex % #debugObjectTypes) + 1
		debugCycleQueued = false
	end



	if debugPlaceQueued then
		local selected = debugObjectTypes[debugSelectedIndex]
		local kind = selected.Kind

		print("[DEBUG SPAWN] Selected:", selected.Name)
		print("[DEBUG SPAWN] Kind:", kind)
		print("[DEBUG SPAWN] Registry exists:", objectRegistry[kind] ~= nil)

		if kind == "PimPom" then
			local before = #activeEntities

			local ok, result = pcall(function()
				return OPT.spawnEntity(
					"PimPom",
					playerX,
					playerY,
					selected.Extra or {
						ppType = 0,
						color = 0
					}
				)
			end)

			if not ok then
				warn("[PIMPOM SPAWN ERROR] " .. tostring(result))

			elseif not result then
				warn("[PIMPOM SPAWN FAILED] Registry missing")

			else
				print("[PIMPOM SPAWN SUCCESS]")
				print("Type:", result.ppType)
				print("State:", tostring(result.state))
				print("Entities before:", before)
				print("Entities after:", #activeEntities)
			end

		elseif kind == "Motobug" or kind == "Bridge"
			or (kind == "Ring" and ringSpriteSheet) then

			local extra = kind == "Bridge" and {length = 12} or nil
			OPT.spawnEntity(kind, playerX, playerY, extra)

		else
			table.insert(debugObjects, {
				Kind = kind,
				X = playerX,
				Y = playerY
			})
		end

		debugPlaceQueued = false
	end



	if usingRSDKLevel then
		local maxCameraX = math.max(0, activeLevel.widthPixels - WIDTH)
		local maxCameraY = math.max(0, activeLevel.heightPixels - HEIGHT)
		cameraX = moveToward(cameraX, playerX - WIDTH * 0.5, 12)
		cameraY = moveToward(cameraY, playerY - HEIGHT * 0.5, 12)
		cameraX = math.clamp(cameraX, 0, maxCameraX)
		cameraY = math.clamp(cameraY, 0, maxCameraY)
	end
end

--============================================================
-- EXAKT HEX-MATCHAD LAYER SWITCHER F R STUDIOPOLIS
--============================================================
-- Mania PlaneSwitch port. With exported settings the lane comes from which
-- side of the (rotated) line Sonic is on once his velocity is added. Levels
-- exported before PlaneSwitchData existed fall back to flipping the lane each
-- time Sonic crosses a switcher.
function processLayerSwitchers()
	if not usingRSDKLevel then return end
	local switchers = OPT.layerSwitchers
	local count = #switchers
	if count == 0 then return end

	local vx = grounded and speedX * math.cos(groundAngleRad) or speedX
	local px, py = playerX, playerY
	for i = 1, count do
		local sw = switchers[i]
		local relX = px - sw.x
		local relY = py - sw.y
		local reach = sw.reach
		local inside = false
		local localX = 0
		if relX <= reach and relX >= -reach and relY <= reach and relY >= -reach then
			local c, s = sw.cos, sw.sin
			localX = relX * c + relY * s
			local localY = relY * c - relX * s
			inside = localX < 24 and localX > -24
				and localY < sw.halfLength and localY > -sw.halfLength
		end

		if inside then
			if sw.planeRight ~= nil then
				if not sw.groundOnly or grounded then
					local wanted = (localX + vx >= 0) and sw.planeRight or sw.planeLeft
					if activeLevelConfig.CollisionPlane ~= wanted then
						activeLevelConfig.CollisionPlane = wanted
						lastCollisionOverlayPlane = nil
					end
				end
			else
				local side = localX >= 0 and 1 or -1
				if sw.lastSide ~= nil and sw.lastSide ~= side then
					activeLevelConfig.CollisionPlane = (activeLevelConfig.CollisionPlane == 1) and 0 or 1
					lastCollisionOverlayPlane = nil
				end
				sw.lastSide = side
			end
		else
			sw.lastSide = nil
		end
	end
end

function simulationTick()
	backgroundScrollFrame += 1
	if OPT.comp and OPT.comp.eliminated then return end
	OPT.stepWater()
	OPT.stepBubbles()
	if OPT.titleCard.active then
		-- Mania restores the regular engine state as soon as the 60-frame hold
		-- ends. Gameplay therefore resumes while the coloured strips slide away.
		if OPT.titleCard.phase ~= "slideAway" then
			clearMovementInput()
			OPT.updateTitleCard()
			return
		end
		OPT.updateTitleCard()
	end
	OPT.hud.ticks += 1
	if OPT.invincible > 0 then OPT.invincible -= 1 end
	if OPT.hurtLock > 0 then
		if grounded then OPT.hurtLock = 0 else OPT.hurtLock -= 1 end
	end
	if debugMode then
		speedY = 0
		updateDebugModeTick()
		return
	end

	-- H R L GGER DU TILL RADEN:
	processLayerSwitchers()

	local jumpPressed = jumpQueued
	jumpQueued = false


	if playerState == "Air" then
		updateAirState(jumpPressed)

	elseif playerState == "DropDash" then
		updateDropDash()

	elseif playerState == "Roll" then
		updateRollPhysics(jumpPressed)

	elseif playerState == "Spindash" then
		updateSpindash(jumpPressed)

	elseif playerState == "LookUp" then
		updateLevelPhysicsTick(upHeld, false)

		if not grounded then
			playerState = "Air"
		elseif upHeld then
			setSpriteAnimation(Anim.LookUp, false, 1)
			if animator.frameID == 5 then animator.speed = 0 end
			if playerTimer < 60 then playerTimer += 1 end
			if jumpPressed then actionJump() end
		else
			animator.speed = 64
			if animator.frameID == 0 or leftHeld or rightHeld then
				playerState = "Ground"
			end
			if jumpPressed then actionJump() end
		end

	elseif playerState == "Crouch" then
		updateLevelPhysicsTick(true, false)

		if not grounded then
			playerState = "Air"
		elseif downHeld then
			setSpriteAnimation(Anim.Crouch, false, 1)
			if animator.frameID == 4 then animator.speed = 0 end
			if playerTimer < 60 then playerTimer += 1 end
			if jumpPressed then actionSpinDash() end
		else
			animator.speed = 128
			if animator.frameID == 0 or leftHeld or rightHeld then
				playerState = "Ground"
			end
			if jumpPressed then actionJump() end
		end

	else -- Ground
		-- Port of the pushing counter in Player_State_Ground.
		if grounded then
			if speedX == 0 then
				if leftHeld then pushing -= 1
				elseif rightHeld then pushing += 1
				else pushing = 0 end
			else
				if not leftHeld and not rightHeld then
					pushing = 0
				elseif math.abs(speedX) > 1 then
					pushing = 0
				end
			end
			if modeFromAngle() ~= MODE_FLOOR then pushing = 0 end -- floor mode only
		end
		updateLevelPhysicsTick(false, false)

		if not grounded then
			playerState = "Air"
		else
			handleGroundAnimation()

			if jumpPressed then
				playerTimer = 0
				actionJump()
			elseif speedX ~= 0 then
				-- Down while rolling at speed enters the rolling state.
				if math.abs(speedX) >= 0.55 and horizontalInput() == 0 and downHeld then
					setSpriteAnimation(Anim.Jump, false, 0)
					playerState = "Roll"
				end
			else
				if upHeld then
					setSpriteAnimation(Anim.LookUp, true, 1)
					playerTimer = 0
					playerState = "LookUp"
				elseif downHeld then
					setSpriteAnimation(Anim.Crouch, true, 1)
					playerTimer = 0
					playerState = "Crouch"
				end
			end
		end
	end

	if grounded then applyJumpCap = false end
	if playerState ~= "Ground" or not grounded then pushing = 0 end
	if grounded then stepGroundRotation() else stepAirRotation() end
	processAnimation()
	updateLevelCamera()
	if OPT.water.enabled then
		OPT.updateWaterSurface()
		OPT.refreshWaterSubmersion()
	end
end

--============================================================
-- INPUT
--============================================================

UserInputService.InputBegan:Connect(function(input, processed)
	local key = input.KeyCode
	if menuOpen and input.UserInputType == Enum.UserInputType.Gamepad2 then
		if not processed and key == Enum.KeyCode.ButtonStart then
			ManiaMenuStartPlayerTwoPreview()
		end
		-- The second controller drives the preview Sonic, not the menu cursor.
		return
	end

	if menuOpen and not processed and input.UserInputType.Name:find("Gamepad") then
		if key == Enum.KeyCode.DPadUp then
			if ManiaMenu.screen == "Main" then ManiaMenuNavigateMain(-1)
			elseif ManiaMenu.screen == "StageSelect" then setMenuSelection(menuSelectedIndex - 1)
			elseif ManiaMenu.screen == "Extras" then ManiaMenuNavigateExtras(-1)
			elseif ManiaMenu.screen == "Competition" then ManiaMenuCompetitionMove(-1) end
			return
		elseif key == Enum.KeyCode.DPadDown then
			if ManiaMenu.screen == "Main" then ManiaMenuNavigateMain(1)
			elseif ManiaMenu.screen == "StageSelect" then setMenuSelection(menuSelectedIndex + 1)
			elseif ManiaMenu.screen == "Extras" then ManiaMenuNavigateExtras(1)
			elseif ManiaMenu.screen == "Competition" then ManiaMenuCompetitionMove(1) end
			return
		elseif key == Enum.KeyCode.DPadLeft then

			if ManiaMenu.screen == "Competition" then ManiaMenuCompetitionAdjust(-1) end
			return
		elseif key == Enum.KeyCode.DPadRight then
			if ManiaMenu.screen == "Competition" then ManiaMenuCompetitionAdjust(1) end
			return
		elseif key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.ButtonStart then
			ManiaMenuConfirm()
			return
		elseif key == Enum.KeyCode.ButtonB then
			ManiaMenuBack()
			return
		end
	end

	if key == Enum.KeyCode.Q and not processed then
		if not menuOpen then
			debugMode = not debugMode
			clearMovementInput()

			if debugMode then
				-- Hide Sonic and freeze his physics at the exact position where
				-- debug mode was entered. The free cursor starts there.
				speedX, speedY = 0, 0
				grounded = false
				onLoop = false
				playerState = "Air"
				OPT.bridgeStanding = false
				OPT.debugHold = 0
				debugCursorX = playerX
				debugCursorY = playerY
				print("[RSDK] Debug mode ON: you fly as Sonic. Arrows/WASD move, Z cycles, Space places, Q exits")
			else
				-- Resume Sonic without any stored downward velocity from before
				-- debug mode. Sonic stays exactly where he is and drops from there.
				speedX, speedY = 0, 0
				grounded = false
				onLoop = false
				groundTrackX = playerX
				playerState = "Air"
				jumpAbilityState = 0
				dropDashReady = false
				skidding = 0
				pushing = 0
				controlLock = 0
				setGroundAngleFromRadians(0)
				setSpriteAnimation(Anim.Jump, true, 0)
				OPT.debugHold = 0

				-- Debug navigation can move the level camera far away from Sonic.
				-- Snap it back so Sonic is visible immediately after Q is pressed.
				if usingRSDKLevel and activeLevel then
					local maxCameraX = math.max(0, activeLevel.widthPixels - WIDTH)
					local maxCameraY = math.max(0, activeLevel.heightPixels - HEIGHT)
					cameraX = math.clamp(playerX - CAMERA_BORDER_RIGHT, 0, maxCameraX)
					cameraY = math.clamp(playerY - CAMERA_FOCUS_DEFAULT, 0, maxCameraY)
					cameraInitialized = true
					cameraFocusY = CAMERA_FOCUS_DEFAULT
					cameraLookInput = 0
					cameraLookHoldFrames = 0
					lastLevelRenderCameraX = nil
					lastLevelRenderCameraY = nil
				end

				print("[RSDK] Debug mode OFF")
			end

			if render then render() end
		end
		return
	end

	if key == Enum.KeyCode.F4 and not processed then
		if not menuOpen and usingRSDKLevel then
			OPT.toggleWater()
			if render then render() end
		else
			print("[WATER] Load a level first; F4 toggles the water test/effect")
		end
		return
	end

	if (key == Enum.KeyCode.LeftBracket or key == Enum.KeyCode.RightBracket
		or key == Enum.KeyCode.PageUp or key == Enum.KeyCode.PageDown) and not processed then
		if not menuOpen and usingRSDKLevel then
			local moveUp = key == Enum.KeyCode.LeftBracket or key == Enum.KeyCode.PageUp
			OPT.adjustWaterLevel(moveUp and -8 or 8)
			if render then render() end
		end
		return
	end

	if key == Enum.KeyCode.F3 and not processed then
		if not menuOpen and usingRSDKLevel then
			showCollisionOverlay = not showCollisionOverlay
			lastCollisionOverlayCameraX = nil
			lastCollisionOverlayCameraY = nil
			lastCollisionOverlayLevel = nil
			lastCollisionOverlayLayers = nil
			lastCollisionOverlayPlane = nil
			print("[RSDK] Collision tile overlay " .. (showCollisionOverlay and "ON" or "OFF") .. " (F3 toggles)")
			if render then render() end
		else
			print("[RSDK] Load a level first; F3 toggles the collision tile overlay")
		end
		return
	end

	if (key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift) and not processed then
		if not menuOpen and usingRSDKLevel then
			-- Toggle between RSDK collision planes (Path A = 0, Path B = 1).
			activeLevelConfig.CollisionPlane = (activeLevelConfig.CollisionPlane == 1) and 0 or 1
			-- Force the F3 overlay to rebuild for the new plane.
			lastCollisionOverlayPlane = nil
			print("[RSDK] Collision plane -> " .. (activeLevelConfig.CollisionPlane == 0 and "A (0)" or "B (1)"))
			if render then render() end
		end
		return
	end

	if key == Enum.KeyCode.P and not processed then
		if not menuOpen then
			openLevelMenu()
		end
		return
	end

	if menuOpen then
		if processed then return end
		if OPT.menu then
			local mapped = ({
				[Enum.KeyCode.Up] = "Up", [Enum.KeyCode.W] = "Up",
				[Enum.KeyCode.Down] = "Down", [Enum.KeyCode.S] = "Down",
				[Enum.KeyCode.Left] = "Left", [Enum.KeyCode.A] = "Left",
				[Enum.KeyCode.Right] = "Right", [Enum.KeyCode.D] = "Right",
				[Enum.KeyCode.Return] = "Confirm", [Enum.KeyCode.KeypadEnter] = "Confirm",
				[Enum.KeyCode.Z] = "Confirm",
				[Enum.KeyCode.Backspace] = "Back", [Enum.KeyCode.Escape] = "Back",
				[Enum.KeyCode.X] = "Back",
			})[key]
			if mapped then OPT.menu:handleKey(mapped) end
			return
		end

		if ManiaMenu.screen == "Main" then
			if key == Enum.KeyCode.Up or key == Enum.KeyCode.W then
				ManiaMenuNavigateMain(-1)
			elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S then
				ManiaMenuNavigateMain(1)
			elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter
				or key == Enum.KeyCode.Z or key == Enum.KeyCode.Space then
				ManiaMenuConfirm()
			elseif key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Escape or key == Enum.KeyCode.X then
				-- The title screen is the root of this LocalScript; Back has no parent.
			end
		elseif ManiaMenu.screen == "StageSelect" then
			if key == Enum.KeyCode.Up or key == Enum.KeyCode.W then
				setMenuSelection(menuSelectedIndex - 1)
			elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S then
				setMenuSelection(menuSelectedIndex + 1)
			elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter
				or key == Enum.KeyCode.Z or key == Enum.KeyCode.Space then
				ManiaMenuConfirm()
			elseif key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Escape or key == Enum.KeyCode.X then
				ManiaMenuBack()
			end
		elseif ManiaMenu.screen == "Extras" then
			if key == Enum.KeyCode.Up or key == Enum.KeyCode.W then
				ManiaMenuNavigateExtras(-1)
			elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S then
				ManiaMenuNavigateExtras(1)
			elseif key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Escape or key == Enum.KeyCode.X then
				ManiaMenuBack()
			elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.Z then
				ManiaMenuConfirm()
			end
		elseif ManiaMenu.screen == "Competition" then
			if key == Enum.KeyCode.Up or key == Enum.KeyCode.W then
				ManiaMenuCompetitionMove(-1)
			elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S then
				ManiaMenuCompetitionMove(1)
			elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.A then
				ManiaMenuCompetitionAdjust(-1)
			elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.D then
				ManiaMenuCompetitionAdjust(1)
			elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.Z or key == Enum.KeyCode.Space then
				ManiaMenuConfirm()
			elseif key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Escape or key == Enum.KeyCode.X then
				ManiaMenuBack()
			end
		end
		return
	end

	if processed then return end
	if key == Enum.KeyCode.Left then
		leftHeld = true
	elseif key == Enum.KeyCode.Right then
		rightHeld = true
	elseif key == Enum.KeyCode.Up or key == Enum.KeyCode.W then
		upHeld = true
	elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S then
		downHeld = true
	elseif key == Enum.KeyCode.Z then
		if debugMode then
			debugCycleQueued = true
		else
			if not jumpHeld then
				jumpQueued = true
			end
			jumpHeld = true
		end
	elseif key == Enum.KeyCode.Space and debugMode then
		debugPlaceQueued = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local key = input.KeyCode
	if key == Enum.KeyCode.Left then
		leftHeld = false
	elseif key == Enum.KeyCode.Right then
		rightHeld = false
	elseif key == Enum.KeyCode.Up or key == Enum.KeyCode.W then
		upHeld = false
	elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S then
		downHeld = false
	elseif key == Enum.KeyCode.Z then
		jumpHeld = false
		if not debugMode and not grounded and speedY < -4 then speedY = -4 end
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	stopGameLoopSound("SpindashCharge")
	leftHeld = false
	rightHeld = false
	upHeld = false
	downHeld = false
	jumpHeld = false
end)

--============================================================
-- COMPETITION ROOMS + MATCH EVENTS (client)
-- Requires ServerScriptService.RSDKMultiplayerServer.
--============================================================
OPT.comp = {
	remote = nil,
	match = nil,
	matchActive = false,
	matchPreparing = false,
	eliminated = false,
	stocksLeft = nil,
	progress = nil,
}

do
	local folder = ReplicatedStorage:WaitForChild("RSDKMultiplayer", 10)
	local remote = folder and folder:WaitForChild("Competition", 10)
	if remote then
		OPT.comp.remote = remote
		remote.OnClientEvent:Connect(function(action, payload)
			local comp = OPT.comp
			if action == "RoomList" then
				ManiaMenu.compRooms = type(payload) == "table" and payload or {}
				ManiaMenu.compNotice = #ManiaMenu.compRooms == 0 and "NO OPEN ROOMS" or "SELECT A ROOM TO JOIN"
				if ManiaMenu.screen == "Competition" and ManiaMenu.compPage == "Browse" then
					ManiaMenu.compSelected = math.clamp(ManiaMenu.compSelected, 1, 2 + math.min(#ManiaMenu.compRooms, 7))
					renderManiaCompetitionInfoToCanvas()
				end
			elseif action == "RoomState" or action == "RoomJoined" or action == "RoomCreated" then
				ManiaMenu.compRoom = payload
				ManiaMenu.compPage = "Lobby"
				ManiaMenu.compSelected = 1
				ManiaMenu.compNotice = "READY UP WHEN YOU ARE SET"
				ManiaMenu.screen = "Competition"
				menuOpen = true
				ManiaMenuCompetitionRender()
			elseif action == "RoomLeft" then
				ManiaMenu.compRoom = nil
				ManiaMenu.compPage = "Browse"
				ManiaMenu.compSelected = 1
				ManiaMenu.compNotice = "YOU LEFT THE ROOM"
				ManiaMenuCompetitionRequestRooms()
			elseif action == "Error" then
				ManiaMenu.compNotice = tostring(payload or "COMPETITION ERROR")
				ManiaMenuCompetitionRender()
			elseif action == "MatchPrepare" then
				ManiaMenuStopMusic()
				comp.matchPreparing = true
				comp.matchActive = false
				comp.eliminated = false
				comp.match = payload
				local record
				for _, candidate in ipairs(levelButtonRecords) do
					if candidate.Key == payload.stageKey then record = candidate break end
				end
				if not record or not record.Folder or not record.Folder.Parent then
					remote:FireServer("MatchLoadFailed", {reason = "STAGE NOT FOUND"})
					return
				end
				startLevel(record.Folder)
				if usingRSDKLevel and activeLevel and selectedLevelName == payload.stageKey then
					remote:FireServer("MatchLoaded", {
						stageKey = selectedLevelName,
						width = activeLevel.widthPixels,
						startX = playerX,
					})
				else
					remote:FireServer("MatchLoadFailed", {reason = "STAGE FAILED TO LOAD"})
				end
			elseif action == "MatchStarted" then
				comp.matchPreparing = false
				comp.matchActive = true
				comp.eliminated = false
				comp.match = payload
				comp.stocksLeft = payload.stocks
				if payload.spawnX and usingRSDKLevel then
					playerX = math.clamp(payload.spawnX, WIDTH_RADIUS, math.max(WIDTH_RADIUS, activeLevel.widthPixels - WIDTH_RADIUS))
					groundTrackX = playerX
					speedX, speedY = 0, 0
					updateLevelCamera()
					render()
				end
			elseif action == "MatchProgress" then
				comp.progress = payload
			elseif action == "BattleHit" then
				comp.stocksLeft = payload.stocksLeft
				if not comp.eliminated then
					local direction = tonumber(payload.knockbackDirection) or 1
					speedX = direction * 5
					speedY = -4
					grounded = false
					playerState = "Air"
					setSpriteAnimation(Anim.Jump, true, 0)
				end
			elseif action == "BattleEliminated" then
				comp.eliminated = true
				speedX, speedY = 0, 0
				clearMovementInput()
			elseif action == "MatchCancelled" then
				comp.matchPreparing = false
				comp.matchActive = false
				menuOpen = true
				ManiaMenu.screen = "Competition"
				ManiaMenu.compPage = "Lobby"
				ManiaMenu.compNotice = tostring(payload and payload.reason or "MATCH CANCELLED")
				ManiaMenuCompetitionRender()
			elseif action == "MatchEnded" then
				comp.matchPreparing = false
				comp.matchActive = false
				comp.eliminated = false
				comp.stocksLeft = nil
				ManiaMenu.compResults = payload
				ManiaMenu.compPage = "Results"
				ManiaMenu.compSelected = 1
				ManiaMenu.compNotice = "MATCH COMPLETE"
				ManiaMenu.screen = "Competition"
				menuOpen = true
				ManiaMenuPlaySound("competition_menu", true)
				ManiaMenuCompetitionRender()
			end
		end)
		print("[MP] Competition room system connected")
	else
		warn("[MP] RSDKMultiplayer.Competition not found - install the server script to enable rooms")
	end
end

--============================================================
-- MATRIX MATH / ROTATED SPRITE DRAWING
--============================================================

local warnedWrongSheet = false

-- Rotation is expressed in 512 discrete units. Cache sin/cos once so every
-- sprite pixel and debug vertex avoids repeated trigonometric calls.
local ROTATION_COS = table.create(512)
local ROTATION_SIN = table.create(512)
for units = 0, 511 do
	local angle = units * (2 * math.pi / 512)
	ROTATION_COS[units + 1] = math.cos(angle)
	ROTATION_SIN[units + 1] = math.sin(angle)
end

function getRotationMatrix(units)
	local normalized = units % 512
	local integerUnits = math.floor(normalized)
	if normalized == integerUnits then
		local index = integerUnits + 1
		return ROTATION_COS[index], ROTATION_SIN[index]
	end
	local angle = normalized * (2 * math.pi / 512)
	return math.cos(angle), math.sin(angle)
end

function rotateOffset(dx, dy, units)
	local c, s = getRotationMatrix(units)
	return dx * c - dy * s, dx * s + dy * c
end

function OPT.drawLine(x0, y0, x1, y1, color)
	local dx = x1 - x0
	local dy = y1 - y0
	local steps = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy))))

	for i = 0, steps do
		local t = i / steps
		pixel(
			math.floor(x0 + dx * t + 0.5),
			math.floor(y0 + dy * t + 0.5),
			color
		)
	end
end

function OPT.drawAxisAlignedDebugBox(centerX, centerY)
	-- This is a visualization of the world-axis-aligned collision bounds.
	-- Sonic's sprite may rotate on slopes, but the floor/side query sensors do not.
	local left = centerX - WIDTH_RADIUS
	local right = centerX + WIDTH_RADIUS
	local top = centerY - HEIGHT_RADIUS
	local bottom = centerY + HEIGHT_RADIUS

	OPT.drawLine(left, top, right, top, WHITE)
	OPT.drawLine(right, top, right, bottom, WHITE)
	OPT.drawLine(right, bottom, left, bottom, WHITE)
	OPT.drawLine(left, bottom, left, top, WHITE)

	-- Fixed world-space sample markers: wall sensors and the floor sensor.
	pixel(left, top + 3, ORANGE)
	pixel(left, centerY - 2, ORANGE)
	pixel(right, top + 3, ORANGE)
	pixel(right, centerY - 2, ORANGE)
	pixel(centerX, bottom, YELLOW)
end

function drawSpriteFrame(frame, centerX, centerY, spriteRotationUnits, sourceSheet, flipX, additive, clipRect)
	if not frame then return false end
	-- Visual rotation is independent of the physics rotation. Ball animations
	-- pass zero here so rolling/jumping Sonic is never additionally tilted by
	-- the slope/loop rotation used by the collision body.
	spriteRotationUnits = spriteRotationUnits or rotationUnits
	sourceSheet = sourceSheet or spriteSheet
	local isFlipped = flipX
	if isFlipped == nil then isFlipped = not facingRight end

	local sheetIndex = frame.sheetIndex
	if sheetIndex == nil then sheetIndex = frame.sheetID or 0 end

	if sheetIndex ~= 0 and sourceSheet == spriteSheet then
		warn("[RSDK] Sprite frame references sheet " .. tostring(sheetIndex) .. "; this renderer has one PNG sheet loaded")
		return false
	end

	local sourceX, sourceY = frame.sprX, frame.sprY
	local width, height = frame.width, frame.height

	if not sourceX or not sourceY or not width or not height then return false end
	if width <= 0 or height <= 0 then return false end
	if sourceX < 0 or sourceY < 0
		or sourceX + width > sourceSheet.width
		or sourceY + height > sourceSheet.height then
		return false
	end

	-- The frame's RSDK pivot defines its local rectangle relative to the
	-- entity origin. When flipped, the source pixels and local pivot are
	-- mirrored before rotating around that same origin.
	local left = isFlipped and (-width - frame.pivotX) or frame.pivotX
	local top = frame.pivotY
	local right = left + width
	local bottom = top + height

	local c, s = getRotationMatrix(spriteRotationUnits)
	local rx1, ry1 = left * c - top * s, left * s + top * c
	local rx2, ry2 = right * c - top * s, right * s + top * c
	local rx3, ry3 = right * c - bottom * s, right * s + bottom * c
	local rx4, ry4 = left * c - bottom * s, left * s + bottom * c
	local minX = centerX + math.min(rx1, rx2, rx3, rx4) + SPRITE_OFFSET_X
	local maxX = centerX + math.max(rx1, rx2, rx3, rx4) + SPRITE_OFFSET_X
	local minY = centerY + math.min(ry1, ry2, ry3, ry4) + SPRITE_OFFSET_Y
	local maxY = centerY + math.max(ry1, ry2, ry3, ry4) + SPRITE_OFFSET_Y

	local x0 = math.max(0, math.floor(minX), clipRect and clipRect.left or 0)
	local x1 = math.min(WIDTH - 1, math.ceil(maxX), clipRect and clipRect.right or (WIDTH - 1))
	local y0 = math.max(0, math.floor(minY), clipRect and clipRect.top or 0)
	local y1 = math.min(HEIGHT - 1, math.ceil(maxY), clipRect and clipRect.bottom or (HEIGHT - 1))

	if x0 > x1 or y0 > y1 then return false end

	local sourcePixels = sourceSheet.pixels

	-- Inverse transform each destination pixel center into the unrotated
	-- source frame. This avoids the holes that forward-mapping rotated
	-- pixel-art sprites would create at diagonal angles.
	-- Hoisted invariants: everything that does not change per pixel is computed
	-- once. localX/localY advance linearly along a row, so the per-pixel work is
	-- two adds instead of a full rotation. Pixels are read/written as one u32.
	local sheetWidth = sourceSheet.width
	local pivotX, pivotY = frame.pivotX, frame.pivotY
	local floor = math.floor
	local readu32, writeu32 = buffer.readu32, buffer.writeu32
	local readu8 = buffer.readu8
	local min = math.min
	local flipBase = width + pivotX
	local startDX = (x0 + 0.5) - centerX - SPRITE_OFFSET_X

	-- Most Sonic/Ring frames are drawn without rotation. In that common case,
	-- walk the source row directly instead of doing an inverse transform and
	-- two floating-point floors for every destination pixel.
	if c == 1 and s == 0 then
		local firstSourceX = isFlipped and floor(startDX + flipBase) or floor(startDX - pivotX)
		local sourceStep = isFlipped and -4 or 4
		for destY = y0, y1 do
			local sourceYInFrame = floor((destY + 0.5) - centerY - SPRITE_OFFSET_Y - pivotY)
			if sourceYInFrame >= 0 and sourceYInFrame < height then
				local sourcePixelX = isFlipped and (sourceX + width - 1 - firstSourceX)
					or (sourceX + firstSourceX)
				local sourceOffset = ((sourceY + sourceYInFrame) * sheetWidth + sourcePixelX) * 4
				local destOffset = (destY * WIDTH + x0) * 4
				local sourceXInFrame = firstSourceX
				for _ = x0, x1 do
					if sourceXInFrame >= 0 and sourceXInFrame < width then
						local packed = readu32(sourcePixels, sourceOffset)
						local alpha = packed // 16777216
						if alpha == 255 and not additive then
							writeu32(framePixels, destOffset, packed)
						elseif alpha > 0 then
							local red = packed % 256
							local green = (packed // 256) % 256
							local blue = (packed // 65536) % 256
							if additive then
								red = min(255, readu8(framePixels, destOffset) + floor(red * alpha / 255 + 0.5))
								green = min(255, readu8(framePixels, destOffset + 1) + floor(green * alpha / 255 + 0.5))
								blue = min(255, readu8(framePixels, destOffset + 2) + floor(blue * alpha / 255 + 0.5))
								writeu32(framePixels, destOffset, red + green * 256 + blue * 65536 + 0xFF000000)
							else
								local inverseAlpha = 255 - alpha
								red = floor((red * alpha + readu8(framePixels, destOffset) * inverseAlpha) / 255 + 0.5)
								green = floor((green * alpha + readu8(framePixels, destOffset + 1) * inverseAlpha) / 255 + 0.5)
								blue = floor((blue * alpha + readu8(framePixels, destOffset + 2) * inverseAlpha) / 255 + 0.5)
								writeu32(framePixels, destOffset, red + green * 256 + blue * 65536 + 0xFF000000)
							end
						end
					end
					sourceXInFrame += 1
					sourceOffset += sourceStep
					destOffset += 4
				end
			end
		end
		return true
	end

	for destY = y0, y1 do
		local dy = (destY + 0.5) - centerY - SPRITE_OFFSET_Y
		local localX = startDX * c + dy * s
		local localY = -startDX * s + dy * c
		local destOffset = (destY * WIDTH + x0) * 4
		for _ = x0, x1 do
			local sx
			if not isFlipped then
				sx = floor(localX - pivotX)
			else
				sx = floor(localX + flipBase)
			end
			if sx >= 0 and sx < width then
				local sy = floor(localY - pivotY)
				if sy >= 0 and sy < height then
					local sourcePixelX = not isFlipped and (sourceX + sx)
						or (sourceX + width - 1 - sx)
					local packed = readu32(sourcePixels, ((sourceY + sy) * sheetWidth + sourcePixelX) * 4)
					local alpha = packed // 16777216
					if alpha == 255 and not additive then
						writeu32(framePixels, destOffset, packed)
					elseif alpha > 0 then
						local red = packed % 256
						local green = (packed // 256) % 256
						local blue = (packed // 65536) % 256
						if additive then
							red = math.min(255, readu8(framePixels, destOffset) + floor(red * alpha / 255 + 0.5))
							green = math.min(255, readu8(framePixels, destOffset + 1) + floor(green * alpha / 255 + 0.5))
							blue = math.min(255, readu8(framePixels, destOffset + 2) + floor(blue * alpha / 255 + 0.5))
							writeu32(framePixels, destOffset, red + green * 256 + blue * 65536 + 0xFF000000)
						else
							local inverseAlpha = 255 - alpha
							red = floor((red * alpha + readu8(framePixels, destOffset) * inverseAlpha) / 255 + 0.5)
							green = floor((green * alpha + readu8(framePixels, destOffset + 1) * inverseAlpha) / 255 + 0.5)
							blue = floor((blue * alpha + readu8(framePixels, destOffset + 2) * inverseAlpha) / 255 + 0.5)
							writeu32(framePixels, destOffset, red + green * 256 + blue * 65536 + 0xFF000000)
						end
					end
				end
			end
			localX += c
			localY -= s
			destOffset += 4
		end
	end

	return true
end

-- Use the loaded RSDK ring frames and the same pixel-accurate renderer as Sonic.
objectRegistry["Ring"].draw = function(entity, _targetBuffer, viewWidth, viewHeight, camX, camY)
	if not ringSpriteSheet or not ringAnimation or not drawSpriteFrame then return end
	local frames = ringAnimation.frames
	if type(frames) ~= "table" or #frames == 0 then return end
	local frame = frames[(entity.frameID or 0) + 1]
	if not frame then return end
	local screenX = entity.x - camX
	local screenY = entity.y - camY
	if screenX < -32 or screenX > viewWidth + 32 or screenY < -32 or screenY > viewHeight + 32 then
		return
	end
	drawSpriteFrame(frame, screenX, screenY, 0, ringSpriteSheet, false)
end


--============================================================
-- SHARED OBJECT HELPERS (sprites, animators, hurt, FX)
--============================================================
OPT.objectSprites = {}
OPT.invincible = 0
OPT.hurtLock = 0
OPT.bridgeStanding = false
OPT.fx = {} -- simple fallback effects for non-Motobug badniks
OPT.spriteEffects = {} -- one-shot effects rendered from real RSDK sprite animations
OPT.bridgeData = {}
OPT.pendingBridgeData = {}
OPT.springData = {}
OPT.pendingSpringData = {}
OPT.ddwreckerData = {}
OPT.pendingDDWreckerData = {}

-- Loads RSDK.<Name>PNGData + RSDK.<Name>AnimationData exactly like the ring
-- art: FF00FE colour key, AnimationParser animations. Cached per object name.
function OPT.getObjectSprites(name)
	local cached = OPT.objectSprites[name]
	if cached ~= nil then return cached or nil end
	local pngModule = RSDK:FindFirstChild(name .. "PNGData")
	local animModule = RSDK:FindFirstChild(name .. "AnimationData")
	if not pngModule or not animModule then
		warn(string.format("[RSDK] %s art not installed. Add RSDK.%sPNGData and RSDK.%sAnimationData ModuleScripts; a placeholder is drawn meanwhile.", name, name, name))
		OPT.objectSprites[name] = false
		return nil
	end
	local ok, result = pcall(function()
		local sheet = PNG.decode(decodeAssetBuffer(require(pngModule)))
		assert(sheet.width > 0 and sheet.height > 0, name .. " PNG has invalid dimensions")
		local p = sheet.pixels
		local keyed = applyColorKey(sheet, 0xFF, 0x00, 0xFE, 2)
		keyed += applyColorKey(sheet, 0x00, 0xF0, 0x00, 0)
		if keyed == 0 then
			-- No known key colour present: treat the sheet's corner pixel as the background.
			keyed = applyColorKey(sheet, buffer.readu8(p, 0), buffer.readu8(p, 1), buffer.readu8(p, 2), 0)
			warn(string.format("[RSDK] %s: no FF00FE/00F000 key found; keyed corner colour %02X%02X%02X instead",
				name, buffer.readu8(p, 0), buffer.readu8(p, 1), buffer.readu8(p, 2)))
		end
		local data = AnimationParser.Parse(require(animModule))
		assert(type(data.animations) == "table" and #data.animations > 0, name .. " has no animations")
		return { sheet = sheet, animations = data.animations }
	end)
	if not ok then
		warn("[RSDK] Could not load " .. name .. " art: " .. tostring(result))
		OPT.objectSprites[name] = false
		return nil
	end
	print(string.format("[RSDK] %s sprites loaded: %dx%d, %d animations", name, result.sheet.width, result.sheet.height, #result.animations))
	OPT.objectSprites[name] = result
	return result
end

-- Begin the two global Sonic Mania screen objects. Expected asset modules:
--   RSDK.HUDPNGData + RSDK.HUDAnimationData
--   RSDK.TitleCardPNGData + RSDK.TitleCardAnimationData
-- These use the exact same module format and loader as Bridge/Motobug/Ring.
function OPT.resetHUD()
	OPT.hud = {
		ticks = 0,
		score = 0,
		lives = math.max(0, math.floor(tonumber(activeLevelConfig and activeLevelConfig.StartLives) or 3)),
		visible = not (activeLevelConfig and activeLevelConfig.ShowHUD == false),
	}
	OPT.getObjectSprites("HUD")
end

function OPT.beginTitleCard(config, levelName)
	config = type(config) == "table" and config or {}
	local cardConfig = type(config.TitleCard) == "table" and config.TitleCard or {}
	local disabled = config.TitleCard == false or config.ShowTitleCard == false or config.SuppressTitleCard == true
		or cardConfig.Enabled == false or cardConfig.Suppress == true
	local zoneName = cardConfig.Name or cardConfig.ZoneName or config.TitleCardName
		or config.ZoneName or config.ZoneTitle or config.DisplayName
	if type(zoneName) ~= "string" or zoneName == "" then
		zoneName = tostring(levelName or "UNTITLED"):gsub("_Act%d+$", ""):gsub("Act%d+$", "")
	end
	zoneName = string.upper(tostring(zoneName):gsub("[_%-]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
	if zoneName == "" then zoneName = "UNTITLED" end

	local actNumber = tonumber(cardConfig.ActNumber or config.ActNumber or config.ActID)
	if not actNumber then
		actNumber = tonumber(tostring(levelName or ""):match("[Aa]ct(%d+)")) or 1
	end
	actNumber = math.clamp(math.floor(actNumber), 1, 3)

	OPT.titleCard = {
		active = not disabled,
		phase = disabled and "hidden" or "setup",
		timer = 0,
		actionTimer = 0,
		zoneName = zoneName,
		actNumber = actNumber,
		actFrameID = actNumber - 1,
		sprites = OPT.getObjectSprites("TitleCard"),
		colors = {
			{240, 140, 24},  -- orange
			{96, 192, 160}, -- green
			{240, 80, 48},  -- red
			{64, 96, 176},  -- blue
			{240, 200, 0},  -- yellow
		},
	}
	if not disabled then
		OPT.initializeTitleCardGeometry(OPT.titleCard)
	end
end

-- A direct port of TitleCard_Update / the Mania title-card state machine.
-- Timings are kept in the original 60 Hz update ticks; the timer itself is
-- in the source object's 24/32-unit increments during the opening.
function OPT.updateTitleCard()
	local card = OPT.titleCard
	if not card or not card.active then return end

	local function moveWordPanels()
		local g = card.geometry
		if card.hasTwoWords then
			local v = g.word1
			v[2][1] -= 32
			if v[2][1] < card.word1XPos - 16 then v[2][1] = card.word1XPos - 16 end
			v[1][1] = v[2][1] - card.word1Width
			v[3][1] -= 32
			if v[3][1] < card.word1XPos then v[3][1] = card.word1XPos end
			v[4][1] = v[3][1] - card.word1Width
		end

		local v2 = g.word2
		v2[2][1] -= 32
		if v2[2][1] < card.word2XPos - 16 then v2[2][1] = card.word2XPos - 16 end
		v2[1][1] = v2[2][1] - card.word2Width
		v2[3][1] -= 32
		if v2[3][1] < card.word2XPos then v2[3][1] = card.word2XPos end
		v2[4][1] = v2[3][1] - card.word2Width

		local vz = g.zone
		vz[2][1] += 32
		if vz[2][1] > card.zoneXPos - 8 then vz[2][1] = card.zoneXPos - 8 end
		vz[1][1] = vz[2][1] - 120
		vz[3][1] += 32
		if vz[3][1] > card.zoneXPos then vz[3][1] = card.zoneXPos end
		vz[4][1] = vz[3][1] - 120

		if card.decorationY < 12 then
			card.decorationX += 2
			card.decorationY += 2
		end
	end

	local function moveTextLetters()
		for i = 1, #card.charPos do
			if card.charPos[i] < 0 then card.charVel[i] += 2.5 end
			card.charPos[i] += card.charVel[i]
			if card.charPos[i] > 0 and card.charVel[i] > 0 then card.charPos[i] = 0 end
		end
		for i = 1, 4 do
			if card.zoneCharPos[i] > 0 then card.zoneCharVel[i] -= 2 end
			card.zoneCharPos[i] += card.zoneCharVel[i]
			if card.zoneCharPos[i] < 0 and card.zoneCharVel[i] < 0 then card.zoneCharPos[i] = 0 end
		end
	end

	if card.phase == "setup" then
		card.timer += 24
		local g = card.geometry
		for _, point in ipairs(g.word1) do point[1] += 40 end
		for _, point in ipairs(g.word2) do point[1] += 40 end
		for _, point in ipairs(g.zone) do point[1] -= 40 end
		if card.timer >= 512 then
			for _, point in ipairs(g.word1) do point[2] += 32 end
			for _, point in ipairs(g.word2) do point[2] -= 32 end
			for _, point in ipairs(g.zone) do point[2] += 32 end
			card.phase = "opening"
		end
	elseif card.phase == "opening" then
		if card.timer >= 1024 then
			card.phase = "enterTitle"
		else
			card.timer += 32
		end
		moveWordPanels()
	elseif card.phase == "enterTitle" then
		local g = card.geometry
		local function approach(value, target)
			local delta = target - value - 16
			local step = delta < 0 and math.ceil(delta / 6) or math.floor(delta / 6)
			value += step
			if value < target then value = target end
			return value
		end
		g.vertMove[1][1] = approach(g.vertMove[1][1], 0)
		g.vertMove[1][2] = approach(g.vertMove[1][2], 138)
		g.vertMove[2][1] = approach(g.vertMove[2][1], 74)
		g.vertMove[2][2] = approach(g.vertMove[2][2], 112)

		local v0, v1 = g.vertMove[1], g.vertMove[2]
		local blue, red, orange, green = g.blue, g.red, g.orange, g.green
		blue[1][1] = v0[1] - 240 + blue[4][1]; blue[1][2] = v0[1]
		blue[2][1] = v0[1] - 240 + blue[3][1]; blue[2][2] = v0[1]
		red[1][1] = v0[2] - 240 + red[4][1]; red[1][2] = v0[2]
		red[2][1] = v0[2] - 240 + red[3][1]; red[2][2] = v0[2]
		orange[1][1] = v1[1] - 240 + orange[4][1]; orange[1][2] = v1[1]
		orange[2][1] = v1[1] - 240 + orange[3][1]; orange[2][2] = v1[1]
		green[1][1] = v1[2] - 240 + green[4][1]; green[1][2] = v1[2]
		green[2][1] = v1[2] - 240 + green[3][1]; green[2][2] = v1[2]

		moveWordPanels()
		moveTextLetters()
		if card.actNumScale < 1.5 then card.actNumScale += 0.125 end
		if card.zoneCharPos[4] == 0 and card.zoneCharVel[4] < 0 then
			card.phase = "show"
			card.actionTimer = 0
		end
	elseif card.phase == "show" then
		if card.actionTimer >= 60 then
			card.actionTimer = 0
			card.phase = "slideAway"
		else
			card.actionTimer += 1
		end
	elseif card.phase == "slideAway" then
		card.actionTimer += 1
		local t = card.actionTimer
		local g = card.geometry
		local function movePoly(poly, dx, dy)
			for _, point in ipairs(poly) do point[1] += dx; point[2] += dy end
		end
		local speed = t * 4
		movePoly(g.green, -speed, -speed)
		if t > 6 then
			speed = (t - 6) * 4
			movePoly(g.orange, -speed, -speed)
			card.decorationX += speed
			card.decorationY += speed
		end
		if t > 12 then
			speed = (t - 12) * 4
			movePoly(g.red, -speed, -speed)
		end
		if t > 18 then
			speed = (t - 12) * 4
			movePoly(g.blue, -speed, -speed)
		end
		if t > 4 then
			speed = (t - 4) * 2
			for _, point in ipairs(g.curtainLeft) do point[1] -= speed end
			for _, point in ipairs(g.curtainRight) do point[1] += speed end
		end
		if t > 60 then
			card.zoneXPos -= 32
			card.word1XPos -= 32
			card.word2XPos += 32
			card.actNumX += 32
			card.actNumY += 32
			for _, point in ipairs(g.word1) do point[1] -= 32 end
			for _, point in ipairs(g.word2) do point[1] += 32 end
			for _, point in ipairs(g.zone) do point[1] -= 32 end
		end
		if t > 80 then
			card.phase = "hidden"
			card.active = false
			card.timer = 0
		end
	end
end

-- Per-entity RSDK animator (SetSpriteAnimation / ProcessAnimation). animID is 0-based.
function OPT.setEntityAnim(entity, sprites, animID)
	local animation = sprites and sprites.animations[animID + 1]
	if not animation or #animation.frames == 0 then
		entity.anim = nil
		entity.animID = animID
		return
	end
	entity.anim = animation
	entity.animID = animID
	entity.frameID = 0
	entity.frameTimer = 0
	entity.frameDuration = math.max(1, animation.frames[1].duration)
	entity.frameSpeed = animation.animationSpeed
	entity.frameLoop = animation.loopIndex
end

function OPT.stepEntityAnim(entity)
	local animation = entity.anim
	if not animation then return end
	entity.frameTimer += entity.frameSpeed
	local safety = 0
	while entity.frameTimer > entity.frameDuration do
		safety += 1
		if safety > 256 then break end
		entity.frameTimer -= entity.frameDuration
		entity.frameID += 1
		if entity.frameID >= #animation.frames then entity.frameID = entity.frameLoop end
		if entity.frameID < 0 or entity.frameID >= #animation.frames then entity.frameID = 0 end
		entity.frameDuration = math.max(1, animation.frames[entity.frameID + 1].duration)
	end
end

-- One-shot sprite effects use real RSDK frames instead of hand-drawn circles.
function OPT.findBreakAnimation(animations)
	local aliases = { "break", "breaking", "destroy", "destroyed", "death", "dead", "explode", "explosion" }
	for _, animation in ipairs(animations or {}) do
		local animationName = string.lower(tostring(animation.name or "")):gsub("[%s%p]", "")
		for _, alias in ipairs(aliases) do
			if animationName == alias or string.find(animationName, alias, 1, true) then
				if type(animation.frames) == "table" and #animation.frames > 0 then
					return animation
				end
			end
		end
	end
	return nil
end

function OPT.spawnSpriteEffect(sprites, animation, x, y, flipX)
	if not sprites or not animation or type(animation.frames) ~= "table" or #animation.frames == 0 then
		return false
	end
	local firstFrame = animation.frames[1]
	table.insert(OPT.spriteEffects, {
		x = x,
		y = y,
		sheet = sprites.sheet,
		animation = animation,
		frameID = 0,
		frameTimer = 0,
		frameDuration = math.max(1, tonumber(firstFrame.duration) or 1),
		frameSpeed = math.max(1, tonumber(animation.animationSpeed) or 128),
		flipX = flipX == true,
	})
	return true
end

-- Motobug's four built-in clips are movement/turn/smoke states, not a known
-- destruction clip. Prefer a named break clip if an asset pack provides one;
-- otherwise use the shared RSDK Explosion sprite sheet when it is imported.
function OPT.spawnMotobugBreak(entity)
	local motobugSprites = OPT.getObjectSprites("Motobug")
	local breakAnimation = motobugSprites and OPT.findBreakAnimation(motobugSprites.animations)
	if breakAnimation and OPT.spawnSpriteEffect(motobugSprites, breakAnimation, entity.x, entity.y, false) then
		return true
	end

	if motobugSprites and not OPT.loggedMotobugAnimationNames then
		OPT.loggedMotobugAnimationNames = true
		local names = {}
		for _, animation in ipairs(motobugSprites.animations) do
			table.insert(names, tostring(animation.name or "unnamed"))
		end
		warn("[RSDK] Motobug clips (no named break clip found): " .. table.concat(names, ", "))
	end

	local explosionSprites = OPT.getObjectSprites("Explosion")
	local explosionAnimation = explosionSprites and (OPT.findBreakAnimation(explosionSprites.animations) or explosionSprites.animations[1])
	if explosionAnimation and OPT.spawnSpriteEffect(explosionSprites, explosionAnimation, entity.x, entity.y, false) then
		return true
	end

	return false
end

function OPT.stepSpriteEffects()
	for index = #OPT.spriteEffects, 1, -1 do
		local effect = OPT.spriteEffects[index]
		local animation = effect.animation
		effect.frameTimer += effect.frameSpeed
		local safety = 0
		if effect.finished then
			table.remove(OPT.spriteEffects, index)
		else
			while effect.frameTimer >= effect.frameDuration do
				safety += 1
				if safety > 256 then
					warn("[RSDK] Sprite effect animation safety limit reached")
					break
				end
				effect.frameTimer -= effect.frameDuration
				effect.frameID += 1
				if effect.frameID >= #animation.frames then
					-- Keep the final frame visible for one draw, then remove next tick.
					effect.frameID = #animation.frames - 1
					effect.finished = true
					break
				end
				effect.frameDuration = math.max(1, tonumber(animation.frames[effect.frameID + 1].duration) or 1)
			end
		end
	end
end

-- Draws an object frame; if the frame can't be drawn, shows a placeholder and
-- prints ONE warning explaining why (instead of silently drawing nothing).
function OPT.drawObjectFrame(name, frame, sheet, sx, sy, flip, pw, ph)
	local ok = frame and sheet and drawSpriteFrame(frame, sx, sy, 0, sheet, flip)
	if ok then return end
	OPT.drawFrameRect(math.floor(sx - pw / 2), math.floor(sy - ph / 2), pw, ph, {0, 220, 220})
	OPT.warned = OPT.warned or {}
	if not OPT.warned[name] then
		OPT.warned[name] = true
		if not frame then
			warn("[RSDK] " .. name .. ": animation/frame missing (check AnimationData order)")
		elseif not sheet then
			warn("[RSDK] " .. name .. ": no sprite sheet loaded")
		else
			warn(string.format("[RSDK] %s: frame rejected. sheet=%dx%d frame src=(%s,%s) size=%sx%s sheetIndex=%s",
				name, sheet.width, sheet.height, tostring(frame.sprX), tostring(frame.sprY),
				tostring(frame.width), tostring(frame.height), tostring(frame.sheetIndex or frame.sheetID)))
		end
	end
end

function OPT.spawnEntity(name, x, y, extra)
	local def = objectRegistry[name]
	if not def then return nil end
	local entity = { x = x, y = y, def = def }
	if extra then for k, v in pairs(extra) do entity[k] = v end end
	if def.init then def.init(entity) end
	table.insert(activeEntities, entity)
	return entity
end

-- RSDK ACTIVE_BOUNDS: only update while within `range` of the camera view.
function OPT.inBounds(x, y, rangeX, rangeY)
	return x > cameraX - rangeX and x < cameraX + WIDTH + rangeX
		and y > cameraY - rangeY and y < cameraY + HEIGHT + rangeY
end

function OPT.playerIsBall()
	return playerState == "Roll" or playerState == "Spindash" or playerState == "DropDash"
		or animator.animation == Anim.Jump
end

function OPT.spawnExplosion(x, y)
	table.insert(OPT.fx, { x = x, y = y, age = 0 })
end

function OPT.hurtPlayer(sourceX)
	if OPT.invincible > 0 or debugMode then return end
	OPT.invincible = 120
	OPT.hurtLock = 60
	ringCount = 0
	speedX = (playerX >= sourceX) and 2 or -2
	speedY = -4
	grounded = false
	onLoop = false
	skidding = 0
	pushing = 0
	jumpAbilityState = 0
	dropDashReady = false
	OPT.bridgeStanding = false
	playerState = "Air"
	local hurt = findAnimation("Hurt", "Hit")
	if hurt then setSpriteAnimation(hurt, true, 0) end
end

-- Player_CheckBadnikTouch + Player_CheckBadnikBreak. Returns true if destroyed.
function OPT.badnikPlayerCheck(entity, radius)
	if debugMode or OPT.invincible > 0 then return false end
	local ball = OPT.playerIsBall()
	local halfH = ball and 14 or HEIGHT_RADIUS
	if math.abs(playerX - entity.x) >= radius + WIDTH_RADIUS
		or math.abs(playerY - entity.y) >= radius + halfH then
		return false
	end
	if ball then
		if entity.def == objectRegistry["Motobug"] then
			if not OPT.spawnMotobugBreak(entity) then
				warn("[RSDK] Motobug was destroyed, but no break animation was found. Add RSDK.ExplosionPNGData and RSDK.ExplosionAnimationData, or include a named Break/Destroy/Death animation in MotobugAnimationData.")
			end
		else
			OPT.spawnExplosion(entity.x, entity.y)
		end
		if not grounded then
			if speedY > 0 then speedY = -speedY else speedY += 1 end
		end
		return true
	end
	OPT.hurtPlayer(entity.x)
	return false
end

--============================================================
-- BRIDGE  (port of Bridge.c; positions in pixels, 16.16 -> px)
--============================================================
OPT.bridgeSprites = nil

objectRegistry["Bridge"] = {
	init = function(entity)
		entity.length = math.max(1, math.floor(tonumber(entity.length) or 12))
		entity.length += 1 -- Bridge_Create: ++self->length
		-- NOTE: 0x80000 = 8px, so `length << 19` is length * 8 px per side.
		local half = entity.length * 8
		entity.startPos = entity.x - half
		entity.endPos = entity.x + half
		entity.halfWidth = half
		entity.stood = -1 -- (Entity*)-1
		entity.stoodCount = 0
		entity.stoodPos = 0
		entity.timer = 0
		entity.depression = 0
		entity.depth = 0
		local sprites = OPT.getObjectSprites("Bridge")
		OPT.setEntityAnim(entity, sprites, 0)
	end,

	update = function(entity)
		if not OPT.inBounds(entity.x, entity.y, entity.halfWidth, 128) then return end
		local b = entity
		if b.stoodCount > 0 then
			if b.timer < 0x80 then b.timer += 8 end
		else
			if b.timer ~= 0 then
				b.stood = -1
				b.timer -= 8
			else
				b.depression = 0
			end
		end
		b.stoodCount = 0
		b.depth = b.depression * b.timer / 128

		OPT.bridgeCollide(b)
	end,

	draw = function(b, _buf, viewWidth, viewHeight, camX, camY)
		if b.x + b.halfWidth < camX - 16 or b.x - b.halfWidth > camX + viewWidth + 16 then return end
		local sprites = OPT.getObjectSprites("Bridge")
		local frame = b.anim and b.anim.frames[1]
		local function drawLog(wx, wy)
			local sx, sy = wx - camX, wy - camY
			if sx < -16 or sx > viewWidth + 16 or sy < -32 or sy > viewHeight + 32 then return end
			if frame and sprites then
				OPT.drawObjectFrame("Bridge", frame, sprites.sheet, sx, sy, false, 14, 16)
			else
				OPT.drawFrameRect(math.floor(sx - 7), math.floor(sy - 8), 14, 16, {150, 90, 30})
				OPT.drawFrameRect(math.floor(sx - 7), math.floor(sy - 8), 14, 3, {210, 140, 60})
			end
		end

		local stoodPos = math.max(b.stoodPos, 0.0001)
		local size = math.floor(b.stoodPos / 16)
		local ang = 8
		local drawX = b.startPos + 8
		for _ = 1, size do
			drawLog(drawX, b.depth * math.sin(math.pi / 2 * ang / stoodPos) + b.y)
			drawX += 16
			ang += 16
		end
		local id = size
		drawLog(drawX, b.depth + b.y)
		id += 1

		ang = 8
		local divisor = math.max(b.endPos - b.startPos - b.stoodPos, 0.0001)
		drawX = b.endPos - 8
		while id < b.length do
			drawLog(drawX, b.depth * math.sin(math.pi / 2 * ang / divisor) + b.y)
			drawX -= 16
			ang += 16
			id += 1
		end
	end,
}

function OPT.bridgeLandPlayer()
	if not grounded then
		grounded = true
		landingWorldSpeedX = speedX
		if playerState == "Air" and jumpAbilityState == 0 then playerState = "Ground" end
	end
	speedY = 0
	onLoop = false
	setGroundAngleFromRadians(0)
	OPT.bridgeStanding = true
end

-- Bridge_HandleCollisions for the single local player.
function OPT.bridgeCollide(b)
	local px = playerX
	local vy = grounded and 0 or speedY
	local start, finish = b.startPos, b.endPos
	local feetOffset = HEIGHT_RADIUS

	if px > start and px < finish then
		if b.stood ~= "p" then
			if b.stoodCount == 0 then b.stoodPos = px - start end
			if vy >= 0 then
				local ratio
				if px - start <= b.stoodPos then
					ratio = (px - start) / math.max(b.stoodPos, 0.0001)
				else
					ratio = (finish - px) / math.max(finish - start - b.stoodPos, 0.0001)
				end
				local hitY = b.depth * math.sin(math.pi / 2 * ratio) - 8
				local top, bottom
				if vy >= 0.5 then
					top = hitY
					bottom = top + 8
				else
					bottom = hitY
					top = bottom - 8
				end
				-- Feet-based test: avoids snapping Sonic from underneath.
				local feet = playerY + feetOffset
				if feet >= b.y + top and feet <= b.y + bottom then
					playerY = b.y + hitY - feetOffset
					b.stoodCount += 1
					OPT.bridgeLandPlayer()
					if b.stood ~= -1 and b.stood ~= -2 then
						local distance = finish - start
						b.stoodPos = px - start
						b.depression = math.sin(math.pi * b.stoodPos / distance) * distance / 16
						b.depth = b.depression * b.timer / 128
					end
					b.stood = "p"
					if vy < 1 then b.timer = 0x80 end
				end
			end
		else
			b.stoodPos = px - start
			local distance = finish - start
			b.depression = math.sin(math.pi * b.stoodPos / distance) * distance / 16
			if playerY > b.y - 48 then
				if vy >= 0 then
					b.stoodCount += 1
					playerY = b.y + b.depth - (feetOffset + 8)
					OPT.bridgeLandPlayer()
				else
					b.stood = -2
				end
			end
		end
	elseif b.stood == "p" then
		b.timer = 32
		b.stood = -2
	end
end

--============================================================
-- MOTOBUG  (port of Motobug.c; velocities in px/frame)
--============================================================
OPT.MOTOBUG_GRAVITY = 0x3800 / 65536

-- ObjectTileGrip(self, layers, CMODE_FLOOR, 0, xOff, 15px, setPos)
function OPT.motobugGrip(e, xOff, falling)
	local d = senseLevel(e.x + xOff, e.y + 15, 0, 1, "top", 14, falling and 8 or 12)
	if d == nil then return false end
	if falling and d > 0.5 then return false end
	e.y += d
	return true
end

function OPT.motobugCreate(e, isSmoke)
	local sprites = OPT.getObjectSprites("Motobug")
	e.startX, e.startY, e.startDir = e.x, e.y, e.direction or 0
	e.active = "bounds"
	e.wasTurning = true
	e.turnTimer = 0
	e.vy = 0
	if isSmoke then
		OPT.setEntityAnim(e, sprites, 3)
		e.state = OPT.motobugSmoke
	else
		e.timer = 16
		OPT.setEntityAnim(e, sprites, 0)
		e.state = OPT.motobugInit
	end
end

function OPT.motobugCheckPlayer(e)
	if e.isSmoke then return end
	if OPT.badnikPlayerCheck(e, 14) then e.dead = true end
end

function OPT.motobugCheckOffScreen(e)
	if not OPT.inBounds(e.x, e.y, 128, 128) and not OPT.inBounds(e.startX, e.startY, 128, 128) then
		e.x, e.y = e.startX, e.startY
		e.direction = e.startDir
		OPT.motobugCreate(e, false)
	end
end

function OPT.motobugFall(e)
	OPT.stepEntityAnim(e)
	if e.wasTurning then e.x += e.vx end
	e.y += e.vy
	e.vy += OPT.MOTOBUG_GRAVITY
	if OPT.motobugGrip(e, 0, true) then
		e.wasTurning = true
		e.vy = 0
		OPT.setEntityAnim(e, OPT.getObjectSprites("Motobug"), 0)
		e.state = OPT.motobugMove
		OPT.motobugMove(e)
	else
		OPT.motobugCheckPlayer(e)
		OPT.motobugCheckOffScreen(e)
	end
end

function OPT.motobugMove(e)
	e.x += e.vx
	if not OPT.motobugGrip(e, 0, false) then
		OPT.setEntityAnim(e, OPT.getObjectSprites("Motobug"), 1)
		e.turnTimer = 0
		local collided = OPT.motobugGrip(e, e.direction ~= 0 and -1 or 1, false)
		e.state = collided and OPT.motobugIdle or OPT.motobugFall
	end

	e.timer -= 1
	if e.timer == 0 then
		e.timer = 16
		local smoke = OPT.spawnEntity("Motobug", e.x, e.y, { isSmoke = true })
		if smoke then
			smoke.x += (e.direction ~= 0) and -20 or 20
		end
	end

	OPT.stepEntityAnim(e)
	OPT.motobugCheckPlayer(e)
	if not e.dead then OPT.motobugCheckOffScreen(e) end
end

function OPT.motobugIdle(e)
	OPT.stepEntityAnim(e)
	local collided = OPT.motobugGrip(e, e.direction ~= 0 and -1 or 1, false)
	if collided then
		e.turnTimer += 1
		if e.turnTimer == 30 then
			OPT.setEntityAnim(e, OPT.getObjectSprites("Motobug"), 2)
			e.state = OPT.motobugTurn
		end
	else
		e.wasTurning = false
		OPT.setEntityAnim(e, OPT.getObjectSprites("Motobug"), 0)
		e.state = OPT.motobugFall
		e.direction = (e.direction == 0) and 1 or 0
		e.vx = -e.vx
	end
	OPT.motobugCheckPlayer(e)
	if not e.dead then OPT.motobugCheckOffScreen(e) end
end

function OPT.motobugInit(e)
	e.active = "normal"
	e.vx = -1
	e.vy = 0
	e.state = OPT.motobugMove
	OPT.motobugMove(e)
end

function OPT.motobugSmoke(e)
	OPT.stepEntityAnim(e)
	if not e.anim or e.frameID == #e.anim.frames - 1 then e.dead = true end
end

function OPT.motobugTurn(e)
	OPT.stepEntityAnim(e)
	local collided = OPT.motobugGrip(e, e.direction ~= 0 and -1 or 1, false)
	if collided then
		if not e.anim or e.frameID == #e.anim.frames - 1 then
			OPT.setEntityAnim(e, OPT.getObjectSprites("Motobug"), 0)
			e.direction = (e.direction == 0) and 1 or 0
			e.vx = -e.vx
			e.state = OPT.motobugMove
			OPT.motobugMove(e)
		else
			OPT.motobugCheckPlayer(e)
			OPT.motobugCheckOffScreen(e)
		end
	else
		e.wasTurning = false
		OPT.setEntityAnim(e, OPT.getObjectSprites("Motobug"), 0)
		e.state = OPT.motobugFall
		e.direction = (e.direction == 0) and 1 or 0
		e.vx = -e.vx
	end
end

objectRegistry["Motobug"] = {
	init = function(entity)
		entity.vx = 0
		entity.vy = 0
		entity.direction = tonumber(entity.direction) or 0
		entity.dead = false
		OPT.motobugCreate(entity, entity.isSmoke == true)
	end,

	update = function(entity)
		if entity.active == "bounds" and not OPT.inBounds(entity.x, entity.y, 128, 128) then
			return
		end
		if entity.state then entity.state(entity) end
	end,

	draw = function(e, _buf, viewWidth, viewHeight, camX, camY)
		local sx, sy = e.x - camX, e.y - camY
		if sx < -48 or sx > viewWidth + 48 or sy < -48 or sy > viewHeight + 48 then return end
		local sprites = OPT.getObjectSprites("Motobug")
		local frame = e.anim and e.anim.frames[e.frameID + 1]
		if frame and sprites then
			OPT.drawObjectFrame("Motobug", frame, sprites.sheet, sx, sy, e.direction ~= 0, 28, 28)
		elseif not e.isSmoke then
			OPT.drawFrameRect(math.floor(sx - 14), math.floor(sy - 14), 28, 28, {200, 30, 30})
			OPT.drawFrameRect(math.floor(sx - 14), math.floor(sy - 14), 28, 4, {255, 120, 120})
		end
	end,
}

--============================================================
-- SPRING (port of Spring.c; type/flip/plane properties by objectID)
-- Expected RSDK modules: SpringPNGData + SpringAnimationData.
-- SpringData in the stage folder is optional and contains rows such as:
-- {objectID=12, type=1, flipFlag=0, planeFilter=0}.
-- type: 0 yellow vertical, 1 red vertical, 2 yellow horizontal,
--       3 red horizontal, 4 yellow diagonal, 5 red diagonal.
-- flipFlag: 0 none, 1 X, 2 Y, 3 XY.
--============================================================

function OPT.springPlaneMatches(entity)
	local filter = math.floor(tonumber(entity.planeFilter) or 0)
	if filter == 0 then return true end
	local wantedPlane = (filter - 1) % 2
	return wantedPlane == (tonumber(activeLevelConfig and activeLevelConfig.CollisionPlane) or 0)
end

function OPT.activateSpring(entity)
	if entity.animSpeed > 0 then return end
	entity.frameID = math.min(1, entity.anim and #entity.anim.frames - 1 or 1)
	entity.frameTimer = 0
	entity.frameDuration = entity.anim and entity.anim.frames[entity.frameID + 1]
		and math.max(1, tonumber(entity.anim.frames[entity.frameID + 1].duration) or 1) or 1
	entity.animSpeed = entity.anim and math.max(1, tonumber(entity.anim.animationSpeed) or 128) or 128
	entity.justActivated = true
end

function OPT.springSetPlayerVelocity(entity, vx, vy)
	speedX, speedY = vx, vy
	grounded = false
	onLoop = false
	jumpAbilityState = 0
	dropDashReady = false
	playerState = "Air"
	OPT.bridgeStanding = false
	if vx > 0 then facingRight = true elseif vx < 0 then facingRight = false end
	local springJump = findAnimation("Spring Twirl", "SpringTwirl", "Jump")
	if springJump then setSpriteAnimation(springJump, true, 0) end
end

function OPT.springTryLaunch(e)
	if debugMode or not OPT.springPlaneMatches(e) then return end
	local dx, dy = playerX - e.x, playerY - e.y
	local kind = e.springType > 1
	local flipX = bit32.band(e.flipFlag, 1) ~= 0
	local flipY = bit32.band(e.flipFlag, 2) ~= 0
	if kind == 0 then
		-- Mania checks direction == FLIP_NONE; any non-zero flipFlag makes
		-- this a spring that fires when the player hits its underside.
		if math.abs(dx) <= 16 + WIDTH_RADIUS then
			if e.flipFlag == 0 then
				local feet = playerY + HEIGHT_RADIUS
				if speedY >= 0 and feet >= e.y - 9 and feet <= e.y + 12 then
					OPT.springSetPlayerVelocity(e, 0, e.velocityY)
					OPT.activateSpring(e)
				end
			else
				local head = playerY - HEIGHT_RADIUS
				if speedY <= 0 and head <= e.y + 9 and head >= e.y - 12 then
					OPT.springSetPlayerVelocity(e, 0, -e.velocityY)
					OPT.activateSpring(e)
				end
			end
		end
	elseif kind == 1 then
		-- Horizontal springs use direction == FLIP_NONE for the right-facing face.
		if math.abs(dy) <= 16 + HEIGHT_RADIUS and (not e.onGround or grounded) then
			if e.flipFlag == 0 then
				local gap = (e.x - 8) - (playerX + WIDTH_RADIUS)
				if horizontalInput() >= 0 and gap <= 4 and gap >= -12 then
					local wasGrounded = grounded
					OPT.springSetPlayerVelocity(e, e.velocityX, 0)
					if wasGrounded then grounded = true; playerState = "Ground"; speedY = 0 end
					OPT.activateSpring(e)
				end
			else
				local gap = (playerX - WIDTH_RADIUS) - (e.x + 8)
				if horizontalInput() <= 0 and gap <= 4 and gap >= -12 then
					local wasGrounded = grounded
					OPT.springSetPlayerVelocity(e, -e.velocityX, 0)
					if wasGrounded then grounded = true; playerState = "Ground"; speedY = 0 end
					OPT.activateSpring(e)
				end
			end
		end
	else
		-- Diagonal springs use the native touch-box plus descending/ball check.
		local touching = math.abs(dx) <= 12 + WIDTH_RADIUS and math.abs(dy) <= 12 + HEIGHT_RADIUS
		local canLaunch = grounded or speedY >= 0 or math.abs(speedX) > -speedY
		if touching and canLaunch then
			local vx, vy = e.velocityX, e.velocityY
			if flipX then vx = -vx end
			if flipY then vy = math.abs(vy) else vy = -math.abs(vy) end
			OPT.springSetPlayerVelocity(e, vx, vy)
			OPT.activateSpring(e)
		end
	end
end

objectRegistry["Spring"] = {
	init = function(entity)
		entity.springType = math.floor(tonumber(entity.springType) or 0) % 6
		entity.flipFlag = math.floor(tonumber(entity.flipFlag) or 0) % 4
		entity.planeFilter = math.floor(tonumber(entity.planeFilter) or 0)
		entity.animSpeed = 0
		entity.sfxTimer = 0
		local kind = entity.springType > 1
		local red = (entity.springType % 2) == 1
		if kind == 0 then
			entity.velocityX = 0
			entity.velocityY = red and -16 or -10
		elseif kind == 1 then
			entity.velocityX = red and 16 or 10
			entity.velocityY = 0
		else
			local diagonalSpeed = red and 11.25 or 7.25
			entity.velocityX = diagonalSpeed
			entity.velocityY = -diagonalSpeed
		end
		local sprites = OPT.getObjectSprites("Spring")
		OPT.setEntityAnim(entity, sprites, entity.springType)
		if entity.anim then entity.animSpeed = 0 end
	end,

	update = function(entity)
		if entity.sfxTimer > 0 then entity.sfxTimer -= 1 end
		if OPT.inBounds(entity.x, entity.y, 96, 96) then
			if entity.anim and entity.animSpeed > 0 then
				entity.frameTimer += entity.animSpeed
				local safety = 0
				while entity.frameTimer > entity.frameDuration do
					safety += 1
					if safety > 64 then break end
					entity.frameTimer -= entity.frameDuration
					entity.frameID += 1
					if entity.frameID >= #entity.anim.frames then
						entity.frameID = math.max(0, #entity.anim.frames - 1)
						entity.animSpeed = 0
						break
					end
					entity.frameDuration = math.max(1, tonumber(entity.anim.frames[entity.frameID + 1].duration) or 1)
				end
				if entity.frameID >= 8 then entity.animSpeed = 0 end
			end
			OPT.springTryLaunch(entity)
		end
	end,

	draw = function(e, _buf, viewWidth, viewHeight, camX, camY)
		local sx, sy = e.x - camX, e.y - camY
		if sx < -32 or sx > viewWidth + 32 or sy < -32 or sy > viewHeight + 32 then return end
		local sprites = OPT.getObjectSprites("Spring")
		local frame = e.anim and e.anim.frames[e.frameID + 1]
		local flipX = bit32.band(e.flipFlag, 1) ~= 0
		local flipY = bit32.band(e.flipFlag, 2) ~= 0
		local visualFlipX = flipX ~= flipY
		local rotation = flipY and 256 or 0
		if frame and sprites then
			drawSpriteFrame(frame, sx, sy, rotation, sprites.sheet, visualFlipX)
		else
			local color = (e.springType % 2 == 1) and {230, 48, 48} or {248, 208, 40}
			OPT.drawFrameRect(math.floor(sx - 12), math.floor(sy - 12), 24, 24, color)
			OPT.drawFrameRect(math.floor(sx - 3), math.floor(sy - 3), 6, 6, {255, 255, 255})
		end
	end,
}

--============================================================
-- DDWRECKER (GHZ mini-boss)
-- Expected RSDK modules: DDWreckerPNGData + DDWreckerAnimationData.
-- The arena object in SceneData creates the core, four chain runs and two
-- wrecking balls as one composite renderer entity. Ball vulnerability and
-- player-hit behavior are simulated locally; the RSDK animation indices are
-- kept: ball=0, spiked transition=1, bounce/hit=2, spiked loop=3,
-- chain=4, core=5.
--============================================================

function OPT.ddwreckerSetBallMode(ball, mode, sprites)
	if ball.mode == mode then return end
	ball.mode = mode
	if mode == "vulnerable" then
		OPT.setEntityAnim(ball, sprites, 0)
	elseif mode == "spiked" then
		OPT.setEntityAnim(ball, sprites, 1)
	elseif mode == "hit" then
		OPT.setEntityAnim(ball, sprites, 2)
	end
end

function OPT.ddwreckerBallCollision(boss, ball)
	if ball.dead or ball.invincibilityTimer > 0 or debugMode then return end
	local radius = 20
	local ballPlayer = OPT.playerIsBall()
	local halfH = ballPlayer and 14 or HEIGHT_RADIUS
	if math.abs(playerX - ball.x) > radius + WIDTH_RADIUS
		or math.abs(playerY - ball.y) > radius + halfH then
		return
	end
	if ball.mode == "vulnerable" and ballPlayer then
		ball.health -= 1
		ball.invincibilityTimer = 48
		OPT.ddwreckerSetBallMode(ball, "hit", OPT.getObjectSprites("DDWrecker"))
		if not grounded then speedY = -math.max(3.5, math.abs(speedY) * 0.5) end
		if ball.health <= 0 then
			ball.dead = true
			OPT.spawnExplosion(ball.x, ball.y)
		end
	elseif ball.mode == "spiked" and not ballPlayer then
		OPT.hurtPlayer(ball.x)
	end
end

objectRegistry["DDWrecker"] = {
	init = function(entity)
		entity.started = false
		entity.mode = "waiting"
		entity.timer = 0
		entity.phaseTimer = 0
		entity.coreX = entity.x
		entity.coreY = entity.y - 52
		entity.radius = 68
		entity.spinAngle = 0
		entity.attackSide = 1
		entity.health = math.max(2, math.floor(tonumber(entity.bossHealth) or 6))
		entity.sprites = OPT.getObjectSprites("DDWrecker")
		entity.core = {frameID = 0, frameTimer = 0, frameDuration = 1}
		OPT.setEntityAnim(entity.core, entity.sprites, 5)
		local hitsPerBall = math.max(1, math.ceil(entity.health / 2))
		entity.balls = {
			{x = entity.x - 32, y = entity.y + 48, angle = -math.pi / 2, health = hitsPerBall, invincibilityTimer = 0, mode = nil, dead = false, frameID = 0, frameTimer = 0},
			{x = entity.x + 32, y = entity.y + 48, angle = math.pi / 2, health = hitsPerBall, invincibilityTimer = 0, mode = nil, dead = false, frameID = 0, frameTimer = 0},
		}
		OPT.ddwreckerSetBallMode(entity.balls[1], "spiked", entity.sprites)
		OPT.ddwreckerSetBallMode(entity.balls[2], "vulnerable", entity.sprites)
		entity.chainAnim = {frameID = 0, frameTimer = 0, frameDuration = 1}
		OPT.setEntityAnim(entity.chainAnim, entity.sprites, 4)
	end,

	update = function(entity)
		local sprites = entity.sprites or OPT.getObjectSprites("DDWrecker")
		OPT.stepEntityAnim(entity.core)
		OPT.stepEntityAnim(entity.chainAnim)
		if entity.mode == "waiting" then
			if playerX > entity.x - 24 then
				entity.mode = "assembling"
				entity.timer = 0
				entity.started = true
			end
			return
		end
		if entity.mode == "defeated" then
			entity.timer += 1
			if entity.timer > 90 then entity.dead = true end
			return
		end

		entity.timer += 1
		entity.phaseTimer += 1
		if entity.mode == "assembling" then
			local t = math.clamp(entity.timer / 72, 0, 1)
			entity.coreY = (entity.y + 30) + (entity.y - 52 - (entity.y + 30)) * (t * t * (3 - 2 * t))
			entity.radius = 22 + 46 * t
			entity.spinAngle += 0.055
			if entity.timer >= 72 then
				entity.mode = "spin"
				entity.timer = 0
				entity.phaseTimer = 0
			end
		elseif entity.mode == "spin" then
			entity.spinAngle += 0.045
			entity.radius += (68 - entity.radius) * 0.08
			if entity.phaseTimer >= 150 then
				entity.mode = "attack"
				entity.phaseTimer = 0
				entity.attackSide = -entity.attackSide
			end
		elseif entity.mode == "attack" then
			entity.spinAngle += 0.026
			if entity.phaseTimer >= 72 then
				entity.mode = "return"
				entity.phaseTimer = 0
			end
		elseif entity.mode == "return" then
			entity.spinAngle += 0.04
			if entity.phaseTimer >= 60 then
				entity.mode = "spin"
				entity.phaseTimer = 0
			end
		end

		local attackAmount = 0
		if entity.mode == "attack" then attackAmount = math.sin(math.min(1, entity.phaseTimer / 72) * math.pi / 2) end
		if entity.mode == "return" then attackAmount = 1 - math.min(1, entity.phaseTimer / 60) end
		for i, ball in ipairs(entity.balls) do
			if not ball.dead then
				if ball.invincibilityTimer > 0 then ball.invincibilityTimer -= 1 end
				local baseAngle = entity.spinAngle + (i == 1 and 0 or math.pi)
				local bx = entity.coreX + math.cos(baseAngle) * entity.radius
				local by = entity.coreY + math.sin(baseAngle) * entity.radius
				if i == 1 then
					bx += entity.attackSide * attackAmount * 40
					by += attackAmount * 14
				else
					bx -= entity.attackSide * attackAmount * 22
				end
				ball.x, ball.y = bx, by
				ball.rotationUnits = math.floor((baseAngle * 512 / (2 * math.pi)) % 512)
				if ball.mode == "hit" then
					OPT.stepEntityAnim(ball)
					if not ball.anim or ball.frameID >= #ball.anim.frames - 1 then
						OPT.ddwreckerSetBallMode(ball, ball.health > 0 and "vulnerable" or "spiked", sprites)
					end
				else
					OPT.stepEntityAnim(ball)
					if ball.mode == "spiked" and ball.animID == 1 and ball.anim and ball.frameID >= #ball.anim.frames - 1 then
						OPT.setEntityAnim(ball, sprites, 3)
					end
				end
				-- Alternate which ball is safe to hit between attack patterns, but
				-- do not interrupt a hit animation or an invincibility flash.
				if entity.mode == "spin" and ball.mode ~= "hit" and ball.invincibilityTimer <= 0 then
					if entity.phaseTimer % 150 < 75 then
						OPT.ddwreckerSetBallMode(ball, i == 1 and "vulnerable" or "spiked", sprites)
					else
						OPT.ddwreckerSetBallMode(ball, i == 1 and "spiked" or "vulnerable", sprites)
					end
				end
				OPT.ddwreckerBallCollision(entity, ball)
			end
		end
		local alive = 0
		for _, ball in ipairs(entity.balls) do if not ball.dead then alive += 1 end end
		if alive == 0 then
			entity.mode = "defeated"
			entity.timer = 0
			OPT.hud.score += 1000
			OPT.spawnExplosion(entity.coreX, entity.coreY)
		end
	end,

	draw = function(e, _buf, viewWidth, viewHeight, camX, camY)
		if e.mode == "waiting" then return end
		local sprites = e.sprites or OPT.getObjectSprites("DDWrecker")
		local function drawFrame(animatorState, x, y, rotation, placeholderW, placeholderH, placeholderColor, key)
			local frame = animatorState and animatorState.anim and animatorState.anim.frames[(animatorState.frameID or 0) + 1]
			local sx, sy = x - camX, y - camY
			if sx < -80 or sx > viewWidth + 80 or sy < -80 or sy > viewHeight + 80 then return end
			if frame and sprites then
				drawSpriteFrame(frame, sx, sy, rotation or 0, sprites.sheet, false)
			else
				OPT.drawFrameRect(math.floor(sx - placeholderW / 2), math.floor(sy - placeholderH / 2), placeholderW, placeholderH, placeholderColor)
			end
		end
		local coreX, coreY = e.coreX, e.coreY
		-- The original object has four chain entities. Draw two chain runs to each ball,
		-- repeating the authentic chain frame along each run and rotating it to the cable.
		for _, ball in ipairs(e.balls) do
			if not ball.dead then
				local dx, dy = ball.x - coreX, ball.y - coreY
				local distance = math.sqrt(dx * dx + dy * dy)
				local angle = math.atan2(dy, dx) * (512 / (2 * math.pi))
				for segment = 1, 2 do
					local t = segment / 3
					drawFrame(e.chainAnim, coreX + dx * t, coreY + dy * t, angle, 8, 8, {180, 180, 190}, "chain")
				end
			end
		end
		drawFrame(e.core, coreX, coreY, 0, 36, 36, {90, 100, 120}, "core")
		for _, ball in ipairs(e.balls) do
			if not ball.dead then
				local flicker = ball.invincibilityTimer > 0 and (ball.invincibilityTimer // 3) % 2 == 0
				if not flicker then
					local frame = ball.anim and ball.anim.frames[(ball.frameID or 0) + 1]
					local sx, sy = ball.x - camX, ball.y - camY
					if sx >= -48 and sx <= viewWidth + 48 and sy >= -48 and sy <= viewHeight + 48 then
						local flipFrame = (ball.frameID or 0) >= 16
						if frame and sprites then drawSpriteFrame(frame, sx, sy, ball.rotationUnits or 0, sprites.sheet, flipFrame)
						else OPT.drawFrameRect(math.floor(sx - 20), math.floor(sy - 20), 40, 40, {170, 170, 185}) end
					end
				end
			end
		end
	end,
}


--============================================================
-- TEXT BUBBLES
--============================================================

--============================================================
-- PIMPOM (port of PimPom.c, Sonic Mania SPZ2) - the bouncy pom-pom bumpers
-- Pixels throughout. Angles are RSDK 256-unit, counter-clockwise (screen y is flipped
-- when laying out sprites). Amplitude kept as RSDK's (raw >> 10) "amp10":
-- px offset = amp10 * trig / 64.
--============================================================
OPT.pp = {}
OPT.entitySlotPos = OPT.entitySlotPos or {} -- [objectID/slot] = {x, y}, filled in spawnLevelEntities (Path targets)
OPT.pimPomData = OPT.pimPomData or {}

-- Reads a stage's optional data module: rows keyed by objectID.
function OPT.loadDataRows(stageFolder, moduleName)
	local out = {}
	local module = stageFolder:FindFirstChild(moduleName) or RSDK:FindFirstChild(moduleName)
	if module and module:IsA("ModuleScript") then
		local ok, rows = pcall(require, module)
		if ok and type(rows) == "table" then
			for key, row in pairs(rows) do
				if type(row) == "table" then
					local objectID = tonumber(row.objectID or key)
					if objectID then out[objectID] = row end
				end
			end
		else
			warn("[RSDK] " .. moduleName .. " could not be read: " .. tostring(rows))
		end
	end
	return out
end

function OPT.pp.sin1024(a) return math.sin(a * 2 * math.pi / 1024) end
function OPT.pp.cos1024(a) return math.cos(a * 2 * math.pi / 1024) end

function OPT.pp.setAnim(e, animID, frame)
	OPT.setEntityAnim(e, OPT.getObjectSprites("PimPom"), animID)
	if e.anim then
		frame = math.clamp(math.floor(frame or 0), 0, #e.anim.frames - 1)
		e.frameID = frame
		e.frameTimer = 0
		e.frameDuration = math.max(1, tonumber(e.anim.frames[frame + 1].duration) or 1)
	end
end

-- offset / moveAmount (Create + State_Vertical)
function OPT.pp.geometry(e)
	local step = (e.ppType ~= 0 and 24 or 8) + e.gap
	local a = e.angle * math.pi / 128
	local c, s = math.cos(a), math.sin(a)
	e.offX, e.offY = e.length * step * c, e.length * step * s
	e.moveX, e.moveY = 2 * step * c, 2 * step * s
end

-- Zone_RotateOnPivot about (0,0): same maths for positions (relative) and velocities
function OPT.pp.rotate(dx, dy, angle)
	local a = angle * math.pi / 128
	local c, s = math.cos(a), math.sin(a)
	return dx * c + dy * s, dy * c - dx * s
end

-- Mania keeps a real 2D velocity even on the ground; the engine keeps ground speed.
function OPT.pp.worldVelocity()
	if grounded then
		return speedX * math.cos(groundAngleRad), speedX * math.sin(groundAngleRad)
	end
	return speedX, speedY
end

function OPT.pp.releasePlayer()
	grounded = false
	onLoop = false
	applyJumpCap = false
	skidding = 0
	pushing = 0
	OPT.bridgeStanding = false
	if playerState == "Spindash" then stopGameLoopSound("SpindashCharge") end
	if playerState == "Spindash" or playerState == "Crouch" or playerState == "LookUp" then
		playerState = "Air"
	end
end

function OPT.pp.playSfx(e, name)
	if e.sfxTimer <= 0 then
		playGameSound(name, false)
		e.sfxTimer = 8
	end
end

-- PimPom_State_Single --------------------------------------------------
function OPT.pp.singleHit(e, cx, cy)
	local halfH = OPT.playerIsBall() and 14 or HEIGHT_RADIUS
	local dx, dy = playerX - cx, playerY - cy
	if math.abs(dx) >= WIDTH_RADIUS + 8 or math.abs(dy) >= halfH + 8 then return end -- Player_CheckBadnikTouch

	local wvx, wvy = OPT.pp.worldVelocity()
	local vel = math.max(math.floor(math.abs(wvx + wvy) * 256), 0x600) -- MAX(abs(vy+vx)>>8, 0x600)
	local power = math.random(0x400, vel)
	local angle = (math.floor(math.atan2(dy, dx) * 256 / (2 * math.pi)) % 256) + math.random(-6, 6)
	local p = power / 256
	speedX = p * math.cos(angle * math.pi / 128)
	speedY = p * math.sin(angle * math.pi / 128)
	OPT.pp.releasePlayer()
	OPT.pp.playSfx(e, "PimPom")
end

function OPT.pp.stateSingle(e)
	if debugMode or playerState == "Static" then return end
	local px, py = e.drawX + e.offX, e.drawY - e.offY
	for _ = 0, e.length do
		OPT.pp.singleHit(e, px, py)
		px -= e.moveX
		py += e.moveY
	end
end

-- PimPom_State_Horizontal (also used by Diagonal and Vertical) -----------
-- The player is rotated into the bar's frame, hits a plain box there, then is rotated back.
function OPT.pp.boxSegment(e, cx, cy)
	local wvx, wvy = OPT.pp.worldVelocity()
	local lx, ly = OPT.pp.rotate(playerX - cx, playerY - cy, e.negAngle)
	local lvx, lvy = OPT.pp.rotate(wvx, wvy, e.negAngle)

	local hw, hh = WIDTH_RADIUS, OPT.playerIsBall() and 14 or HEIGHT_RADIUS
	if (((math.floor(e.angle) % 256) - 32) % 128) < 0x40 then hw, hh = hh, hw end -- rotated bars swap the hitbox

	local hb = e.hitbox
	local pTop = ly + hh - hb.top
	local pBottom = hb.bottom - (ly - hh)
	local pLeft = lx + hw - hb.left
	local pRight = hb.right - (lx - hw)
	if pTop <= 0 or pBottom <= 0 or pLeft <= 0 or pRight <= 0 then return end -- C_NONE

	local side, depth = "top", pTop
	if pBottom < depth then side, depth = "bottom", pBottom end
	if pLeft < depth then side, depth = "left", pLeft end
	if pRight < depth then side = "right" end

	local nvx, nvy = lvx, lvy
	if side == "top" then
		ly = hb.top - hh
		nvy = math.clamp(-(lvy + lvy / 16), -14, -4) -- CLAMP(-(v + (v>>4)), -0xE0000, -0x40000)
	elseif side == "bottom" then
		ly = hb.bottom + hh
		nvy = math.clamp(-(lvy + lvy / 16), 4, 14)
	elseif side == "left" then
		lx = hb.left - hw
		nvx = math.clamp(-lvx, -8, -2)
	else
		lx = hb.right + hw
		nvx = math.clamp(-lvx, 2, 8)
	end

	local rx, ry = OPT.pp.rotate(lx, ly, e.angle) -- back out of the bar's frame
	local vx, vy = OPT.pp.rotate(nvx, nvy, e.angle)
	playerX, playerY = cx + rx, cy + ry
	speedX, speedY = vx, vy
	OPT.pp.releasePlayer()
	OPT.pp.playSfx(e, "Bumper2")
end

function OPT.pp.stateHorizontal(e)
	if debugMode or playerState == "Static" then return end
	local px, py = e.drawX, e.drawY
	local len = 0
	if e.gap >= 16 then
		px += e.offX
		py -= e.offY
		len = e.length
	end
	for _ = 0, len do
		OPT.pp.boxSegment(e, px, py)
		px -= e.moveX
		py += e.moveY
	end
end

function OPT.pp.stateVertical(e)
	local spin = backgroundScrollFrame * e.spinSpeed -- Zone->timer * spinSpeed
	if e.direction ~= 0 then spin = -spin end
	e.angle = (e.newAngle % 256) + math.floor(spin / 2)
	e.negAngle = 256 - e.angle
	e.rotation = (2 * e.negAngle) % 512
	OPT.pp.geometry(e)
	OPT.pp.stateHorizontal(e)
end

-- Move states -----------------------------------------------------------
-- Every move except Fixed also drags the following `numChildren` entities along.
function OPT.pp.moveTo(e, nx, ny)
	local mx, my = nx - e.drawX, ny - e.drawY
	e.drawX, e.drawY = nx, ny
	if e.children and (mx ~= 0 or my ~= 0) then
		for _, child in ipairs(e.children) do
			child.x += mx
			child.y += my
		end
	end
end

function OPT.pp.moveFixed(e)
	e.drawX, e.drawY = e.x, e.y
end

function OPT.pp.moveNormal(e)
	local s = OPT.pp.sin1024(e.speed * backgroundScrollFrame)
	OPT.pp.moveTo(e, e.x + e.amp10x * s / 64, e.y + e.amp10y * s / 64)
end

function OPT.pp.moveCircle(e)
	local a = e.speed * backgroundScrollFrame + 4 * e.angleM
	OPT.pp.moveTo(e,
		e.x + e.amp10x * OPT.pp.cos1024(a) / 64,
		e.y + e.amp10y * OPT.pp.sin1024(a) / 64)
end

-- Literal port of the decomp's fixed-point track maths.
function OPT.pp.moveTrack(e)
	local t = backgroundScrollFrame
	local scaled = (t % 65536) * 128
	local ax, ay = e.amp10x, e.amp10y
	local dx, dy
	if math.floor(t / 512) % 2 == e.direction then
		dx = math.floor(scaled * ax / 64) - ax * 32768
		dy = math.floor(scaled * ay / 64) - ay * 32768
	else
		dx = ax * 32768 - math.floor(scaled * ax / 64)
		dy = ay * 32768 - math.floor(scaled * ay / 64)
	end
	OPT.pp.moveTo(e, e.x + dx / 65536, e.y + dy / 65536)
end

function OPT.pp.movePath(e)
	local nx, ny = e.drawX + e.vx, e.drawY + e.vy
	local target = OPT.entitySlotPos[e.speed] -- speed = target entity slot
	if target then
		if e.vx <= 0 then
			if nx < target.x then nx = target.x end
		elseif nx > target.x then
			nx = target.x
		end
		if e.vy <= 0 then
			if ny < target.y then ny = target.y end
		elseif ny > target.y then
			ny = target.y
		end
	end
	OPT.pp.moveTo(e, nx, ny)
end

-- Path PimPoms start inert (ACTIVE_NEVER); call this from whatever object triggers them.
function OPT.pp.startPath(e, vx, vy)
	e.vx, e.vy = vx, vy
	e.active = "normal"
end

-- Resolve each parent's `numChildren` following slots into entity references.
function OPT.pp.linkChildren()
	local byId = {}
	for _, e in ipairs(activeEntities) do
		if e.id ~= nil then byId[e.id] = e end
	end
	for _, e in ipairs(activeEntities) do
		if e.def == objectRegistry["PimPom"] and (e.numChildren or 0) > 0 then
			e.children = {}
			for i = 1, e.numChildren do
				local child = byId[e.id + i]
				if child then table.insert(e.children, child) end
			end
		end
	end
end

objectRegistry["PimPom"] = {
	init = function(e)
		e.ppType = math.floor(tonumber(e.ppType) or 0)
		e.color = math.floor(tonumber(e.color) or 0)
		e.direction = math.floor(tonumber(e.direction) or 0)
		e.spinSpeed = tonumber(e.spinSpeed) or 0
		e.moveType = math.floor(tonumber(e.moveType) or 0)
		e.speed = tonumber(e.speed) or 0
		e.angleM = tonumber(e.angleM) or 0
		e.length = math.max(0, math.floor(tonumber(e.length) or 0))
		e.gap = math.floor(tonumber(e.gap) or 0)
		e.numChildren = math.floor(tonumber(e.numChildren) or 0)
		e.amp10x = math.floor((tonumber(e.ampX) or 0) / 1024) -- amplitude.x >>= 10
		e.amp10y = math.floor((tonumber(e.ampY) or 0) / 1024)
		e.sfxTimer = 0
		e.vx, e.vy = 0, 0
		e.active = "bounds"
		e.drawX, e.drawY = e.x, e.y
		e.flipX = false
		e.useRotation = false

		e.angle = 0x20 * math.floor(tonumber(e.angleProp) or 0)
		e.newAngle = e.angle
		e.negAngle = 256 - e.angle
		e.rotation = 2 * e.negAngle
		OPT.pp.geometry(e)

		local L, G = e.length, e.gap
		if e.ppType == 0 then -- PIMPOM_SINGLE
			OPT.pp.setAnim(e, 0, e.color)
			e.hitbox = { left = -8, top = -8, right = 8, bottom = 8 }
			e.state = OPT.pp.stateSingle
		elseif e.ppType == 1 then -- PIMPOM_HORIZONTAL
			if e.angle == 0x00 then
				OPT.pp.setAnim(e, 1, 0)
			elseif e.angle == 0x20 then
				e.flipX = true
				e.direction = 1
				OPT.pp.setAnim(e, 2, 0)
			elseif e.angle == 0x40 then
				OPT.pp.setAnim(e, 3, 0)
			elseif e.angle == 0x60 then
				OPT.pp.setAnim(e, 2, 0)
			end
			if G >= 16 then
				e.hitbox = { left = -24, top = -8, right = 24, bottom = 8 }
			else
				local len = L * (G + 24)
				e.hitbox = { left = -24 - len, top = -8, right = len + 24, bottom = 8 }
			end
			e.state = OPT.pp.stateHorizontal
		elseif e.ppType == 2 then -- PIMPOM_DIAGONAL
			OPT.pp.setAnim(e, 2, 0)
			e.useRotation = true -- rotation was fixed at Create (before the angle override below)
			e.flipX = e.direction ~= 0
			e.hitbox = { left = -24, top = -6, right = 24, bottom = 6 }
			e.angle = e.direction == 1 and 0x20 or 0xE0
			e.negAngle = 256 - e.angle
			e.state = OPT.pp.stateHorizontal
		elseif e.ppType == 3 then -- PIMPOM_VERTICAL
			OPT.pp.setAnim(e, 1, 0)
			e.useRotation = true
			if G >= 16 then
				e.hitbox = { left = -24, top = -8, right = 24, bottom = 8 }
			else
				local len = L * (G + 24)
				e.hitbox = { left = -24 - len, top = -8, right = len + 24, bottom = 8 }
			end
			e.state = OPT.pp.stateVertical
		else
			e.hitbox = { left = -8, top = -8, right = 8, bottom = 8 }
		end

		-- move type + update range (px)
		local span = L * (G + 24)
		local ax, ay = math.abs(e.amp10x), math.abs(e.amp10y)
		if e.moveType == 1 then
			e.stateMove = OPT.pp.moveNormal
			e.rangeX, e.rangeY = ax / 64 + span + 88, ay / 64 + span + 88
		elseif e.moveType == 2 then
			e.stateMove = OPT.pp.moveCircle
			e.rangeX, e.rangeY = ax / 64 + span + 88, ay / 64 + span + 88
		elseif e.moveType == 3 then
			e.stateMove = OPT.pp.moveTrack
			e.rangeX, e.rangeY = ax / 128 + span + 88, ay / 128 + span + 88
		elseif e.moveType == 4 then
			e.stateMove = OPT.pp.movePath
			e.active = "never"
			e.rangeX, e.rangeY = span + 88, span + 88
		else
			e.stateMove = OPT.pp.moveFixed
			e.rangeX, e.rangeY = span + 88, span + 88
		end
	end,

	update = function(e)
		if e.active == "never" then return end
		if e.active == "bounds" and not OPT.inBounds(e.x, e.y, e.rangeX, e.rangeY) then return end
		if e.state then e.state(e) end
		e.stateMove(e)
		if e.sfxTimer > 0 then e.sfxTimer -= 1 end
	end,

	draw = function(e, _buf, viewWidth, viewHeight, camX, camY)
		local sprites = OPT.getObjectSprites("PimPom")
		local frame = e.anim and e.anim.frames[e.frameID + 1]
		local rotation = e.useRotation and e.rotation or 0
		local x, y = e.drawX + e.offX, e.drawY - e.offY
		for _ = e.length, 0, -1 do
			local sx, sy = x - camX, y - camY
			if sx > -64 and sx < viewWidth + 64 and sy > -64 and sy < viewHeight + 64 then
				if frame and sprites then
					drawSpriteFrame(frame, sx, sy, rotation, sprites.sheet, e.flipX)
				else
					OPT.drawObjectFrame("PimPom", frame, sprites and sprites.sheet, sx, sy, false, 16, 16)
				end
			end
			x -= e.moveX
			y += e.moveY
		end
	end,
}

OPT.bubbles = {}
local lastBubbleMessages = {}

function OPT.wrapBubbleText(text, maxChars)
	text = string.upper((string.gsub(tostring(text or ""), "%s+", " ")))
	local lines, line = {}, ""

	for word in string.gmatch(text, "%S+") do
		while #word > maxChars do
			if line ~= "" then
				table.insert(lines, line)
				line = ""
			end
			table.insert(lines, string.sub(word, 1, maxChars))
			word = string.sub(word, maxChars + 1)
		end

		if line == "" then
			line = word
		elseif #line + 1 + #word <= maxChars then
			line = line .. " " .. word
		else
			table.insert(lines, line)
			line = word
		end
	end

	if line ~= "" then
		table.insert(lines, line)
	end

	if #lines > 4 then
		lines = {
			lines[1],
			lines[2],
			lines[3],
			string.sub(lines[4], 1, maxChars - 2) .. ".."
		}
	end

	return lines
end

function OPT.addBubble(userId, message)
	if type(message) ~= "string" or #message == 0 then
		return
	end

	message = string.sub(message, 1, 120)

	-- Prevent duplicate events from TextChatService and Player.Chatted.
	local now = os.clock()
	local previous = lastBubbleMessages[userId]

	if previous
		and previous.text == message
		and now - previous.time < 1 then
		return
	end

	lastBubbleMessages[userId] = {
		text = message,
		time = now
	}

	local lines = OPT.wrapBubbleText(message, 22)
	if #lines == 0 then
		return
	end

	local widest = 0
	for _, line in ipairs(lines) do
		widest = math.max(widest, #line)
	end

	OPT.bubbles[userId] = {
		lines = lines,
		width = widest,
		age = 0,
		life = 200 + #message * 3
	}
end

-- Listen to every player's chat, including friends.
local function connectPlayerChat(player)
	player.Chatted:Connect(function(message)
		OPT.addBubble(player.UserId, message)
	end)
end

-- Connect players already in the server.
for _, player in ipairs(Players:GetPlayers()) do
	connectPlayerChat(player)
end

-- Connect future players.
Players.PlayerAdded:Connect(connectPlayerChat)

Players.PlayerRemoving:Connect(function(player)
	OPT.bubbles[player.UserId] = nil
	lastBubbleMessages[player.UserId] = nil
end)

-- Modern Roblox TextChatService support.
local TextChatService = game:GetService("TextChatService")

if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
	TextChatService.MessageReceived:Connect(function(message)
		local source = message.TextSource

		if source then
			OPT.addBubble(source.UserId, message.Text)
		end
	end)
end

function OPT.stepBubbles()
	for userId, bubble in pairs(OPT.bubbles) do
		bubble.age += 1

		if bubble.age >= bubble.life then
			OPT.bubbles[userId] = nil
		end
	end
end

function OPT.drawBubble(b, screenX, screenY)
	local textW = b.width * 6 - 1
	local w = textW + 8
	local h = #b.lines * 9 + 5

	local x = math.clamp(
		math.floor(screenX - w / 2),
		1,
		WIDTH - w - 1
	)

	local y = math.floor(screenY - 28 - h)

	if y < 1 then y = 1 end
	if y > HEIGHT - h - 8 then return end

	local black = {0, 0, 0}
	local white = {255, 255, 255}

	OPT.drawFrameRect(x - 1, y - 1, w + 2, h + 2, black)
	OPT.drawFrameRect(x, y, w, h, white)

	-- Speech bubble tail.
	local tailX = math.clamp(
		math.floor(screenX),
		x + 3,
		x + w - 4
	)

	OPT.drawFrameRect(tailX - 2, y + h + 1, 5, 1, black)
	OPT.drawFrameRect(tailX - 1, y + h + 2, 3, 1, black)
	OPT.drawFrameRect(tailX, y + h + 3, 1, 1, black)
	OPT.drawFrameRect(tailX - 1, y + h, 3, 1, white)
	OPT.drawFrameRect(tailX, y + h + 1, 1, 1, white)

	for i, line in ipairs(b.lines) do
		OPT.drawFrameText(
			line,
			x + 4,
			y + 3 + (i - 1) * 9,
			black
		)
	end
end

function OPT.drawAllBubbles(camX, camY)
	local localId = Players.LocalPlayer.UserId

	-- Local player's bubble.
	local mine = OPT.bubbles[localId]

	if mine and not menuOpen then
		OPT.drawBubble(
			mine,
			playerX - camX,
			playerY - camY
		)
	end

	-- Other players' bubbles.
	for userId, s in pairs(OPT.mp.players) do
		local bubble = OPT.bubbles[userId]

		if bubble and s.levelKey == selectedLevelName then
			OPT.drawBubble(
				bubble,
				s.drawX - camX,
				s.drawY - camY
			)
		end
	end
end


function OPT.drawExplosions(camX, camY)
	-- Authentic one-shot sprite effects (including Motobug destruction).
	for _, effect in ipairs(OPT.spriteEffects) do
		local frame = effect.animation.frames[effect.frameID + 1]
		if frame then
			drawSpriteFrame(frame, effect.x - camX, effect.y - camY, 0, effect.sheet, effect.flipX)
		end
	end

	-- Keep the old diagnostic-circle effect for other badniks only.
	for i = #OPT.fx, 1, -1 do
		local fx = OPT.fx[i]
		local sx, sy = math.floor(fx.x - camX), math.floor(fx.y - camY)
		OPT.drawDebugCircle(sx, sy, 3 + fx.age * 0.9, fx.age < 7 and WHITE or YELLOW, 1.2)
		if fx.age < 6 then OPT.drawDebugCircle(sx, sy, fx.age * 0.5, ORANGE, 1) end
	end
end

function OPT.stepExplosions()
	OPT.stepSpriteEffects()
	for i = #OPT.fx, 1, -1 do
		OPT.fx[i].age += 1
		if OPT.fx[i].age > 14 then table.remove(OPT.fx, i) end
	end
end

--============================================================
-- DEBUG MODE OBJECT ART / PIXEL HUD
--============================================================

-- Circle pixel offsets are computed once per (radius, thickness) pair and
-- reused; no sqrt per pixel per frame.
function OPT.getCircleOffsets(radius, thickness)
	local key = radius * 1000 + thickness
	local offsets = OPT.circleCache[key]
	if offsets then return offsets end
	offsets = {}
	local inner = math.max(0, radius - thickness)
	local outer = radius + thickness
	local reach = math.ceil(outer)
	local innerSq, outerSq = inner * inner, outer * outer
	for y = -reach, reach do
		for x = -reach, reach do
			local distSq = x * x + y * y
			if distSq >= innerSq and distSq <= outerSq then
				table.insert(offsets, x)
				table.insert(offsets, y)
			end
		end
	end
	OPT.circleCache[key] = offsets
	return offsets
end

function OPT.drawDebugCircle(centerX, centerY, radius, color, thickness)
	local offsets = OPT.getCircleOffsets(radius, thickness or 1.5)
	for i = 1, #offsets, 2 do
		pixel(centerX + offsets[i], centerY + offsets[i + 1], color)
	end
end

function OPT.drawDebugObject(object)
	local x = math.floor(object.X - (usingRSDKLevel and cameraX or 0) + 0.5)
	local y = math.floor(object.Y - (usingRSDKLevel and cameraY or 0) + 0.5)
	-- Off-screen culling: every object sprite fits within 16px of its origin.
	if x < -16 or x > WIDTH + 16 or y < -16 or y > HEIGHT + 16 then return end

	if object.Kind == "Ring" then
		OPT.drawDebugCircle(x, y, 5, YELLOW, 1.2)
	elseif object.Kind == "Monitor" then
		OPT.drawLine(x - 6, y - 6, x + 6, y - 6, WHITE)
		OPT.drawLine(x + 6, y - 6, x + 6, y + 6, WHITE)
		OPT.drawLine(x + 6, y + 6, x - 6, y + 6, WHITE)
		OPT.drawLine(x - 6, y + 6, x - 6, y - 6, WHITE)
		OPT.drawLine(x - 3, y - 2, x + 3, y - 2, CYAN)
		OPT.drawLine(x - 3, y + 1, x + 3, y + 1, CYAN)
		OPT.drawLine(x, y + 6, x, y + 9, WHITE)
	elseif object.Kind == "Spring" then
		OPT.drawLine(x - 7, y + 7, x + 7, y + 7, WHITE)
		OPT.drawLine(x - 6, y + 6, x - 4, y + 2, ORANGE)
		OPT.drawLine(x - 4, y + 2, x - 1, y + 6, ORANGE)
		OPT.drawLine(x - 1, y + 6, x + 2, y + 2, ORANGE)
		OPT.drawLine(x + 2, y + 2, x + 5, y - 3, ORANGE)
		OPT.drawLine(x - 7, y - 4, x + 7, y - 4, YELLOW)
	elseif object.Kind == "Spikes" then
		OPT.drawLine(x - 9, y + 6, x - 5, y - 5, WHITE)
		OPT.drawLine(x - 5, y - 5, x - 1, y + 6, WHITE)
		OPT.drawLine(x - 1, y + 6, x + 3, y - 5, WHITE)
		OPT.drawLine(x + 3, y - 5, x + 7, y + 6, WHITE)
		OPT.drawLine(x + 7, y + 6, x + 10, y + 6, WHITE)
	elseif object.Kind == "StarPost" then
		OPT.drawLine(x, y + 9, x, y - 8, CYAN)
		OPT.drawDebugCircle(x, y - 8, 4, YELLOW, 1)
		OPT.drawLine(x - 3, y + 9, x + 3, y + 9, WHITE)
	elseif object.Kind == "Capsule" then
		OPT.drawLine(x - 7, y - 7, x + 7, y - 7, WHITE)
		OPT.drawLine(x + 7, y - 7, x + 7, y + 7, WHITE)
		OPT.drawLine(x + 7, y + 7, x - 7, y + 7, WHITE)
		OPT.drawLine(x - 7, y + 7, x - 7, y - 7, WHITE)
		OPT.drawLine(x - 7, y, x + 7, y, ORANGE)
		OPT.drawDebugCircle(x, y, 2, YELLOW, 1)
	end
end

-- Cache solid scanlines by packed color and visible width. The original
-- per-pixel rectangle loop performed over 100,000 Luau calls for the TitleCard
-- full-screen panels every frame; copying one prepared row per scanline is far
-- cheaper and prevents the intro from stalling the renderer.
OPT.frameRectRowCache = OPT.frameRectRowCache or {}

function OPT.drawFrameRect(x, y, width, height, color)
	x = math.floor(tonumber(x) or 0)
	y = math.floor(tonumber(y) or 0)
	width = math.floor(tonumber(width) or 0)
	height = math.floor(tonumber(height) or 0)
	if width <= 0 or height <= 0 then return end

	local left = math.max(0, x)
	local top = math.max(0, y)
	local right = math.min(WIDTH, x + width)
	local bottom = math.min(HEIGHT, y + height)
	if left >= right or top >= bottom then return end

	local visibleWidth = right - left
	local rowBytes = visibleWidth * 4
	local packed = getPackedPixelColor(color)
	local rowsByWidth = OPT.frameRectRowCache[packed]
	if not rowsByWidth then
		rowsByWidth = {}
		OPT.frameRectRowCache[packed] = rowsByWidth
	end

	local row = rowsByWidth[visibleWidth]
	if not row then
		row = buffer.create(rowBytes)
		for offset = 0, rowBytes - 4, 4 do
			writePixelU32(row, offset, packed)
		end
		rowsByWidth[visibleWidth] = row
	end

	for py = top, bottom - 1 do
		buffer.copy(framePixels, (py * WIDTH + left) * 4, row, 0, rowBytes)
	end
end

function OPT.drawFrameText(text, x, y, color, maxChars)
	text = string.upper(tostring(text or ""))
	if maxChars then text = string.sub(text, 1, maxChars) end
	local cursorX = x
	for index = 1, #text do
		local char = string.sub(text, index, index)
		local points = PIXEL_GLYPH_OFFSETS[char] or PIXEL_GLYPH_OFFSETS["?"]
		for pointIndex = 1, #points, 2 do
			putPixel(framePixels, cursorX + points[pointIndex], y + points[pointIndex + 1], color)
		end
		cursorX += 6
	end
end

-- Animation IDs and frame IDs below are zero-based, matching the C objects.
-- HUD.bin: elements=0, numbers=1, lives=2, hyper numbers=9.
-- TitleCard.bin: decoration=0, name letters=1, zone letters=2, act numbers=3.
function OPT.getAnimationFrame(sprites, animationID, frameID)
	local animation = sprites and sprites.animations and sprites.animations[animationID + 1]
	if not animation or type(animation.frames) ~= "table" then return nil end
	return animation.frames[(math.max(0, math.floor(tonumber(frameID) or 0))) + 1]
end

function OPT.drawAnimationFrame(sprites, animationID, frameID, x, y, flipX, clipRect)
	local frame = OPT.getAnimationFrame(sprites, animationID, frameID)
	if not frame or not sprites or not sprites.sheet then return false end
	return drawSpriteFrame(frame, x, y, 0, sprites.sheet, flipX == true, false, clipRect)
end

function OPT.drawHUDNumbers(sprites, x, y, value, digitCount)
	value = math.max(0, math.floor(tonumber(value) or 0))
	if not digitCount then
		digitCount = 1
		local probe = value
		while probe >= 10 do digitCount += 1; probe = math.floor(probe / 10) end
	end
	local place = 1
	for _ = 1, digitCount do
		local digit = math.floor(value / place) % 10
		if not OPT.drawAnimationFrame(sprites, 1, digit, x, y) then
			OPT.drawFrameText(tostring(digit), x - 2, y - 3, WHITE, 1)
		end
		place *= 10
		x -= 8
	end
	-- Match HUD_DrawNumbersBase10: it leaves the caller's draw position
	-- one digit-step left of the last rendered digit.
	return x
end

function OPT.drawHUD()
	local hud = OPT.hud
	if not hud or not hud.visible or menuOpen or not usingRSDKLevel or (OPT.titleCard and OPT.titleCard.active) then return end
	local sprites = OPT.getObjectSprites("HUD")
	local scorePos = Vector2.new(16, 12)
	local timePos = Vector2.new(16, 28)
	local ringsPos = Vector2.new(16, 44)
	local lifePos = Vector2.new(16, HEIGHT - 12)
	local flash = ((hud.ticks // 8) % 2) == 1
	local minutes = math.floor(hud.ticks / 3600)
	local seconds = math.floor(hud.ticks / 60) % 60
	local hundredths = math.floor((hud.ticks % 60) * (100 / 60))

	if not sprites then
		OPT.drawFrameText("SCORE " .. string.format("%06d", hud.score), 16, 8, WHITE, 18)
		OPT.drawFrameText(string.format("TIME: %d %02d %02d", minutes, seconds, hundredths), 16, 24, WHITE, 22)
		OPT.drawFrameText("RINGS " .. string.format("%03d", ringCount), 16, 40, YELLOW, 18)
		OPT.drawFrameText("LIVES " .. tostring(hud.lives), 16, HEIGHT - 18, WHITE, 12)
		return
	end

	-- Score label and value.
	if not OPT.drawAnimationFrame(sprites, 0, 0, scorePos.X, scorePos.Y) then
		OPT.drawFrameText("SCORE", 16, 8, WHITE, 8)
	end
	OPT.drawHUDNumbers(sprites, scorePos.X + 97, scorePos.Y + 14, hud.score)

	-- Time label, colon, hundredths, seconds and minutes.
	-- Mania only flashes the TIME label once the clock reaches minute 9.
	-- The ring label keeps its separate zero-rings flash below.
	local timeLabelFrame = (minutes == 9 and flash) and 2 or 1
	if not OPT.drawAnimationFrame(sprites, 0, timeLabelFrame, timePos.X, timePos.Y) then
		OPT.drawFrameText("TIME", 16, 24, WHITE, 6)
	end
	OPT.drawAnimationFrame(sprites, 0, 12, timePos.X + 52, timePos.Y - 2)

	-- Draw the clock groups sequentially. drawHUDNumbers returns the next
	-- X position after its digits, just like the original HUD helper mutates
	-- its Vector2 pointer. The 9px group spacing is applied after each pair.
	local timerY = timePos.Y + 14
	local timerX = timePos.X + 97
	timerX = OPT.drawHUDNumbers(sprites, timerX, timerY, hundredths, 2) - 9
	timerX = OPT.drawHUDNumbers(sprites, timerX, timerY, seconds, 2) - 9
	local minuteDigits = minutes >= 10 and 2 or 1
	OPT.drawHUDNumbers(sprites, timerX, timerY, minutes, minuteDigits)

	-- Rings label and value. Its label flashes while the ring count is zero.
	if not OPT.drawAnimationFrame(sprites, 0, (ringCount == 0 and flash) and 4 or 3, ringsPos.X, ringsPos.Y) then
		OPT.drawFrameText("RINGS", 16, 40, WHITE, 8)
	end
	OPT.drawHUDNumbers(sprites, ringsPos.X + 97, ringsPos.Y + 14, ringCount)

	-- Character icon, multiplication sign and lives count.
	if not OPT.drawAnimationFrame(sprites, 2, 0, lifePos.X, lifePos.Y) then
		OPT.drawFrameText("SONIC", 8, HEIGHT - 18, WHITE, 8)
	end
	OPT.drawAnimationFrame(sprites, 0, 14, lifePos.X + 20, lifePos.Y)
	local livesX = lifePos.X + (hud.lives < 10 and 40 or 48)
	OPT.drawHUDNumbers(sprites, livesX, lifePos.Y + 2, hud.lives)
end

function OPT.drawFrameSpan(y, left, right, color)
	left = math.max(0, math.floor(left))
	right = math.min(WIDTH - 1, math.floor(right))
	y = math.floor(y)
	if y < 0 or y >= HEIGHT or left > right then return end
	local width = right - left + 1
	local packed = getPackedPixelColor(color)
	local byWidth = OPT.frameRectRowCache[packed]
	if not byWidth then byWidth = {}; OPT.frameRectRowCache[packed] = byWidth end
	local row = byWidth[width]
	if not row then
		row = buffer.create(width * 4)
		for offset = 0, width * 4 - 4, 4 do writePixelU32(row, offset, packed) end
		byWidth[width] = row
	end
	buffer.copy(framePixels, (y * WIDTH + left) * 4, row, 0, width * 4)
end

function OPT.drawFramePolygon(points, color)
	if type(points) ~= "table" or #points < 3 then return end
	local minY, maxY = math.huge, -math.huge
	for _, point in ipairs(points) do
		minY = math.min(minY, point[2])
		maxY = math.max(maxY, point[2])
	end
	for y = math.max(0, math.floor(minY)), math.min(HEIGHT - 1, math.ceil(maxY)) do
		local scanY = y + 0.5
		local intersections = {}
		for i = 1, #points do
			local a = points[i]
			local b = points[(i % #points) + 1]
			if (a[2] <= scanY and b[2] > scanY) or (b[2] <= scanY and a[2] > scanY) then
				local t = (scanY - a[2]) / (b[2] - a[2])
				table.insert(intersections, a[1] + (b[1] - a[1]) * t)
			end
		end
		table.sort(intersections)
		for i = 1, #intersections - 1, 2 do
			OPT.drawFrameSpan(y, math.ceil(intersections[i]), math.floor(intersections[i + 1]), color)
		end
	end
end

-- Width of the RSDK sprite-font string. Animation 1 is indexed by ASCII-32;
-- spaces advance the pen but don't draw a glyph, as in RSDK's DrawText.
function OPT.titleCardTextWidth(sprites, text)
	local animation = sprites and sprites.animations and sprites.animations[2]
	local width = 0
	for i = 1, #text do
		local byte = string.byte(string.upper(string.sub(text, i, i)))
		if byte == 32 then
			width += 5
		else
			local frame = animation and animation.frames and animation.frames[byte - 31]
			width += (frame and tonumber(frame.width) or 8) + 1
		end
	end
	return width
end

function OPT.initializeTitleCardGeometry(card)
	local sprites = card.sprites
	local text = card.zoneName or "UNTITLED"
	local splitAt = string.find(text, " ", 1, true)
	card.hasTwoWords = splitAt ~= nil
	if splitAt then
		card.word1 = string.sub(text, 1, splitAt - 1)
		card.word2 = string.sub(text, splitAt + 1)
	else
		card.word1 = ""
		card.word2 = text
	end
	card.word1Width = card.hasTwoWords and (OPT.titleCardTextWidth(sprites, card.word1) + 24) or 0
	card.word2Width = OPT.titleCardTextWidth(sprites, card.word2) + 24

	local centerX = WIDTH / 2
	local baseX = centerX - math.floor((centerX - 160) / 8) + 72
	card.zoneXPos = baseX
	card.word2XPos = baseX
	if card.word2Width < 128 then card.word2XPos -= 40 end
	card.word1XPos = card.word1Width - card.word2Width + card.word2XPos - 32
	card.decorationX = WIDTH - 160
	card.decorationY = -52
	card.actNumX = centerX + 106
	card.actNumY = 168
	card.actNumScale = -0.5

	if card.word2XPos - card.word2Width < 16 then
		local dist = (card.word2XPos - card.word2Width) - 16
		card.word1XPos -= dist
		card.zoneXPos -= dist
		card.actNumX -= dist
		card.word2XPos -= dist
	end

	card.charPos = {}
	card.charVel = {}
	for i = 1, #text do
		card.charPos[i] = 40 + (i - 1) * 16
		card.charVel[i] = -8
	end
	card.zoneCharPos = {}
	card.zoneCharVel = {}
	for i = 1, 4 do
		card.zoneCharPos[i] = (2 - #text) * 8 - ((i - 1) * 16)
		card.zoneCharVel[i] = 4
	end

	local cx = centerX
	local stripPos = {cx - 152, cx - 152, cx - 160, cx + 20}
	local function rect(x1, y1, x2, y2)
		return {{x1,y1},{x2,y1},{x2,y2},{x1,y2}}
	end
	local function quad(x1, y1, x2, y2, x3, y3, x4, y4)
		return {{x1,y1},{x2,y2},{x3,y3},{x4,y4}}
	end
	card.geometry = {
		vertMove = {{240,496},{752,1008}},
		vertTarget = {{0,138},{74,112}},
		word1 = rect(-card.word1Width,82,0,98),
		word2 = rect(-card.word2Width,186,0,202),
		zone = rect(WIDTH,154,WIDTH+120,162),
		blue = quad(stripPos[1],240,stripPos[1]+64,240,stripPos[1]+304,240,stripPos[1]+240,240),
		red = quad(stripPos[2],240,stripPos[2]+128,240,stripPos[2]+230,240,stripPos[2]+102,240),
		orange = quad(stripPos[3],240,stripPos[3]+240,240,stripPos[3]+262,240,stripPos[3]+166,240),
		green = quad(stripPos[4],240,stripPos[4]+32,240,stripPos[4]+160,240,stripPos[4]+128,240),
		curtainLeft = quad(0,0,(stripPos[1]+stripPos[1]+64)/2,0,(stripPos[1]+240+stripPos[1]+304)/2,240,0,240),
		curtainRight = quad((stripPos[1]+stripPos[1]+64)/2,0,WIDTH,0,WIDTH,240,(stripPos[1]+240+stripPos[1]+304)/2,240),
	}
end

function OPT.drawTitleCardSpriteText(sprites, text, centerX, y, offsets, firstChar, clipRect, fallbackColor)
	text = tostring(text or "")
	local animation = sprites and sprites.animations and sprites.animations[2]
	if not animation or type(animation.frames) ~= "table" or #animation.frames < 64 then
		local fallback = string.upper(text)
		OPT.drawFrameText(fallback, math.floor(centerX - #fallback * 3), y, fallbackColor or WHITE, 52)
		return false
	end
	local totalWidth = OPT.titleCardTextWidth(sprites, text)
	local cursorX = centerX - totalWidth / 2
	local charBase = (firstChar or 1) - 1
	for i = 1, #text do
		local char = string.sub(text, i, i)
		local byte = string.byte(string.upper(char))
		local charY = y + (offsets and (offsets[charBase + i] or 0) or 0)
		if byte == 32 then
			cursorX += 5
		else
			local frame = animation.frames[byte - 31]
			if frame then
				local fw = tonumber(frame.width) or 8
				drawSpriteFrame(frame, cursorX + fw / 2, charY, 0, sprites.sheet, false, false, clipRect)
				cursorX += fw + 1
			else
				cursorX += 9
			end
		end
	end
	return true
end

function OPT.drawTitleCardScaledFrame(sprites, animationID, frameID, centerX, centerY, scaleX, scaleY)
	local frame = OPT.getAnimationFrame(sprites, animationID, frameID)
	if not frame or not sprites or not sprites.sheet then return false end
	scaleX = math.max(0, tonumber(scaleX) or 1)
	scaleY = math.max(0, tonumber(scaleY) or 1)
	if scaleX <= 0.001 or scaleY <= 0.001 then return true end
	if math.abs(scaleX - 1) < 0.001 and math.abs(scaleY - 1) < 0.001 then
		return drawSpriteFrame(frame, centerX, centerY, 0, sprites.sheet, false)
	end
	local sheet = sprites.sheet
	local fw, fh = frame.width, frame.height
	if not fw or not fh or fw <= 0 or fh <= 0 then return false end
	local pivotX, pivotY = tonumber(frame.pivotX) or 0, tonumber(frame.pivotY) or 0
	local left = pivotX * scaleX
	local top = pivotY * scaleY
	local x0 = math.max(0, math.floor(centerX + left + SPRITE_OFFSET_X))
	local x1 = math.min(WIDTH - 1, math.ceil(centerX + (pivotX + fw) * scaleX + SPRITE_OFFSET_X))
	local y0 = math.max(0, math.floor(centerY + top + SPRITE_OFFSET_Y))
	local y1 = math.min(HEIGHT - 1, math.ceil(centerY + (pivotY + fh) * scaleY + SPRITE_OFFSET_Y))
	if x0 > x1 or y0 > y1 then return true end
	local sx0, sy0 = tonumber(frame.sprX), tonumber(frame.sprY)
	if not sx0 or not sy0 or sx0 < 0 or sy0 < 0 or sx0 + fw > sheet.width or sy0 + fh > sheet.height then return false end
	local readu32, readu8, writeu32 = buffer.readu32, buffer.readu8, buffer.writeu32
	for py = y0, y1 do
		local srcY = math.floor((py + 0.5 - centerY - SPRITE_OFFSET_Y) / scaleY - pivotY)
		if srcY >= 0 and srcY < fh then
			for px = x0, x1 do
				local srcX = math.floor((px + 0.5 - centerX - SPRITE_OFFSET_X) / scaleX - pivotX)
				if srcX >= 0 and srcX < fw then
					local packed = readu32(sheet.pixels, ((sy0 + srcY) * sheet.width + sx0 + srcX) * 4)
					local alpha = packed // 16777216
					if alpha == 255 then
						writeu32(framePixels, (py * WIDTH + px) * 4, packed)
					elseif alpha > 0 then
						local offset = (py * WIDTH + px) * 4
						local inverse = 255 - alpha
						local r = math.floor(((packed % 256) * alpha + readu8(framePixels, offset) * inverse) / 255 + 0.5)
						local g = math.floor((((packed // 256) % 256) * alpha + readu8(framePixels, offset + 1) * inverse) / 255 + 0.5)
						local b = math.floor((((packed // 65536) % 256) * alpha + readu8(framePixels, offset + 2) * inverse) / 255 + 0.5)
						writeu32(framePixels, offset, r + g * 256 + b * 65536 + 0xFF000000)
					end
				end
			end
		end
	end
	return true
end

function OPT.drawTitleCard()
	local card = OPT.titleCard
	if not card or not card.active then return end
	local sprites = card.sprites
	local g = card.geometry
	local colors = card.colors
	local function drawLogo()
		OPT.drawAnimationFrame(sprites, 0, 1, card.decorationX, card.decorationY)
	end
	local function drawPanels()
		if card.hasTwoWords then OPT.drawFramePolygon(g.word1, {0,0,0}) end
		OPT.drawFramePolygon(g.word2, {0,0,0})
		OPT.drawFramePolygon(g.zone, {240,240,240})
	end
	local function drawZoneLetters(clipped)
		local anim = sprites and sprites.animations and sprites.animations[3]
		if anim and anim.frames and #anim.frames >= 4 then
			local clip = clipped and {left=0,top=170,right=WIDTH-1,bottom=HEIGHT-1} or nil
			for i = 1, 4 do
				OPT.drawAnimationFrame(sprites, 2, i - 1, card.zoneXPos,
					186 + card.zoneCharPos[i], false, clip)
			end
		else
			OPT.drawFrameText("ZONE", math.floor(card.zoneXPos - 12), 181, {0,0,0}, 4)
		end
	end
	local function drawTitleWords(slideAway)
		local clipFirst = slideAway and nil or {left=0,top=0,right=WIDTH-1,bottom=129}
		local clipSecond = slideAway and nil or {left=0,top=0,right=WIDTH-1,bottom=169}
		if card.hasTwoWords then
			OPT.drawTitleCardSpriteText(sprites, card.word1, card.word1XPos - 20, 114,
				card.charPos, 1, clipFirst, WHITE)
		end
		local firstIndex = card.hasTwoWords and (#card.word1 + 2) or 1
		OPT.drawTitleCardSpriteText(sprites, card.word2, card.word2XPos - 20, 154,
			card.charPos, firstIndex, clipSecond, WHITE)
	end
	local function drawActNumber(scaled)
		if card.actFrameID == 3 then return end
		if scaled then
			if card.actNumScale > 0 then
				local decorationScale = math.clamp(card.actNumScale, 0, 1)
				local numberScale = math.clamp(card.actNumScale - 0.5, 0, 1)
				OPT.drawTitleCardScaledFrame(sprites, 0, 0, card.actNumX, card.actNumY, decorationScale, 1)
				OPT.drawTitleCardScaledFrame(sprites, 3, card.actFrameID, card.actNumX, card.actNumY, numberScale, 1)
			end
		else
			OPT.drawAnimationFrame(sprites, 0, 0, card.actNumX, card.actNumY)
			OPT.drawAnimationFrame(sprites, 3, card.actFrameID, card.actNumX, card.actNumY)
		end
	end

	if card.phase == "setup" or card.phase == "opening" then
		-- Exact SlideIn stack from TitleCard_Draw_SlideIn: five centered
		-- horizontal colour fields grow in sequence, not diagonal ribbons.
		if card.timer < 256 then OPT.drawFrameRect(0, 0, WIDTH, HEIGHT, {0,0,0}) end
		local h = card.timer
		if card.timer < 512 and h > 0 then OPT.drawFrameRect(0, HEIGHT/2 - math.floor(h/2), WIDTH, h, colors[4]) end
		h = card.timer - 128
		if card.timer > 128 and card.timer < 640 and h > 0 then OPT.drawFrameRect(0, HEIGHT/2 - math.floor(h/2), WIDTH, h, colors[3]) end
		h = card.timer - 256
		if card.timer > 256 and card.timer < 768 and h > 0 then OPT.drawFrameRect(0, HEIGHT/2 - math.floor(h/2), WIDTH, h, colors[1]) end
		h = card.timer - 384
		if card.timer > 384 and card.timer < 896 and h > 0 then OPT.drawFrameRect(0, HEIGHT/2 - math.floor(h/2), WIDTH, h, colors[2]) end
		h = card.timer - 512
		if card.timer > 512 and h > 0 then OPT.drawFrameRect(0, HEIGHT/2 - math.floor(h/2), WIDTH, h, colors[5]) end
		drawPanels()
		drawLogo()
		return
	end

	if card.phase == "enterTitle" or card.phase == "show" then
		OPT.drawFrameRect(0, 0, WIDTH, HEIGHT, colors[5])
		if g.vertMove[2][1] < 240 then OPT.drawFramePolygon(g.orange, colors[1]) end
		if g.vertMove[2][2] < 240 then OPT.drawFramePolygon(g.green, colors[2]) end
		if g.vertMove[1][2] < 240 then OPT.drawFramePolygon(g.red, colors[3]) end
		if g.vertMove[1][1] < 240 then OPT.drawFramePolygon(g.blue, colors[4]) end
		drawLogo()
		drawPanels()
		drawZoneLetters(true)
		drawTitleWords(false)
		drawActNumber(true)
		return
	end

	if card.phase == "slideAway" then
		OPT.drawFramePolygon(g.curtainLeft, colors[5])
		OPT.drawFramePolygon(g.curtainRight, colors[5])
		if g.vertMove[2][1] < 240 then OPT.drawFramePolygon(g.orange, colors[1]) end
		if g.vertMove[2][2] < 240 then OPT.drawFramePolygon(g.green, colors[2]) end
		if g.vertMove[1][2] < 240 then OPT.drawFramePolygon(g.red, colors[3]) end
		if g.vertMove[1][1] < 240 then OPT.drawFramePolygon(g.blue, colors[4]) end
		drawLogo()
		drawActNumber(false)
		drawPanels()
		drawZoneLetters(false)
		drawTitleWords(true)
	end
end

function OPT.drawDebugCursorAndHud()
	local screenX = math.floor(debugCursorX - (usingRSDKLevel and cameraX or 0) + 0.5)
	local screenY = math.floor(debugCursorY - (usingRSDKLevel and cameraY or 0) + 0.5)

	-- Tiny marker showing exactly where a placed object will appear.
	OPT.drawLine(screenX - 3, screenY, screenX + 3, screenY, CYAN)
	OPT.drawLine(screenX, screenY - 3, screenX, screenY + 3, CYAN)

	OPT.drawFrameRect(0, 0, 184, 43, {0, 0, 0})
	OPT.drawFrameText("DEBUG MODE", 5, 3, YELLOW, 20)
	OPT.drawFrameText("ITEM: " .. debugObjectTypes[debugSelectedIndex].Name, 5, 12, WHITE, 28)
	OPT.drawFrameText("Z NEXT SPACE PLACE", 5, 21, CYAN, 29)
	OPT.drawFrameText(string.format("X %03d Y %03d", math.floor(debugCursorX), math.floor(debugCursorY)), 5, 31, WHITE, 22)
end

--============================================================
-- INTEGRATED RSDK BACKGROUND / LAYER RENDERING
-- This lives in the existing engine LocalScript. It deliberately reuses the
-- existing RSDKLevelParser.RenderViewport tile renderer one layer at a time;
-- no additional ModuleScript or duplicate parser is required.
--============================================================

function OPT.isBackgroundLayerName(layerName)
	local lowerName = string.lower(tostring(layerName or ""))
	return string.find(lowerName, "background", 1, true) ~= nil
		or string.match(lowerName, "^%s*bg[%s_%-]?") ~= nil
end

function OPT.isFrontTileLayer(layerName)
	return string.find(string.lower(tostring(layerName or "")), "fg high", 1, true) ~= nil
end

function OPT.positiveModulo(value, divisor)
	return ((value % divisor) + divisor) % divisor
end

function OPT.getLayerRenderCopies(cameraOffset, mapPixelSize, viewPixelSize, shouldRepeat)
	if not shouldRepeat or mapPixelSize <= 0 then
		return { cameraOffset }
	end

	-- Normalize the first copy into the map, then add enough preceding/following
	-- copies to cover the viewport even when the background map is narrower than
	-- the canvas. Negative camera offsets are supported by RenderViewport's
	-- existing tile clipping and let tile zero appear at the wrap seam.
	local phase = OPT.positiveModulo(cameraOffset, mapPixelSize)
	local copies = table.create(math.ceil(viewPixelSize / mapPixelSize) + 2)
	local copyCount = math.ceil(viewPixelSize / mapPixelSize) + 1
	for copyIndex = 0, copyCount do
		local copyCamera = phase - copyIndex * mapPixelSize
		if -copyCamera < viewPixelSize then
			table.insert(copies, copyCamera)
		end
	end
	return copies
end

function OPT.getEngineLayerProxy(level, layer)
	-- RenderViewport's public pass filter draws only "FG High" when pass="front".
	-- A shallow one-layer proxy lets the engine reuse that renderer for any
	-- selected layer without touching the real parsed layer or collision data.
	local cached = layer._engineViewportProxy
	if cached then
		cached.proxyLayer.tileData = layer.tileData
		cached.proxyLayer.width = layer.width
		cached.proxyLayer.height = layer.height
		cached.proxyLevel.widthTiles = layer.width
		cached.proxyLevel.heightTiles = layer.height
		return cached.proxyLevel
	end

	local proxyLayer = {}
	for key, value in pairs(layer) do
		if key ~= "_engineViewportProxy" then
			proxyLayer[key] = value
		end
	end
	proxyLayer.name = "FG High"
	local proxyLevel = {
		layers = { proxyLayer },
		widthTiles = layer.width,
		heightTiles = layer.height,
		backgroundColor1 = level.backgroundColor1,
	}
	layer._engineViewportProxy = {
		proxyLayer = proxyLayer,
		proxyLevel = proxyLevel,
	}
	return proxyLevel
end

function OPT.fillLevelBackground(level, target, viewWidth, viewHeight)
	local color = level.backgroundColor1 or { 0, 0, 0, 255 }
	local red = math.clamp(math.floor(tonumber(color[1]) or 0), 0, 255)
	local green = math.clamp(math.floor(tonumber(color[2]) or 0), 0, 255)
	local blue = math.clamp(math.floor(tonumber(color[3]) or 0), 0, 255)
	-- One u32 write per pixel for the first row, then row-sized buffer.copy
	-- calls for the rest (far fewer VM operations than 4 writeu8 per pixel).
	local packed = red + green * 256 + blue * 65536 + 255 * 16777216
	local rowBytes = viewWidth * 4
	for offset = 0, rowBytes - 4, 4 do
		buffer.writeu32(target, offset, packed)
	end
	for row = 1, viewHeight - 1 do
		buffer.copy(target, row * rowBytes, target, 0, rowBytes)
	end
end

function renderLevelBackLayers(level, tileSheet, target, viewWidth, viewHeight,
	cameraX, cameraY, scrollSettings, scrollFrame)
	assert(level and type(level.layers) == "table", "Background renderer requires parsed scene layers")
	assert(tileSheet and tileSheet.pixels, "A decoded PNG tileset is required")
	OPT.fillLevelBackground(level, target, viewWidth, viewHeight)

	local frame = tonumber(scrollFrame) or 0
	local settingsByName = type(scrollSettings) == "table" and scrollSettings or nil

	-- Preserve native scene layer order. FG High is intentionally left for the
	-- existing foreground pass, which draws it over Sonic after the sprite.
	for _, layer in ipairs(level.layers) do
		local cached = layer._renderSettingsCache
		if not cached or cached.sourceSettings ~= settingsByName then
			local isFront = layer._isFront
			if isFront == nil then
				isFront = OPT.isFrontTileLayer(layer.name)
				layer._isFront = isFront
				layer._isBackground = OPT.isBackgroundLayerName(layer.name)
			end
			local isBackground = layer._isBackground
			local normalizedName = string.lower(tostring(layer.name or ""))
			local settings = settingsByName and (settingsByName[layer.name]
				or settingsByName[normalizedName]) or nil
			if type(settings) ~= "table" then settings = nil end
			local parallaxX = settings and tonumber(settings.ParallaxX)
			local parallaxY = settings and tonumber(settings.ParallaxY)
			if parallaxX == nil then parallaxX = isBackground and 0.5 or 1 end
			if parallaxY == nil then parallaxY = isBackground and 0 or 1 end
			local repeatX = settings and settings.RepeatX
			local repeatY = settings and settings.RepeatY
			if repeatX == nil then repeatX = isBackground end
			if repeatY == nil then repeatY = false end
			cached = {
				sourceSettings = settingsByName,
				isFront = isFront,
				parallaxX = parallaxX,
				parallaxY = parallaxY,
				offsetX = settings and (tonumber(settings.OffsetX) or 0) or 0,
				offsetY = settings and (tonumber(settings.OffsetY) or 0) or 0,
				speedX = settings and (tonumber(settings.ScrollSpeedX) or 0) or 0,
				speedY = settings and (tonumber(settings.ScrollSpeedY) or 0) or 0,
				repeatX = repeatX == true,
				repeatY = repeatY == true,
			}
			layer._renderSettingsCache = cached
		end

		if not cached.isFront and layer.width > 0 and layer.height > 0 then
			local layerCameraX = math.floor(cameraX * cached.parallaxX + cached.offsetX + frame * cached.speedX)
			local layerCameraY = math.floor(cameraY * cached.parallaxY + cached.offsetY + frame * cached.speedY)
			local mapWidthPixels = layer.width * 16
			local mapHeightPixels = layer.height * 16
			local proxyLevel = OPT.getEngineLayerProxy(level, layer)
			local shouldRepeatX = cached.repeatX and mapWidthPixels > 0
			local shouldRepeatY = cached.repeatY and mapHeightPixels > 0

			if not shouldRepeatX and not shouldRepeatY then
				RSDKLevelParser.RenderViewport(
					proxyLevel, tileSheet, target, viewWidth, viewHeight,
					layerCameraX, layerCameraY, "front"
				)
			elseif shouldRepeatX and not shouldRepeatY then
				local xCopies = OPT.getLayerRenderCopies(layerCameraX, mapWidthPixels, viewWidth, true)
				for copyIndex = 1, #xCopies do
					RSDKLevelParser.RenderViewport(
						proxyLevel, tileSheet, target, viewWidth, viewHeight,
						xCopies[copyIndex], layerCameraY, "front"
					)
				end
			elseif shouldRepeatY and not shouldRepeatX then
				local yCopies = OPT.getLayerRenderCopies(layerCameraY, mapHeightPixels, viewHeight, true)
				for copyIndex = 1, #yCopies do
					RSDKLevelParser.RenderViewport(
						proxyLevel, tileSheet, target, viewWidth, viewHeight,
						layerCameraX, yCopies[copyIndex], "front"
					)
				end
			else
				local xCopies = OPT.getLayerRenderCopies(layerCameraX, mapWidthPixels, viewWidth, true)
				local yCopies = OPT.getLayerRenderCopies(layerCameraY, mapHeightPixels, viewHeight, true)
				for yIndex = 1, #yCopies do
					local copyY = yCopies[yIndex]
					for xIndex = 1, #xCopies do
						RSDKLevelParser.RenderViewport(
							proxyLevel, tileSheet, target, viewWidth, viewHeight,
							xCopies[xIndex], copyY, "front"
						)
					end
				end
			end
		end
	end
end

--============================================================
-- MULTIPLAYER (client)
--============================================================
OPT.mp = {
	remote = nil,
	players = {},      -- [userId] = state + smoothed drawX/drawY
	animCache = {},
	sendTimer = 0,
	wasActive = false,
}

do
	local folder = ReplicatedStorage:WaitForChild("RSDKMultiplayer", 10)
	local remote = folder and folder:WaitForChild("State", 10)
	if remote then
		OPT.mp.remote = remote
		remote.OnClientEvent:Connect(function(action, a, b)
			local mp = OPT.mp
			if action == "Update" then
				local userId, state = a, b
				if userId == Players.LocalPlayer.UserId then return end
				local old = mp.players[userId]
				state.drawX = old and old.drawX or state.x
				state.drawY = old and old.drawY or state.y
				mp.players[userId] = state
			elseif action == "Remove" then
				mp.players[a] = nil
			elseif action == "Snapshot" then
				mp.players = {}
				for userId, state in pairs(a) do
					state.drawX, state.drawY = state.x, state.y
					mp.players[userId] = state
				end
			end
		end)
		remote:FireServer("RequestSnapshot")
		print("[MP] Client connected")
	else
		warn("[MP] RSDKMultiplayer.State not found - is the server script running?")
	end
end

function OPT.mpFindAnimation(name)
	local cache = OPT.mp.animCache
	local anim = cache[name]
	if anim == nil then
		anim = false
		for _, a in ipairs(parsed.animations) do
			if a.name == name then anim = a break end
		end
		cache[name] = anim
	end
	return anim or nil
end

function OPT.mpTick(dt)
	local mp = OPT.mp
	if not mp.remote then return end
	local active = (not menuOpen) and usingRSDKLevel and selectedLevelName ~= nil and not debugMode

	if not active then
		if mp.wasActive then
			mp.wasActive = false
			mp.remote:FireServer("Hide")
		end
		return
	end
	if not mp.wasActive then
		mp.wasActive = true
		mp.remote:FireServer("RequestSnapshot")
	end

	mp.sendTimer += dt
	if mp.sendTimer >= 0.05 then
		mp.sendTimer = 0
		local anim = animator.animation
		mp.remote:FireServer("Update", {
			x = playerX,
			y = playerY,
			levelKey = string.sub(selectedLevelName, 1, 64),
			animation = anim and string.sub(anim.name, 1, 48) or "Idle",
			frameID = animator.frameID,
			rotationUnits = math.floor(rotationUnits) % 512,
			groundAngle256 = math.floor(groundAngle256) % 256,
			speedX = speedX,
			speedY = speedY,
			facingRight = facingRight,
			grounded = grounded,
			playerState = playerState,
		})
	end

	-- smooth remote movement
	local alpha = math.min(1, dt * 20)
	for _, s in pairs(mp.players) do
		s.drawX += (s.x - s.drawX) * alpha
		s.drawY += (s.y - s.drawY) * alpha
	end
end

function OPT.drawRemotePlayers(camX, camY)
	for _, s in pairs(OPT.mp.players) do
		if s.levelKey == selectedLevelName then
			local anim = OPT.mpFindAnimation(s.animation)
			local frame = anim and anim.frames[math.min(s.frameID, #anim.frames - 1) + 1]
			local sx = s.drawX - camX
			local sy = s.drawY - camY
			if frame and sx > -48 and sx < WIDTH + 48 and sy > -48 and sy < HEIGHT + 48 then
				local isBall = s.playerState == "Roll" or s.playerState == "Spindash"
					or s.playerState == "DropDash" or s.animation == "Jump"
				drawSpriteFrame(frame, sx, sy - 1, isBall and 0 or s.rotationUnits, nil, not s.facingRight)
				OPT.drawFrameText(s.displayName or "", math.floor(sx) - 12, math.floor(sy) - 34, WHITE, 12)
			end
		end
	end
end

--============================================================
-- RENDER
--============================================================

function render()
	local drawPlayerX = playerX
	local drawPlayerY = playerY
	if usingRSDKLevel then
		-- Rebuild when the camera changes, or once per fixed simulation tick
		-- when a configured background layer has autonomous scroll speed.
		local renderCameraX = math.floor(cameraX)
		local renderCameraY = math.floor(cameraY)
		local backgroundScroll = activeLevelConfig and activeLevelConfig.BackgroundScroll
		-- Computed once per loaded level instead of iterating settings every frame.
		local animatedLayerScroll = activeLevelConfig._animatedScroll
		if animatedLayerScroll == nil then
			animatedLayerScroll = false
			if type(backgroundScroll) == "table" then
				for _, settings in pairs(backgroundScroll) do
					if type(settings) == "table"
						and ((tonumber(settings.ScrollSpeedX) or 0) ~= 0
							or (tonumber(settings.ScrollSpeedY) or 0) ~= 0) then
						animatedLayerScroll = true
						break
					end
				end
			end
			activeLevelConfig._animatedScroll = animatedLayerScroll
		end
		if renderCameraX ~= lastLevelRenderCameraX
			or renderCameraY ~= lastLevelRenderCameraY
			or (animatedLayerScroll and backgroundScrollFrame ~= lastLevelRenderFrame) then
			renderLevelBackLayers(
				activeLevel, activeTileset, basePixels, WIDTH, HEIGHT,
				renderCameraX, renderCameraY, backgroundScroll, backgroundScrollFrame
			)
			lastLevelRenderCameraX = renderCameraX
			lastLevelRenderCameraY = renderCameraY
			lastLevelRenderFrame = backgroundScrollFrame
		end
		drawPlayerX = playerX - cameraX
		drawPlayerY = playerY - cameraY
	end

	-- Collision overlay: rebuilt only when camera/plane/layers change, and kept as
	-- a SPARSE list of the pixels it changed. It is applied as the very last
	-- step of the frame so it always draws over tiles, Sonic and FG High.
	local overlayActive = usingRSDKLevel and showCollisionOverlay and activeLevel and #levelCollisionLayers > 0
	if overlayActive then
		local overlayCameraX = math.floor(cameraX)
		local overlayCameraY = math.floor(cameraY)
		local overlayPlane = activeLevelConfig and activeLevelConfig.CollisionPlane or 0
		if overlayCameraX ~= lastCollisionOverlayCameraX
			or overlayCameraY ~= lastCollisionOverlayCameraY
			or activeLevel ~= lastCollisionOverlayLevel
			or levelCollisionLayers ~= lastCollisionOverlayLayers
			or overlayPlane ~= lastCollisionOverlayPlane then
			buffer.copy(collisionOverlayPixels, 0, basePixels, 0, FRAME_BYTE_LENGTH)
			-- Only the ACTIVE plane of the layers actually used for collision.
			for _, collisionLayer in ipairs(levelCollisionLayers) do
				RSDKLevelParser.RenderCollisionOverlay(
					activeLevel, collisionLayer, collisionOverlayPixels,
					WIDTH, HEIGHT, overlayCameraX, overlayCameraY, overlayPlane
				)
			end
			-- Extract just the pixels the overlay changed.
			if not OPT.overlayOffsets then
				OPT.overlayOffsets = buffer.create(WIDTH * HEIGHT * 4)
				OPT.overlayValues = buffer.create(WIDTH * HEIGHT * 4)
			end
			local offsets, values = OPT.overlayOffsets, OPT.overlayValues
			local count = 0
			local readu32, writeu32 = buffer.readu32, buffer.writeu32
			for offset = 0, FRAME_BYTE_LENGTH - 4, 4 do
				local after = readu32(collisionOverlayPixels, offset)
				if after ~= readu32(basePixels, offset) then
					writeu32(offsets, count * 4, offset)
					writeu32(values, count * 4, after)
					count += 1
				end
			end
			OPT.overlayCount = count
			lastCollisionOverlayCameraX = overlayCameraX
			lastCollisionOverlayCameraY = overlayCameraY
			lastCollisionOverlayLevel = activeLevel
			lastCollisionOverlayLayers = levelCollisionLayers
			lastCollisionOverlayPlane = overlayPlane
		end
	end
	buffer.copy(framePixels, 0, basePixels, 0, FRAME_BYTE_LENGTH)

	for _, object in ipairs(debugObjects) do
		OPT.drawDebugObject(object)
	end

	-- Draw RSDK scene entities (including animated Ring sprites) in world space.
	local entityCameraX = usingRSDKLevel and math.floor(cameraX) or 0
	local entityCameraY = usingRSDKLevel and math.floor(cameraY) or 0
	for _, entity in ipairs(activeEntities) do
		local definition = entity.def
		if definition and type(definition.draw) == "function" then
			definition.draw(entity, framePixels, WIDTH, HEIGHT, entityCameraX, entityCameraY)
		end
	end


	OPT.drawRemotePlayers(entityCameraX, entityCameraY)
	OPT.drawExplosions(entityCameraX, entityCameraY)
	do
		local cx = math.floor(drawPlayerX + 0.5)
		local cy = math.floor(drawPlayerY + 0.5)
		local frame = animator.animation and animator.animation.frames[animator.frameID + 1] or nil

		local sprX, sprY = drawPlayerX, drawPlayerY - 1 -- visual only: lift sprite 1px off the ground
		local anim = animator.animation
		-- Ball form includes jump, roll, spindash and drop dash. The animation
		-- test covers curled jump frames; the state test covers rolling states
		-- even if an animation alias or transition changes the current clip.
		local isBall = anim == Anim.Jump
			or anim == Anim.DropDash
			or anim == Anim.SpinDash
			or playerState == "Roll"
			or playerState == "Spindash"
			or playerState == "DropDash"
		local visualRotationUnits = isBall and 0 or rotationUnits
		if grounded and playerState == "Roll" then
			-- Offset along the surface normal, using the true ground angle (not the
			-- ball's unrotated sprite angle) so it stays correct on slopes/loops.
			local ox, oy = rotateOffset(0, ROLL_DRAW_OFFSET, groundAngle256 * 2)
			sprX += ox
			sprY += oy
		end
		local flicker = OPT.invincible > 0 and (OPT.invincible // 3) % 2 == 1
		local drawn = flicker or drawSpriteFrame(frame, sprX, sprY, visualRotationUnits)
		if not drawn then
			local corners = {{-4, -17}, {4, -17}, {4, 17}, {-4, 17}}
			local transformed = {}
			for i, point in ipairs(corners) do
				local x, y = rotateOffset(point[1], point[2], visualRotationUnits)
				transformed[i] = {cx + x, cy + y}
			end
			for i = 1, 4 do
				local j = (i % 4) + 1
				OPT.drawLine(transformed[i][1], transformed[i][2], transformed[j][1], transformed[j][2], SONIC_TEMP)
			end
		end

		if usingRSDKLevel then
			RSDKLevelParser.RenderViewport(
				activeLevel, activeTileset, framePixels, WIDTH, HEIGHT,
				math.floor(cameraX), math.floor(cameraY), "front"
			)
		end

		if SHOW_COLLISION_DEBUG then
			OPT.drawAxisAlignedDebugBox(cx, cy)
		end
	end
	if debugMode then OPT.drawDebugCursorAndHud() end

	-- Draw the real Ring.bin pickup sparkle animations (Sparkle1-3),
	-- including the additive overlay used by Mania's first sparkle type.
	for _, effect in ipairs(ringPickupEffects) do
		if effect.visible and effect.animation and effect.animation.frames then
			local frames = effect.animation.frames
			local frame = frames[effect.frameID + 1]
			if frame then
				local screenX = effect.x - entityCameraX
				local screenY = effect.y - entityCameraY
				if screenX >= -32 and screenX <= WIDTH + 32
					and screenY >= -32 and screenY <= HEIGHT + 32 then
					-- RSDK Ring_Draw_Sparkle draws the +16 frame additively for
					-- Sparkle1, then draws the standard frame over it.
					if effect.additive then
						local glowFrame = frames[effect.frameID + 17]
						if glowFrame then
							drawSpriteFrame(glowFrame, screenX, screenY, 0, ringSpriteSheet, false, true)
						end
					end
					drawSpriteFrame(frame, screenX, screenY, 0, ringSpriteSheet, false)
				end
			end
		end
	end

	-- Mania applies the water palette below the waterline across all draw
	-- groups. Do the equivalent after the player and FG High are composited,
	-- but before collision-debug overlays so diagnostics remain readable.
	if usingRSDKLevel and OPT.water.enabled then
		OPT.applyWaterVisuals(framePixels, math.floor(cameraX), math.floor(cameraY))
	end

	OPT.drawAllBubbles(entityCameraX, entityCameraY)

	if overlayActive and OPT.overlayCount and OPT.overlayCount > 0 then
		local offsets, values = OPT.overlayOffsets, OPT.overlayValues
		local readu32, writeu32 = buffer.readu32, buffer.writeu32
		for i = 0, OPT.overlayCount * 4 - 4, 4 do
			writeu32(framePixels, readu32(offsets, i), readu32(values, i))
		end
	end

	if usingRSDKLevel and showCollisionOverlay then
		local camX, camY = math.floor(cameraX), math.floor(cameraY)
		for _, sw in ipairs(OPT.layerSwitchers) do
			local sx, sy = sw.x - camX, sw.y - camY
			if sx > -80 and sx < WIDTH + 80 and sy > -80 and sy < HEIGHT + 80 then
				local len = sw.halfLength
				local color = sw.planeRight == nil and WHITE or (sw.planeRight == 1 and ORANGE or CYAN)
				OPT.drawLine(sx + sw.sin * len, sy - sw.cos * len, sx - sw.sin * len, sy + sw.cos * len, color)
				if sw.planeRight ~= nil then
					OPT.drawFrameText(string.format("L%s R%s", sw.planeLeft == 1 and "B" or "A", sw.planeRight == 1 and "B" or "A"),
						sx - 12, sy - 4, YELLOW, 8)
				end
			end
		end
		OPT.drawFrameRect(WIDTH - 92, 0, 92, 10, {0, 0, 0})
		OPT.drawFrameText(string.format("PLANE %s SW %d", (activeLevelConfig.CollisionPlane == 1) and "B" or "A",
			#OPT.layerSwitchers), WIDTH - 90, 2, YELLOW, 15)
	end

	-- Global UI objects render after the stage, player, water and diagnostics.
	-- The title card owns the screen during its intro/hold/slide sequence; HUD
	-- becomes visible as soon as the card exits.
	OPT.drawTitleCard()
	OPT.drawHUD()

	if OPT.comp and OPT.comp.matchActive and OPT.comp.match then
		local match = OPT.comp.match
		local progress = OPT.comp.progress or {}
		OPT.drawFrameRect(WIDTH - 142, 4, 136, 27, {0, 0, 0, 210})
		OPT.drawFrameRect(WIDTH - 142, 4, 136, 2, {248, 196, 48, 255})
		if match.mode == "Battle" then
			local scores = progress.scores or {}
			local localScore = tonumber(scores[Players.LocalPlayer.UserId]) or 0
			OPT.drawFrameText("BATTLE", WIDTH - 136, 9, {255, 224, 72}, 10)
			OPT.drawFrameText("STOCKS " .. tostring(OPT.comp.stocksLeft or match.stocks or 0) .. "  KOs " .. tostring(localScore), WIDTH - 136, 20, {255, 255, 255}, 24)
		else
			local finished = tonumber(progress.finished) or 0
			local total = tonumber(progress.total) or (ManiaMenu.compRoom and ManiaMenu.compRoom.playerCount) or 0
			OPT.drawFrameText("RACE", WIDTH - 136, 9, {255, 224, 72}, 8)
			OPT.drawFrameText(string.format("FINISHED %d/%d", finished, total), WIDTH - 136, 20, {255, 255, 255}, 19)
		end
		if OPT.comp.eliminated then
			OPT.drawFrameRect(112, 101, 200, 34, {0, 0, 0, 230})
			OPT.drawFrameText("ELIMINATED", 159, 107, {255, 96, 96}, 18)
			OPT.drawFrameText("WAITING FOR RESULTS", 138, 121, {255, 255, 255}, 21)
		end
	end

	canvasImage:WritePixelsBuffer(CANVAS_ORIGIN, CANVAS_SIZE, framePixels)
end

--============================================================
-- RESIZE
--============================================================

function resizeCanvas()
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local viewport = camera.ViewportSize
	if viewport.X < 1 or viewport.Y < 1 then return end

	canvasScale.Scale = math.min(viewport.X / WIDTH, viewport.Y / HEIGHT)
end

local viewportConnection
function connectCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	local camera = Workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			updateBackground()
			resizeCanvas()
		end)
	end

	updateBackground()
	resizeCanvas()
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectCamera)

--============================================================
-- START
--============================================================

if usingRSDKLevel then
	setGroundAngleFromRadians(0)
	updateGroundRotation()
	updateLevelCamera()
else
	placeGroundPlayer()
	updateGroundRotation()
end
setSpriteAnimation(Anim.Idle, true, 0)
connectCamera()
ManiaMenuBuildAssetIndex(true)
refreshLevelSelect()
openLevelMenu()
canvasLabel.Visible = true
renderManiaMainMenuToCanvas()

accumulator = 0
RunService.RenderStepped:Connect(function(dt)
	OPT.mpTick(dt)

	if menuOpen then
		accumulator = 0
		local menu = OPT.menu
		if menu then
			OPT.menuAccumulator += math.min(dt, 0.25)
			local ticked = false
			while OPT.menuAccumulator >= FIXED_DT do
				menu:update()
				OPT.menuAccumulator -= FIXED_DT
				ticked = true
			end
			if ticked then OPT.drawMenu() end
		else
			ManiaMenu.menuAccumulator += math.min(dt, 0.25)
			local menuTicks = 0
			while ManiaMenu.menuAccumulator >= FIXED_DT do
				updateManiaMenu()
				ManiaMenu.menuAccumulator -= FIXED_DT
				menuTicks += 1
			end
			if menuTicks > 0 and ManiaMenu.screen ~= "StageSelect" then
				-- Keep menu state/animation at 60Hz, but upload the expensive
				-- 424x240 pixel canvas at 30Hz. Input handlers still redraw immediately.
				ManiaMenu.menuRenderDivider += menuTicks
				if ManiaMenu.menuRenderDivider >= 2 then
					ManiaMenu.menuRenderDivider %= 2
					renderManiaMenuScreen()
				end
			end
		end
		return
	end

	accumulator += math.min(dt, 0.25)
	local steps = 0

	while accumulator >= FIXED_DT and steps < 12 do
		simulationTick()
		-- UPDATE ENTITY PHYSICS EACH FIXED STEP
		updateEntities(FIXED_DT)

		accumulator -= FIXED_DT
		steps += 1
	end

	if steps > 0 then
		render()
	end
end)
