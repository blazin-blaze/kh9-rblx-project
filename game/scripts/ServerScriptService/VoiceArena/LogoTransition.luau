-- ServerScriptService.VoiceArena.LogoTransition (ModuleScript)
-- The "Incantation" logo transition: the screen fades to dark, the logo writes itself on, then the
-- screen fades out onto whatever is next. Used only for lobby -> match intro and victory podium -> lobby.
-- The server publishes the timing as attributes on ReplicatedStorage.VoiceArena so every player sees it
-- at the same moment; StarterPlayerScripts.LogoTransitionClient draws it.
--   LogoTransitionId     changes once per transition
--   LogoTransitionStart  server time the fade-in starts
--   LogoTransitionReveal server time the fade-out starts (can be pushed later while the screen is dark)
local Transition = {
	FadeIn = 0.35,  -- to fully dark
	Draw = 2.0,     -- the logo writing itself on (sped up from the original ~4.3s)
	Hold = 0.3,     -- finished logo on screen
	FadeOut = 0.45, -- reveal
}
local serial = 0

local function now() return workspace:GetServerTimeNow() end

function Transition.WaitUntil(t)
	while now() < t do task.wait(0.03) end
end

-- Starts a transition for everyone. Returns { blackAt, revealAt, endsAt } in server time.
function Transition.Begin(folder)
	serial += 1
	local start = now() + 0.05
	local reveal = start + Transition.FadeIn + Transition.Draw + Transition.Hold
	folder:SetAttribute("LogoFadeIn", Transition.FadeIn)
	folder:SetAttribute("LogoDraw", Transition.Draw)
	folder:SetAttribute("LogoFadeOut", Transition.FadeOut)
	folder:SetAttribute("LogoTransitionStart", start)
	folder:SetAttribute("LogoTransitionReveal", reveal)
	folder:SetAttribute("LogoTransitionId", serial)
	return { blackAt = start + Transition.FadeIn, revealAt = reveal, endsAt = reveal + Transition.FadeOut }
end

-- Keeps the logo up longer (e.g. if respawning fighters ran long). Never moves the reveal earlier.
function Transition.HoldUntil(folder, info, t)
	if t > info.revealAt then
		info.revealAt = t
		info.endsAt = t + Transition.FadeOut
		folder:SetAttribute("LogoTransitionReveal", t)
	end
end

return Transition
