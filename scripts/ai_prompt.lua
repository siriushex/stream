-- AstralAI prompt/context builder scaffold

ai_prompt = ai_prompt or {}

function ai_prompt.build_context(opts)
    return {
        version = "v1",
        ts = os.time(),
        notes = "context builder not implemented",
    }
end

