--[[
    Lightweight client -> server callbacks
    ----------------------------------------------------------------------------
    Why not ox_lib callbacks? Because ox_lib is optional here. This is a tiny,
    self contained request/response layer with:
      * a per player token bucket (Config.Security.maxCallbacksPerSecond),
      * strict token validation (a client can only resolve its own requests),
      * a timeout so a dropped response never leaks a pending promise,
      * one handler table, so every endpoint is registered in exactly one place.

    Handler signature on the server:  function(source, payload) -> result
    Call signature on the client:     Nexora.Callback.Await('name', payload)
--]]

Nexora = Nexora or {}
Nexora.Callback = {}

local REQUEST_EVENT  = 'nexora:callback:request'
local RESPONSE_EVENT = 'nexora:callback:response'

if Nexora.IsServer then
    local handlers = {}
    local buckets  = {}   -- [src] = { count = n, resetAt = ms }

    --- Register a server callback endpoint.
    ---@param name string
    ---@param handler fun(source: number, payload: table): any
    function Nexora.Callback.Register(name, handler)
        if type(name) ~= 'string' or type(handler) ~= 'function' then
            Nexora.Error('Callback.Register expects (string, function)')
            return
        end
        if handlers[name] then
            Nexora.Warn(('callback "%s" was registered twice'):format(name))
        end
        handlers[name] = handler
    end

    function Nexora.Callback.Exists(name)
        return handlers[name] ~= nil
    end

    --- Token bucket: returns false when the player is sending too many requests.
    local function allow(src)
        local limit = (Config.Security and Config.Security.maxCallbacksPerSecond) or 20
        local now = GetGameTimer()
        local bucket = buckets[src]

        if not bucket or now >= bucket.resetAt then
            buckets[src] = { count = 1, resetAt = now + 1000 }
            return true
        end

        bucket.count = bucket.count + 1
        if bucket.count > limit then
            if bucket.count == limit + 1 then
                Nexora.Debug(('rate limited player %s (%d req/s)'):format(src, bucket.count))
            end
            return false
        end
        return true
    end

    RegisterNetEvent(REQUEST_EVENT, function(name, token, payload)
        local src = source

        -- shape checks before anything else
        if type(name) ~= 'string' or type(token) ~= 'number' then return end
        if payload ~= nil and type(payload) ~= 'table' then return end
        if token ~= token or token < 0 then return end

        if not allow(src) then
            TriggerClientEvent(RESPONSE_EVENT, src, token, { ok = false, error = 'rate_limited' })
            return
        end

        local handler = handlers[name]
        if not handler then
            Nexora.Debug(('player %s requested unknown callback "%s"'):format(src, name))
            TriggerClientEvent(RESPONSE_EVENT, src, token, { ok = false, error = 'unknown_endpoint' })
            return
        end

        -- Handlers may yield (database work), so always run in their own thread.
        CreateThread(function()
            local ok, result = pcall(handler, src, payload or {})
            if not ok then
                Nexora.Error(('callback "%s" failed: %s'):format(name, tostring(result)))
                TriggerClientEvent(RESPONSE_EVENT, src, token, { ok = false, error = 'server_error' })
                return
            end
            TriggerClientEvent(RESPONSE_EVENT, src, token, { ok = true, data = result })
        end)
    end)

    AddEventHandler('playerDropped', function()
        buckets[source] = nil
    end)
else
    local pending = {}
    local nextToken = 0

    RegisterNetEvent(RESPONSE_EVENT, function(token, response)
        if type(token) ~= 'number' then return end
        local request = pending[token]
        if not request then return end
        pending[token] = nil
        request.resolved = true
        request.promise:resolve(response)
    end)

    --- Await a server callback. Returns (data, error).
    ---@param name string
    ---@param payload table|nil
    ---@param timeout number|nil milliseconds (default 15000)
    function Nexora.Callback.Await(name, payload, timeout)
        if type(name) ~= 'string' then return nil, 'invalid_name' end

        nextToken = nextToken + 1
        local token = nextToken
        local request = { promise = promise.new(), resolved = false }
        pending[token] = request

        TriggerServerEvent(REQUEST_EVENT, name, token, payload or {})

        -- Timeout guard so a lost response cannot hang the caller forever.
        SetTimeout(timeout or 15000, function()
            if not request.resolved then
                pending[token] = nil
                request.resolved = true
                request.promise:resolve({ ok = false, error = 'timeout' })
            end
        end)

        local response = Citizen.Await(request.promise)
        if type(response) ~= 'table' then return nil, 'bad_response' end
        if not response.ok then return nil, response.error or 'unknown_error' end
        return response.data
    end

    --- Fire and forget variant for things we never read a result from.
    function Nexora.Callback.Send(name, payload)
        if type(name) ~= 'string' then return end
        nextToken = nextToken + 1
        TriggerServerEvent(REQUEST_EVENT, name, nextToken, payload or {})
    end
end
