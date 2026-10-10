-- Every connected player must be alive, equipped and standing in the white square.
local ReadyZone = {}
function ReadyZone.Contains(area, position)
 local p=area.CFrame:PointToObjectSpace(position)
 return math.abs(p.X)<=area.Size.X/2 and math.abs(p.Z)<=area.Size.Z/2
  and p.Y>=-2 and p.Y<=12
end
function ReadyZone.Status(players, isEquipped)
 local maps=workspace:FindFirstChild("Maps")
 local zone=maps and maps:FindFirstChild("MatchReadyZone")
 local area=zone and zone:FindFirstChild("Area")
 local inside,equipped=0,0
 for _,player in ipairs(players) do
  if isEquipped(player) then equipped+=1 end
  local char=player.Character
  local root=char and char:FindFirstChild("HumanoidRootPart")
  local humanoid=char and char:FindFirstChildOfClass("Humanoid")
  if area and root and humanoid and humanoid.Health>0 and ReadyZone.Contains(area,root.Position) then inside+=1 end
 end
 local total=#players
 return total>0 and inside==total and equipped==total,inside,total,equipped
end
return ReadyZone