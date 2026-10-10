-- Shared movement locks: Freeze and Ultimate can overlap without leaving a character anchored.
local Locks = {}
local states = setmetatable({}, { __mode = "k" })
function Locks.Acquire(character, reason)
 local h = character:FindFirstChildOfClass("Humanoid")
 local root = character:FindFirstChild("HumanoidRootPart")
 if not h or not root then return false end
 local state = states[character]
 if not state then
  state = { h=h, root=root, reasons={}, anchored=root.Anchored, walk=h.WalkSpeed,
   jumpPower=h.JumpPower, jumpHeight=h.JumpHeight, rotate=h.AutoRotate }
  states[character] = state
 end
 state.reasons[reason] = true
 root.AssemblyLinearVelocity = Vector3.zero
 root.AssemblyAngularVelocity = Vector3.zero
 root.Anchored = true
 h.WalkSpeed=0; h.JumpPower=0; h.JumpHeight=0; h.AutoRotate=false
 return true
end
function Locks.Release(character, reason)
 local state=states[character]
 if not state then return end
 state.reasons[reason]=nil
 if next(state.reasons) then return end
 states[character]=nil
 if state.root.Parent then state.root.Anchored=state.anchored end
 if state.h.Parent then
  state.h.WalkSpeed=state.walk; state.h.JumpPower=state.jumpPower
  state.h.JumpHeight=state.jumpHeight; state.h.AutoRotate=state.rotate
 end
end
return Locks
