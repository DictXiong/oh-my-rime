local function ctrl_space_hook(key, env)
    local context = env.engine.context
    if key:repr() == "Control+space" and context:is_composing() then
        local raw_input = context.input
        env.engine:commit_text(raw_input)
        context:clear()
        
        --local is_ascii = context:get_option("ascii_mode")
        --context:set_option("ascii_mode", not is_ascii)

        return 1 
    end
    return 2 
end

return { func = ctrl_space_hook }
