# scml
**Super Corporate Markup Language**, a dialogue markup language built for games like Super Corporate World.

## Syntax

SCML has a straightforward syntax designed for expressive dialogue. If any part of the syntax is incorrect or malformed, that portion is included in the final text as plain text rather than causing errors.

### Literals

Literals are characters that are not parsed. This functionality is also called "escaping." To write a literal, place a **backslash** (`\`) before the character you want to escape.

The following is an example of a literal left square bracket:

```scml
\[
```

This example becomes `[` in the final parsed text.

### Symbols

Symbols are placeholders for icons or other graphical elements in your dialogue. They are written inside **colons** (`: :`) and are removed from the final text, but their **names** and **positions** are tracked, so your renderer can display them correctly.

The following is an example of a 🤣 (rofl) symbol:

```scml
:rofl:
```

This example could become something like `🤣` depending on your renderer.

### Commands

Commands are **directives** for your renderer. They are written inside **angle brackets** (`< >`) and are removed from the final text, but their **names** and **positions** are tracked so your renderer can act on them.

The following is an example of a line break command:

```scml
Line one<br>Line two
```

This example could be something like
```
Line one
Line two
```
depending on your renderer.

#### Note:
Any actual newlines in the SCML raw text are automatically converted to `<br>` commands to maintain consistency for your renderer.

### Blocks

Blocks are sections of text with optional **modifiers** (**flags** and **fields**) that provide metadata for your renderer. They are composed of two groups: the **modifier group** written using **square brackets** (`[ ]`), followed by the **content group** written using **curly braces** (`{ }`). Both groups are required. Blocks' modifier groups and their content group's grouping symbols are removed, but the **start** and **end** positions of their content groups and the **modifiers** are tracked so your renderer can act on them.

The following is an example of a simple block:

```scml
[]{This text is inside a block}
```

This example becomes `This text is inside a block` in the final parsed text.

Only whitespace between the modifier and content groups is allowed:

```scml
[] {This works}

[]
{This also works}

[]a{This does not work because of the "a"}
```

Blocks can contain other blocks (nested blocks):

```scml
[]{This is a []{nested block} inside a block}
```

This example becomes `This is a nested block inside a block` in the final parsed text.

### Modifiers

Modifiers provide additional metadata for sections of text that your renderer can use. They can be:

- **Flags:** single words indicating a property or behavior (example: italic)
- **Fields:** key-value pairs providing more detailed settings (example: color=red)

These are a couple examples of modifiers in use:

```scml
[bold]{Bold text}
[size=12]{Text with size 12}
```

Mutliple modifiers in one modifier group must be separated by commas:

```scml
[bold, size=12]{Bold text with size 12}
```

Whitespace after and before the grouping symbols, between commas, and between equals signs in fields is ignored:

```scml
[  bold,     size=   12  ]{This works}
```

## Usage

To use SCML in Lua, require the parser module and call the `parse` function:

```lua
local scml = require("src.scml")

local text, meta = scml.parse("[bold]{Hello! :hand: }<br>Welcome!")
print(text) -- Outputs "Hello   Welcome!"
print(meta) -- Contains symbols, commands, and blocks with positions and metadata
```

`parse` returns two values:  
1. The cleaned text with all correct SCML notation removed
2. A table of metadata containing:  
    ```luau
    symbols: {
        {
            pos: number,
            name: string
        }
    },
    commands: {
        {
            pos: number,
            name: string
        }
    },
    blocks: {
        {
            startPos: number,
            endPos: number,
            modifiers: {
                flags: {string},
                fields: {[string]: string}
            }
            children: {...}? -- Optional array of nested blocks
        }
    }
    ```