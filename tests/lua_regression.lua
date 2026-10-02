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
local aux = dofile('lua/aux_code_filter.lua')
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
local function stream(candidates)
    return {iter = function()
        local index = 0
        return function() index = index + 1; return candidates[index] end
    end}
end
local function filter_aux(env, text, code)
    yielded = {}
    env.engine.context.input = 'ni' .. env.trigger_key .. code
    local cand = {text = text, type = 'phrase', comment = '', get_dynamic_type = function() return 'Phrase' end}
    aux.func(stream({cand}), env)
    return yielded
end
local zrm_code = zrm.aux_code[differing]:match('%S+')
equal(#filter_aux(zrm, differing, zrm_code), 1, 'zrm retained after flypy init')
equal(#filter_aux(zrm, differing, zrm_code), 1, 'zrm repeat')
-- The upstream optimization must not combine keys from different characters/codes.
zrm.aux_code = {['甲'] = 'ab cd', ['乙'] = 'ef'}
zrm.aux_index = {}
equal(#filter_aux(zrm, '甲乙', 'ab'), 1, 'complete auxiliary code')
equal(#filter_aux(zrm, '甲乙', 'a'), 1, 'single auxiliary key')
equal(#filter_aux(zrm, '甲乙', 'ad'), 0, 'do not combine separate codes')
equal(#filter_aux(zrm, '甲乙', 'af'), 0, 'do not combine separate characters')
rime_api.get_user_data_dir = function() return '/nonexistent-rime-test-directory' end
equal(next(aux.readAuxTxt('ZRM_Aux-code_4.3')), nil, 'cache must use full data directory')
rime_api.get_user_data_dir = function() return '.' end
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
for digit = 2, 6 do
    context.input = 'N'
    equal(kp.func(key(tostring(digit)), kp_env), 1, 'N followed by ' .. digit)
    equal(context.input, 'N' .. digit, 'append digit ' .. digit)
end
equal(context.selected, 0, 'N digits 2~6 must not select')
context.input = 'N2'
equal(kp.func(key('3', true), kp_env), 1, 'keypad date')
equal(context.input, 'N23', 'keypad append')
context.input = 'ni'
equal(kp.func(key('2'), kp_env), 1, 'ordinary selection')
equal(context.selected, 1, 'ordinary selection preserved')
context.input = ''
kp_env.is_composing = false
equal(kp.func(key('2', true), kp_env), 0, 'idle keypad passes to application')
equal(context.input, '', 'idle keypad does not start composition')
kp_env.kp_mode = 'compose'
equal(kp.func(key('2', true), kp_env), 1, 'compose mode accepts idle keypad')
equal(context.input, '2', 'compose mode keypad input')
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

-- Upstream English repositioning must keep order and isolate schema settings.
local english = dofile('lua/reduce_english_filter.lua')
local function english_env(mode, idx)
    local env = {name_space = 'reduce_english_filter', engine = {
        context = {input = 'aid'}, schema = {config = {
            get_int = function() return idx end, get_list = function() return nil end,
            get_string = function() return mode end,
        }}
    }}
    english.init(env)
    return env
end
local reposition, unchanged = english_env('all', 2), english_env('none', 1)
local function english_order(env, texts)
    local candidates = {}
    for _, text in ipairs(texts) do candidates[#candidates + 1] = {text = text, preedit = ''} end
    yielded = {}
    english.func(stream(candidates), env)
    local results = {}
    for _, cand in ipairs(yielded) do results[#results + 1] = cand.text end
    return table.concat(results, ',')
end
equal(english_order(reposition, {'甲', '乙', 'aid', '丙'}), '甲,aid,乙,丙', 'promote English')
equal(english_order(reposition, {'aid', '甲', '乙'}), '甲,aid,乙', 'demote English')
equal(english_order(unchanged, {'甲', '乙', 'aid'}), '甲,乙,aid', 'none schema stays unchanged')
equal(english_order(reposition, {'甲', '乙'}), '甲,乙', 'missing English preserves order')

-- Unicode lookup is an independent translator; astral characters use surrogate pairs.
local unicode = dofile('lua/unicode_translator.lua')
local lookup_code, disconnected
Memory = function()
    return {
        dict_lookup = function(_, code) lookup_code = code; return true end,
        iter_dict = function() return stream({
            {text = '😀', weight = 5}, {text = '一', weight = 1}, {text = '😀', weight = 10},
        }):iter() end,
        disconnect = function() disconnected = true end,
    }
end
local unicode_env = {engine = {schema = {}}}
unicode.init(unicode_env)
yielded = {}
unicode.func('Ucni', {start = 0, _end = 4}, unicode_env)
equal(lookup_code, 'ni', 'Unicode strips prefix')
equal(#yielded, 10, 'Unicode lookup deduplicates dictionary entries')
equal(yielded[1].text, 'U+1F600', 'Unicode orders by highest weight')
equal(yielded[3].text, '\\uD83D\\uDE00', 'Unicode surrogate pair')
yielded = {}
unicode.func('ni', {has_tag = function() return false end}, unicode_env)
equal(#yielded, 0, 'ordinary input bypasses Unicode translator')
unicode.fini(unicode_env)
equal(disconnected, true, 'Unicode memory disconnected')

-- Pinyin visibility also applies to predictions with untyped syllables.
local corrector = dofile('lua/corrector_filter.lua')
local correction_segment = {tags = 0}
local corrector_env = {name_space = 'corrector_filter', engine = {
    schema = {config = {get_string = function() return " '" end}},
    context = {input = 'yebuib', tone_display = false,
        get_option = function(self) return self.tone_display end,
        composition = {back = function() return correction_segment end},
    },
}}
corrector.init(corrector_env)
local function filter_comment(kind, text, comment, preedit)
    local cand = {type = kind, text = text, comment = comment, preedit = preedit,
        get_genuine = function(self) return self end}
    yielded = {}
    corrector.func(stream({cand}), corrector_env)
    equal(yielded[1], cand, 'preserve candidate ' .. kind)
    return cand.comment
end
local predictions = {
    {'也不是', 'yě bú shì'},
    {'也不是不行', 'yě bú shì bù xíng'},
    {'也不是不能加', 'yě bú shì bù néng jiā'},
}
for _, prediction in ipairs(predictions) do
    for _, enabled in ipairs({false, true, false}) do
        corrector_env.engine.context.tone_display = enabled
        equal(filter_comment('completion', prediction[1], prediction[2], 'ye bu ui b'),
            enabled and prediction[2] or '', 'prediction tone visibility ' .. prediction[1])
    end
end
for _, kind in ipairs({'phrase', 'sentence', 'user_phrase'}) do
    equal(filter_comment(kind, '也不是', 'yě bú shì'), '', 'ordinary pinyin hidden ' .. kind)
end
for _, kind in ipairs({'reverse_lookup', 'unicode', 'number', 'shijian', 'english'}) do
    equal(filter_comment(kind, '提示', '独立注释'), '独立注释', 'keep translator comment ' .. kind)
end
equal(filter_comment('completion', '主角', 'zhǔ jiǎo'), '[zhǔ jué]', 'correction survives tone off')
equal(filter_comment('completion', '也不是', ''), '', 'empty prediction comment')

print('Lua regressions passed (' .. count .. ' assertions)')
