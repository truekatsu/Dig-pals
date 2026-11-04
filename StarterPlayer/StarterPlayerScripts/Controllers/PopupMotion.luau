--!strict
-- Shared 0.5-second popup motion. The latest open/close request owns completion.
local TweenService = game:GetService("TweenService")
local PopupMotion = {}
type Motion = {
	Base: number,
	Progress: NumberValue,
	Tween: Tween?,
	Revision: number,
	Opening: boolean,
}
local motions: {[UIScale]: Motion} = setmetatable({}, {__mode = "k"}) :: any

local function getMotion(scale: UIScale): Motion
	local existing = motions[scale]
	if existing then return existing end
	local progress = Instance.new("NumberValue")
	progress.Name = "PopupProgress"
	progress.Value = 1
	progress.Parent = scale
	local motion: Motion = {Base = scale.Scale, Progress = progress, Revision = 0, Opening = false}
	motions[scale] = motion
	progress.Changed:Connect(function(value)
		scale.Scale = motion.Base * math.max(0, value)
	end)
	scale.Destroying:Connect(function()
		if motion.Tween then motion.Tween:Cancel() end
		motions[scale] = nil
	end)
	return motion
end

function PopupMotion.SetBaseScale(scale: UIScale, base: number)
	local motion = motions[scale]
	if motion then
		motion.Base = base
		scale.Scale = base * math.max(0, motion.Progress.Value)
	else
		scale.Scale = base
	end
end

function PopupMotion.Play(panel: GuiObject, backdrop: GuiObject?, opening: boolean, providedScale: UIScale?)
	local scale = providedScale or panel:FindFirstChild("PopupScale") :: UIScale?
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "PopupScale"
		scale.Parent = panel
	end
	local motion = getMotion(scale)
	if opening and motion.Opening and panel.Visible then return end
	motion.Revision += 1
	local revision = motion.Revision
	motion.Opening = opening
	if motion.Tween then motion.Tween:Cancel() end
	if opening then
		if not panel.Visible then motion.Progress.Value = 0 end
		panel.Visible = true
		if backdrop then backdrop.Visible = true end
	elseif not panel.Visible then
		if backdrop then backdrop.Visible = false end
		return
	end
	local tween = TweenService:Create(motion.Progress,
		TweenInfo.new(0.5, if opening then Enum.EasingStyle.Back else Enum.EasingStyle.Quint,
			if opening then Enum.EasingDirection.Out else Enum.EasingDirection.In),
		{Value = if opening then 1 else 0})
	motion.Tween = tween
	tween.Completed:Connect(function(state)
		if state ~= Enum.PlaybackState.Completed or motion.Revision ~= revision then return end
		motion.Tween = nil
		if not opening then
			panel.Visible = false
			if backdrop then backdrop.Visible = false end
		end
	end)
	tween:Play()
end

return PopupMotion
