local function extractBlockToken(raw, start)
    local token = {
        modifiers = {
            flags = {},
            fields = {}
        },
        modifierStart = start,
        modifierEnd = nil,
        contentStart = nil,
        contentEnd = nil
    }

    local currentModifier = ""
    local currentModifierValue = nil

    local function insertModifierEntry()
        if currentModifierValue ~= nil then
            -- Field
            token.modifiers.fields[currentModifier] = currentModifierValue
        else
            -- Flag
            local exists = false
            for i, flag in pairs(token.modifiers.flags) do
                if flag == currentModifier then
                    exists = true
                    break
                end
            end
            if exists == false then
                table.insert(token.modifiers.flags, currentModifier)
            end
        end
        -- Reset modifier values for possible next entry
        currentModifier = ""
        currentModifierValue = nil
    end

    local i = start + 1
    local literal = false

    while i <= #raw do
        local char = raw:sub(i, i)

        if token.modifierEnd == nil then -- MODIFIER GROUP + "]"
                
            if char == "]" then -- Found the end of the modifier group

                token.modifierEnd = i

                if currentModifier ~= "" then
                    insertModifierEntry() -- Add last entry if available
                end

            else -- Parse modifier group contents
                        
                if char:match("[a-zA-Z0-9_-]") then
                    if currentModifierValue ~= nil then
                        currentModifierValue = currentModifierValue..char
                    else
                        currentModifier = currentModifier..char
                    end
                elseif char == "=" then
                    if currentModifier ~= "" then
                        currentModifierValue = ""
                    else
                        return nil -- Token could not be created (incorrect modifier equals syntax)
                    end
                elseif char == "," or char == ";" then
                    if currentModifier ~= "" then
                        insertModifierEntry()
                    else
                        return nil -- Token could not be created (incorrect modifier comma syntax)
                    end
                elseif char ~= " " and char ~= "\n" then -- Ignore whitespace, new lines, and tabs
                    return nil -- Token could not be created (incompatible modifier character)
                end

            end

        elseif literal == false then
            
            if char == "\\" then
                
                literal = true

            elseif token.contentStart == nil then -- "{"

                if char == "{" then -- Found the start of the content group

                    token.contentStart = i

                elseif char ~= " " and char ~= "\n" then
                    return nil -- Token could not be created (no characters can exist between the "]" and "{")
                end
                
            elseif token.contentEnd == nil then -- CONTENT GROUP + "}"
                    
                if char == "}" then -- Found the end of the content group

                    token.contentEnd = i

                    return token, i -- Full block is completed

                elseif char == "[" and #raw >= 4 and i <= #raw - 3 then -- Potential child token

                    local childToken, tokenEnd = extractBlockToken(raw, i) -- Extract token (and its children)
                
                    if childToken ~= nil then -- The token was created successfully if it isn't nil
                            
                        if token.children == nil then
                            token.children = {}
                        end

                        table.insert(token.children, childToken)
                            
                        ---@cast tokenEnd integer
                        i = tokenEnd -- Skip to after the token (don't add one because it is added at the end of the loop)

                    end
                        
                end
                
            end

        else

            literal = false

        end

        i = i + 1
    end

    return nil -- Token could not be created
end

local function trimBlocks(blocks, index, trim) -- Removes characters from blocks during the symbol and command parsing step
    for i, block in pairs(blocks) do
        if block.startPos >= index then
            block.startPos = block.startPos - trim
        end
        if block.endPos >= index then
            block.endPos = block.endPos - trim
        end
        if block.children ~= nil then
            trimBlocks(block.children, index, trim)
        end
    end
end

local function isIndexBlocked(index, blocks)
    for i, block in pairs(blocks) do
        if block.startPos == index then
            return true
        end
        if block.endPos == index then
            return true
        end
        if block.children ~= nil then
            return isIndexBlocked(index, block.children)
        end
    end
    return false
end

local function parse(raw, returnRawTokens)
    raw = raw:gsub("\r\n", "\n")
    raw = raw:gsub("\r", "\n")

    -- Tokenize blocks

    local blockTokens = {}
    
    local i = 1
    local literal = false

    while i <= #raw do
        local char = raw:sub(i, i)

        if literal == false then -- Check if this character is not literal

            if char == "\\" then

                literal = true

            elseif char == "[" and #raw >= 4 and i <= #raw - 3 then -- Potential token

                local token, tokenEnd = extractBlockToken(raw, i) -- Extract token (and its children)
                
                if token ~= nil then -- The token was created successfully if it isn't nil
                
                    table.insert(blockTokens, token)
                    
                    ---@cast tokenEnd integer
                    i = tokenEnd -- Skip to after the token (don't add one because it is added at the end of the loop)

                end

            end

        else

            literal = false

        end

        i = i + 1
    end

    local blocks = {}
    local cleaned = ""

    if returnRawTokens ~= true then
        -- Remove block notation and package blocks

        local cleanedOffset = 0 -- Amount of characters trimmed

        local function extractBlock(token)
            if token.contentEnd - token.contentStart - 1 >= 1 then -- Is there any text inside? If there isn't, there's no reason for this block to exist.
                
                -- Create block and copy modifiers
            
                local block = {
                    modifiers = {
                        flags = {},
                        fields = {}
                    }
                }
                for i, flag in pairs(token.modifiers.flags) do
                    table.insert(block.modifiers.flags, flag)
                end
                for field, value in pairs(token.modifiers.fields) do
                    block.modifiers.fields[field] = value
                end
                
                -- "[...]" + "{"

                cleanedOffset = cleanedOffset + (token.contentStart - token.modifierStart + 1)

                block.startPos = token.contentStart + 1 - cleanedOffset

                -- Children + "}"

                if token.children == nil then -- Simple, add all text between
                    
                    cleaned = cleaned..raw:sub(token.contentStart + 1, token.contentEnd - 1)

                    block.endPos = token.contentEnd - 1 - cleanedOffset

                    cleanedOffset = cleanedOffset + 1 -- Offset for "}"

                else

                    block.children = {}

                    for i, childToken in pairs(token.children) do
                        if i == 1 then
                            cleaned = cleaned..raw:sub(token.contentStart + 1, childToken.modifierStart - 1) -- Add text before any children
                        end

                        table.insert(block.children, extractBlock(childToken))

                        if i == #token.children then
                            cleaned = cleaned..raw:sub(childToken.contentEnd + 1, token.contentEnd - 1) -- Add text after any children
                        else
                            cleaned = cleaned..raw:sub(childToken.contentEnd + 1, token.children[i + 1].modifierStart - 1) -- Add text between children
                        end
                    end

                    block.endPos = token.contentEnd - 1 - cleanedOffset

                    cleanedOffset = cleanedOffset + 1 -- Offset for "}"

                end

                return block
            
            end
        end

        for i, token in pairs(blockTokens) do

            if i == 1 then
                cleaned = raw:sub(1, token.modifierStart - 1) -- Add text before any blocks
            end

            table.insert(blocks, extractBlock(token))

            if i == #blockTokens then
                cleaned = cleaned..raw:sub(token.contentEnd + 1, #raw) -- Add text after any blocks
            else
                cleaned = cleaned..raw:sub(token.contentEnd + 1, blockTokens[i + 1].modifierStart - 1) -- Add text between blocks
            end

        end

    end

    -- Package symbols and commands and remove symbol and command notation

    if returnRawTokens == true then
        cleaned = raw
    end

    local output = ""
    local outputIndex = 0
    local literal = false
    local trims = {}

    local symbols = {}
    local symbolTokens = {}
    local commands = {}
    local commandTokens = {}

    local currentSymbol = nil
    local rawSymbolPosition = 0
    local finalSymbolPosition = 0
    local currentCommand = nil
    local rawCommandPosition = 0
    local finalCommandPosition = 0

    for i = 1, #cleaned do
        local char = cleaned:sub(i, i)

        if currentSymbol ~= nil then

            if isIndexBlocked(i, blocks) and char ~= ":" then -- No symbol can be inside multiple blocks
                
                currentSymbol = nil
                output = output..cleaned:sub(rawSymbolPosition, i)
                outputIndex = outputIndex + #cleaned:sub(rawSymbolPosition, i)
            
            else

                if char == ":" then

                    if currentSymbol ~= "" then
                        
                        if returnRawTokens == true then
                            table.insert(symbolTokens, {startPos = rawSymbolPosition, endPos = i, name = currentSymbol})
                        else
                            trims[i] = #currentSymbol + 2 -- ":" and ":"
                            table.insert(symbols, {pos = finalSymbolPosition, name = currentSymbol})
                            currentSymbol = nil
                        end

                    else

                        output = output..cleaned:sub(rawSymbolPosition, i - 1)
                        outputIndex = outputIndex + #cleaned:sub(rawSymbolPosition, i - 1)
                        
                        currentSymbol = ""
                        rawSymbolPosition = i
                        finalSymbolPosition = outputIndex

                    end

                elseif char:match("[a-zA-Z0-9_-]") then

                    currentSymbol = currentSymbol..char

                else

                    currentSymbol = nil
                    output = output..cleaned:sub(rawSymbolPosition, i)
                    outputIndex = outputIndex + #cleaned:sub(rawSymbolPosition, i)

                    if char == "\\" then
                        literal = true
                    end
                end

            end

        elseif currentCommand ~= nil then

            if isIndexBlocked(i, blocks) and char ~= "<" and char ~= ">" then -- No command can be inside multiple blocks
                
                currentCommand = nil
                output = output..cleaned:sub(rawCommandPosition, i)
                outputIndex = outputIndex + #cleaned:sub(rawCommandPosition, i)
            
            else

                if char == ">" then

                    if currentCommand ~= "" then

                        if returnRawTokens == true then
                            table.insert(commandTokens, {startPos = rawCommandPosition, endPos = i, name = currentCommand})
                        else
                            trims[i] = #currentCommand + 2 -- "<" and ">"
                            table.insert(commands, {pos = finalCommandPosition, name = currentCommand})
                            currentCommand = nil
                        end

                    else

                        currentCommand = nil
                        output = output..cleaned:sub(rawCommandPosition, i)
                        outputIndex = outputIndex + #cleaned:sub(rawCommandPosition, i)

                    end
                    
                elseif char:match("[a-zA-Z0-9_-]") then

                    currentCommand = currentCommand..char

                else

                    currentCommand = nil
                    output = output..cleaned:sub(rawCommandPosition, i)
                    outputIndex = outputIndex + #cleaned:sub(rawCommandPosition, i)

                    if char == "\\" then
                        literal = true
                    end
                end

            end

        elseif literal == false then

            if char == "\\" then -- Literal
                
                literal = true

            else
            
                if char == ":" then

                    currentSymbol = ""
                    rawSymbolPosition = i
                    finalSymbolPosition = outputIndex
                
                elseif char == "<" then

                    currentCommand = ""
                    rawCommandPosition = i
                    finalCommandPosition = outputIndex

                elseif char == "\n" then

                    if returnRawTokens ~= true then
                        trims[i] = 1 -- "\n" counts as one character to be trimmed
                        table.insert(commands, {pos = outputIndex, name = "br"})
                    end

                else

                    output = output..char
                    outputIndex = outputIndex + 1

                end

            end

        else

            if returnRawTokens ~= true then
                trims[i] = 1
                output = output..char
                outputIndex = outputIndex + 1
            end
            literal = false

        end
    end

    -- Didn't finish symbol/command
    if currentSymbol ~= nil then
        output = output..cleaned:sub(rawSymbolPosition, #cleaned)
    end
    if currentCommand ~= nil then
        output = output..cleaned:sub(rawCommandPosition, #cleaned)
    end

    if returnRawTokens ~= true then
        local trimTotal = 0
        for i, trim in pairs(trims) do
            trimBlocks(blocks, i - trimTotal, trim)
            trimTotal = trimTotal + trim -- Index must be offset for the amount trimmed
        end
    end

    if returnRawTokens == true then
        return raw, {
            symbols = symbolTokens,
            commands = commandTokens,
            blocks = blockTokens
        }
    else
        return output, {
            symbols = symbols,
            commands = commands,
            blocks = blocks
        }
    end
end

return {
    parse = parse
}