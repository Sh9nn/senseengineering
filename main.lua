-- services
local runService = game:GetService("RunService");
local players = game:GetService("Players");
local workspace = game:GetService("Workspace");

-- variables
local localPlayer = players.LocalPlayer;
local camera = workspace.CurrentCamera;
local viewportSize = camera.ViewportSize;
local container = Instance.new("Folder",
	gethui and gethui() or game:GetService("CoreGui"));

-- locals
local floor = math.floor;
local round = math.round;
local clamp = math.clamp;
local mathMin = math.min;
local mathMax = math.max;
local sin = math.sin;
local cos = math.cos;
local clear = table.clear;
local unpack = table.unpack;
local find = table.find;
local create = table.create;
local fromMatrix = CFrame.fromMatrix;

-- methods
local wtvp = camera.WorldToViewportPoint;
local isA = workspace.IsA;
local getPivot = workspace.GetPivot;
local findFirstChild = workspace.FindFirstChild;
local findFirstChildOfClass = workspace.FindFirstChildOfClass;
local getChildren = workspace.GetChildren;
local toOrientation = CFrame.identity.ToOrientation;
local pointToObjectSpace = CFrame.identity.PointToObjectSpace;
local lerpColor = Color3.new().Lerp;
local min2 = Vector2.zero.Min;
local max2 = Vector2.zero.Max;
local lerp2 = Vector2.zero.Lerp;
local min3 = Vector3.zero.Min;
local max3 = Vector3.zero.Max;

-- constants
local HEALTH_BAR_OFFSET = Vector2.new(5, 0);
local HEALTH_TEXT_OFFSET = Vector2.new(3, 0);
local HEALTH_BAR_OUTLINE_OFFSET = Vector2.new(0, 1);
local NAME_OFFSET = Vector2.new(0, 2);
local BAR_BASE_OFFSET = 5;      -- отступ первого бара от бокса
local BAR_STACK_STEP = 6;       -- шаг между барами на одной стороне
local BAR_OUTLINE_OFFSET_H = Vector2.new(1, 0);
local BAR_SIDES = { "Left", "Right", "Top", "Bottom" };
local TEXT_RIGHT_GAP = 4;      -- отступ кастомного текста от бокса / баров справа
local TEXT_LINE_GAP = 1;       -- расстояние между строками кастомного текста
local TEXT_MIN_SIZE = 8;       -- минимальный размер кастомного текста при масштабировании
local GRADIENT_DEFAULT_SEGMENTS = 16;
local GRADIENT_MAX_SEGMENTS = 64;
local DISTANCE_OFFSET = Vector2.new(0, 2);
local VERTICES = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(-1, -1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
	Vector3.new(1, -1, 1)
};

local GLOW_MAX_LAYERS = 8;
local GLOW_DIRECTIONS = {
	Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1),
	Vector2.new(0.707, 0.707), Vector2.new(-0.707, 0.707), Vector2.new(0.707, -0.707), Vector2.new(-0.707, -0.707)
};
local CORNER_NAMES = { "topLeft", "topRight", "bottomLeft", "bottomRight" };
local CORNER_SIGNS = { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } };
local CORNER_GLOW_KEYS = {};
for i = 1, 8 do
	CORNER_GLOW_KEYS[i] = "cornerBox" .. i;
end
local BOX3D_GLOW_KEYS = {};
for i = 1, 4 do
	BOX3D_GLOW_KEYS[i] = {};
	for j = 1, 3 do
		BOX3D_GLOW_KEYS[i][j] = "box3d" .. i .. "_" .. j;
	end
end

-- functions
local function isBodyPart(name)
	return name == "Head" or name:find("Torso") or name:find("Leg") or name:find("Arm");
end

local function getBoundingBox(parts)
	local min, max;
	for i = 1, #parts do
		local part = parts[i];
		local cframe, size = part.CFrame, part.Size;

		min = min3(min or cframe.Position, (cframe - size*0.5).Position);
		max = max3(max or cframe.Position, (cframe + size*0.5).Position);
	end

	local center = (min + max)*0.5;
	local front = Vector3.new(center.X, center.Y, max.Z);
	return CFrame.new(center, front), max - min;
end

local function worldToScreen(world)
	local screen, inBounds = wtvp(camera, world);
	return Vector2.new(screen.X, screen.Y), inBounds, screen.Z;
end

local function calculateCorners(cframe, size)
	local corners = create(#VERTICES);
	for i = 1, #VERTICES do
		corners[i] = worldToScreen((cframe + size*0.5*VERTICES[i]).Position);
	end

	local min = min2(viewportSize, unpack(corners));
	local max = max2(Vector2.zero, unpack(corners));
	return {
		corners = corners,
		topLeft = Vector2.new(floor(min.X), floor(min.Y)),
		topRight = Vector2.new(floor(max.X), floor(min.Y)),
		bottomLeft = Vector2.new(floor(min.X), floor(max.Y)),
		bottomRight = Vector2.new(floor(max.X), floor(max.Y))
	};
end

local function rotateVector(vector, radians)
	local x, y = vector.X, vector.Y;
	local c, s = cos(radians), sin(radians);
	return Vector2.new(x*c - y*s, x*s + y*c);
end

local function parseColor(self, color, isOutline)
	if color == "Team Color" or (self.interface and self.interface.sharedSettings.useTeamColor and not isOutline) then
		return (self.interface and self.interface.getTeamColor(self.player)) or Color3.new(1,1,1);
	end
	return color;
end

-- glow (Drawing API не умеет blur, поэтому свечение = несколько полупрозрачных слоёв позади элемента)
local function glowAllowed(options, element)
	if not options.glow then
		return false;
	end
	local elements = options.glowElements;
	return not elements or elements[element] ~= false;
end

local function getGlowPool(store, key, class, count)
	local pool = store[key];
	if not pool then
		pool = {};
		store[key] = pool;
	end

	for i = #pool + 1, count do
		local drawing = Drawing.new(class);
		pcall(function()
			drawing.ZIndex = 0;
			drawing.Visible = false;
			if class == "Text" then
				drawing.Center = true;
				drawing.Outline = false;
			end
		end);
		pool[i] = drawing;
	end
	return pool;
end

-- возвращает пул drawing'ов и число слоёв (0 = свечение не нужно, лишнее скрывается)
local function prepareGlow(self, key, class, show, options, element, perLayer)
	perLayer = perLayer or 1;

	local layers = 0;
	if show and glowAllowed(options, element) then
		local requested = perLayer > 1 and (options.glowTextLayers or 1) or (options.glowLayers or 3);
		layers = clamp(floor(requested), 0, GLOW_MAX_LAYERS);
	end

	local store = self.glowStore;
	local needed = layers*perLayer;
	local pool = store[key];
	if needed > 0 then
		pool = getGlowPool(store, key, class, needed);
	end

	if pool then
		for i = needed + 1, #pool do
			pool[i].Visible = false;
		end
	end
	return pool, layers;
end

local function hideAllGlow(store)
	for _, pool in next, store do
		for i = 1, #pool do
			pool[i].Visible = false;
		end
	end
end

local function destroyGlow(store)
	for key, pool in next, store do
		for i = 1, #pool do
			pool[i]:Remove();
		end
		store[key] = nil;
	end
end

local function glowColorOf(self, options, fallback)
	local color = options.glowColor;
	if color == nil then
		return fallback;
	end
	return parseColor(self, color);
end

local function layerAlpha(transparency, options, layers)
	return clamp((transparency or 1)*(options.glowIntensity or 0.6)/layers, 0, 1);
end

local function glowLine(self, key, show, from, to, color, transparency, options, element, base)
	local pool, layers = prepareGlow(self, key, "Line", show, options, element);
	if layers == 0 then
		return;
	end

	local size = options.glowSize or 2;
	local glowColor = glowColorOf(self, options, color);
	local alpha = layerAlpha(transparency, options, layers);
	for i = 1, layers do
		local drawing = pool[i];
		drawing.From = from;
		drawing.To = to;
		drawing.Thickness = base + i*size*2;
		drawing.Color = glowColor;
		drawing.Transparency = alpha;
		drawing.Visible = true;
	end
end

local function glowSquare(self, key, show, position, size, color, transparency, options, element, base, filled)
	local pool, layers = prepareGlow(self, key, "Square", show, options, element);
	if layers == 0 then
		return;
	end

	local step = options.glowSize or 2;
	local glowColor = glowColorOf(self, options, color);
	local alpha = layerAlpha(transparency, options, layers);
	for i = 1, layers do
		local drawing = pool[i];
		drawing.Filled = filled or false;
		if filled then
			drawing.Position = position - Vector2.one*i*step;
			drawing.Size = size + Vector2.one*i*step*2;
		else
			drawing.Position = position;
			drawing.Size = size;
			drawing.Thickness = base + i*step*2;
		end
		drawing.Color = glowColor;
		drawing.Transparency = alpha;
		drawing.Visible = true;
	end
end

local function glowTriangle(self, key, show, a, b, c, color, transparency, options, element, base)
	local pool, layers = prepareGlow(self, key, "Triangle", show, options, element);
	if layers == 0 then
		return;
	end

	local size = options.glowSize or 2;
	local glowColor = glowColorOf(self, options, color);
	local alpha = layerAlpha(transparency, options, layers);
	for i = 1, layers do
		local drawing = pool[i];
		drawing.PointA = a;
		drawing.PointB = b;
		drawing.PointC = c;
		drawing.Filled = false;
		drawing.Thickness = base + i*size*2;
		drawing.Color = glowColor;
		drawing.Transparency = alpha;
		drawing.Visible = true;
	end
end

-- текст: копии с оффсетом в 8 направлениях на каждый слой
local function glowText(self, key, main, options, element, allow)
	local perLayer = #GLOW_DIRECTIONS;
	local pool, layers = prepareGlow(self, key, "Text", main.Visible and allow ~= false, options, element, perLayer);
	if layers == 0 then
		return;
	end

	local step = (options.glowSize or 2)*0.5;
	local glowColor = glowColorOf(self, options, main.Color);
	local alpha = layerAlpha(main.Transparency, options, layers);
	local text, size, font, position = main.Text, main.Size, main.Font, main.Position;
	for layer = 1, layers do
		for d = 1, perLayer do
			local drawing = pool[(layer - 1)*perLayer + d];
			drawing.Text = text;
			drawing.Size = size;
			drawing.Font = font;
			drawing.Center = true;
			drawing.Outline = false;
			drawing.Position = position + GLOW_DIRECTIONS[d]*layer*step;
			drawing.Color = glowColor;
			drawing.Transparency = alpha;
			drawing.Visible = true;
		end
	end
end

-- corner box: 4 уголка по 2 линии (+ 8 линий обводки), общий для EspObject и InstanceObject
local function renderCornerBox(self, show, corners, options, color, transparency, outlineColor, outlineTransparency)
	local lines, outlines = self.cornerLines, self.cornerOutlines;
	if not show then
		for i = 1, 8 do
			lines[i].Visible = false;
			outlines[i].Visible = false;
		end
		return;
	end

	local showOutline = options.cornerBoxOutline and true or false;
	local width = corners.topRight.X - corners.topLeft.X;
	local height = corners.bottomLeft.Y - corners.topLeft.Y;
	local length = mathMin(width*clamp(options.cornerBoxLength or 0.25, 0, 0.5), height*0.5);

	for i = 1, 4 do
		local point = corners[CORNER_NAMES[i]];
		local sx, sy = CORNER_SIGNS[i][1], CORNER_SIGNS[i][2];
		local dx, dy = Vector2.new(sx*length, 0), Vector2.new(0, sy*length);

		local h, v = lines[i*2 - 1], lines[i*2];
		h.From, h.To = point, point + dx;
		v.From, v.To = point, point + dy;
		h.Color, v.Color = color, color;
		h.Transparency, v.Transparency = transparency, transparency;
		h.Visible, v.Visible = true, true;

		local oh, ov = outlines[i*2 - 1], outlines[i*2];
		oh.From, oh.To = point - Vector2.new(sx, 0), point + dx + Vector2.new(sx, 0);
		ov.From, ov.To = point - Vector2.new(0, sy), point + dy + Vector2.new(0, sy);
		oh.Color, ov.Color = outlineColor, outlineColor;
		oh.Transparency, ov.Transparency = outlineTransparency, outlineTransparency;
		oh.Visible, ov.Visible = showOutline, showOutline;
	end
end

-- distance: шаблон строки ("{distance} studs", "{distance}m") или функция(distance, player) -> string
local function formatDistance(template, distance, player)
	local value = round(distance);
	if type(template) == "function" then
		local ok, result = pcall(template, value, player);
		return ok and tostring(result) or tostring(value);
	end
	return (tostring(template or "{distance} studs"):gsub("{distance}", tostring(value)));
end

-- bars
local function normalizeSide(position, default)
	if position == "Left" or position == "Right" or position == "Top" or position == "Bottom" then
		return position;
	elseif position == "Below" then
		return "Bottom";
	elseif position == "Above" then
		return "Top";
	end
	return default;
end

local function normalizeBar(spec)
	spec.enabled = spec.enabled == nil and true or spec.enabled;
	spec.position = spec.position or "Right";
	spec.outline = spec.outline == nil and true or spec.outline;
	spec.outlineColor = spec.outlineColor or { Color3.new(), 0.5 };
	spec.healthyColor = spec.healthyColor or Color3.new(0, 1, 0);
	spec.dyingColor = spec.dyingColor or Color3.new(1, 0, 0);
	spec.gradient = spec.gradient or false;
	spec.gradientSegments = spec.gradientSegments or GRADIENT_DEFAULT_SEGMENTS;
	spec.text = spec.text == nil and true or spec.text;
	spec.textColor = spec.textColor or { Color3.new(1, 1, 1), 1 };
	spec.textOutline = spec.textOutline == nil and true or spec.textOutline;
	spec.textOutlineColor = spec.textOutlineColor or Color3.new();
	spec.textSuffix = spec.textSuffix or "";
	spec._normalized = true;
end

local function normalizeText(spec)
	spec.enabled = spec.enabled == nil and true or spec.enabled;
	spec.color = spec.color or { Color3.new(1, 1, 1), 1 };
	spec.outline = spec.outline == nil and true or spec.outline;
	spec.outlineColor = spec.outlineColor or Color3.new();
	spec._normalized = true;
end

local function barExtent(count, distance)
	if count > 0 then
		return distance + 2;
	end
	return 0;
end

-- esp object
local EspObject = {};
EspObject.__index = EspObject;

function EspObject.new(player, interface)
	local self = setmetatable({}, EspObject);
	self.player = assert(player, "Missing argument #1 (Player expected)");
	self.interface = assert(interface, "Missing argument #2 (table expected)");
	self:Construct();
	return self;
end

function EspObject:_create(class, properties)
	local drawing = Drawing.new(class);
	pcall(function() drawing.ZIndex = 1; end);
	for property, value in next, properties do
		pcall(function() drawing[property] = value; end);
	end
	self.bin[#self.bin + 1] = drawing;
	return drawing;
end

function EspObject:Construct()
	self.charCache = {};
	self.childCount = 0;
	self.bin = {};
	self.healthBarSegments = {};
	self.glowStore = {};
	self.drawings = {
		box3d = {
			{
				self:_create("Line", { Thickness = 1, Visible = false }),
				self:_create("Line", { Thickness = 1, Visible = false }),
				self:_create("Line", { Thickness = 1, Visible = false })
			},
			{
				self:_create("Line", { Thickness = 1, Visible = false }),
				self:_create("Line", { Thickness = 1, Visible = false }),
				self:_create("Line", { Thickness = 1, Visible = false })
			},
			{
				self:_create("Line", { Thickness = 1, Visible = false }),
				self:_create("Line", { Thickness = 1, Visible = false }),
				self:_create("Line", { Thickness = 1, Visible = false })
			},
			{
				self:_create("Line", { Thickness = 1, Visible = false }),
				self:_create("Line", { Thickness = 1, Visible = false }),
				self:_create("Line", { Thickness = 1, Visible = false })
			}
		},
		visible = {
			tracerOutline = self:_create("Line", { Thickness = 3, Visible = false }),
			tracer = self:_create("Line", { Thickness = 1, Visible = false }),
			boxFill = self:_create("Square", { Filled = true, Visible = false }),
			boxOutline = self:_create("Square", { Thickness = 3, Visible = false }),
			box = self:_create("Square", { Thickness = 1, Visible = false }),
			healthBarOutline = self:_create("Line", { Thickness = 3, Visible = false }),
			healthBar = self:_create("Line", { Thickness = 1, Visible = false }),
			healthText = self:_create("Text", { Center = true, Visible = false }),
			name = self:_create("Text", { Text = self.player.DisplayName, Center = true, Visible = false }),
			distance = self:_create("Text", { Center = true, Visible = false }),
			weapon = self:_create("Text", { Center = true, Visible = false }),
		},
		hidden = {
			arrowOutline = self:_create("Triangle", { Thickness = 3, Visible = false }),
			arrow = self:_create("Triangle", { Filled = true, Visible = false })
		}
	};

	-- corner box
	self.cornerOutlines = {};
	self.cornerLines = {};
	for i = 1, 8 do
		self.cornerOutlines[i] = self:_create("Line", { Thickness = 3, Visible = false });
	end
	for i = 1, 8 do
		self.cornerLines[i] = self:_create("Line", { Thickness = 1, Visible = false });
	end

	-- bars state
	self.healthSpec = {};
	self.mainSlot = {
		outline = self.drawings.visible.healthBarOutline,
		line = self.drawings.visible.healthBar,
		text = self.drawings.visible.healthText,
		segments = self.healthBarSegments,
		glowBar = "healthBar",
		glowText = "healthText",
		glowBarElement = "healthBar",
		glowTextElement = "healthText"
	};
	self.barSlots = { self.mainSlot };
	self.barByName = {};
	self.barEntries = {};
	self.barData = {};
	self.barCount = 0;
	self.entryCount = 0;
	self.renderId = 0;
	self.topExtent = 0;
	self.bottomExtent = 0;
	self.textData = {};
	self.textCount = 0;
	self.textSlots = {};
	self.textList = {};
	self.sideCount = { Left = 0, Right = 0, Top = 0, Bottom = 0 };
	self.sideDistance = { Left = BAR_BASE_OFFSET, Right = BAR_BASE_OFFSET, Top = BAR_BASE_OFFSET, Bottom = BAR_BASE_OFFSET };

	self.renderConnection = runService.Heartbeat:Connect(function(deltaTime)
		self:Update(deltaTime);
		self:Render(deltaTime);
	end);
end

function EspObject:HideGradient(segments, from)
	for i = from or 1, #segments do
		segments[i].Visible = false;
	end
end

-- gradient: цвет зависит от позиции на полосе (начало dyingColor -> конец healthyColor)
function EspObject:RenderGradient(slot, barFrom, barTo, ratio, spec)
	local segments = slot.segments;
	local count = clamp(floor(spec.gradientSegments or GRADIENT_DEFAULT_SEGMENTS), 1, GRADIENT_MAX_SEGMENTS);
	local used = 0;

	for i = 1, count do
		local t0 = (i - 1)/count;
		local t1 = mathMin(i/count, ratio);
		if t1 <= t0 then
			break;
		end

		used = i;
		local segment = segments[i];
		if not segment then
			segment = self:_create("Line", { Thickness = 1, Visible = false });
			segments[i] = segment;
		end

		segment.From = lerp2(barTo, barFrom, t0);
		segment.To = lerp2(barTo, barFrom, t1);
		segment.Color = lerpColor(spec.dyingColor, spec.healthyColor, (t0 + t1)*0.5);
		segment.Visible = true;
	end

	self:HideGradient(segments, used + 1);
end

function EspObject:_getBarSlot(name)
	local slot = self.barByName[name];
	if not slot then
		slot = {
			outline = self:_create("Line", { Thickness = 3, Visible = false }),
			line = self:_create("Line", { Thickness = 1, Visible = false }),
			text = self:_create("Text", { Center = true, Visible = false }),
			segments = {},
			glowBar = "bar:" .. name,
			glowText = "barText:" .. name,
			glowBarElement = "bar",
			glowTextElement = "barText"
		};
		self.barByName[name] = slot;
		self.barSlots[#self.barSlots + 1] = slot;
	end
	return slot;
end

-- значения кастомных баров (getValue), вызывается из Update
function EspObject:UpdateBars()
	local interface = self.interface;
	local specs = self.options.bars;
	local data = self.barData;
	local count = 0;

	if specs then
		for i = 1, #specs do
			local spec = specs[i];
			if not spec._normalized then
				normalizeBar(spec);
			end

			if spec.enabled and spec.name then
				local getter = spec.getValue or interface.getValue;
				local ok, value, max = pcall(getter, self.player, spec.name);
				if ok and type(value) == "number" then
					count = count + 1;
					local item = data[count];
					if not item then
						item = {};
						data[count] = item;
					end
					item.spec = spec;
					item.value = value;
					item.max = type(max) == "number" and max or 100;
				end
			end
		end
	end

	self.barCount = count;
end

-- кастомные тексты справа от бокса: значения из getText, вызывается из Update
function EspObject:UpdateTexts()
	local interface = self.interface;
	local specs = self.options.texts;
	local data = self.textData;
	local count = 0;

	if specs then
		for i = 1, #specs do
			local spec = specs[i];
			if not spec._normalized then
				normalizeText(spec);
			end

			if spec.enabled and spec.name then
				local text;
				if type(spec.text) == "string" then
					text = spec.text;
				else
					local ok, result = pcall(spec.getText or interface.getText, self.player, spec.name);
					text = ok and result or nil;
				end

				if text ~= nil and text ~= "" then
					count = count + 1;
					local item = data[count];
					if not item then
						item = {};
						data[count] = item;
					end
					item.spec = spec;
					item.text = tostring(text);
				end
			end
		end
	end

	self.textCount = count;
end

function EspObject:_getTextSlot(name)
	local slot = self.textSlots[name];
	if not slot then
		slot = {
			drawing = self:_create("Text", { Center = true, Visible = false }),
			glowKey = "customText:" .. name
		};
		self.textSlots[name] = slot;
		self.textList[#self.textList + 1] = slot;
	end
	return slot;
end

-- стек кастомных текстов: каждый следующий видимый текст ниже предыдущего,
-- всё сдвигается правее, если справа есть бары (и их текст).
-- Если стек не влезает в высоту бокса (игрок далеко), размер текста уменьшается,
-- чтобы он не уезжал вниз (отключается: scale = false, минимум: minSize)
function EspObject:RenderTexts(active, corners)
	local renderId = self.renderId;

	if active and self.textCount > 0 then
		local interface = self.interface;
		local shared = interface.sharedSettings;
		local data = self.textData;

		local extent = 0;
		if self.sideCount.Right > 0 then
			extent = self.sideDistance.Right + 2;
		end

		local x = corners.topRight.X + extent + TEXT_RIGHT_GAP;
		local y = corners.topRight.Y;
		local boxHeight = corners.bottomLeft.Y - corners.topLeft.Y;

		-- 1) высота стека при базовом размере (замер кешируется, пока не изменится текст/размер/шрифт)
		local total = 0;
		for i = 1, self.textCount do
			local item = data[i];
			local spec = item.spec;
			local slot = self:_getTextSlot(spec.name);
			local drawing = slot.drawing;

			item.slot = slot;
			item.baseSize = spec.size or shared.textSize;
			item.font = spec.font or shared.textFont;

			if slot.measuredText ~= item.text or slot.measuredSize ~= item.baseSize or slot.measuredFont ~= item.font then
				drawing.Text = item.text;
				drawing.Size = item.baseSize;
				drawing.Font = item.font;
				slot.baseHeight = drawing.TextBounds.Y;
				slot.measuredText, slot.measuredSize, slot.measuredFont = item.text, item.baseSize, item.font;
			end

			total = total + slot.baseHeight + (spec.spacing or TEXT_LINE_GAP);
		end

		local scale = 1;
		if total > boxHeight and total > 0 then
			scale = mathMax(boxHeight, 0)/total;
		end

		-- 2) отрисовка
		for i = 1, self.textCount do
			local item = data[i];
			local spec = item.spec;
			local slot = item.slot;
			slot.usedId = renderId;

			local size = item.baseSize;
			if scale < 1 and spec.scale ~= false then
				local scaled = floor(size*scale + 0.5);
				size = mathMin(size, mathMax(spec.minSize or TEXT_MIN_SIZE, scaled));
			end

			local drawing = slot.drawing;
			drawing.Visible = true;
			drawing.Text = item.text;
			drawing.Size = size;
			drawing.Font = item.font;
			drawing.Color = parseColor(self, spec.color[1]);
			drawing.Transparency = spec.color[2];
			drawing.Outline = spec.outline;
			drawing.OutlineColor = parseColor(self, spec.outlineColor, true);

			local bounds = drawing.TextBounds;
			drawing.Position = Vector2.new(x + bounds.X*0.5, y);
			y = y + bounds.Y + (spec.spacing or TEXT_LINE_GAP);
		end
	end

	local list = self.textList;
	for i = 1, #list do
		if list[i].usedId ~= renderId then
			list[i].drawing.Visible = false;
		end
	end
end

function EspObject:_pushEntry(n, slot, spec, value, max, defaultSide, drawBar, drawText)
	n = n + 1;
	local entry = self.barEntries[n];
	if not entry then
		entry = {};
		self.barEntries[n] = entry;
	end

	local side = normalizeSide(spec.position, defaultSide);
	entry.slot = slot;
	entry.spec = spec;
	entry.value = value;
	entry.max = max;
	entry.side = side;
	entry.drawBar = drawBar;
	entry.drawText = drawText;

	if drawBar then
		local index = self.sideCount[side] + 1;
		self.sideCount[side] = index;
		entry.index = index;
	else
		entry.index = 0;
	end

	return n;
end

-- раскладка баров по сторонам (стек наружу от бокса), считает сдвиги для name/distance/weapon
function EspObject:LayoutBars(active, options)
	local counts, distances = self.sideCount, self.sideDistance;
	for i = 1, #BAR_SIDES do
		local side = BAR_SIDES[i];
		counts[side] = 0;
	end

	local n = 0;
	if active then
		-- основной healthBar
		local spec = self.healthSpec;
		spec.enabled = options.healthBar;
		spec.position = options.healthBarPosition;
		spec.outline = options.healthBarOutline;
		spec.outlineColor = options.healthBarOutlineColor;
		spec.healthyColor = options.healthyColor;
		spec.dyingColor = options.dyingColor;
		spec.gradient = options.healthBarGradient;
		spec.gradientSegments = options.healthBarGradientSegments;
		spec.text = options.healthText;
		spec.textColor = options.healthTextColor;
		spec.textOutline = options.healthTextOutline;
		spec.textOutlineColor = options.healthTextOutlineColor;
		spec.textSuffix = "";

		local drawBar = spec.enabled and true or false;
		local drawText = drawBar and spec.text and true or false;
		if drawBar then
			n = self:_pushEntry(n, self.mainSlot, spec, self.health, self.maxHealth, "Left", drawBar, drawText);
		end

		-- кастомные бары
		local data = self.barData;
		for i = 1, self.barCount do
			local item = data[i];
			local custom = item.spec;
			n = self:_pushEntry(n, self:_getBarSlot(custom.name), custom, item.value, item.max, "Right", true, custom.text and true or false);
		end
	end
	self.entryCount = n;

	for i = 1, #BAR_SIDES do
		local side = BAR_SIDES[i];
		distances[side] = BAR_BASE_OFFSET + mathMax(counts[side] - 1, 0)*BAR_STACK_STEP;
	end
	self.topExtent = barExtent(counts.Top, distances.Top);
	self.bottomExtent = barExtent(counts.Bottom, distances.Bottom);
end

function EspObject:HideBar(slot)
	slot.line.Visible = false;
	slot.outline.Visible = false;
	slot.text.Visible = false;
	slot.glowShow = false;
	slot.smooth = nil;
	self:HideGradient(slot.segments);
end

function EspObject:RenderBar(entry, corners)
	local slot, spec, side = entry.slot, entry.spec, entry.side;
	local interface = self.interface;
	local value, max = entry.value, entry.max;
	local ratio = (max and max > 0) and clamp(value/max, 0, 1) or 0;
	local actualRatio = ratio;
	slot.usedId = self.renderId;

	-- smoothBars: отображаемое значение плавно догоняет реальное
	local alpha = self.smoothAlpha;
	if alpha then
		local shown = slot.smooth;
		if shown == nil then
			shown = ratio;
		else
			shown = shown + (ratio - shown)*alpha;
			if math.abs(ratio - shown) < 0.0005 then
				shown = ratio;
			end
		end
		slot.smooth = shown;
		ratio = shown;
	else
		slot.smooth = nil;
	end

	local topLeft, topRight = corners.topLeft, corners.topRight;
	local bottomLeft, bottomRight = corners.bottomLeft, corners.bottomRight;
	local vertical = side == "Left" or side == "Right";
	local textDistance = self.sideDistance[side];
	local offset = entry.index > 0 and (BAR_BASE_OFFSET + (entry.index - 1)*BAR_STACK_STEP) or textDistance;

	-- barTo = начало (пусто), barFrom = конец (полный)
	local barFrom, barTo;
	if side == "Left" then
		local shift = Vector2.new(offset, 0);
		barFrom, barTo = topLeft - shift, bottomLeft - shift;
	elseif side == "Right" then
		local shift = Vector2.new(offset, 0);
		barFrom, barTo = topRight + shift, bottomRight + shift;
	elseif side == "Top" then
		local shift = Vector2.new(0, offset);
		barFrom, barTo = topRight - shift, topLeft - shift;
	else
		local shift = Vector2.new(0, offset);
		barFrom, barTo = bottomRight + shift, bottomLeft + shift;
	end

	local fillEnd = lerp2(barTo, barFrom, ratio);
	local tint = lerpColor(spec.dyingColor, spec.healthyColor, ratio);

	if entry.drawBar then
		local useGradient = spec.gradient;
		slot.line.Visible = not useGradient;
		slot.outline.Visible = spec.outline and true or false;

		if useGradient then
			self:RenderGradient(slot, barFrom, barTo, ratio, spec);
		else
			local line = slot.line;
			line.To = barTo;
			line.From = fillEnd;
			line.Color = tint;
			self:HideGradient(slot.segments);
		end

		if spec.outline then
			local outline = slot.outline;
			if vertical then
				outline.To = barTo + HEALTH_BAR_OUTLINE_OFFSET;
				outline.From = barFrom - HEALTH_BAR_OUTLINE_OFFSET;
			else
				outline.To = barTo - BAR_OUTLINE_OFFSET_H;
				outline.From = barFrom + BAR_OUTLINE_OFFSET_H;
			end
			outline.Color = parseColor(self, spec.outlineColor[1], true);
			outline.Transparency = spec.outlineColor[2];
		end

		slot.glowShow = true;
		slot.gFrom = barTo;
		slot.gTo = fillEnd;
		slot.gTint = tint;
		slot.gBase = spec.outline and 3 or 1;
	else
		slot.line.Visible = false;
		slot.outline.Visible = false;
		slot.glowShow = false;
		self:HideGradient(slot.segments);
	end

	-- текст: только число, прямо на краю заливки; виден только если бар не полный
	local text = slot.text;
	if entry.drawText and (actualRatio < 1 or ratio < 0.995) then
		local textValue = alpha and ratio*(max or 0) or value;
		text.Visible = true;
		text.Text = tostring(spec.textFormat and spec.textFormat(textValue, max) or (round(textValue) .. (spec.textSuffix or "")));
		text.Size = interface.sharedSettings.textSize;
		text.Font = interface.sharedSettings.textFont;
		text.Color = parseColor(self, spec.textColor[1]);
		text.Transparency = spec.textColor[2];
		text.Outline = spec.textOutline;
		text.OutlineColor = parseColor(self, spec.textOutlineColor, true);
		text.Position = fillEnd - Vector2.new(0, text.TextBounds.Y*0.5);
	else
		text.Visible = false;
	end
end

function EspObject:Destruct()
	self.renderConnection:Disconnect();

	for i = 1, #self.bin do
		self.bin[i]:Remove();
	end

	destroyGlow(self.glowStore);
	clear(self);
end

function EspObject:Update()
	local interface = self.interface;

	self.options = interface.teamSettings[interface.isFriendly(self.player) and "friendly" or "enemy"];
	self.character = interface.getCharacter(self.player);
	self.health, self.maxHealth = interface.getHealth(self.player);
	self.weapon = interface.getWeapon(self.player);
	self.enabled = self.options.enabled and self.character and not
		(#interface.whitelist > 0 and not find(interface.whitelist, self.player.UserId));

	self.barCount = 0;
	self.textCount = 0;
	if self.enabled then
		self:UpdateBars();
		self:UpdateTexts();
	end

	local head = self.enabled and findFirstChild(self.character, "Head");
	if not head then
		self.charCache = {};
		self.onScreen = false;
		return;
	end

	local _, onScreen, depth = worldToScreen(head.Position);
	self.onScreen = onScreen;
	self.distance = depth;

	if interface.sharedSettings.limitDistance and depth > interface.sharedSettings.maxDistance then
		self.onScreen = false;
	end

	if self.onScreen then
		local cache = self.charCache;
		local children = getChildren(self.character);
		if not cache[1] or self.childCount ~= #children then
			clear(cache);

			for i = 1, #children do
				local part = children[i];
				if isA(part, "BasePart") and isBodyPart(part.Name) then
					cache[#cache + 1] = part;
				end
			end

			self.childCount = #children;
		end

		self.corners = calculateCorners(getBoundingBox(cache));
	elseif self.options.offScreenArrow then
		local cframe = camera.CFrame;
		local flat = fromMatrix(cframe.Position, cframe.RightVector, Vector3.yAxis);
		local objectSpace = pointToObjectSpace(flat, head.Position);
		self.direction = Vector2.new(objectSpace.X, objectSpace.Z).Unit;
	end
end

function EspObject:Render(deltaTime)
	local onScreen = self.onScreen or false;
	local enabled = self.enabled or false;
	local visible = self.drawings.visible;
	local hidden = self.drawings.hidden;
	local box3d = self.drawings.box3d;
	local interface = self.interface;
	local options = self.options;
	local corners = self.corners;

	visible.box.Visible = enabled and onScreen and options.box;
	visible.boxOutline.Visible = visible.box.Visible and options.boxOutline;
	if visible.box.Visible then
		local box = visible.box;
		box.Position = corners.topLeft;
		box.Size = corners.bottomRight - corners.topLeft;
		box.Color = parseColor(self, options.boxColor[1]);
		box.Transparency = options.boxColor[2];

		local boxOutline = visible.boxOutline;
		boxOutline.Position = box.Position;
		boxOutline.Size = box.Size;
		boxOutline.Color = parseColor(self, options.boxOutlineColor[1], true);
		boxOutline.Transparency = options.boxOutlineColor[2];
	end

	visible.boxFill.Visible = enabled and onScreen and options.boxFill;
	if visible.boxFill.Visible then
		local boxFill = visible.boxFill;
		boxFill.Position = corners.topLeft;
		boxFill.Size = corners.bottomRight - corners.topLeft;
		boxFill.Color = parseColor(self, options.boxFillColor[1]);
		boxFill.Transparency = options.boxFillColor[2];
	end

	if enabled and onScreen and options.cornerBox then
		renderCornerBox(
			self, true, corners, options,
			parseColor(self, options.cornerBoxColor[1]), options.cornerBoxColor[2],
			parseColor(self, options.cornerBoxOutlineColor[1], true), options.cornerBoxOutlineColor[2]
		);
	else
		renderCornerBox(self, false);
	end

	-- плавность баров: коэффициент интерполяции за кадр (nil = выключено)
	if options.smoothBars then
		self.smoothAlpha = 1 - math.exp(-(options.smoothBarsSpeed or 8)*(deltaTime or 1/60));
	else
		self.smoothAlpha = nil;
	end

	-- bars: healthBar + кастомные бары (позиция Left / Right / Top / Bottom)
	self.renderId = self.renderId + 1;
	self:LayoutBars(enabled and onScreen, options);
	for i = 1, self.entryCount do
		self:RenderBar(self.barEntries[i], corners);
	end
	for i = 1, #self.barSlots do
		local slot = self.barSlots[i];
		if slot.usedId ~= self.renderId then
			self:HideBar(slot);
		end
	end
	self:RenderTexts(enabled and onScreen, corners);

	visible.name.Visible = enabled and onScreen and options.name;
	if visible.name.Visible then
		local name = visible.name;
		name.Size = interface.sharedSettings.textSize;
		name.Font = interface.sharedSettings.textFont;
		name.Color = parseColor(self, options.nameColor[1]);
		name.Transparency = options.nameColor[2];
		name.Outline = options.nameOutline;
		name.OutlineColor = parseColor(self, options.nameOutlineColor, true);
		name.Position = (corners.topLeft + corners.topRight)*0.5 - Vector2.yAxis*name.TextBounds.Y - NAME_OFFSET - Vector2.yAxis*self.topExtent;
	end

	visible.distance.Visible = enabled and onScreen and self.distance and options.distance;
	if visible.distance.Visible then
		local distance = visible.distance;
		distance.Text = formatDistance(options.distanceText, self.distance, self.player);
		distance.Size = interface.sharedSettings.textSize;
		distance.Font = interface.sharedSettings.textFont;
		distance.Color = parseColor(self, options.distanceColor[1]);
		distance.Transparency = options.distanceColor[2];
		distance.Outline = options.distanceOutline;
		distance.OutlineColor = parseColor(self, options.distanceOutlineColor, true);
		distance.Position = (corners.bottomLeft + corners.bottomRight)*0.5 + DISTANCE_OFFSET + Vector2.yAxis*self.bottomExtent;
	end

	visible.weapon.Visible = enabled and onScreen and options.weapon;
	if visible.weapon.Visible then
		local weapon = visible.weapon;
		weapon.Text = self.weapon;
		weapon.Size = interface.sharedSettings.textSize;
		weapon.Font = interface.sharedSettings.textFont;
		weapon.Color = parseColor(self, options.weaponColor[1]);
		weapon.Transparency = options.weaponColor[2];
		weapon.Outline = options.weaponOutline;
		weapon.OutlineColor = parseColor(self, options.weaponOutlineColor, true);
		weapon.Position =
			(corners.bottomLeft + corners.bottomRight)*0.5 + Vector2.yAxis*self.bottomExtent +
			(visible.distance.Visible and DISTANCE_OFFSET + Vector2.yAxis*visible.distance.TextBounds.Y or Vector2.zero);
	end

	visible.tracer.Visible = enabled and onScreen and options.tracer;
	visible.tracerOutline.Visible = visible.tracer.Visible and options.tracerOutline;
	if visible.tracer.Visible then
		local tracer = visible.tracer;
		tracer.Color = parseColor(self, options.tracerColor[1]);
		tracer.Transparency = options.tracerColor[2];
		tracer.To = (corners.bottomLeft + corners.bottomRight)*0.5;
		tracer.From =
			options.tracerOrigin == "Middle" and viewportSize*0.5 or
			options.tracerOrigin == "Top" and viewportSize*Vector2.new(0.5, 0) or
			options.tracerOrigin == "Bottom" and viewportSize*Vector2.new(0.5, 1);

		local tracerOutline = visible.tracerOutline;
		tracerOutline.Color = parseColor(self, options.tracerOutlineColor[1], true);
		tracerOutline.Transparency = options.tracerOutlineColor[2];
		tracerOutline.To = tracer.To;
		tracerOutline.From = tracer.From;
	end

	hidden.arrow.Visible = enabled and (not onScreen) and options.offScreenArrow;
	hidden.arrowOutline.Visible = hidden.arrow.Visible and options.offScreenArrowOutline;
	if hidden.arrow.Visible and self.direction then
		local arrow = hidden.arrow;
		arrow.PointA = min2(max2(viewportSize*0.5 + self.direction*options.offScreenArrowRadius, Vector2.one*25), viewportSize - Vector2.one*25);
		arrow.PointB = arrow.PointA - rotateVector(self.direction, 0.45)*options.offScreenArrowSize;
		arrow.PointC = arrow.PointA - rotateVector(self.direction, -0.45)*options.offScreenArrowSize;
		arrow.Color = parseColor(self, options.offScreenArrowColor[1]);
		arrow.Transparency = options.offScreenArrowColor[2];

		local arrowOutline = hidden.arrowOutline;
		arrowOutline.PointA = arrow.PointA;
		arrowOutline.PointB = arrow.PointB;
		arrowOutline.PointC = arrow.PointC;
		arrowOutline.Color = parseColor(self, options.offScreenArrowOutlineColor[1], true);
		arrowOutline.Transparency = options.offScreenArrowOutlineColor[2];
	end

	local box3dEnabled = enabled and onScreen and options.box3d;
	for i = 1, #box3d do
		local face = box3d[i];
		for i2 = 1, #face do
			local line = face[i2];
			line.Visible = box3dEnabled;
			line.Color = parseColor(self, options.box3dColor[1]);
			line.Transparency = options.box3dColor[2];
		end

		if box3dEnabled then
			local line1 = face[1];
			line1.From = corners.corners[i];
			line1.To = corners.corners[i == 4 and 1 or i+1];

			local line2 = face[2];
			line2.From = corners.corners[i == 4 and 1 or i+1];
			line2.To = corners.corners[i == 4 and 5 or i+5];

			local line3 = face[3];
			line3.From = corners.corners[i == 4 and 5 or i+5];
			line3.To = corners.corners[i == 4 and 8 or i+4];
		end
	end

	-- glow
	if options.glow or self.glowActive then
		self.glowActive = options.glow and true or false;

		local box = visible.box;
		glowSquare(self, "box", box.Visible, box.Position, box.Size, box.Color, box.Transparency, options, "box", options.boxOutline and 3 or 1, false);

		local boxFill = visible.boxFill;
		glowSquare(self, "boxFill", boxFill.Visible, boxFill.Position, boxFill.Size, boxFill.Color, boxFill.Transparency, options, "boxFill", 1, true);

		for i = 1, #self.barSlots do
			local slot = self.barSlots[i];
			glowLine(self, slot.glowBar, slot.glowShow, slot.gFrom, slot.gTo, slot.gTint, 1, options, slot.glowBarElement, slot.gBase);
			-- текст бара получает glow только вместе с самим баром
			glowText(self, slot.glowText, slot.text, options, slot.glowTextElement, (slot.glowShow and glowAllowed(options, slot.glowBarElement)) and true or false);
		end

		for i = 1, #self.textList do
			local slot = self.textList[i];
			glowText(self, slot.glowKey, slot.drawing, options, "customText");
		end

		glowText(self, "name", visible.name, options, "name");
		glowText(self, "distance", visible.distance, options, "distance");
		glowText(self, "weapon", visible.weapon, options, "weapon");

		local tracer = visible.tracer;
		glowLine(self, "tracer", tracer.Visible, tracer.From, tracer.To, tracer.Color, tracer.Transparency, options, "tracer", options.tracerOutline and 3 or 1);

		local arrow = hidden.arrow;
		glowTriangle(self, "arrow", arrow.Visible and self.direction ~= nil, arrow.PointA, arrow.PointB, arrow.PointC, arrow.Color, arrow.Transparency, options, "arrow", options.offScreenArrowOutline and 3 or 1);

		for i = 1, #box3d do
			local face = box3d[i];
			for i2 = 1, #face do
				local line = face[i2];
				glowLine(self, BOX3D_GLOW_KEYS[i][i2], box3dEnabled, line.From, line.To, line.Color, line.Transparency, options, "box3d", 1);
			end
		end

		for i = 1, 8 do
			local line = self.cornerLines[i];
			glowLine(self, CORNER_GLOW_KEYS[i], line.Visible, line.From, line.To, line.Color, line.Transparency, options, "cornerBox", options.cornerBoxOutline and 3 or 1);
		end
	end
end

-- cham object
local ChamObject = {};
ChamObject.__index = ChamObject;

function ChamObject.new(player, interface)
	local self = setmetatable({}, ChamObject);
	self.player = assert(player, "Missing argument #1 (Player expected)");
	self.interface = assert(interface, "Missing argument #2 (table expected)");
	self:Construct();
	return self;
end

function ChamObject:Construct()
	self.highlight = Instance.new("Highlight", container);
	self.updateConnection = runService.Heartbeat:Connect(function()
		self:Update();
	end);
end

function ChamObject:Destruct()
	self.updateConnection:Disconnect();
	self.highlight:Destroy();

	clear(self);
end

function ChamObject:Update()
	local highlight = self.highlight;
	local interface = self.interface;
	local character = interface.getCharacter(self.player);
	local options = interface.teamSettings[interface.isFriendly(self.player) and "friendly" or "enemy"];
	local enabled = options.enabled and character and not
		(#interface.whitelist > 0 and not find(interface.whitelist, self.player.UserId));

	highlight.Enabled = enabled and options.chams;
	if highlight.Enabled then
		highlight.Adornee = character;
		highlight.FillColor = parseColor(self, options.chamsFillColor[1]);
		highlight.FillTransparency = options.chamsFillColor[2];
		highlight.OutlineColor = parseColor(self, options.chamsOutlineColor[1], true);
		highlight.OutlineTransparency = options.chamsOutlineColor[2];
		highlight.DepthMode = options.chamsVisibleOnly and "Occluded" or "AlwaysOnTop";
	end
end

-- instance class
local InstanceObject = {};
InstanceObject.__index = InstanceObject;

function InstanceObject.new(instance, options)
	local self = setmetatable({}, InstanceObject);
	self.instance = assert(instance, "Missing argument #1 (Instance Expected)");
	self.options = assert(options, "Missing argument #2 (table expected)");
	self:Construct();
	return self;
end

function InstanceObject:Construct()
	local options = self.options;
	options.enabled = options.enabled == nil and true or options.enabled;

	-- text
	options.text = options.text or "";
	options.textColor = options.textColor or { Color3.new(1,1,1), 1 };
	options.textOutline = options.textOutline == nil and true or options.textOutline;
	options.textOutlineColor = options.textOutlineColor or Color3.new();
	options.textSize = options.textSize or 13;
	options.textFont = options.textFont or 2;

	-- name (над боксом)
	options.name = options.name or false;
	options.nameColor = options.nameColor or { Color3.new(1,1,1), 1 };
	options.nameOutline = options.nameOutline == nil and true or options.nameOutline;
	options.nameOutlineColor = options.nameOutlineColor or Color3.new();

	-- distance (под боксом)
	options.distance = options.distance or false;
	options.distanceColor = options.distanceColor or { Color3.new(1,1,1), 1 };
	options.distanceOutline = options.distanceOutline == nil and true or options.distanceOutline;
	options.distanceOutlineColor = options.distanceOutlineColor or Color3.new();
	options.distanceText = options.distanceText or "{distance} studs";

	-- box
	options.box = options.box or false;
	options.boxColor = options.boxColor or { Color3.new(1,1,1), 1 };
	options.boxOutline = options.boxOutline == nil and true or options.boxOutline;
	options.boxOutlineColor = options.boxOutlineColor or { Color3.new(), 1 };
	options.boxFill = options.boxFill or false;
	options.boxFillColor = options.boxFillColor or { Color3.new(1,1,1), 0.5 };

	-- box3d
	options.box3d = options.box3d or false;
	options.box3dColor = options.box3dColor or { Color3.new(1,1,1), 1 };

	-- corner box
	options.cornerBox = options.cornerBox or false;
	options.cornerBoxColor = options.cornerBoxColor or { Color3.new(1,1,1), 1 };
	options.cornerBoxOutline = options.cornerBoxOutline == nil and true or options.cornerBoxOutline;
	options.cornerBoxOutlineColor = options.cornerBoxOutlineColor or { Color3.new(), 1 };
	options.cornerBoxLength = options.cornerBoxLength or 0.25;

	-- tracer
	options.tracer = options.tracer or false;
	options.tracerOrigin = options.tracerOrigin or "Bottom";
	options.tracerColor = options.tracerColor or { Color3.new(1,1,1), 1 };
	options.tracerOutline = options.tracerOutline == nil and true or options.tracerOutline;
	options.tracerOutlineColor = options.tracerOutlineColor or { Color3.new(), 1 };

	-- chams
	options.chams = options.chams or false;
	options.chamsVisibleOnly = options.chamsVisibleOnly or false;
	options.chamsFillColor = options.chamsFillColor or { Color3.new(0.2, 0.2, 0.2), 0.5 };
	options.chamsOutlineColor = options.chamsOutlineColor or { Color3.new(1,1,1), 0 };

	-- distance limit
	options.limitDistance = options.limitDistance or false;
	options.maxDistance = options.maxDistance or 150;

	-- glow
	options.glow = options.glow or false;
	options.glowLayers = options.glowLayers or 3;
	options.glowSize = options.glowSize or 2;
	options.glowIntensity = options.glowIntensity or 0.6;
	options.glowTextLayers = options.glowTextLayers or 1;
	self.glowStore = {};

	-- text drawing (кастомный текст)
	self.text = Drawing.new("Text");
	self.text.Center = true;

	-- name drawing (над боксом)
	self.nameDrawing = Drawing.new("Text");
	self.nameDrawing.Center = true;
	self.nameDrawing.Visible = false;

	-- distance drawing (под боксом)
	self.distanceDrawing = Drawing.new("Text");
	self.distanceDrawing.Center = true;
	self.distanceDrawing.Visible = false;

	-- box drawings
	self.boxOutlineDrawing = Drawing.new("Square");
	self.boxOutlineDrawing.Thickness = 3;
	self.boxOutlineDrawing.Visible = false;

	self.boxDrawing = Drawing.new("Square");
	self.boxDrawing.Thickness = 1;
	self.boxDrawing.Visible = false;

	self.boxFillDrawing = Drawing.new("Square");
	self.boxFillDrawing.Filled = true;
	self.boxFillDrawing.Visible = false;

	-- corner box drawings
	self.cornerOutlines = {};
	self.cornerLines = {};
	for i = 1, 8 do
		local outline = Drawing.new("Line");
		outline.Thickness = 3;
		outline.Visible = false;
		self.cornerOutlines[i] = outline;
	end
	for i = 1, 8 do
		local line = Drawing.new("Line");
		line.Thickness = 1;
		line.Visible = false;
		self.cornerLines[i] = line;
	end

	-- box3d drawings (4 грани по 3 линии)
	self.box3dDrawings = {};
	for i = 1, 4 do
		self.box3dDrawings[i] = {};
		for j = 1, 3 do
			local line = Drawing.new("Line");
			line.Thickness = 1;
			line.Visible = false;
			self.box3dDrawings[i][j] = line;
		end
	end

	-- tracer drawings
	self.tracerOutlineDrawing = Drawing.new("Line");
	self.tracerOutlineDrawing.Thickness = 3;
	self.tracerOutlineDrawing.Visible = false;

	self.tracerDrawing = Drawing.new("Line");
	self.tracerDrawing.Thickness = 1;
	self.tracerDrawing.Visible = false;

	-- ZIndex: основные элементы над свечением
	local mainDrawings = {
		self.text, self.nameDrawing, self.distanceDrawing, self.boxOutlineDrawing, self.boxDrawing,
		self.boxFillDrawing, self.tracerOutlineDrawing, self.tracerDrawing
	};
	for i = 1, 4 do
		for j = 1, 3 do
			mainDrawings[#mainDrawings + 1] = self.box3dDrawings[i][j];
		end
	end
	for i = 1, 8 do
		mainDrawings[#mainDrawings + 1] = self.cornerOutlines[i];
		mainDrawings[#mainDrawings + 1] = self.cornerLines[i];
	end
	for i = 1, #mainDrawings do
		pcall(function() mainDrawings[i].ZIndex = 1; end);
	end

	-- chams highlight
	self.highlight = Instance.new("Highlight", container);
	self.highlight.Enabled = false;

	self.renderConnection = runService.Heartbeat:Connect(function(deltaTime)
		self:Render(deltaTime);
	end);
end

function InstanceObject:Destruct()
	self.renderConnection:Disconnect();
	self.text:Remove();
	self.nameDrawing:Remove();
	self.distanceDrawing:Remove();
	self.boxDrawing:Remove();
	self.boxOutlineDrawing:Remove();
	self.boxFillDrawing:Remove();
	self.tracerDrawing:Remove();
	self.tracerOutlineDrawing:Remove();
	self.highlight:Destroy();
	destroyGlow(self.glowStore);
	for i = 1, 8 do
		self.cornerOutlines[i]:Remove();
		self.cornerLines[i]:Remove();
	end

	for i = 1, 4 do
		for j = 1, 3 do
			self.box3dDrawings[i][j]:Remove();
		end
	end
end

function InstanceObject:Render()
	local instance = self.instance;
	if not instance or not instance.Parent then
		return self:Destruct();
	end

	local text = self.text;
	local options = self.options;

	if not options.enabled then
		text.Visible = false;
		self.nameDrawing.Visible = false;
		self.distanceDrawing.Visible = false;
		self.boxDrawing.Visible = false;
		self.boxOutlineDrawing.Visible = false;
		self.boxFillDrawing.Visible = false;
		self.tracerDrawing.Visible = false;
		self.tracerOutlineDrawing.Visible = false;
		self.highlight.Enabled = false;
		hideAllGlow(self.glowStore);
		for i = 1, 8 do
			self.cornerOutlines[i].Visible = false;
			self.cornerLines[i].Visible = false;
		end
		for i = 1, 4 do
			for j = 1, 3 do
				self.box3dDrawings[i][j].Visible = false;
			end
		end
		return;
	end

	local world = getPivot(instance).Position;
	local position, visible, depth = worldToScreen(world);
	if options.limitDistance and depth > options.maxDistance then
		visible = false;
	end

	-- кастомный текст
	text.Visible = visible and options.text ~= "";
	if text.Visible then
		text.Position = position;
		text.Color = options.textColor[1];
		text.Transparency = options.textColor[2];
		text.Outline = options.textOutline;
		text.OutlineColor = options.textOutlineColor;
		text.Size = options.textSize;
		text.Font = options.textFont;
		text.Text = options.text
			:gsub("{name}", instance.Name)
			:gsub("{distance}", round(depth))
			:gsub("{position}", tostring(world));
	end

	-- chams
	self.highlight.Enabled = options.chams and instance.Parent ~= nil;
	if self.highlight.Enabled then
		self.highlight.Adornee = instance;
		self.highlight.FillColor = options.chamsFillColor[1];
		self.highlight.FillTransparency = options.chamsFillColor[2];
		self.highlight.OutlineColor = options.chamsOutlineColor[1];
		self.highlight.OutlineTransparency = options.chamsOutlineColor[2];
		self.highlight.DepthMode = options.chamsVisibleOnly and "Occluded" or "AlwaysOnTop";
	end

	-- bounding box calculation
	local boxCFrame, boxSize;
	if isA(instance, "BasePart") then
		boxCFrame = getPivot(instance);
		boxSize = instance.Size;
	elseif isA(instance, "Model") then
		local parts = {};
		for _, v in ipairs(instance:GetDescendants()) do
			if isA(v, "BasePart") then
				parts[#parts + 1] = v;
			end
		end
		if #parts > 0 then
			boxCFrame, boxSize = getBoundingBox(parts);
		end
	end

	if not boxCFrame then
		boxCFrame = getPivot(instance);
		boxSize = Vector3.new(4, 4, 4);
	end

	local corners = calculateCorners(boxCFrame, boxSize);

	-- name (над боксом)
	self.nameDrawing.Visible = visible and options.name;
	if self.nameDrawing.Visible then
		local nameD = self.nameDrawing;
		nameD.Text = instance.Name;
		nameD.Size = options.textSize;
		nameD.Font = options.textFont;
		nameD.Color = options.nameColor[1];
		nameD.Transparency = options.nameColor[2];
		nameD.Outline = options.nameOutline;
		nameD.OutlineColor = options.nameOutlineColor;
		nameD.Position = (corners.topLeft + corners.topRight)*0.5 - Vector2.yAxis*nameD.TextBounds.Y - NAME_OFFSET;
	end

	-- distance (под боксом)
	self.distanceDrawing.Visible = visible and options.distance;
	if self.distanceDrawing.Visible then
		local distD = self.distanceDrawing;
		distD.Text = formatDistance(options.distanceText, depth);
		distD.Size = options.textSize;
		distD.Font = options.textFont;
		distD.Color = options.distanceColor[1];
		distD.Transparency = options.distanceColor[2];
		distD.Outline = options.distanceOutline;
		distD.OutlineColor = options.distanceOutlineColor;
		distD.Position = (corners.bottomLeft + corners.bottomRight)*0.5 + DISTANCE_OFFSET;
	end

	-- box
	local boxVisible = visible and options.box;
	self.boxDrawing.Visible = boxVisible;
	self.boxOutlineDrawing.Visible = boxVisible and options.boxOutline;

	if boxVisible then
		local box = self.boxDrawing;
		box.Position = corners.topLeft;
		box.Size = corners.bottomRight - corners.topLeft;
		box.Color = options.boxColor[1];
		box.Transparency = options.boxColor[2];

		local boxOutline = self.boxOutlineDrawing;
		boxOutline.Position = corners.topLeft;
		boxOutline.Size = corners.bottomRight - corners.topLeft;
		boxOutline.Color = options.boxOutlineColor[1];
		boxOutline.Transparency = options.boxOutlineColor[2];
	end

	-- box fill
	self.boxFillDrawing.Visible = visible and options.boxFill;
	if self.boxFillDrawing.Visible then
		local boxFill = self.boxFillDrawing;
		boxFill.Position = corners.topLeft;
		boxFill.Size = corners.bottomRight - corners.topLeft;
		boxFill.Color = options.boxFillColor[1];
		boxFill.Transparency = options.boxFillColor[2];
	end

	-- corner box
	renderCornerBox(
		self, visible and options.cornerBox, corners, options,
		options.cornerBoxColor[1], options.cornerBoxColor[2],
		options.cornerBoxOutlineColor[1], options.cornerBoxOutlineColor[2]
	);

	-- box3d
	local box3dEnabled = visible and options.box3d;
	for i = 1, 4 do
		local face = self.box3dDrawings[i];
		for j = 1, 3 do
			local line = face[j];
			line.Visible = box3dEnabled;
			if box3dEnabled then
				line.Color = options.box3dColor[1];
				line.Transparency = options.box3dColor[2];
			end
		end

		if box3dEnabled then
			local line1 = face[1];
			line1.From = corners.corners[i];
			line1.To = corners.corners[i == 4 and 1 or i+1];

			local line2 = face[2];
			line2.From = corners.corners[i == 4 and 1 or i+1];
			line2.To = corners.corners[i == 4 and 5 or i+5];

			local line3 = face[3];
			line3.From = corners.corners[i == 4 and 5 or i+5];
			line3.To = corners.corners[i == 4 and 8 or i+4];
		end
	end

	-- tracer
	self.tracerDrawing.Visible = visible and options.tracer;
	self.tracerOutlineDrawing.Visible = self.tracerDrawing.Visible and options.tracerOutline;
	if self.tracerDrawing.Visible then
		local tracer = self.tracerDrawing;
		tracer.Color = options.tracerColor[1];
		tracer.Transparency = options.tracerColor[2];
		tracer.To = (corners.bottomLeft + corners.bottomRight)*0.5;
		tracer.From =
			options.tracerOrigin == "Middle" and viewportSize*0.5 or
			options.tracerOrigin == "Top" and viewportSize*Vector2.new(0.5, 0) or
			options.tracerOrigin == "Bottom" and viewportSize*Vector2.new(0.5, 1);

		local tracerOutline = self.tracerOutlineDrawing;
		tracerOutline.Color = options.tracerOutlineColor[1];
		tracerOutline.Transparency = options.tracerOutlineColor[2];
		tracerOutline.To = tracer.To;
		tracerOutline.From = tracer.From;
	end

	-- glow
	if options.glow or self.glowActive then
		self.glowActive = options.glow and true or false;

		glowText(self, "text", text, options, "text");
		glowText(self, "name", self.nameDrawing, options, "name");
		glowText(self, "distance", self.distanceDrawing, options, "distance");

		local box = self.boxDrawing;
		glowSquare(self, "box", box.Visible, box.Position, box.Size, box.Color, box.Transparency, options, "box", options.boxOutline and 3 or 1, false);

		local boxFill = self.boxFillDrawing;
		glowSquare(self, "boxFill", boxFill.Visible, boxFill.Position, boxFill.Size, boxFill.Color, boxFill.Transparency, options, "boxFill", 1, true);

		local tracer = self.tracerDrawing;
		glowLine(self, "tracer", tracer.Visible, tracer.From, tracer.To, tracer.Color, tracer.Transparency, options, "tracer", options.tracerOutline and 3 or 1);

		for i = 1, 4 do
			for j = 1, 3 do
				local line = self.box3dDrawings[i][j];
				glowLine(self, BOX3D_GLOW_KEYS[i][j], box3dEnabled, line.From, line.To, line.Color, line.Transparency, options, "box3d", 1);
			end
		end

		for i = 1, 8 do
			local line = self.cornerLines[i];
			glowLine(self, CORNER_GLOW_KEYS[i], line.Visible, line.From, line.To, line.Color, line.Transparency, options, "cornerBox", options.cornerBoxOutline and 3 or 1);
		end
	end
end

-- interface
local EspInterface = {
	_hasLoaded = false,
	_objectCache = {},
	whitelist = {},
	sharedSettings = {
		textSize = 13,
		textFont = 2,
		limitDistance = false,
		maxDistance = 150,
		useTeamColor = false
	},
	teamSettings = {
		enemy = {
			enabled = false,
			glow = false,
			glowLayers = 3,
			glowSize = 2,
			glowIntensity = 0.6,
			glowTextLayers = 1,
			-- glowColor = Color3.new(1, 1, 1), -- необязательно; по умолчанию цвет самого элемента
			-- glowElements = { box = true, boxFill = true, box3d = true, cornerBox = true, healthBar = true, healthText = true,
			--                  name = true, distance = true, weapon = true, tracer = true, arrow = true };
			box = false,
			boxColor = { Color3.new(1,0,0), 1 },
			boxOutline = true,
			boxOutlineColor = { Color3.new(), 1 },
			cornerBox = false,
			cornerBoxColor = { Color3.new(1,0,0), 1 },
			cornerBoxOutline = true,
			cornerBoxOutlineColor = { Color3.new(), 1 },
			cornerBoxLength = 0.25, -- длина уголка (доля ширины бокса, максимум 0.5)
			boxFill = false,
			boxFillColor = { Color3.new(1,0,0), 0.5 },
			healthBar = false,
			healthyColor = Color3.new(0,1,0),
			dyingColor = Color3.new(1,0,0),
			healthBarPosition = "Left", -- "Left" | "Right" | "Top" | "Bottom" (или "Below")
			smoothBars = false,       -- плавная анимация healthBar и кастомных баров
			smoothBarsSpeed = 8,      -- скорость анимации (больше = быстрее)
			-- кастомные бары, значения берутся из EspInterface.getValue(player, name):
			-- bars = { { name = "armor", position = "Right", healthyColor = Color3.new(0, 0.6, 1), text = true } },
			-- либо EspInterface.AddBar("armor", { position = "Right", text = true })
			bars = {},
			-- кастомные тексты справа от бокса, значения из EspInterface.getText(player, name):
			-- texts = { { name = "ammo", color = { Color3.new(1, 1, 0), 1 } } },
			-- либо EspInterface.AddText("ammo", { color = { Color3.new(1, 1, 0), 1 } })
			texts = {},
			healthBarGradient = false,
			healthBarGradientSegments = 16,
			healthBarOutline = true,
			healthBarOutlineColor = { Color3.new(), 0.5 },
			healthText = true, -- число HP на краю заливки (только если HP не полное), работает вместе с healthBar
			healthTextColor = { Color3.new(1,1,1), 1 },
			healthTextOutline = true,
			healthTextOutlineColor = Color3.new(),
			box3d = false,
			box3dColor = { Color3.new(1,0,0), 1 },
			name = false,
			nameColor = { Color3.new(1,1,1), 1 },
			nameOutline = true,
			nameOutlineColor = Color3.new(),
			weapon = false,
			weaponColor = { Color3.new(1,1,1), 1 },
			weaponOutline = true,
			weaponOutlineColor = Color3.new(),
			distance = false,
			distanceColor = { Color3.new(1,1,1), 1 },
			distanceOutline = true,
			distanceOutlineColor = Color3.new(),
			distanceText = "{distance} studs", -- шаблон ({distance} = число) или function(distance, player) return "..." end
			tracer = false,
			tracerOrigin = "Bottom",
			tracerColor = { Color3.new(1,0,0), 1 },
			tracerOutline = true,
			tracerOutlineColor = { Color3.new(), 1 },
			offScreenArrow = false,
			offScreenArrowColor = { Color3.new(1,1,1), 1 },
			offScreenArrowSize = 15,
			offScreenArrowRadius = 150,
			offScreenArrowOutline = true,
			offScreenArrowOutlineColor = { Color3.new(), 1 },
			chams = false,
			chamsVisibleOnly = false,
			chamsFillColor = { Color3.new(0.2, 0.2, 0.2), 0.5 },
			chamsOutlineColor = { Color3.new(1,0,0), 0 },
		},
		friendly = {
			enabled = false,
			glow = false,
			glowLayers = 3,
			glowSize = 2,
			glowIntensity = 0.6,
			glowTextLayers = 1,
			-- glowColor = Color3.new(1, 1, 1), -- необязательно; по умолчанию цвет самого элемента
			-- glowElements = { box = true, boxFill = true, box3d = true, cornerBox = true, healthBar = true, healthText = true,
			--                  name = true, distance = true, weapon = true, tracer = true, arrow = true };
			box = false,
			boxColor = { Color3.new(0,1,0), 1 },
			boxOutline = true,
			boxOutlineColor = { Color3.new(), 1 },
			cornerBox = false,
			cornerBoxColor = { Color3.new(0,1,0), 1 },
			cornerBoxOutline = true,
			cornerBoxOutlineColor = { Color3.new(), 1 },
			cornerBoxLength = 0.25, -- длина уголка (доля ширины бокса, максимум 0.5)
			boxFill = false,
			boxFillColor = { Color3.new(0,1,0), 0.5 },
			healthBar = false,
			healthyColor = Color3.new(0,1,0),
			dyingColor = Color3.new(1,0,0),
			healthBarPosition = "Left", -- "Left" | "Right" | "Top" | "Bottom" (или "Below")
			smoothBars = false,       -- плавная анимация healthBar и кастомных баров
			smoothBarsSpeed = 8,      -- скорость анимации (больше = быстрее)
			-- кастомные бары, значения берутся из EspInterface.getValue(player, name):
			-- bars = { { name = "armor", position = "Right", healthyColor = Color3.new(0, 0.6, 1), text = true } },
			-- либо EspInterface.AddBar("armor", { position = "Right", text = true })
			bars = {},
			-- кастомные тексты справа от бокса, значения из EspInterface.getText(player, name):
			-- texts = { { name = "ammo", color = { Color3.new(1, 1, 0), 1 } } },
			-- либо EspInterface.AddText("ammo", { color = { Color3.new(1, 1, 0), 1 } })
			texts = {},
			healthBarGradient = false,
			healthBarGradientSegments = 16,
			healthBarOutline = true,
			healthBarOutlineColor = { Color3.new(), 0.5 },
			healthText = true, -- число HP на краю заливки (только если HP не полное), работает вместе с healthBar
			healthTextColor = { Color3.new(1,1,1), 1 },
			healthTextOutline = true,
			healthTextOutlineColor = Color3.new(),
			box3d = false,
			box3dColor = { Color3.new(0,1,0), 1 },
			name = false,
			nameColor = { Color3.new(1,1,1), 1 },
			nameOutline = true,
			nameOutlineColor = Color3.new(),
			weapon = false,
			weaponColor = { Color3.new(1,1,1), 1 },
			weaponOutline = true,
			weaponOutlineColor = Color3.new(),
			distance = false,
			distanceColor = { Color3.new(1,1,1), 1 },
			distanceOutline = true,
			distanceOutlineColor = Color3.new(),
			distanceText = "{distance} studs", -- шаблон ({distance} = число) или function(distance, player) return "..." end
			tracer = false,
			tracerOrigin = "Bottom",
			tracerColor = { Color3.new(0,1,0), 1 },
			tracerOutline = true,
			tracerOutlineColor = { Color3.new(), 1 },
			offScreenArrow = false,
			offScreenArrowColor = { Color3.new(1,1,1), 1 },
			offScreenArrowSize = 15,
			offScreenArrowRadius = 150,
			offScreenArrowOutline = true,
			offScreenArrowOutlineColor = { Color3.new(), 1 },
			chams = false,
			chamsVisibleOnly = false,
			chamsFillColor = { Color3.new(0.2, 0.2, 0.2), 0.5 },
			chamsOutlineColor = { Color3.new(0,1,0), 0 }
		}
	}
};

function EspInterface.AddInstance(instance, options)
	local cache = EspInterface._objectCache;
	if cache[instance] then
		warn("Instance handler already exists.");
	else
		cache[instance] = { InstanceObject.new(instance, options) };
	end
	return cache[instance][1];
end

-- кастомные бары: EspInterface.AddBar(name, config, team)
-- team = "enemy" | "friendly" (nil = оба). Конфиг (все поля необязательны):
--   position = "Left" | "Right" | "Top" | "Bottom" (или "Below"), по умолчанию "Right"
--   healthyColor, dyingColor, gradient, gradientSegments, outline, outlineColor = { Color3, transparency }
--   text (по умолчанию true; число на краю заливки, показывается только если бар не полный), textColor = { Color3, transparency },
--   textOutline, textOutlineColor, textSuffix, textFormat = function(value, max)
--   getValue = function(player, name) return value, max end -- переопределяет EspInterface.getValue
local function addSpec(listName, normalize, name, config, team)
	assert(type(name) == "string", "Missing argument #1 (string expected)");

	local spec = config or {};
	spec.name = name;
	spec._normalized = nil;
	normalize(spec);

	local targets = {};
	if team then
		targets[1] = assert(EspInterface.teamSettings[team], "Unknown team (enemy / friendly expected)");
	else
		targets[1], targets[2] = EspInterface.teamSettings.enemy, EspInterface.teamSettings.friendly;
	end

	for i = 1, #targets do
		local settings = targets[i];
		settings[listName] = settings[listName] or {};

		local list, replaced = settings[listName], false;
		for j = 1, #list do
			if list[j].name == name then
				list[j] = spec;
				replaced = true;
				break;
			end
		end
		if not replaced then
			list[#list + 1] = spec;
		end
	end
	return spec;
end

local function removeSpec(listName, name, team)
	for teamName, settings in next, EspInterface.teamSettings do
		if not team or team == teamName then
			local list = settings[listName];
			if list then
				for i = #list, 1, -1 do
					if list[i].name == name then
						table.remove(list, i);
					end
				end
			end
		end
	end
end

function EspInterface.AddBar(name, config, team)
	return addSpec("bars", normalizeBar, name, config, team);
end

function EspInterface.RemoveBar(name, team)
	removeSpec("bars", name, team);
end

-- кастомные тексты справа от бокса: EspInterface.AddText(name, config, team)
-- Конфиг (все поля необязательны):
--   color = { Color3, transparency }, outline, outlineColor, size, font, spacing
--   scale = false -- не уменьшать размер, когда стек не влезает в бокс; minSize = 8 -- нижний предел размера
--   text = "строка" -- статичный текст (вместо getText)
--   getText = function(player, name) return "30/90" end -- переопределяет EspInterface.getText
-- Текст nil или "" = строка скрыта, следующие поднимаются вверх
function EspInterface.AddText(name, config, team)
	return addSpec("texts", normalizeText, name, config, team);
end

function EspInterface.RemoveText(name, team)
	removeSpec("texts", name, team);
end

function EspInterface.Load()
	assert(not EspInterface._hasLoaded, "Esp has already been loaded.");

	local function createObject(player)
		EspInterface._objectCache[player] = {
			EspObject.new(player, EspInterface),
			ChamObject.new(player, EspInterface)
		};
	end

	local function removeObject(player)
		local object = EspInterface._objectCache[player];
		if object then
			for i = 1, #object do
				object[i]:Destruct();
			end
			EspInterface._objectCache[player] = nil;
		end
	end

	local plrs = players:GetPlayers();
	for i = 2, #plrs do
		createObject(plrs[i]);
	end

	EspInterface.playerAdded = players.PlayerAdded:Connect(createObject);
	EspInterface.playerRemoving = players.PlayerRemoving:Connect(removeObject);
	EspInterface._hasLoaded = true;
end

function EspInterface.Unload()
	assert(EspInterface._hasLoaded, "Esp has not been loaded yet.");

	for index, object in next, EspInterface._objectCache do
		for i = 1, #object do
			object[i]:Destruct();
		end
		EspInterface._objectCache[index] = nil;
	end

	EspInterface.playerAdded:Disconnect();
	EspInterface.playerRemoving:Disconnect();
	EspInterface._hasLoaded = false;
end

-- game specific functions
function EspInterface.getWeapon(player)
	return "Unknown";
end

-- значение для кастомных баров: return value, maxValue (nil = бар скрыт)
-- пример: if name == "armor" then return player.Character.Armor.Value, 100 end
function EspInterface.getValue(player, name)
	return nil;
end

-- текст для кастомных строк справа от бокса: return "строка" (nil / "" = скрыто)
-- пример: if name == "ammo" then return player.Character.Gun.Ammo.Value .. "/" .. player.Character.Gun.Reserve.Value end
function EspInterface.getText(player, name)
	return nil;
end

function EspInterface.isFriendly(player)
	return player.Team and player.Team == localPlayer.Team;
end

function EspInterface.getTeamColor(player)
	return player.Team and player.Team.TeamColor and player.Team.TeamColor.Color;
end

function EspInterface.getCharacter(player)
	return player.Character;
end

function EspInterface.getHealth(player)
	local character = player and EspInterface.getCharacter(player);
	local humanoid = character and findFirstChildOfClass(character, "Humanoid");
	if humanoid then
		return humanoid.Health, humanoid.MaxHealth;
	end
	return 100, 100;
end

return EspInterface;
