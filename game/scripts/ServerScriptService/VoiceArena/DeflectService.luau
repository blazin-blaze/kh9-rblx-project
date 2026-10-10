local Players=game:GetService("Players")
local Config=require(script.Parent.SpellConfig)
local Service={}
local active={}
function Service.IsActive(character)
 local state=active[character]
 local h=character and character:FindFirstChildOfClass("Humanoid")
 return state~=nil and workspace:GetServerTimeNow()<state.endsAt and character.Parent~=nil and h~=nil and h.Health>0
end
function Service.Damage(h,amount)
 if h and h.Parent and h.Health>0 then
  h:TakeDamage(amount*(Service.IsActive(h.Parent) and .5 or 1))
 end
end
function Service.Start(character,remote)
 local cfg=Config.Deflect
 local endsAt=workspace:GetServerTimeNow()+cfg.Duration
 local state={endsAt=endsAt}
 active[character]=state
 character:SetAttribute("DeflectEndsAt",endsAt)
 remote:FireAllClients({op="deflect_cast",target=character,endsAt=endsAt,radius=cfg.Radius})
 task.delay(cfg.Duration,function()
  if active[character]==state then
   active[character]=nil
   if character.Parent then character:SetAttribute("DeflectEndsAt",nil) end
  end
 end)
end
-- Swept sphere against every active bubble, even before the projectile reaches the body.
function Service.Intercept(from,step,projectileRadius,owner,maximumDistance)
 local length=step.Magnitude
 if length<1e-5 then return end
 local direction=step/length
 local best=math.min(length,maximumDistance or length)
 local defender,point
 for character in pairs(active) do
  if character~=owner and Service.IsActive(character) then
   local root=character:FindFirstChild("HumanoidRootPart")
   local ownerPlayer=Players:GetPlayerFromCharacter(owner)
   local defenderPlayer=Players:GetPlayerFromCharacter(character)
   local friendly=ownerPlayer and defenderPlayer and not ownerPlayer.Neutral and not defenderPlayer.Neutral and ownerPlayer.Team==defenderPlayer.Team
   if root and not friendly then
    local offset=from-root.Position
    local radius=Config.Deflect.Radius+projectileRadius
    local b=offset:Dot(direction)
    local discriminant=b*b-offset:Dot(offset)+radius*radius
    if discriminant>=0 then
     local distance=math.max(0,-b-math.sqrt(discriminant))
     if distance<=best and (offset.Magnitude<=radius or b<0) then
      best=distance; defender=character; point=from+direction*distance
     end
    end
   end
  end
 end
 if defender then return defender,point,best end
end
return Service
