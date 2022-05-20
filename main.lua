-- Inspector Kern
-- For usage info, see README.md
-- For license info, see LICENSE

local PROGRAM_VERSION = "1.0.2"

require("lib.test.strict")
local nativefs = require("lib.nativefs")
local kerning_pairs = require("kerning_pairs") -- https://github.com/andre-fuchs/kerning-pairs


-- Set up LÖVE
love.keyboard.setKeyRepeat(true)


-- * Program Config *
local font_size = 72 -- Used when checking kerning
local font_size_display = 24

local bulk_path = false
local fs_backend = "lfs"

local tick_time = 1/30

local show_zero_kern_fonts = false

local check_hasglyphs = false
local glyphs_t = {
	{"()", ""}, -- Empty string
	{"(\\t)", "\t"}, -- Horizontal tab
	{"(\\r)", "\r"}, -- Carriage return
	{"(\\n)", "\n"}, -- Line feed (newline)
	{"( )", " "}, -- Space
}


-- * Program State *
local mode = "interactive"
local sub_state = "scanning" -- "scanning", "working", "no_fonts_found"

local co_enumerate -- will hold coroutine for file enumeration
local co_time -- Coroutine yields if love.timer.getTime() exceeds this value (after running at least one loop iter.)
local co_path_status -- Something to print while scanning takes place

local translate_x, translate_y = 16, 96
local list_y = 1

local font_paths = {}
local font_i = 1

local accumulator = 0

local int_font = love.graphics.newFont(font_size)
local int_font_display = love.graphics.newFont(font_size_display)
local int_font_regular = love.graphics.newFont()
local int_name = "<LÖVE Built-in Font>"
local int_n_offsets = 0

local display_lines = {}


-- * Program Stats *
local fonts_with_non_zero_kerning = 0
local fonts_total = 0


function love.keypressed(kc, sc)
	if sc == "escape" then
		love.event.quit()
		return

	elseif sc == "up" then
		list_y = math.max(1, list_y - 1)

	elseif sc == "pageup" then
		list_y = math.max(1, list_y - 10)

	elseif sc == "home" then
		list_y = 1

	elseif sc == "down" then
		list_y = math.min(math.max(1, #display_lines), list_y + 1)

	elseif sc == "pagedown" then
		list_y = math.min(math.max(1, #display_lines), list_y + 10)

	elseif sc == "end" then
		list_y = #display_lines

	elseif sc == "left" then
		translate_x = translate_x + 16

	elseif sc == "right" then
		translate_x = translate_x - 16
	end
end


function love.wheelmoved(x, y)
	translate_x = translate_x - math.floor(0.5 + x) * 16
	list_y = math.max(1, math.min(#display_lines, list_y - math.floor(0.5 + y)))
end


-- * Filesystem Wrappers *


local function fs_getInfo(file)
	if fs_backend == "lfs" then
		return love.filesystem.getInfo(file)
	elseif fs_backend == "nfs" then
		return nativefs.getInfo(file)
	else
		error("invalid filesystem backend: " .. fs_backend)
	end
end


local function fs_getDirectoryItems(folder)
	if fs_backend == "lfs" then
		return love.filesystem.getDirectoryItems(folder)
	elseif fs_backend == "nfs" then
		return nativefs.getDirectoryItems(folder)
	else
		error("invalid filesystem backend: " .. fs_backend)
	end
end


local function fs_newFileData(path)
	local f_data, err
	if fs_backend == "lfs" then
		f_data, err = love.filesystem.newFileData(path)
	elseif fs_backend == "nfs" then
		f_data, err = nativefs.newFileData(path)
	else
		error("invalid filesystem backend: " .. fs_backend)
	end

	if not f_data then
		error(err)
	else
		return f_data
	end
end


-- * / Filesystem Wrappers *


local function _recursiveEnumerate(folder, filters, _file_list)
	if _file_list and coroutine.running() and love.timer.getTime() >= co_time then
		coroutine.yield()
	end

	_file_list = _file_list or {}

	local filesTable = fs_getDirectoryItems(folder)

	for i,v in ipairs(filesTable) do
		local file = folder.."/"..v
		local info = fs_getInfo(file)

		if not info then
			print("ERROR: failed to get file info for: " .. file)

		else
			if info.type == "file" then
				local ext = string.match(file, ".*%.(.*)$") or ""
				if not filters or filters[string.lower(ext)] then
					table.insert(_file_list, file)
				end

			elseif info.type == "directory" then
				_recursiveEnumerate(file, filters, _file_list)
			end
		end
		if coroutine.running() and love.timer.getTime() >= co_time then
			co_path_status = file
			coroutine.yield()
		end
	end

	return _file_list
end


local function initBulk(fs_back, b_path)
	mode = "bulk"
	fs_backend = fs_back
	if not b_path then
		error("no path for bulk mode found.")
	end

	bulk_path = b_path

	co_enumerate = coroutine.create(_recursiveEnumerate)
end


local function countKerningOffsets(font)
	local non_zero_pairs = 0

	for i, pair in ipairs(kerning_pairs) do
		local kern_value = font:getKerning(pair[1], pair[2])
		if kern_value ~= 0 then
			non_zero_pairs = non_zero_pairs + 1
			--print(i, pair[1], pair[2], kern_value)
		end
	end

	return non_zero_pairs
end


local function reportHasGlyphs(font, glyph_defs)
	local ret_str = ""

	for i, def in ipairs(glyph_defs) do
		ret_str = ret_str .. def[1] .. ": " .. tostring(font:hasGlyphs(def[2]))
		if i < #glyph_defs then
			ret_str = ret_str .. ", "
		end
	end

	return ret_str
end


function love.load(arguments)
	print("* INSPECTOR KERN *")
	print("VERSION: " .. PROGRAM_VERSION)
	print("")

	local bulk_mode = false
	local bulk_path

	local i = 1
	while i <= #arguments do
		local argument = arguments[i]

		-- Bulk Mode (using love.filesystem)
		if arguments[i] == "--bulk" then
			bulk_mode = "lfs"
			bulk_path = arguments[i + 1]
			i = i + 2

		-- Bulk Mode (using nativefs)
		elseif arguments[i] == "--bulk-nfs" then
			bulk_mode = "nfs"
			bulk_path = arguments[i + 1]
			i = i + 2

		-- Font:hasGlyphs() test
		elseif arguments[i] == "--has-glyphs" then
			check_hasglyphs = true
			i = i + 1
		
		elseif arguments[i] == "--show-zero-kern" then
			show_zero_kern_fonts = true
			i = i + 1
		end
	end

	if bulk_mode then
		initBulk(bulk_mode, bulk_path)
	end

	if mode == "interactive" then
		int_n_offsets = countKerningOffsets(int_font)
		print("-> Interactive Mode -- drag-and-drop a TTF file to check for non-zero kerning offsets.")
	else
		print("-> Bulk Mode -- Checking files...\n")
	end
end


function love.filedropped(file)
	mode = "interactive"

	if int_font then
		int_font:release()
		int_font = false
	end
	if int_font_display then
		int_font_display:release()
		int_font_display = false
	end

	file:open("r")
	--local data = file:read()

	print(file:getFilename())

	local b_data = file:read("data")

	local try_ok, try_font_or_err = pcall(love.graphics.newFont, b_data, font_size)
	if not try_ok then
		int_font = love.graphics.newFont(font_size)
		int_font_display = love.graphics.newFont(font_size_display)
		int_name = try_font_or_err
		int_n_offsets = 0

	else
		int_font = try_font_or_err
		int_font_display = love.graphics.newFont(b_data, font_size_display)
		int_name = string.match(file:getFilename(), ".*/(.*)$") or file:getFilename()
		int_n_offsets = countKerningOffsets(int_font)
	end

	file:close()

	collectgarbage("collect")
	collectgarbage("collect")
end


local first_update = true
function love.update(dt)
	if mode == "bulk" then
		accumulator = accumulator + dt

		if sub_state == "scanning" then
			co_time = love.timer.getTime() + tick_time
			local co_ok, co_res

			if first_update then
				co_ok, co_res = coroutine.resume(co_enumerate, bulk_path, {["ttf"] = true})
			else
				co_ok, co_res = coroutine.resume(co_enumerate)
			end

			if co_ok == false then
				error("coroutine failure: " .. tostring(co_res))
			end
			if co_res then
				font_paths = co_res

				if #font_paths == 0 then
					sub_state = "no_fonts_found"
				else
					sub_state = "working"
				end

				-- Debug: show all found files
				--[[
				for i, f_path in ipairs(font_paths) do
					print(i, f_path)
				end
				--]]
			end

		elseif sub_state == "working" then
		
			local count = 1
			local max_time = love.timer.getTime() + tick_time

			while font_i <= #font_paths do
				local font_path = font_paths[font_i]

				local ok, err_or_obj
				ok, err_or_obj = pcall(fs_newFileData, font_path)

				if not ok then
					table.insert(display_lines, "ERR" .. " | " .. font_path)

				else
					local font_file_data = err_or_obj
					ok, err_or_obj = pcall(love.graphics.newFont, font_file_data, font_size)
					if not ok then
						table.insert(display_lines, "ERR" .. " | " .. font_path)
						print("ERR", font_path)

					else
						local font = err_or_obj
						local non_zero_pairs = countKerningOffsets(font)

						if non_zero_pairs > 0 or show_zero_kern_fonts then
							print(non_zero_pairs, font_path)
							table.insert(display_lines, non_zero_pairs .. " | " .. font_path)
						end

						if non_zero_pairs ~= 0 then
							fonts_with_non_zero_kerning = fonts_with_non_zero_kerning + 1
						end

						if check_hasglyphs then
							print(font_path, "hasGlyphs:", reportHasGlyphs(font, glyphs_t))
						end

						font:release()
						collectgarbage("collect")
						collectgarbage("collect")
					end

					fonts_total = fonts_total + 1
					font_i = font_i + 1

					if love.timer.getTime() >= max_time then
						break
					end
				end
			end
			if font_i > #font_paths then
				sub_state = "done"

				print("\n\n~ Final Stats ~")
				print("Fonts with non-zero kerning: " .. fonts_with_non_zero_kerning)
				print("Total fonts: " .. fonts_total)
			end
		end
	end
end


function love.draw()
	if mode == "interactive" then
		love.graphics.setFont(int_font_display)

		local yy = 32
		local y_inc = 32
		love.graphics.print("Font: " .. int_name, 32, yy)
		yy = yy + y_inc
		love.graphics.print("Number of non-zero kerning pair offsets: " .. int_n_offsets, 32, yy)
		yy = yy + y_inc*2
		love.graphics.setFont(int_font)
		love.graphics.print("LT TA ST LA SZ", 32, yy)
		yy = yy + y_inc*3
		love.graphics.print("lt ta st la sz", 32, yy)
		yy = yy + y_inc*3

		if check_hasglyphs then
			love.graphics.setFont(int_font_regular)
			love.graphics.print("hasGlyphs: " .. reportHasGlyphs(int_font_display, glyphs_t), 32, yy)
		end

	else
		if sub_state == "scanning" then
			if co_path_status then
				love.graphics.print("Scanning: " .. co_path_status)
			end

		elseif sub_state == "no_fonts_found" then
			love.graphics.print("No fonts found at path: |" .. bulk_path .. "|")

		else
			love.graphics.translate(translate_x, translate_y)

			local line_bot = list_y + math.ceil(love.graphics.getHeight() / 24)

			for i = list_y, line_bot do
				local line = display_lines[i]
				if line then
					love.graphics.print(line)
					love.graphics.translate(0, 24)
				end
			end
			love.graphics.origin()

			love.graphics.setColor(0,0,0,0.75)
			love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), 64)
			love.graphics.setColor(1,1,1,1)

			love.graphics.translate(16, 16)
			love.graphics.print("Checking font " .. math.min(font_i, #font_paths) .. " of " .. #font_paths .. "...")

			if sub_state == "done" then
				love.graphics.print("~ Final Stats ~", 500, 0)
				love.graphics.print("Fonts with non-zero kerning: " .. fonts_with_non_zero_kerning, 500, 16)
				love.graphics.print("Total fonts: " .. fonts_total, 500, 32)
			end

			love.graphics.translate(0, 16)
			if font_i == #font_paths then
				love.graphics.print("Done! (Ctrl+C to copy list)")
			end
		end
	end
end


