local M = {}

local function scale_bound()
	return math.max(1, math.max(rt.preview.max_width, rt.preview.max_height))
end

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err = self:preload(job)
	if not ok or err then
		return ya.preview_widget(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))
	local _, show_err = ya.image_show(cache, job.area)
	ya.preview_widget(job, show_err)
end

function M:preload(job)
	local cache = ya.file_cache(job)
	if not cache or fs.cha(cache) then
		return true
	end

	local converter = os.getenv("HOME") .. "/.config/yazi/plugins/png-to-jpeg.yazi/convert.py"
	local output, err = Command("python3")
		:arg({
			converter,
			tostring(job.file.path),
			tostring(cache) .. ".jpg",
			tostring(scale_bound()),
			tostring(rt.preview.image_quality),
		})
		:output()

	if not output then
		return true, Err("Failed to start PNG preview conversion: %s", err)
	elseif not output.status.success then
		return true, Err("Failed to convert PNG preview: %s", output.stderr)
	end

	return ya.image_precache(Url(tostring(cache) .. ".jpg"), cache)
end

return M
