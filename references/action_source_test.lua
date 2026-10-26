-- FugScheduler 2000 ActionSource test.
-- Connect this Text Controller's built-in `code` output directly to the
-- plugin's ordinary `ActionSource` Text input.
-- Optional local test controls:
--   TestCallback1  Momentary Button input
--   TestCallback2  Momentary Button input

-- Return the trusted callback definitions that FugScheduler discovers.
function GetFugSchedulerActions()
  return {
    {
      id = "Callback1",
      label = "Callback 1",
      description = "Prints a state-restoring test message from the first callback.",
      defaults = {
        oneShot = false,
        fireOnStartup = true,
        fireOnResume = true,
        repeatSeconds = 300
      },
      callback = function()
        print("FugScheduler Callback 1 executed")
      end
    },
    {
      id = "Callback2",
      label = "Callback 2",
      description = "Prints a one-shot test message from the second callback.",
      defaults = {
        oneShot = true
      },
      callback = function()
        print("FugScheduler Callback 2 executed")
      end
    }
  }
end

-- Find and execute an action locally so the Text Controller can test its definitions too.
function TestFugSchedulerAction(actionId)
  for _, action in ipairs(GetFugSchedulerActions()) do
    if action.id == actionId then
      local ok, callbackError = pcall(action.callback)
      if not ok then print("Callback error: " .. tostring(callbackError)) end
      return
    end
  end
  print("Unknown test action: " .. tostring(actionId))
end

if Controls and Controls.TestCallback1 then
  Controls.TestCallback1.EventHandler = function(control)
    if control.Boolean then TestFugSchedulerAction("Callback1") end
  end
end

if Controls and Controls.TestCallback2 then
  Controls.TestCallback2.EventHandler = function(control)
    if control.Boolean then TestFugSchedulerAction("Callback2") end
  end
end
