-- Run from the repository root: lua tests/lua_regression.lua
local count = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    count = count + 1
end
local yielded = {}
Candidate = function(kind, first, last, text, comment)
    return {type = kind, start = first, _end = last, text = text, comment = comment}
end
yield = function(candidate) yielded[#yielded + 1] = candidate end

-- The exported translator, including malformed/incomplete input.
local number = dofile('lua/number_translator.lua')
local number_env = {engine = {schema = {config = {
    get_string = function() return '^R[0-9]+[.]?[0-9]*' end
}}}}
local function numbers(code)
    yielded = {}
    number(code, {start = 0, _end = #code}, number_env)
    return yielded
end
for _, case in ipairs({
    {'R0', '〇', '零', '〇元整', '零元整'},
    {'R0000', '〇', '零', '〇元整', '零元整'},
    {'R1.001', '一点〇〇一', '壹点零零壹', '一元〇一厘', '壹元零壹厘'},
    {'R0.001', '〇点〇〇一', '零点零零壹', '〇元〇一厘', '零元零壹厘'},
    {'R1.000', '一点〇〇〇', '壹点零零零', '一元整', '壹元整'},
    {'R10000', '一万', '壹萬', '一万元整', '壹万元整'},
    {'R1000000000000', '数值超限！', '数值超限！', '数值超限！整', '数值超限！整'},
}) do
    local results = numbers(case[1])
    equal(#results, 4, case[1] .. ' candidate count')
    for i = 1, 4 do equal(results[i].text, case[i + 1], case[1] .. ' candidate ' .. i) end
end
for _, code in ipairs({'R', 'R.', 'R1..2', 'R1x', 'Rbad', 'hello'}) do
    equal(#numbers(code), 0, 'ignore ' .. code)
end

-- Budget violations cannot leak a hook to the main Lua thread or stop later input.
local calc = dofile('lua/mint_calculator_translator.lua')
Set = function() return 0 end
local segment = {start = 0, _end = 100, tags = 0, has_tag = function() return false end}
local calc_env = {name_space = 'mint_calculator_translator', engine = {
    context = {composition = {empty = function() return false end, back = function() return segment end}},
    schema = {config = {get_string = function(_, key)
        if key == 'recognizer/patterns/expression' then return '^=.*$' end
    end}}
}}
calc.init(calc_env)
local function calculate(code)
    yielded = {}
    calc.func(code, segment, calc_env)
    return yielded
end
local hook = function() end
debug.sethook(hook, '', 10000000)
equal(calculate('=fact(1e10)')[1].comment, '执行错误', 'factorial bound')
equal(calculate('=(function() while true do end end)()')[1].comment, '计算量超限', 'infinite loop budget')
equal(calculate('=zys(1000000000000037)')[1].comment, '计算量超限', 'prime factor budget')
equal(calculate('=1/0+fact(-1)')[1].comment, '执行错误', 'invalid factorial')
equal(calculate('=psjs(1,1001,1)')[1].text, '数量超限，最多生成1000个随机数', 'random allocation bound')
equal(calculate('=fact(5)')[1].text, '120', 'normal factorial after failure')
assert(tonumber(calculate('=fact(21)')[1].text) > 1e19, 'factorial integer overflow')
count = count + 1
local factorial_limit = tonumber(calculate('=fact(170)')[1].text)
assert(factorial_limit > 1e300 and factorial_limit < math.huge, 'finite factorial limit')
count = count + 1
equal(calculate('=fact(171)')[1].comment, '执行错误', 'factorial overflow rejected')
equal(calculate('=1+2*3')[1].text, '7', 'normal expression after failure')
equal(debug.gethook(), hook, 'preserve main hook')
debug.sethook()

-- Several scheme instances remain isolated even when the Lua module is shared.
rime_api = {get_user_data_dir = function() return '.' end}
local aux = dofile('lua/auxCode_filter.lua')
local function aux_env(name)
    local env_callback
    local env = {name_space = name, engine = {
        schema = {config = {get_string = function(_, key)
            if key == 'aux_code/show_aux_notice' then return 'always' end
        end}},
        context = {select_notifier = {connect = function(_, callback)
            env_callback = callback
            return {disconnect = function() end}
        end}}
    }}
    aux.init(env)
    env.callback = env_callback
    return env
end
local zrm, fly = aux_env('ZRM_Aux-code_4.3'), aux_env('flypy_full')
assert(zrm.aux_code ~= fly.aux_code, 'different schemes share a cache')
count = count + 1
equal(aux.readAuxTxt('ZRM_Aux-code_4.3'), zrm.aux_code, 'reuse same file')
equal(aux.readAuxTxt('missing-scheme'), zrm.aux_code, 'fallback file')
local differing
for char, code in pairs(zrm.aux_code) do
    if fly.aux_code[char] and fly.aux_code[char] ~= code then differing = char; break end
end
assert(differing, 'fixture must contain differing codes')
local before = aux.fullAux(zrm, differing)
local again = aux.fullAux(zrm, differing)
equal(aux.match(before, zrm.aux_code[differing]:match('%S+')), true, 'zrm retained after flypy init')
equal(aux.match(again, zrm.aux_code[differing]:match('%S+')), true, 'zrm repeat')
local ctx = {input = 'nihao', commit = function() error('unexpected commit') end}
zrm.callback(ctx)
equal(ctx.input, 'nihao', 'always mode must not change ordinary selection')
aux.fini(zrm)
equal(zrm.aux_code, nil, 'release env')
aux.fini(fly)

-- Exercise the processor itself: dates must append digits instead of selecting.
local kp = dofile('lua/kp_number_processor.lua')
local context = {input = 'N', pushed = 0, selected = 0,
    is_composing = function() return true end,
    has_menu = function() return true end,
    push_input = function(self, s) self.input = self.input .. s; self.pushed = self.pushed + 1 end,
    select = function(self) self.selected = self.selected + 1; return true end,
    composition = {empty = function() return false end, back = function() return {
        selected_index = 0,
        menu = {empty = function() return false end, candidate_count = function() return 10 end}
    } end},
    update_notifier = {connect = function() return {disconnect = function() end} end},
}
local rules = {
    date = '^N[0-9]{1,8}', rmb = '^R[0-9]+[.]?[0-9]*', expression = '^=.*$',
    punct = '^/([0-9]0?|[a-zA-Z]+)$', fixed = '^D[0-9]{4}$',
    groups = '^((X))[0-9]{1,2}$', escaped = '^Q\\d{2}$',
}
local config = {
    get_int = function() return 10 end, get_string = function() return 'auto' end,
    get_map = function() return {
        keys = function() local keys = {}; for key in pairs(rules) do keys[#keys + 1] = key end; return keys end,
        get_value = function(_, key) return {value = rules[key]} end,
    } end,
}
local kp_env = {engine = {context = context, schema = {config = config}}}
kp.init(kp_env)
local function key(digit, keypad)
    return {keycode = keypad and 0xFFB0 + tonumber(digit) or 48 + tonumber(digit),
        repr = function() return digit end, release = function() return false end,
        ctrl = function() return false end, alt = function() return false end,
        super = function() return false end, shift = function() return false end}
end
for digit in ('20260922'):gmatch('.') do equal(kp.func(key(digit), kp_env), 1, 'append date digit') end
equal(context.input, 'N20260922', 'complete date')
equal(context.selected, 0, 'date must not select')
context.input = 'N2'
equal(kp.func(key('3', true), kp_env), 1, 'keypad date')
equal(context.input, 'N23', 'keypad append')
context.input = 'ni'
equal(kp.func(key('2'), kp_env), 1, 'ordinary selection')
equal(context.selected, 1, 'ordinary selection preserved')
local function matches(code)
    for _, pattern in ipairs(kp_env.function_patterns) do if code:match(pattern) then return true end end
    return false
end
for _, code in ipairs({'N2', 'N20260922', 'R1.2', '=1+2', '/10', '/abc', 'D2026', 'X12', 'Q12'}) do
    equal(matches(code), true, 'match ' .. code)
end
for _, code in ipairs({'N', 'N123456789', 'N1x', 'D12', 'Q1', 'ni2'}) do
    equal(matches(code), false, 'reject ' .. code)
end
kp.fini(kp_env)
print('Lua regressions passed (' .. count .. ' assertions)')
