--[[
    file: Summary
    title: Write notes, not boilerplate.
    description: The summary module creates links and annotations to all files in a given workspace.
    summary: Creates links to all files in any workspace.
    ---
<!-- TODO: GIF -->
The `core.summary` module exposes a single command - `:Neorg generate-workspace-summary`.

When executed with the cursor hovering over a heading, `core.summary` will generate, you guessed it,
a summary of the entire workspace, with links to each respective entry in that workspace.

The way the summary is generated relies on the `strategy` configuration option, which by default
consults the document metadata (see also [`core.esupports.metagen`](@core.esupports.metagen))
of each file to build up a tree of categories, titles and descriptions.
--]]

require("neorg.modules.base")
require("neorg.modules")
require("neorg.external.helpers")

local module = neorg.modules.create("core.summary")

module.setup = function()
    return {
        sucess = true,
        requires = { "core.neorgcmd", "core.integrations.treesitter" },
    }
end

module.load = function()
    module.required["core.neorgcmd"].add_commands_from_table({
        ["generate-workspace-summary"] = {
            args = 0,
            condition = "norg",
            name = "summary.summarize",
        },
    })

    local ts = module.required["core.integrations.treesitter"]

    module.config.public.strategy = neorg.lib.match(module.config.public.strategy)({
        metadata = function()
            return function(files, heading_level)
                local categories = vim.defaulttable()

                neorg.utils.read_files(files, function(bufnr, filename)
                    local metadata = ts.get_document_metadata(bufnr)

                    if not metadata or vim.tbl_isempty(metadata) then
                        return
                    end

                    -- normalise categories into a list. Could be vim.NIL, a number, a string or a list ...
                    if not metadata.categories or metadata.categories == vim.NIL then
                        metadata.categories = { "Uncategorised" }
                    elseif not vim.tbl_islist(metadata.categories) then
                        metadata.categories = { tostring(metadata.categories) }
                    end
                    for _, category in ipairs(metadata.categories) do
                        if not metadata.title then
                            metadata.title = vim.fs.basename(filename)
                        end
                        if metadata.description == vim.NIL then
                            metadata.description = nil
                        end
                        table.insert(
                            categories[neorg.lib.title(category)],
                            {
                                title = tostring(metadata.title),
                                filename = filename,
                                description = metadata.description,
                            }
                        )
                    end
                end)
                local result = {}
                local prefix = string.rep("*", heading_level)

                for category, data in vim.spairs(categories) do
                    table.insert(result, prefix .. " " .. category)

                    for _, datapoint in ipairs(data) do
                        table.insert(
                            result,
                            table.concat({ "   - {:", datapoint.filename, ":}[", neorg.lib.title(datapoint.title), "]" })
                                .. (datapoint.description and (table.concat({ " - ", datapoint.description })) or "")
                        )
                    end
                end

                return result
            end
        end,
        headings = function()
            return function() end
        end,
    }) or module.config.public.strategy
end

module.config.public = {
    -- The strategy to use to generate a summary.
    --
    -- Possible options are:
    -- - "metadata" - read the metadata to categorize and annotate files. Files
    --   without metadata will be ignored.
    -- - "headings" (UNIMPLEMENTED) - read the top level heading and use that as the title.
    --   files in subdirectories are treated as subheadings.
    ---@type string|fun(files: string[], heading_level: number?): string[]?
    strategy = "metadata",
}

module.public = {}

module.events.subscribed = {
    ["core.neorgcmd"] = {
        ["summary.summarize"] = true,
    },
}

module.on_event = function(event)
    if event.type == "core.neorgcmd.events.summary.summarize" then
        local ts = module.required["core.integrations.treesitter"]
        local buffer = event.buffer

        local node_at_cursor = ts.get_first_node_on_line(buffer, event.cursor_position[1] - 1)

        if not node_at_cursor or not node_at_cursor:type():match("^heading%d$") then
            neorg.utils.notify(
                "No heading under cursor! Please move your cursor under the heading you'd like to generate the summary under."
            )
            return
        end
        -- heading level of 'node_at_cursor' (summary headings should be one level deeper)
        local level = tonumber(string.sub(node_at_cursor:type(), -1))

        local dirman = neorg.modules.get_module("core.dirman")

        if not dirman then
            neorg.utils.notify("`core.dirman` is not loaded! It is required to generate summaries")
            return
        end

        local generated =
            module.config.public.strategy(dirman.get_norg_files(dirman.get_current_workspace()[1]) or {}, level + 1)

        if not generated or vim.tbl_isempty(generated) then
            neorg.utils.notify(
                "No summary to generate! Either change the `strategy` option or ensure you have some indexable files in your workspace."
            )
            return
        end

        vim.api.nvim_buf_set_lines(buffer, event.cursor_position[1], event.cursor_position[1], true, generated)
    end
end

return module
